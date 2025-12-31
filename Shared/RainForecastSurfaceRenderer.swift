//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI
import CoreGraphics

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

        if isExtension {
            cfg.glossEnabled = false
            cfg.glintEnabled = false
            cfg.fuzzHazeBlurFractionOfBand = 0.0
        }

        cfg.maxDenseSamples = max(120, min(cfg.maxDenseSamples, isExtension ? 620 : 900))

        let chartRect = rect
        let baselineY = chartRect.minY
        + chartRect.height * CGFloat(Self.clamp01(cfg.baselineFractionFromTop))
        + CGFloat(cfg.baselineOffsetPixels) / max(1.0, ds)

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

        let topY = chartRect.minY + chartRect.height * CGFloat(Self.clamp01(cfg.topHeadroomFraction))
        let usableHeight = max(1.0, baselineY - topY)
        let peakHeight = usableHeight * CGFloat(Self.clamp01(cfg.typicalPeakFraction))

        var minuteHeights: [CGFloat] = filledIntensities.map { v in
            let x = max(0.0, v.isFinite ? v : 0.0)
            let n = Self.clamp01(x / max(0.001, referenceMax))
            let g = pow(n, max(0.01, cfg.intensityGamma))
            return CGFloat(g) * peakHeight
        }

        minuteHeights = Self.applyEdgeEasing(
            values: minuteHeights,
            fraction: cfg.edgeEasingFraction,
            power: cfg.edgeEasingPower
        )

        let minuteCertainties = Self.makeMinuteCertainties(
            sourceCount: minuteHeights.count,
            certainties01: certainties01
        )

        let denseCount = Self.denseSampleCount(
            sourceCount: minuteHeights.count,
            rectWidthPoints: Double(chartRect.width),
            displayScale: Double(ds),
            maxDense: cfg.maxDenseSamples
        )

        var denseHeights = Self.resampleLinear(minuteHeights, toCount: denseCount)
        let denseCertainties = Self.resampleLinear(minuteCertainties, toCount: denseCount)

        denseHeights = Self.smooth(values: denseHeights, radius: max(1, Int(round(Double(ds) * 1.5))))

        let curvePoints = Self.makeCurvePoints(rect: chartRect, baselineY: baselineY, heights: denseHeights)

        let corePath = Self.buildCoreFillPath(
            rect: chartRect,
            baselineY: baselineY,
            curvePoints: curvePoints
        )

        Self.drawCore(
            in: &context,
            corePath: corePath,
            curvePoints: curvePoints,
            baselineY: baselineY,
            configuration: cfg
        )

        Self.drawRim(
            in: &context,
            curvePoints: curvePoints,
            configuration: cfg,
            displayScale: ds
        )

        if cfg.fuzzEnabled, cfg.canEnableFuzz, cfg.fuzzTextureEnabled {
            let bandHalfWidth = Self.computeBandHalfWidthPoints(rect: chartRect, displayScale: ds, configuration: cfg)
            if bandHalfWidth > onePx * 0.5 {
                Self.drawDissipationFuzz(
                    in: &context,
                    rect: chartRect,
                    baselineY: baselineY,
                    corePath: corePath,
                    curvePoints: curvePoints,
                    heights: denseHeights,
                    certainties01: denseCertainties,
                    bandHalfWidth: bandHalfWidth,
                    displayScale: ds,
                    configuration: cfg
                )
            }
        }

        Self.drawBaseline(in: &context, chartRect: chartRect, baselineY: baselineY, configuration: cfg, displayScale: ds)
    }
}

// MARK: - Core / Rim / Baseline

