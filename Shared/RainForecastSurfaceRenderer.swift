//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Nowcast “rain surface” chart renderer.
//  Goals:
//  - Pure black background (handled by caller, renderer assumes it)
//  - Soft blue core mound
//  - Fuzzy, dissipating uncertainty band that stays inside WidgetKit budgets
//
//  This version replaces “thousands of tiny vector circles” with a two-pass,
//  texture-masked band. Draw calls stay bounded and do not scale with rain amount.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct RainForecastSurfaceRenderer {

    private let intensities: [Double]
    private let certainties01: [Double]
    private let configuration: RainForecastSurfaceConfiguration

    init(
        intensities: [Double],
        certainties: [Double] = [],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties01 = certainties.map { Self.clamp01($0) }
        self.configuration = configuration
    }

    init(
        intensities: [Double],
        certainties: [Double?],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties01 = certainties.map { Self.clamp01($0 ?? 0.0) }
        self.configuration = configuration
    }

    func render(in context: inout GraphicsContext, rect: CGRect, displayScale: CGFloat) {
        guard rect.width > 1.0, rect.height > 1.0 else { return }

        var cfg = configuration
        cfg.sourceMinuteCount = intensities.count

        let isExtension = WidgetWeaverRuntime.isRunningInAppExtension
        let ds: CGFloat = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0
        let onePx: CGFloat = 1.0 / max(1.0, ds)

        // WidgetKit safety clamps.
        if isExtension {
            cfg.fuzzHazeBlurFractionOfBand = 0.0
            cfg.glossEnabled = false
            cfg.glintEnabled = false
        }
        cfg.maxDenseSamples = max(120, min(cfg.maxDenseSamples, isExtension ? 620 : 900))

        let chartRect = rect
        let baselineY = chartRect.minY
        + chartRect.height * CGFloat(Self.clamp01(cfg.baselineFractionFromTop))
        + CGFloat(cfg.baselineOffsetPixels) / max(1.0, ds)

        // No data: baseline only.
        guard !intensities.isEmpty else {
            Self.drawBaseline(in: &context, chartRect: chartRect, baselineY: baselineY, configuration: cfg, displayScale: ds)
            return
        }

        let filledIntensities = Self.fillMissingLinearHoldEnds(intensities)

        let referenceMax = Self.robustReferenceMaxMMPerHour(
            values: filledIntensities,
            defaultMax: cfg.intensityReferenceMaxMMPerHour,
            percentile: cfg.robustMaxPercentile
        )

        let maxHeight = Self.maxUsableHeight(chartRect: chartRect, baselineY: baselineY, cfg: cfg)

        var minuteHeights = Self.makeMinuteHeights(
            intensities: filledIntensities,
            referenceMax: referenceMax,
            maxHeight: maxHeight,
            gamma: cfg.intensityGamma
        )

        Self.applyEdgeEasing(to: &minuteHeights, fraction: cfg.edgeEasingFraction, power: cfg.edgeEasingPower)

        let minuteCertainties = Self.makeMinuteCertainties(
            sourceCount: intensities.count,
            certainties01: certainties01
        )

        let denseCount = Self.denseSampleCount(
            chartRect: chartRect,
            displayScale: ds,
            sourceCount: minuteHeights.count,
            cfg: cfg
        )

        var denseHeights = Self.resampleLinear(values: minuteHeights, targetCount: denseCount)
        let denseCertainties = Self.resampleLinear(values: minuteCertainties, targetCount: denseCount)

        let smoothRadius = max(1, min(5, Int(round(Double(denseCount) / 180.0))))
        denseHeights = Self.smooth(denseHeights, windowRadius: smoothRadius, passes: 2)

        let curvePoints = Self.makeCurvePoints(rect: chartRect, baselineY: baselineY, heights: denseHeights)
        let corePath = Self.buildCoreFillPath(rect: chartRect, baselineY: baselineY, curvePoints: curvePoints)

        // Core mound.
        Self.drawCore(in: &context, corePath: corePath, rect: chartRect, baselineY: baselineY, configuration: cfg)

        // Rim highlight.
        Self.drawRim(in: &context, rect: chartRect, curvePoints: curvePoints, displayScale: ds, configuration: cfg)

        // Fuzz / dissipation.
        if cfg.fuzzEnabled && cfg.canEnableFuzz {
            let bandHalfWidth = Self.computeBandHalfWidthPt(rect: chartRect, displayScale: ds, cfg: cfg)
            if bandHalfWidth > onePx * 2.0 {
                Self.drawFuzzTexture(
                    in: &context,
                    rect: chartRect,
                    baselineY: baselineY,
                    curvePoints: curvePoints,
                    heights: denseHeights,
                    certainties: denseCertainties,
                    bandHalfWidth: bandHalfWidth,
                    displayScale: ds,
                    configuration: cfg,
                    isExtension: isExtension
                )
            }
        }

        // Baseline last so it stays crisp.
        Self.drawBaseline(in: &context, chartRect: chartRect, baselineY: baselineY, configuration: cfg, displayScale: ds)
    }
}