private extension RainForecastSurfaceRenderer {
    static func drawCore(
        in context: inout GraphicsContext,
        corePath: Path,
        curvePoints: [CGPoint],
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        guard !curvePoints.isEmpty else { return }

        let topY = curvePoints.map(\.y).min() ?? baselineY
        let startPoint = CGPoint(x: curvePoints.first?.x ?? 0.0, y: topY)
        let endPoint = CGPoint(x: curvePoints.first?.x ?? 0.0, y: baselineY)

        let top = cfg.coreTopColor
        let body = cfg.coreBodyColor
        let mid = Color.blend(body, top, t: cfg.coreTopMix)

        let fade = clamp01(cfg.coreFadeFraction)
        let midStop = 0.42
        let fadeStart = max(midStop, 1.0 - fade)

        let gradient = Gradient(stops: [
            Gradient.Stop(color: top, location: 0.0),
            Gradient.Stop(color: mid, location: midStop),
            Gradient.Stop(color: body, location: fadeStart),
            Gradient.Stop(color: body.opacity(0.0), location: 1.0),
        ])

        context.fill(corePath, with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint))
    }

    static func drawRim(
        in context: inout GraphicsContext,
        curvePoints: [CGPoint],
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale ds: CGFloat
    ) {
        guard cfg.rimEnabled, !curvePoints.isEmpty else { return }

        let path = buildCurveStrokePath(curvePoints: curvePoints)
        let px = max(1.0, ds)

        if cfg.rimInnerOpacity > 0.0001, cfg.rimInnerWidthPixels > 0.0001 {
            context.stroke(
                path,
                with: .color(cfg.rimColor.opacity(clamp01(cfg.rimInnerOpacity))),
                lineWidth: CGFloat(cfg.rimInnerWidthPixels) / px
            )
        }

        if cfg.rimOpacity > 0.0001, cfg.rimWidthPixels > 0.0001 {
            context.stroke(
                path,
                with: .color(cfg.rimColor.opacity(clamp01(cfg.rimOpacity))),
                lineWidth: CGFloat(cfg.rimWidthPixels) / px
            )
        }

        if cfg.rimOuterOpacity > 0.0001, cfg.rimOuterWidthPixels > 0.0001 {
            context.stroke(
                path,
                with: .color(cfg.rimColor.opacity(clamp01(cfg.rimOuterOpacity))),
                lineWidth: CGFloat(cfg.rimOuterWidthPixels) / px
            )
        }
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale ds: CGFloat
    ) {
        guard cfg.baselineEnabled else { return }
        guard cfg.baselineWidthPixels > 0.0001, cfg.baselineLineOpacity > 0.0001 else { return }

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: baselineY))
        p.addLine(to: CGPoint(x: chartRect.maxX, y: baselineY))

        let fade = clamp01(cfg.baselineEndFadeFraction)
        let base = cfg.baselineColor.opacity(clamp01(cfg.baselineLineOpacity))

        let gradient = Gradient(stops: [
            Gradient.Stop(color: base.opacity(0.0), location: 0.0),
            Gradient.Stop(color: base, location: fade),
            Gradient.Stop(color: base, location: 1.0 - fade),
            Gradient.Stop(color: base.opacity(0.0), location: 1.0),
        ])

        context.stroke(
            p,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: chartRect.minX, y: baselineY),
                endPoint: CGPoint(x: chartRect.maxX, y: baselineY)
            ),
            lineWidth: CGFloat(cfg.baselineWidthPixels) / max(1.0, ds)
        )
    }
}

// MARK: - Dissipation fuzz (subtractive erosion + optional outer dust)

private extension RainForecastSurfaceRenderer {
    static func drawDissipationFuzz(
        in context: inout GraphicsContext,
        rect: CGRect,
        baselineY: CGFloat,
        corePath: Path,
        curvePoints: [CGPoint],
        heights: [CGFloat],
        certainties01: [CGFloat],
        bandHalfWidth: CGFloat,
        displayScale ds: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        guard cfg.fuzzMaxOpacity > 0.0001 else { return }
        guard curvePoints.count == heights.count, heights.count == certainties01.count else { return }
        guard heights.count >= 3 else { return }

        let isExtension = WidgetWeaverRuntime.isRunningInAppExtension

        let curvePath = buildCurveStrokePath(curvePoints: curvePoints)

        let clipRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(0.0, baselineY - rect.minY)
        )