// MARK: - Core

private extension RainForecastSurfaceRenderer {

    static func drawCore(
        in context: inout GraphicsContext,
        corePath: Path,
        rect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        let top = cfg.coreTopColor
        let body = cfg.coreBodyColor
        let mid = Color.blend(a: body, b: top, t: cfg.coreTopMix)

        let gradient = Gradient(stops: [
            .init(color: top, location: 0.0),
            .init(color: mid, location: 0.28),
            .init(color: body, location: 1.0),
        ])

        context.fill(
            corePath,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: baselineY)
            )
        )

        // Optional gloss (kept off by default).
        if cfg.glossEnabled && cfg.glossMaxOpacity > 0.0001 {
            let opacity = clamp01(cfg.glossMaxOpacity)
            let glossColor = Color.white.opacity(opacity)
            let glossY = rect.minY + (baselineY - rect.minY) * 0.26

            var p = Path()
            p.addRoundedRect(
                in: CGRect(
                    x: rect.minX,
                    y: glossY,
                    width: rect.width,
                    height: (baselineY - rect.minY) * 0.18
                ),
                cornerSize: CGSize(width: 28, height: 28),
                style: .continuous
            )

            context.blendMode = .screen
            context.fill(p, with: .color(glossColor.opacity(0.10)))
            context.blendMode = .normal
        }

        // Subtle darkening at extreme ends (tail softness).
        if cfg.coreFadeFraction > 0.0001 {
            let fade = CGFloat(clamp01(cfg.coreFadeFraction))
            let w = max(1.0, rect.width)
            let fadeW = w * fade

            let g = Gradient(stops: [
                .init(color: Color.black.opacity(0.0), location: 0.0),
                .init(color: Color.black.opacity(0.11), location: Double(clamp01(Double(fadeW / w)))),
                .init(color: Color.black.opacity(0.11), location: Double(clamp01(Double(1.0 - fadeW / w)))),
                .init(color: Color.black.opacity(0.0), location: 1.0),
            ])

            context.blendMode = .multiply
            context.fill(
                corePath,
                with: .linearGradient(
                    g,
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )
            context.blendMode = .normal
        }
    }

    static func drawRim(
        in context: inout GraphicsContext,
        rect: CGRect,
        curvePoints: [CGPoint],
        displayScale: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        guard cfg.rimEnabled, curvePoints.count >= 2 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds

        let innerOpacity = clamp01(cfg.rimInnerOpacity)
        let outerOpacity = clamp01(cfg.rimOuterOpacity)
        guard innerOpacity > 0.0001 || outerOpacity > 0.0001 else { return }

        let curvePath = buildCurveStrokePath(curvePoints: curvePoints)

        if outerOpacity > 0.0001, cfg.rimOuterWidthPixels > 0.01 {
            let w = max(onePx, CGFloat(cfg.rimOuterWidthPixels) / ds)
            context.blendMode = .screen
            context.stroke(curvePath, with: .color(cfg.rimColor.opacity(outerOpacity)), lineWidth: w)
            context.blendMode = .normal
        }

        if innerOpacity > 0.0001, cfg.rimInnerWidthPixels > 0.01 {
            let w = max(onePx, CGFloat(cfg.rimInnerWidthPixels) / ds)
            context.blendMode = .screen
            context.stroke(curvePath, with: .color(cfg.rimColor.opacity(innerOpacity)), lineWidth: w)
            context.blendMode = .normal
        }
    }
}

// MARK: - Fuzz (texture band)

private extension RainForecastSurfaceRenderer {