        var strength = computeFuzzStrengthPerPoint(
            heights: heights,
            certainties01: certainties01.map { Double($0) },
            configuration: cfg
        )

        let wetEps = max(0.5 / max(1.0, Double(ds)), 0.0001)
        let wetMask = heights.map { Double($0) > wetEps }
        let distToWet = distanceToNearestTrue(wetMask)

        let samplesPerPx = Double(heights.count) / max(1.0, Double(rect.width))
        let edgeWindowSamples = max(1, Int(round(cfg.fuzzEdgeWindowPx * samplesPerPx)))

        if distToWet.count == strength.count {
            for i in 0..<strength.count where distToWet[i] > edgeWindowSamples {
                strength[i] = 0.0
            }
        }

        let tailMinutes = max(0.0, cfg.fuzzTailMinutes)
        if tailMinutes > 0.01 {
            let tailSamples = max(1, Int(round(tailMinutes / 60.0 * Double(strength.count))))
            if tailSamples > 0 {
                for i in 1..<strength.count {
                    let prevWet = wetMask[i - 1]
                    let curWet = wetMask[i]
                    if prevWet != curWet {
                        let start = max(0, i - tailSamples)
                        let end = min(strength.count - 1, i + tailSamples)
                        for j in start...end {
                            let d = Double(abs(j - i))
                            let t = 1.0 - clamp01(d / Double(tailSamples))
                            strength[j] *= (1.0 + 0.65 * pow(t, 1.25))
                        }
                    }
                }
            }
        }

        let maxH = max(0.0001, Double(heights.max() ?? 0.0))
        let invMaxH = 1.0 / maxH

        var maxSlope: Double = 0.0
        let dx = max(1e-6, Double(rect.width) / Double(max(1, heights.count - 1)))
        var slopes = Array(repeating: 0.0, count: heights.count)

        for i in 0..<heights.count {
            let a = Double(heights[max(0, i - 1)])
            let b = Double(heights[min(heights.count - 1, i + 1)])
            let s = abs(b - a) / (2.0 * dx)
            slopes[i] = s
            maxSlope = max(maxSlope, s)
        }

        for i in 0..<strength.count {
            let hn = clamp01(Double(heights[i]) * invMaxH)
            let low = pow(max(0.0, 1.0 - hn), max(0.05, cfg.fuzzLowHeightPower))
            let heightFade = 0.12 + 0.88 * low
            strength[i] *= heightFade

            if maxSlope > 0.000001 {
                let sn = clamp01(slopes[i] / maxSlope)
                let slopeFactor = 0.22 + 0.78 * pow(sn, 0.65)
                strength[i] *= slopeFactor
            }
        }

        let maxStrength = strength.max() ?? 0.0
        guard maxStrength > 0.00001 else { return }

        var maxAlpha = clamp01(cfg.fuzzMaxOpacity)
        maxAlpha *= max(0.0, cfg.fuzzSpeckStrength)

        let maxStopCap = isExtension ? 18 : 64
        let stopCount = max(8, min(cfg.fuzzTextureGradientStops, maxStopCap))

        // Important: no cyan. Use core colours so the body appears to dissolve into itself.
        let dissipationColor = cfg.coreBodyColor

        let colourGradient = makeAlphaGradient(
            baseColor: dissipationColor,
            strength: strength,
            maxAlpha: maxAlpha,
            stops: stopCount
        )

        let maskGradient = makeAlphaGradient(
            baseColor: Color.white,
            strength: strength,
            maxAlpha: 1.0,
            stops: stopCount
        )

        let tilePx = max(32, min(cfg.fuzzTextureTilePixels, isExtension ? 256 : 512))
        let noiseTileScale = fuzzNoiseTileScale(desiredTilePixels: tilePx)

        let baseSeed = RainSurfacePRNG.combine(
            cfg.noiseSeed,
            UInt64(curvePoints.count &* 977) &+ 0xA5A5_A5A5_A5A5_A5A5
        )

        // Asset-backed noise (sparse + dense variants). Procedural noise removed to keep widget renders cheap.
        let dustNoise = fuzzNoiseImage(preferred: .sparse)
        let erodeNoise = fuzzNoiseImage(preferred: .dense)

        if cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.0001 {
            applyEdgeErosion(
                in: &context,
                rect: rect,
                clipRect: clipRect,
                corePath: corePath,
                curvePath: curvePath,
                bandHalfWidth: bandHalfWidth,
                maskGradient: maskGradient,
                noiseImage: erodeNoise,
                noiseTileScale: noiseTileScale,
                configuration: cfg,
                seed: RainSurfacePRNG.combine(baseSeed, 0xBEE1_BEE1_BEE1_BEE1)
            )
        }

        // In the widget extension, keep to erosion only to avoid the system placeholder.
        if !isExtension {
            drawOuterDust(
                in: &context,
                rect: rect,
                clipRect: clipRect,
                corePath: corePath,
                curvePath: curvePath,
                bandHalfWidth: bandHalfWidth,
                colourGradient: colourGradient,
                noiseImage: dustNoise,
                noiseTileScale: noiseTileScale,
                configuration: cfg,
                seed: RainSurfacePRNG.combine(baseSeed, 0xD005_700D_D005_700D)
            )

            if cfg.fuzzHazeStrength > 0.0001 {
                let hazeAlpha = clamp01(cfg.fuzzHazeStrength) * clamp01(maxStrength) * maxAlpha
                if hazeAlpha > 0.00001 {
                    context.blendMode = .normal
                    context.stroke(
                        curvePath,
                        with: .color(dissipationColor.opacity(hazeAlpha)),
                        lineWidth: bandHalfWidth * 2.0 * CGFloat(max(0.10, cfg.fuzzHazeStrokeWidthFactor))
                    )
                    context.blendMode = .normal
                }
            }
        }
    }

    static func applyEdgeErosion(
        in context: inout GraphicsContext,
        rect: CGRect,
        clipRect: CGRect,
        corePath: Path,
        curvePath: Path,
        bandHalfWidth: CGFloat,
        maskGradient: Gradient,
        noiseImage: SwiftUI.Image?,
        noiseTileScale: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        seed: UInt64
    ) {
        let strength = clamp01(cfg.fuzzErodeStrength)
        guard strength > 0.0001 else { return }

        let narrowMul = max(0.10, cfg.fuzzErodeStrokeWidthFactor)
        let wideMul = max(narrowMul * 2.25, narrowMul + 0.55)

        // Wide smooth subtraction (broad fade into the slope)
        context.blendMode = .destinationOut
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))
            layer.clip(to: corePath)

            let wideStroke = curvePath.strokedPath(
                StrokeStyle(lineWidth: bandHalfWidth * 2.0 * CGFloat(wideMul), lineCap: .round, lineJoin: .round)
            )
            let wideGrad = scaledGradient(maskGradient, alphaMultiplier: 0.30 * strength)

            layer.fill(
                wideStroke,
                with: .linearGradient(
                    wideGrad,
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )
        }
        context.blendMode = .normal

        // Narrow grain subtraction (speckle)
        context.blendMode = .destinationOut
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))
            layer.clip(to: corePath)

            let narrowStroke = curvePath.strokedPath(
                StrokeStyle(lineWidth: bandHalfWidth * 2.0 * CGFloat(narrowMul), lineCap: .round, lineJoin: .round)
            )
            let narrowGrad = scaledGradient(maskGradient, alphaMultiplier: 0.70 * strength)

            layer.fill(
                narrowStroke,
                with: .linearGradient(
                    narrowGrad,
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )

            if let noiseImage {
                var prng = RainSurfacePRNG(seed: seed)
                let ox = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.45
                let oy = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.45

                let origin = CGPoint(x: rect.minX + ox, y: rect.minY + oy)
                let shading = GraphicsContext.Shading.tiledImage(
                    noiseImage,
                    origin: origin,
                    sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    scale: noiseTileScale
                )

                layer.blendMode = .destinationIn
                layer.fill(Path(rect), with: shading)
                layer.blendMode = .normal
            }
        }
        context.blendMode = .normal
    }

    static func drawOuterDust(
        in context: inout GraphicsContext,
        rect: CGRect,
        clipRect: CGRect,
        corePath: Path,
        curvePath: Path,
        bandHalfWidth: CGFloat,
        colourGradient: Gradient,
        noiseImage: SwiftUI.Image?,
        noiseTileScale: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        seed: UInt64
    ) {
        let innerW = max(0.10, cfg.fuzzTextureInnerBandMultiplier)
        let outerW = max(innerW, cfg.fuzzTextureOuterBandMultiplier)

        let innerA = max(0.0, cfg.fuzzTextureInnerOpacityMultiplier)
        let outerA = max(0.0, cfg.fuzzTextureOuterOpacityMultiplier)

        let tMid = 0.55
        let widthMuls: [Double] = [
            innerW,
            lerp(innerW, outerW, tMid),
            outerW,
        ]
        let alphaMuls: [Double] = [
            innerA,
            lerp(innerA, outerA, tMid),
            outerA,
        ]

        context.blendMode = .normal
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))

            for i in 0..<widthMuls.count {
                let wMul = widthMuls[i]
                let aMul = alphaMuls[i]
                if aMul <= 0.00001 { continue }

                let stroke = curvePath.strokedPath(
                    StrokeStyle(lineWidth: bandHalfWidth * 2.0 * CGFloat(wMul), lineCap: .round, lineJoin: .round)
                )

                let g = scaledGradient(colourGradient, alphaMultiplier: aMul)

                layer.fill(
                    stroke,
                    with: .linearGradient(
                        g,
                        startPoint: CGPoint(x: rect.minX, y: rect.midY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                    )
                )
            }

            if let noiseImage {
                var prng = RainSurfacePRNG(seed: seed)
                let ox = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.65
                let oy = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.65 + bandHalfWidth * 0.20

                let origin = CGPoint(x: rect.minX + ox, y: rect.minY + oy)
                let shading = GraphicsContext.Shading.tiledImage(
                    noiseImage,
                    origin: origin,
                    sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    scale: noiseTileScale
                )

                layer.blendMode = .destinationIn
                layer.fill(Path(rect), with: shading)
                layer.blendMode = .normal
            }

            // Keep only outside the core body.
            layer.blendMode = .destinationOut
            layer.fill(corePath, with: .color(Color.white))
            layer.blendMode = .normal
        }
        context.blendMode = .normal
    }
}