    static func drawFuzzTexture(
        in context: inout GraphicsContext,
        rect: CGRect,
        baselineY: CGFloat,
        curvePoints: [CGPoint],
        heights: [CGFloat],
        certainties: [Double],
        bandHalfWidth: CGFloat,
        displayScale: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        isExtension: Bool
    ) {
        guard curvePoints.count >= 2,
              curvePoints.count == heights.count,
              certainties.count == heights.count
        else { return }

        let ds = max(1.0, displayScale)
        let onePx: CGFloat = 1.0 / ds
        let wetEps: CGFloat = max(onePx * 0.35, 0.000_1)

        // Strength (0...1) along the curve.
        var strength = computeFuzzStrengthPerPoint(
            heights: heights,
            certainties: certainties,
            wetEps: wetEps,
            cfg: cfg
        )

        // Suppress far-from-wet regions so fuzz does not pepper dry baseline.
        let samplesPerPx = Double(max(1, curvePoints.count - 1)) / Double(max(1.0, rect.width * ds))
        let edgeWindowSamples = max(1, Int(round(max(0.0, cfg.fuzzEdgeWindowPx) * samplesPerPx)))

        let wetMask = heights.map { $0 > wetEps }
        let distToWet = distanceToNearestTrue(wetMask)
        if distToWet.count == strength.count {
            for i in 0..<strength.count {
                if distToWet[i] > edgeWindowSamples {
                    strength[i] = 0.0
                }
            }
        }

        // Boost around wet↔dry transitions (tail fuzz).
        if cfg.fuzzTailMinutes > 0.001 {
            applyTailBoost(
                strength: &strength,
                wetMask: wetMask,
                sourceMinuteCount: max(2, cfg.sourceMinuteCount),
                tailMinutes: cfg.fuzzTailMinutes
            )
        }

        let maxStrength = strength.max() ?? 0.0
        guard maxStrength > 0.0005 else { return }

        // Final alpha scale.
        let maxAlpha = clamp01(cfg.fuzzMaxOpacity) * max(0.0, cfg.fuzzSpeckStrength)
        guard maxAlpha > 0.0001 else { return }

        // Clip fuzz to the chart area above the baseline (keeps labels clean).
        let clipH = max(0.0, min(rect.height, baselineY - rect.minY))
        guard clipH > onePx else { return }
        let clipRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: clipH)

        let curvePath = buildCurveStrokePath(curvePoints: curvePoints)

        // Noise textures (cached).
        let seedBase = RainSurfacePRNG.combine(cfg.noiseSeed, UInt64(curvePoints.count &* 977))
        let tilePx = max(32, min(cfg.fuzzTextureTilePixels, 512))
        let innerNoise = FuzzNoiseCache.shared.image(pixels: tilePx, seed: RainSurfacePRNG.combine(seedBase, 0x1111_2222_3333_4444), cut: 0.48)
        let outerNoise = FuzzNoiseCache.shared.image(pixels: tilePx, seed: RainSurfacePRNG.combine(seedBase, 0x9999_AAAA_BBBB_CCCC), cut: 0.72)

        let innerResolved = innerNoise.flatMap { context.resolve($0) }
        let outerResolved = outerNoise.flatMap { context.resolve($0) }

        // Gradient stops (bounded).
        let stopsCount = max(8, min(cfg.fuzzTextureGradientStops, 64))
        let alphaGradient = makeAlphaGradient(
            color: cfg.fuzzColor,
            strength: strength,
            maxAlpha: maxAlpha,
            stops: stopsCount
        )

        // Pass parameters.
        let innerBandMul = max(0.1, cfg.fuzzTextureInnerBandMultiplier)
        let outerBandMul = max(0.1, cfg.fuzzTextureOuterBandMultiplier)
        let innerOpacityMul = max(0.0, cfg.fuzzTextureInnerOpacityMultiplier)
        let outerOpacityMul = max(0.0, cfg.fuzzTextureOuterOpacityMultiplier)

        // Outer pass: wider + lower opacity (the “dissipating” slope dust).
        drawNoiseBandPass(
            in: &context,
            clipRect: clipRect,
            curvePath: curvePath,
            bandHalfWidth: bandHalfWidth * CGFloat(outerBandMul),
            alphaGradient: alphaGradient,
            alphaMultiplier: outerOpacityMul,
            resolvedNoise: outerResolved,
            seed: RainSurfacePRNG.combine(seedBase, 0x0BAD_F00D),
            rect: rect
        )

        // Inner pass: tighter + stronger (edge coherence).
        drawNoiseBandPass(
            in: &context,
            clipRect: clipRect,
            curvePath: curvePath,
            bandHalfWidth: bandHalfWidth * CGFloat(innerBandMul),
            alphaGradient: alphaGradient,
            alphaMultiplier: innerOpacityMul,
            resolvedNoise: innerResolved,
            seed: RainSurfacePRNG.combine(seedBase, 0xFEED_FACE),
            rect: rect
        )

        // Cheap haze stroke to keep the band visually continuous (no blur).
        if cfg.fuzzHazeStrength > 0.0001 {
            let meanStrength = average(strength)
            let hazeAlpha = clamp01(cfg.fuzzHazeStrength) * maxAlpha * (0.55 + 0.45 * meanStrength)
            if hazeAlpha > 0.0001 {
                let strokeW = max(onePx, (bandHalfWidth * 2.0) * CGFloat(max(0.10, cfg.fuzzHazeStrokeWidthFactor)))

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    layer.blendMode = .screen
                    layer.stroke(curvePath, with: .color(cfg.fuzzColor.opacity(hazeAlpha)), lineWidth: strokeW)
                    layer.blendMode = .normal
                }
            }
        }
    }

    static func drawNoiseBandPass(
        in context: inout GraphicsContext,
        clipRect: CGRect,
        curvePath: Path,
        bandHalfWidth: CGFloat,
        alphaGradient: Gradient,
        alphaMultiplier: Double,
        resolvedNoise: GraphicsContext.ResolvedImage?,
        seed: UInt64,
        rect: CGRect
    ) {
        guard bandHalfWidth.isFinite, bandHalfWidth > 0.25 else { return }
        guard alphaMultiplier > 0.0001 else { return }

        let lineWidth = max(0.5, bandHalfWidth * 2.0)

        // A small, deterministic offset prevents the noise from feeling “stuck”.
        var rng = RainSurfacePRNG(seed: seed)
        let ox = CGFloat(rng.nextSignedFloat()) * rect.width * 0.12
        let oy = CGFloat(rng.nextSignedFloat()) * rect.height * 0.10
        let drawRect = rect.offsetBy(dx: ox, dy: oy)

        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))

            let strokeRegion = curvePath.strokedPath(
                StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            layer.clip(to: strokeRegion)

            // Strength gradient (screen blend over black/core).
            layer.blendMode = .screen

            let scaledGradient = Gradient(stops: alphaGradient.stops.map { stop in
                .init(color: stop.color.opacity(alphaMultiplier), location: stop.location)
            })

            layer.fill(
                Path(drawRect),
                with: .linearGradient(
                    scaledGradient,
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )

            // Apply noise alpha as a mask to create grain.
            if let resolvedNoise {
                layer.blendMode = .destinationIn
                layer.draw(resolvedNoise, in: drawRect)
            }

            layer.blendMode = .normal
        }
    }

    static func makeAlphaGradient(
        color: Color,
        strength: [Double],
        maxAlpha: Double,
        stops: Int
    ) -> Gradient {
        let n = strength.count
        let sCount = max(2, stops)

        var out: [Gradient.Stop] = []
        out.reserveCapacity(sCount)

        for i in 0..<sCount {
            let t = (sCount <= 1) ? 0.0 : (Double(i) / Double(sCount - 1))
            let idx = max(0, min(n - 1, Int(round(t * Double(max(0, n - 1))))))
            let a = clamp01(strength[idx]) * clamp01(maxAlpha)
            out.append(.init(color: color.opacity(a), location: t))
        }

        return Gradient(stops: out)
    }
}

// MARK: - Baseline

private extension RainForecastSurfaceRenderer {

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard cfg.baselineEnabled else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds
        let width = max(onePx, CGFloat(cfg.baselineWidthPixels) / ds)

        let opacity = clamp01(cfg.baselineLineOpacity)
        guard opacity > 0.0001, width > 0.0001 else { return }

        let y = baselineY
        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: y))
        p.addLine(to: CGPoint(x: chartRect.maxX, y: y))

        let fadeFrac = clamp01(cfg.baselineEndFadeFraction)
        if fadeFrac > 0.0001 {
            let g = Gradient(stops: [
                .init(color: cfg.baselineColor.opacity(0.0), location: 0.0),
                .init(color: cfg.baselineColor.opacity(opacity), location: fadeFrac),
                .init(color: cfg.baselineColor.opacity(opacity), location: 1.0 - fadeFrac),
                .init(color: cfg.baselineColor.opacity(0.0), location: 1.0),
            ])

            context.stroke(
                p,
                with: .linearGradient(
                    g,
                    startPoint: CGPoint(x: chartRect.minX, y: y),
                    endPoint: CGPoint(x: chartRect.maxX, y: y)
                ),
                lineWidth: width
            )
        } else {
            context.stroke(p, with: .color(cfg.baselineColor.opacity(opacity)), lineWidth: width)
        }
    }
}