// MARK: - Geometry helpers

private extension RainForecastSurfaceRenderer {
    static func computeBandHalfWidthPoints(
        rect: CGRect,
        displayScale ds: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> CGFloat {
        let minDim = min(rect.height * 0.28, rect.width * 0.10)
        let frac = max(0.0, cfg.fuzzWidthFraction)
        var widthPt = minDim * CGFloat(frac)

        let clampPx = cfg.fuzzWidthPixelsClamp
        let loPx = max(0.0, min(clampPx.lowerBound, clampPx.upperBound))
        let hiPx = max(loPx, clampPx.upperBound)

        let minPt = CGFloat(loPx) / max(1.0, ds)
        let maxPt = CGFloat(hiPx) / max(1.0, ds)
        widthPt = max(minPt, min(widthPt, maxPt))

        return widthPt
    }

    static func makeCurvePoints(rect: CGRect, baselineY: CGFloat, heights: [CGFloat]) -> [CGPoint] {
        let n = max(2, heights.count)
        let dx = rect.width / CGFloat(max(1, n - 1))

        var pts: [CGPoint] = []
        pts.reserveCapacity(n)

        for i in 0..<n {
            let x = rect.minX + CGFloat(i) * dx
            let y = baselineY - heights[i]
            pts.append(CGPoint(x: x, y: y))
        }

        return pts
    }

    static func buildCurveStrokePath(curvePoints: [CGPoint]) -> Path {
        var p = Path()
        guard let first = curvePoints.first else { return p }
        p.move(to: first)
        for pt in curvePoints.dropFirst() {
            p.addLine(to: pt)
        }
        return p
    }

    static func buildCoreFillPath(rect: CGRect, baselineY: CGFloat, curvePoints: [CGPoint]) -> Path {
        var p = Path()
        guard let first = curvePoints.first, let last = curvePoints.last else { return p }

        p.move(to: CGPoint(x: first.x, y: baselineY))
        p.addLine(to: first)
        for pt in curvePoints.dropFirst() { p.addLine(to: pt) }
        p.addLine(to: CGPoint(x: last.x, y: baselineY))
        p.closeSubpath()

        return p
    }
}

// MARK: - Data shaping helpers

private extension RainForecastSurfaceRenderer {
    static func fillMissingLinearHoldEnds(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return values }
        var out = values