// MARK: - Geometry + helpers

private extension RainForecastSurfaceRenderer {

    static func computeBandHalfWidthPt(rect: CGRect, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let ds = max(1.0, displayScale)
        let minDim = min(rect.height * 0.28, rect.width * 0.10)
        let unclamped = minDim * CGFloat(max(0.0, cfg.fuzzWidthFraction))

        let lo = CGFloat(max(0.0, cfg.fuzzWidthPixelsClamp.lowerBound)) / ds
        let hi = CGFloat(max(lo, cfg.fuzzWidthPixelsClamp.upperBound)) / ds

        return max(lo, min(hi, unclamped))
    }

    static func maxUsableHeight(chartRect: CGRect, baselineY: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let topY = chartRect.minY + chartRect.height * CGFloat(clamp01(cfg.topHeadroomFraction))
        let available = max(0.0, baselineY - topY)
        return available * CGFloat(clamp01(cfg.typicalPeakFraction))
    }

    static func makeMinuteHeights(intensities: [Double], referenceMax: Double, maxHeight: CGFloat, gamma: Double) -> [CGFloat] {
        guard !intensities.isEmpty else { return [] }

        let ref = max(0.000_001, referenceMax)
        let g = max(0.10, gamma)

        return intensities.map { raw in
            let v = max(0.0, raw.isFinite ? raw : 0.0)
            let n = clamp01(v / ref)
            let shaped = pow(n, g)
            return maxHeight * CGFloat(shaped)
        }
    }

    static func makeMinuteCertainties(sourceCount: Int, certainties01: [Double]) -> [Double] {
        guard sourceCount > 0 else { return [] }

        if certainties01.isEmpty {
            return Array(repeating: 1.0, count: sourceCount)
        }
        if certainties01.count == sourceCount {
            return certainties01.map { clamp01($0) }
        }
        if certainties01.count == 1 {
            return Array(repeating: clamp01(certainties01[0]), count: sourceCount)
        }
        return resampleLinear(values: certainties01.map { clamp01($0) }, targetCount: sourceCount)
    }

    static func denseSampleCount(chartRect: CGRect, displayScale: CGFloat, sourceCount: Int, cfg: RainForecastSurfaceConfiguration) -> Int {
        let wPx = Double(max(1.0, chartRect.width * displayScale))
        let desired = max(sourceCount, Int(wPx * 1.70))
        return max(2, min(cfg.maxDenseSamples, desired))
    }

    static func makeCurvePoints(rect: CGRect, baselineY: CGFloat, heights: [CGFloat]) -> [CGPoint] {
        let count = heights.count
        guard count > 0 else { return [] }

        if count == 1 {
            return [CGPoint(x: rect.midX, y: baselineY - heights[0])]
        }

        let denom = CGFloat(count - 1)
        var pts: [CGPoint] = []
        pts.reserveCapacity(count)

        for i in 0..<count {
            let t = CGFloat(i) / denom
            let x = rect.minX + rect.width * t
            let y = baselineY - heights[i]
            pts.append(CGPoint(x: x, y: y))
        }

        return pts
    }

    static func buildCoreFillPath(rect: CGRect, baselineY: CGFloat, curvePoints: [CGPoint]) -> Path {
        guard let first = curvePoints.first, let last = curvePoints.last else { return Path() }

        return Path { p in
            p.move(to: CGPoint(x: rect.minX, y: baselineY))
            p.addLine(to: first)
            for pt in curvePoints.dropFirst() {
                p.addLine(to: pt)
            }
            p.addLine(to: CGPoint(x: rect.maxX, y: baselineY))
            p.closeSubpath()
        }
    }

    static func buildCurveStrokePath(curvePoints: [CGPoint]) -> Path {
        guard let first = curvePoints.first else { return Path() }
        return Path { p in
            p.move(to: first)
            if curvePoints.count == 1 { return }
            for pt in curvePoints.dropFirst() {
                p.addLine(to: pt)
            }
        }
    }
}

// MARK: - Fuzz strength shaping