        let firstFinite = out.firstIndex(where: { $0.isFinite })
        if firstFinite == nil {
            return Array(repeating: 0.0, count: out.count)
        }

        if let first = firstFinite {
            let v = out[first]
            for i in 0..<first { out[i] = v }
        }

        var lastFinite: Int? = nil
        for i in 0..<out.count {
            let v = out[i]
            guard v.isFinite else { continue }
            if let last = lastFinite {
                let gap = i - last
                if gap > 1 {
                    let a = out[last]
                    let b = v
                    for k in 1..<gap {
                        let t = Double(k) / Double(gap)
                        out[last + k] = a + (b - a) * t
                    }
                }
            }
            lastFinite = i
        }

        if let last = lastFinite {
            let v = out[last]
            if last + 1 < out.count {
                for i in (last + 1)..<out.count { out[i] = v }
            }
        }

        for i in 0..<out.count {
            if !out[i].isFinite { out[i] = 0.0 }
            if out[i] < 0.0 { out[i] = 0.0 }
        }

        return out
    }

    static func robustReferenceMaxMMPerHour(values: [Double], defaultMax: Double, percentile: Double) -> Double {
        let finite = values.filter { $0.isFinite && $0 >= 0.0 }
        guard !finite.isEmpty else { return max(0.001, defaultMax) }
        let sorted = finite.sorted()
        let p = clamp01(percentile)
        let idx = Int(round(p * Double(max(0, sorted.count - 1))))
        let v = sorted[min(sorted.count - 1, max(0, idx))]
        return max(0.001, max(defaultMax, v))
    }

    static func applyEdgeEasing(values: [CGFloat], fraction: Double, power: Double) -> [CGFloat] {
        guard values.count >= 2 else { return values }
        let f = clamp01(fraction)
        guard f > 0.0001 else { return values }

        var out = values
        let n = out.count

        for i in 0..<n {
            let t = Double(i) / Double(max(1, n - 1))
            var m = 1.0
            if t < f {
                m = pow(clamp01(t / f), max(0.01, power))
            } else if t > 1.0 - f {
                m = pow(clamp01((1.0 - t) / f), max(0.01, power))
            }
            out[i] = out[i] * CGFloat(m)
        }

        return out
    }

    static func denseSampleCount(sourceCount: Int, rectWidthPoints: Double, displayScale: Double, maxDense: Int) -> Int {
        let px = max(1.0, rectWidthPoints * max(1.0, displayScale))
        let target = Int(round(px * 0.90))
        return max(sourceCount, min(maxDense, max(120, target)))
    }

    static func makeMinuteCertainties(sourceCount: Int, certainties01: [Double]) -> [CGFloat] {
        guard sourceCount > 0 else { return [] }

        if certainties01.count == sourceCount {
            return certainties01.map { CGFloat(clamp01($0)) }
        }

        if certainties01.isEmpty {
            return Array(repeating: CGFloat(1.0), count: sourceCount)
        }

        let clamped: [CGFloat] = certainties01.map { CGFloat(clamp01($0)) }
        return resampleLinear(clamped, toCount: sourceCount)
    }

    static func resampleLinear(_ values: [CGFloat], toCount n: Int) -> [CGFloat] {
        guard n > 0 else { return [] }
        guard values.count >= 2 else { return Array(repeating: values.first ?? 0.0, count: n) }
        if values.count == n { return values }

        var out: [CGFloat] = []
        out.reserveCapacity(n)

        let m = values.count
        for i in 0..<n {
            let t = Double(i) / Double(max(1, n - 1))
            let x = t * Double(m - 1)
            let i0 = Int(floor(x))
            let i1 = min(m - 1, i0 + 1)
            let u = x - Double(i0)
            let a = Double(values[i0])
            let b = Double(values[i1])
            out.append(CGFloat(a + (b - a) * u))
        }

        return out
    }

    static func smooth(values: [CGFloat], radius: Int) -> [CGFloat] {
        guard values.count >= 3, radius > 0 else { return values }
        let r = min(radius, max(1, values.count / 12))

        var out = values
        for i in 0..<values.count {
            let a = max(0, i - r)
            let b = min(values.count - 1, i + r)
            var sum: CGFloat = 0.0
            var count: CGFloat = 0.0
            for j in a...b {
                sum += values[j]
                count += 1.0
            }
            out[i] = sum / max(1.0, count)
        }

        return out
    }
}

// MARK: - Strength shaping + gradients

private extension RainForecastSurfaceRenderer {
    static func computeFuzzStrengthPerPoint(
        heights: [CGFloat],
        certainties01: [Double],
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> [Double] {
        let n = min(heights.count, certainties01.count)
        guard n > 0 else { return [] }

        let maxH = max(0.0001, Double(heights.prefix(n).max() ?? 0.0))
        let invMaxH = 1.0 / maxH

        let thr = clamp01(cfg.fuzzChanceThreshold)
        let trans = max(0.0001, cfg.fuzzChanceTransition)
        let expo = max(0.05, cfg.fuzzChanceExponent)

        let floorBase = clamp01(cfg.fuzzChanceFloor)
        let minStrength = clamp01(cfg.fuzzChanceMinStrength)

        let lowPow = max(0.05, cfg.fuzzLowHeightPower)
        let lowBoost = max(0.0, cfg.fuzzLowHeightBoost)

        var out = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            let c = clamp01(certainties01[i])
            var t = (thr - c) / trans
            t = clamp01(t)
            t = pow(t, expo)

            var s = floorBase + (1.0 - floorBase) * t
            s = max(s, minStrength)

            let hn = clamp01(Double(heights[i]) * invMaxH)
            let low = pow(max(0.0, 1.0 - hn), lowPow)
            s *= (1.0 + lowBoost * low)

            out[i] = clamp01(s)
        }

        return out
    }

    static func makeAlphaGradient(baseColor: Color, strength: [Double], maxAlpha: Double, stops: Int) -> Gradient {
        let n = max(1, strength.count)
        let stopCount = max(2, stops)

        var out: [Gradient.Stop] = []
        out.reserveCapacity(stopCount)

        for i in 0..<stopCount {
            let t = Double(i) / Double(stopCount - 1)
            let idx = min(n - 1, max(0, Int(round(t * Double(n - 1)))))
            let a = clamp01(strength[idx]) * max(0.0, maxAlpha)
            out.append(Gradient.Stop(color: baseColor.opacity(a), location: t))
        }

        return Gradient(stops: out)
    }