private extension RainForecastSurfaceRenderer {

    static func computeFuzzStrengthPerPoint(
        heights: [CGFloat],
        certainties: [Double],
        wetEps: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) -> [Double] {
        let n = heights.count
        guard n > 0 else { return [] }

        let maxH = heights.max() ?? 0.0
        let invMaxH: CGFloat = (maxH > 0.000_01) ? (1.0 / maxH) : 0.0

        let thr = clamp01(cfg.fuzzChanceThreshold)
        let trans = max(0.000_1, cfg.fuzzChanceTransition)
        let exp = max(0.10, cfg.fuzzChanceExponent)

        let floorBase = clamp01(cfg.fuzzChanceFloor)
        let minStrength = clamp01(cfg.fuzzChanceMinStrength)

        let lowHPow = max(0.10, cfg.fuzzLowHeightPower)
        let lowHBoost = max(0.0, cfg.fuzzLowHeightBoost)

        var out = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            let h = heights[i]
            if h <= wetEps {
                out[i] = 0.0
                continue
            }

            let chance = clamp01(certainties[i])

            // Lower chance -> stronger fuzz.
            let t = clamp01((thr - chance) / trans)
            var s = floorBase + (1.0 - floorBase) * pow(t, exp)

            // Boost low heights so drizzle still has visible uncertainty.
            if invMaxH > 0.0 {
                let hn = clamp01(Double(h * invMaxH))
                let low = pow(1.0 - hn, lowHPow)
                s *= (1.0 + lowHBoost * low)
            }

            s = max(s, minStrength)
            out[i] = clamp01(s)
        }

        return out
    }

    static func applyTailBoost(
        strength: inout [Double],
        wetMask: [Bool],
        sourceMinuteCount: Int,
        tailMinutes: Double
    ) {
        let n = strength.count
        guard n >= 2 else { return }
        guard tailMinutes > 0.001 else { return }

        let denom = max(1, sourceMinuteCount - 1)
        let samplesPerMinute = Double(n - 1) / Double(denom)
        let tailSamples = max(1, Int(round(tailMinutes * samplesPerMinute)))

        // Transition indices (wet↔dry).
        var transitions: [Int] = []
        transitions.reserveCapacity(8)
        for i in 1..<wetMask.count {
            if wetMask[i] != wetMask[i - 1] {
                transitions.append(i)
            }
        }
        guard !transitions.isEmpty else { return }

        for tIdx in transitions {
            for k in 0...tailSamples {
                let w = 1.0 - (Double(k) / Double(max(1, tailSamples)))
                let boost = 1.0 + 0.85 * pow(w, 1.25)

                let a = tIdx - k
                if a >= 0 && a < n {
                    strength[a] = clamp01(strength[a] * boost)
                }
                let b = tIdx + k
                if b >= 0 && b < n {
                    strength[b] = clamp01(strength[b] * boost)
                }
            }
        }
    }
}

// MARK: - Misc helpers

private extension RainForecastSurfaceRenderer {

    static func fillMissingLinearHoldEnds(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }

        var out = values.map { v -> Double in
            if v.isFinite { return max(0.0, v) }
            return Double.nan
        }

        let n = out.count
        var firstIdx: Int? = nil
        var lastIdx: Int? = nil

        for i in 0..<n {
            if out[i].isFinite {
                firstIdx = i
                break
            }
        }
        for i in stride(from: n - 1, through: 0, by: -1) {
            if out[i].isFinite {
                lastIdx = i
                break
            }
        }

        guard let fi = firstIdx, let li = lastIdx else {
            return Array(repeating: 0.0, count: n)
        }

        // Hold ends.
        if fi > 0 {
            let v = out[fi]
            for i in 0..<fi { out[i] = v }
        }
        if li < n - 1 {
            let v = out[li]
            for i in (li + 1)..<n { out[i] = v }
        }

        // Linear fill between known points.
        var i = fi
        while i <= li {
            if out[i].isFinite {
                i += 1
                continue
            }

            let start = i - 1
            var end = i
            while end <= li, !out[end].isFinite {
                end += 1
            }
            if end > li { break }

            let a = out[start]
            let b = out[end]
            let span = Double(end - start)
            if span > 0 {
                for k in (start + 1)..<end {
                    let t = Double(k - start) / span
                    out[k] = a + (b - a) * t
                }
            }
            i = end + 1
        }

        // Final sanitise.
        return out.map { $0.isFinite ? max(0.0, $0) : 0.0 }
    }

    static func robustReferenceMaxMMPerHour(values: [Double], defaultMax: Double, percentile: Double) -> Double {
        let p = clamp01(percentile)
        var v = values.filter { $0.isFinite && $0 > 0.0 }
        if v.isEmpty { return max(0.25, defaultMax) }
        v.sort()
        let idx = Int(round(p * Double(max(0, v.count - 1))))
        let ref = v[max(0, min(v.count - 1, idx))]
        return max(0.25, max(ref, defaultMax * 0.35))
    }

    static func applyEdgeEasing(to heights: inout [CGFloat], fraction: Double, power: Double) {
        let n = heights.count
        guard n >= 2 else { return }

        let f = clamp01(fraction)
        if f <= 0.0001 { return }

        let k = max(1, Int(round(Double(n) * f)))
        let p = max(0.10, power)

        // Left ramp.
        for i in 0..<min(k, n) {
            let t = Double(i) / Double(max(1, k))
            let e = pow(t, p)
            heights[i] *= CGFloat(e)
        }

        // Right ramp.
        for i in 0..<min(k, n) {
            let idx = n - 1 - i
            let t = Double(i) / Double(max(1, k))
            let e = pow(t, p)
            heights[idx] *= CGFloat(e)
        }
    }

    static func resampleLinear(values: [CGFloat], targetCount: Int) -> [CGFloat] {
        let n = values.count
        if targetCount <= 0 { return [] }
        if n == 0 { return Array(repeating: 0.0, count: targetCount) }
        if n == 1 { return Array(repeating: values[0], count: targetCount) }
        if n == targetCount { return values }

        let denom = Double(max(1, n - 1))
        var out: [CGFloat] = []
        out.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let t = (targetCount <= 1) ? 0.0 : Double(i) / Double(targetCount - 1)
            let u = t * denom
            let i0 = max(0, min(n - 2, Int(floor(u))))
            let frac = CGFloat(u - Double(i0))
            let a = values[i0]
            let b = values[i0 + 1]
            out.append(a + (b - a) * frac)
        }

        return out
    }

    static func resampleLinear(values: [Double], targetCount: Int) -> [Double] {
        let n = values.count
        if targetCount <= 0 { return [] }
        if n == 0 { return Array(repeating: 0.0, count: targetCount) }
        if n == 1 { return Array(repeating: values[0], count: targetCount) }
        if n == targetCount { return values }

        let denom = Double(max(1, n - 1))
        var out: [Double] = []
        out.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let t = (targetCount <= 1) ? 0.0 : Double(i) / Double(targetCount - 1)
            let u = t * denom
            let i0 = max(0, min(n - 2, Int(floor(u))))
            let frac = u - Double(i0)
            let a = values[i0]
            let b = values[i0 + 1]
            out.append(a + (b - a) * frac)
        }

        return out
    }

    static func smooth(_ values: [CGFloat], windowRadius: Int, passes: Int) -> [CGFloat] {
        let n = values.count
        if n <= 2 { return values }
        let r = max(0, windowRadius)
        if r == 0 { return values }
        let p = max(1, passes)

        var cur = values
        for _ in 0..<p {
            var out = Array(repeating: CGFloat(0.0), count: n)
            for i in 0..<n {
                var acc: CGFloat = 0.0
                var wsum: CGFloat = 0.0
                let lo = max(0, i - r)
                let hi = min(n - 1, i + r)
                for j in lo...hi {
                    // Triangular weights.
                    let w = CGFloat((r + 1) - abs(i - j))
                    acc += cur[j] * w
                    wsum += w
                }
                out[i] = (wsum > 0.0) ? (acc / wsum) : cur[i]
            }
            cur = out
        }
        return cur
    }

    static func allocateCounts(budget: Int, weights: [Double], totalWeight: Double) -> [Int] {
        let n = weights.count
        guard n > 0, budget > 0, totalWeight > 0.0 else { return Array(repeating: 0, count: n) }

        var out = Array(repeating: 0, count: n)
        var carry = 0.0
        var used = 0

        for i in 0..<n {
            let w = max(0.0, weights[i])
            let exact = (w / totalWeight) * Double(budget)
            let base = Int(floor(exact))
            let frac = exact - Double(base)

            out[i] = base
            used += base

            carry += frac
            if carry >= 1.0 {
                out[i] += 1
                used += 1
                carry -= 1.0
            }
        }

        if used > budget {
            var extra = used - budget
            for i in stride(from: n - 1, through: 0, by: -1) {
                if extra <= 0 { break }
                let take = min(out[i], extra)
                out[i] -= take
                extra -= take
            }
        }

        return out
    }

    static func distanceToNearestTrue(_ mask: [Bool]) -> [Int] {
        let n = mask.count
        if n == 0 { return [] }

        let big = 1_000_000
        var dist = Array(repeating: big, count: n)

        var last = -1
        for i in 0..<n {
            if mask[i] {
                last = i
                dist[i] = 0
            } else if last >= 0 {
                dist[i] = i - last
            }
        }

        last = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if mask[i] {
                last = i
                dist[i] = 0
            } else if last >= 0 {
                dist[i] = min(dist[i], last - i)
            }
        }

        return dist
    }

    static func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.0 }
        var s = 0.0
        for v in values { s += v }
        return s / Double(values.count)
    }

    static func clamp01(_ x: Double) -> Double {
        if x < 0.0 { return 0.0 }
        if x > 1.0 { return 1.0 }
        return x.isFinite ? x : 0.0
    }
}