    static func scaledGradient(_ g: Gradient, alphaMultiplier: Double) -> Gradient {
        let m = max(0.0, alphaMultiplier)
        if m == 1.0 { return g }

        let scaledStops: [Gradient.Stop] = g.stops.map { s in
            Gradient.Stop(color: s.color.opacity(m), location: s.location)
        }
        return Gradient(stops: scaledStops)
    }
}

// MARK: - Distance transform

private extension RainForecastSurfaceRenderer {
    static func distanceToNearestTrue(_ mask: [Bool]) -> [Int] {
        guard !mask.isEmpty else { return [] }
        let n = mask.count
        let inf = n + 10
        var dist = Array(repeating: inf, count: n)

        var lastTrue = -inf
        for i in 0..<n {
            if mask[i] { lastTrue = i }
            dist[i] = i - lastTrue
        }

        lastTrue = inf * 2
        for i in stride(from: n - 1, through: 0, by: -1) {
            if mask[i] { lastTrue = i }
            dist[i] = min(dist[i], lastTrue - i)
        }

        return dist
    }
}

// MARK: - Fuzz noise assets

private extension RainForecastSurfaceRenderer {
    enum FuzzNoiseVariant {
        case sparse
        case normal
        case dense

        var assetName: String {
            switch self {
            case .sparse: return "RainFuzzNoise_Sparse"
            case .normal: return "RainFuzzNoise"
            case .dense: return "RainFuzzNoise_Dense"
            }
        }
    }

    static func fuzzNoiseImage(preferred: FuzzNoiseVariant) -> SwiftUI.Image? {
        #if canImport(UIKit)
        if UIKit.UIImage(named: preferred.assetName) != nil { return SwiftUI.Image(preferred.assetName) }
        if UIKit.UIImage(named: FuzzNoiseVariant.normal.assetName) != nil { return SwiftUI.Image(FuzzNoiseVariant.normal.assetName) }
        if UIKit.UIImage(named: FuzzNoiseVariant.sparse.assetName) != nil { return SwiftUI.Image(FuzzNoiseVariant.sparse.assetName) }
        if UIKit.UIImage(named: FuzzNoiseVariant.dense.assetName) != nil { return SwiftUI.Image(FuzzNoiseVariant.dense.assetName) }
        return nil
        #else
        return SwiftUI.Image(preferred.assetName)
        #endif
    }

    static func fuzzNoiseTileScale(desiredTilePixels: Int) -> CGFloat {
        // Assumes the provided assets are authored at 256×256.
        // Scale maps the requested tile pixel size onto the authored tile.
        let authored: Double = 256.0
        let desired = Double(max(16, min(desiredTilePixels, 1024)))
        let s = desired / authored
        return CGFloat(max(0.10, min(s, 6.0)))
    }
}

// MARK: - Maths

private extension RainForecastSurfaceRenderer {
    static func clamp01(_ x: Double) -> Double { max(0.0, min(1.0, x)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * clamp01(t) }
}

// MARK: - Colour blend helper

private extension Color {
    static func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        #if canImport(UIKit)
        let ta = RainForecastSurfaceRenderer.clamp01(t)
        let ua = UIKit.UIColor(a)
        let ub = UIKit.UIColor(b)

        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0

        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)

        let r = ar + (br - ar) * CGFloat(ta)
        let g = ag + (bg - ag) * CGFloat(ta)
        let bV = ab + (bb - ab) * CGFloat(ta)
        let aOut = aa + (ba - aa) * CGFloat(ta)

        return Color(red: Double(r), green: Double(g), blue: Double(bV)).opacity(Double(aOut))
        #else
        return a
        #endif
    }
}