// MARK: - Noise cache

private final class FuzzNoiseCache: @unchecked Sendable {

    static let shared = FuzzNoiseCache()

    private struct Key: Hashable {
        let pixels: Int
        let seed: UInt64
        let cutBucket: Int
    }

    private let lock = NSLock()
    private var cache: [Key: CGImage] = [:]

    func image(pixels: Int, seed: UInt64, cut: Double) -> Image? {
        let cutBucket = Int(round(max(0.0, min(1.0, cut)) * 1000.0))
        let key = Key(pixels: pixels, seed: seed, cutBucket: cutBucket)

        let cg: CGImage? = lock.withLock {
            if let existing = cache[key] { return existing }
            let made = Self.makeNoiseCGImage(pixels: pixels, seed: seed, cut: cut)
            if let made { cache[key] = made }
            return made
        }

        guard let cg else { return nil }
        return Image(decorative: cg, scale: 1.0, orientation: .up)
    }

    private static func makeNoiseCGImage(pixels: Int, seed: UInt64, cut: Double) -> CGImage? {
        let w = max(16, min(pixels, 1024))
        let h = w

        let bytesPerPixel = 4
        let bytesPerRow = w * bytesPerPixel
        var data = [UInt8](repeating: 0, count: h * bytesPerRow)

        let c = max(0.0, min(0.98, cut))
        var rng = RainSurfacePRNG(seed: seed)

        for y in 0..<h {
            for x in 0..<w {
                let u = rng.nextFloat01()

                // Sparse speckles: most pixels fully transparent.
                let a: UInt8
                if u < c {
                    a = 0
                } else {
                    let t = (u - c) / max(0.000_001, (1.0 - c))
                    // Bias towards brighter specks.
                    let shaped = pow(max(0.0, min(1.0, t)), 0.35)
                    a = UInt8(max(0, min(255, Int(round(shaped * 255.0)))))
                }

                let i = y * bytesPerRow + x * 4
                data[i + 0] = 255
                data[i + 1] = 255
                data[i + 2] = 255
                data[i + 3] = a
            }
        }

        let cfData = Data(data) as CFData
        guard let provider = CGDataProvider(data: cfData) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

// MARK: - Color blending

private extension Color {

    static func blend(a: Color, b: Color, t: Double) -> Color {
        let tt = max(0.0, min(1.0, t))

        #if canImport(UIKit)
        let ua = UIColor(a)
        let ub = UIColor(b)

        var ra: CGFloat = 0, ga: CGFloat = 0, ba: CGFloat = 0, aa: CGFloat = 0
        var rb: CGFloat = 0, gb: CGFloat = 0, bb: CGFloat = 0, ab: CGFloat = 0

        _ = ua.getRed(&ra, green: &ga, blue: &ba, alpha: &aa)
        _ = ub.getRed(&rb, green: &gb, blue: &bb, alpha: &ab)

        let tCg = CGFloat(tt)
        let r = ra + (rb - ra) * tCg
        let g = ga + (gb - ga) * tCg
        let bC = ba + (bb - ba) * tCg
        let aC = aa + (ab - aa) * tCg

        return Color(red: Double(r), green: Double(g), blue: Double(bC), opacity: Double(aC))
        #else
        return tt < 0.5 ? a : b
        #endif
    }
}
