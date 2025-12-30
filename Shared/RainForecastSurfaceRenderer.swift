//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Rebuilt renderer for the nowcast “rain surface” chart.
//  Goals:
//  - Pure black background (handled by caller, but renderer assumes it)
//  - Soft blue core mound
//  - Fuzzy, speckled uncertainty band (cheap enough for WidgetKit)
//  - Hard clamps + graceful degradation to avoid WidgetKit placeholder fallbacks
//

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

        // Always avoid blur in WidgetKit paths (big offscreen cost).
        if isExtension {
            cfg.fuzzHazeBlurFractionOfBand = 0.0
            cfg.glossEnabled = false
            cfg.glintEnabled = false
        }

        // Hard caps (Regression A guardrails).
        cfg.maxDenseSamples = max(120, min(cfg.maxDenseSamples, isExtension ? 620 : 900))
        cfg.fuzzSpeckleBudget = max(0, min(cfg.fuzzSpeckleBudget, isExtension ? 1800 : 4200))

        let chartRect = rect

        let baselineY = chartRect.minY
            + chartRect.height * CGFloat(Self.clamp01(cfg.baselineFractionFromTop))
            + CGFloat(cfg.baselineOffsetPixels) / max(1.0, ds)

        // No data: baseline only.
        guard !intensities.isEmpty else {
            Self.drawBaseline(in: &context, chartRect: chartRect, baselineY: baselineY, configuration: cfg, displayScale: ds)
            return
        }

        // Fill missing (NaN/±inf) so the silhouette is coherent.
        let filledIntensities = Self.fillMissingLinearHoldEnds(intensities)

        // Scale intensity -> height using robust max so a single spike doesn’t flatten everything.
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

        // Rounded silhouette.
        let smoothRadius = max(1, min(5, Int(round(Double(denseCount) / 180.0))))
        denseHeights = Self.smooth(denseHeights, windowRadius: smoothRadius, passes: 2)

        let curvePoints = Self.makeCurvePoints(rect: chartRect, baselineY: baselineY, heights: denseHeights)

        // Core mound.
        let corePath = Self.buildCoreFillPath(rect: chartRect, baselineY: baselineY, curvePoints: curvePoints)
        Self.drawCore(in: &context, corePath: corePath, rect: chartRect, baselineY: baselineY, configuration: cfg)

        // Rim highlight (subtle).
        Self.drawRim(in: &context, rect: chartRect, curvePoints: curvePoints, displayScale: ds, configuration: cfg)

        // Fuzzy uncertainty band.
        if cfg.fuzzEnabled && cfg.canEnableFuzz {
            let bandWidthPt = Self.computeBandWidthPt(rect: chartRect, displayScale: ds, cfg: cfg)
            if bandWidthPt > onePx * 2.0 {
                Self.drawFuzz(
                    in: &context,
                    rect: chartRect,
                    baselineY: baselineY,
                    curvePoints: curvePoints,
                    heights: denseHeights,
                    certainties: denseCertainties,
                    bandWidthPt: bandWidthPt,
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

        // mid mixes body->top using coreTopMix
        let mid = Color.blend(a: body, b: top, t: cfg.coreTopMix)

        let gradient = Gradient(stops: [
            .init(color: top, location: 0.0),
            .init(color: mid, location: 0.28),
            .init(color: body, location: 1.0)
        ])

        context.fill(
            corePath,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                endPoint: CGPoint(x: rect.midX, y: baselineY)
            )
        )

        // Optional gentle gloss (kept off by default).
        if cfg.glossEnabled && cfg.glossMaxOpacity > 0.0001 {
            let opacity = CGFloat(clamp01(cfg.glossMaxOpacity))
            let glossColor = Color.white.opacity(Double(opacity))
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

        // Subtle darkening at extreme ends (mock tail softness).
        if cfg.coreFadeFraction > 0.0001 {
            let fade = CGFloat(clamp01(cfg.coreFadeFraction))
            let w = max(1.0, rect.width)
            let fadeW = w * fade

            let g = Gradient(stops: [
                .init(color: Color.black.opacity(0.0), location: 0.0),
                .init(color: Color.black.opacity(0.11), location: Double(clamp01(Double(fadeW / w)))),
                .init(color: Color.black.opacity(0.11), location: Double(clamp01(Double(1.0 - fadeW / w)))),
                .init(color: Color.black.opacity(0.0), location: 1.0)
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

        // Outer rim
        if outerOpacity > 0.0001, cfg.rimOuterWidthPixels > 0.01 {
            let w = max(onePx, CGFloat(cfg.rimOuterWidthPixels) / ds)
            context.blendMode = .screen
            context.stroke(curvePath, with: .color(cfg.rimColor.opacity(outerOpacity)), lineWidth: w)
            context.blendMode = .normal
        }

        // Inner rim
        if innerOpacity > 0.0001, cfg.rimInnerWidthPixels > 0.01 {
            let w = max(onePx, CGFloat(cfg.rimInnerWidthPixels) / ds)
            context.blendMode = .screen
            context.stroke(curvePath, with: .color(cfg.rimColor.opacity(innerOpacity)), lineWidth: w)
            context.blendMode = .normal
        }
    }
}

// MARK: - Fuzz

private extension RainForecastSurfaceRenderer {

    static func drawFuzz(
        in context: inout GraphicsContext,
        rect: CGRect,
        baselineY: CGFloat,
        curvePoints: [CGPoint],
        heights: [CGFloat],
        certainties: [Double],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        isExtension: Bool
    ) {
        guard curvePoints.count >= 2, curvePoints.count == heights.count, certainties.count == heights.count else { return }

        let ds = max(1.0, displayScale)
        let onePx: CGFloat = 1.0 / ds
        let wetEps: CGFloat = max(onePx * 0.55, 0.000_1)

        let (tangents, normals) = computeTangentsAndNormals(curvePoints: curvePoints)

        // Strength per sample (0...1) representing uncertainty.
        var strength = computeFuzzStrengthPerPoint(
            heights: heights,
            certainties: certainties,
            wetEps: wetEps,
            rect: rect,
            displayScale: ds,
            cfg: cfg
        )

        // Kill far-from-wet zones so baseline doesn’t get peppered.
        let samplesPerPx = Double(max(1, curvePoints.count - 1)) / Double(max(1.0, rect.width * ds))
        let edgeWindowSamples = max(1, Int(round(max(0.0, cfg.fuzzEdgeWindowPx) * samplesPerPx)))

        let wetMask = heights.map { $0 > wetEps }
        let distToWet = distanceToNearestTrue(wetMask)

        for i in 0..<strength.count {
            if distToWet[i] > edgeWindowSamples {
                strength[i] = 0.0
            }
        }

        // Boost around wet↔dry transitions.
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

        // Budget (hard clamped).
        let density = max(0.0, cfg.fuzzDensity)
        var budget = max(0, Int(round(Double(cfg.fuzzSpeckleBudget) * density)))

        // Additional clamp: keep WidgetKit safe even if cfg is cranked.
        budget = min(budget, isExtension ? 1400 : 2600)
        guard budget > 0 else { return }

        // Optional cheap “haze” stroke (no blur).
        if cfg.fuzzHazeStrength > 0.0001 {
            let hazeAlpha = clamp01(cfg.fuzzHazeStrength) * clamp01(cfg.fuzzMaxOpacity) * 0.45
            if hazeAlpha > 0.0001 {
                let strokeW = max(onePx, bandWidthPt * CGFloat(max(0.10, cfg.fuzzHazeStrokeWidthFactor)))
                let hazePath = buildCurveStrokePath(curvePoints: curvePoints)
                context.blendMode = .screen
                context.stroke(hazePath, with: .color(cfg.fuzzColor.opacity(hazeAlpha)), lineWidth: strokeW)
                context.blendMode = .normal
            }
        }

        // Weights for distributing particles along the curve.
        var weights = Array(repeating: 0.0, count: strength.count)
        var totalW = 0.0
        for i in 0..<strength.count {
            // Slight exponent to push particles into higher-uncertainty regions.
            let w = pow(Double(strength[i]), 1.25)
            weights[i] = w
            totalW += w
        }
        guard totalW > 0.0 else { return }

        // Allocate counts per sample (O(n), deterministic).
        let counts = allocateCounts(budget: budget, weights: weights, totalWeight: totalW)

        // Particle parameters.
        let maxAlpha = clamp01(cfg.fuzzMaxOpacity) * max(0.0, cfg.fuzzSpeckStrength)
        guard maxAlpha > 0.0001 else { return }

        let insideFraction = clamp01(cfg.fuzzInsideSpeckleFraction)
        let insideWidthFactor = max(0.0, cfg.fuzzInsideWidthFactor)
        let insideOpacityFactor = max(0.0, cfg.fuzzInsideOpacityFactor)

        let distPowOut = max(0.10, cfg.fuzzDistancePowerOutside)
        let distPowIn = max(0.10, cfg.fuzzDistancePowerInside)

        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        let rPx = cfg.fuzzSpeckleRadiusPixels
        let minR = max(0.05, rPx.lowerBound) / Double(ds)
        let maxR = max(minR, rPx.upperBound) / Double(ds)

        // Quantised radii (reduces draw calls massively).
        let radiusBucketCount = isExtension ? 4 : 5
        let alphaBucketCount = isExtension ? 7 : 8

        let radii = makeGeometricBuckets(min: minR, max: maxR, count: radiusBucketCount)

        let keyCount = radiusBucketCount * alphaBucketCount
        var paths = Array(repeating: Path(), count: keyCount)
        var bucketHitCount = Array(repeating: 0, count: keyCount)

        // Deterministic PRNG.
        let seed = RainSurfacePRNG.combine(
            cfg.noiseSeed,
            UInt64(curvePoints.count &* 9973) ^ UInt64(budget &* 31337)
        )
        var rng = RainSurfacePRNG(seed: seed)

        context.drawLayer { layer in
            layer.clip(to: Path(rect))

            for i in 0..<counts.count {
                let c = counts[i]
                if c <= 0 { continue }

                let s = Double(strength[i])
                if s <= 0.0001 { continue }

                let p0 = curvePoints[i]
                let n = normals[i]
                let t = tangents[i]

                for _ in 0..<c {
                    let isInside = (rng.nextFloat01() < insideFraction)
                    let sign: CGFloat = isInside ? -1.0 : 1.0

                    // Distance from curve.
                    let u = rng.nextFloat01()
                    let distNorm = isInside ? pow(u, distPowIn) : pow(u, distPowOut)
                    let width = isInside ? bandWidthPt * CGFloat(insideWidthFactor) : bandWidthPt
                    let signedDist = sign * width * CGFloat(distNorm)

                    // Tangential jitter (keeps the band “cloudy”).
                    let tanJ = CGFloat(rng.nextSignedFloat()) * bandWidthPt * CGFloat(tangentJitter) * 0.35

                    // Small grain jitter to break uniformity.
                    let grainJx = CGFloat(rng.nextSignedFloat()) * onePx * 0.9
                    let grainJy = CGFloat(rng.nextSignedFloat()) * onePx * 0.9

                    let x = p0.x + n.x * signedDist + t.x * tanJ + grainJx
                    let y = p0.y + n.y * signedDist + t.y * tanJ + grainJy

                    // Edge factor: particles closer to the curve boundary read “sharper”.
                    let edgeFactor = pow(max(0.0, 1.0 - Double(abs(signedDist) / max(onePx, width))), 0.55)

                    var a = maxAlpha * s * edgeFactor
                    if isInside {
                        a *= insideOpacityFactor
                    }
                    if a <= 0.00015 { continue }

                    // Radius biased small, then quantised to a small bucket set.
                    let rr = rng.nextFloat01()
                    let radius = sampleRadius(min: minR, max: maxR, u: rr)
                    let rIdx = bucketIndexForValue(radius, buckets: radii)

                    let alphaBucket = bucketIndexForAlpha(alpha: a, maxAlpha: maxAlpha, bucketCount: alphaBucketCount)
                    let key = rIdx * alphaBucketCount + alphaBucket

                    let bucketRadius = CGFloat(radii[rIdx])
                    let ellipse = CGRect(
                        x: x - bucketRadius,
                        y: y - bucketRadius,
                        width: bucketRadius * 2.0,
                        height: bucketRadius * 2.0
                    )

                    paths[key].addEllipse(in: ellipse)
                    bucketHitCount[key] += 1
                }
            }

            // Draw buckets: faint first, bright last; large first, small last.
            for alphaBucket in 0..<alphaBucketCount {
                let alpha = bucketAlphaValue(bucket: alphaBucket, maxAlpha: maxAlpha, bucketCount: alphaBucketCount)

                for rIdx in stride(from: radiusBucketCount - 1, through: 0, by: -1) {
                    let key = rIdx * alphaBucketCount + alphaBucket
                    if bucketHitCount[key] <= 0 { continue }

                    layer.fill(paths[key], with: .color(cfg.fuzzColor.opacity(alpha)))
                }
            }
        }
    }

    static func sampleRadius(min: Double, max: Double, u: Double) -> Double {
        // Bias strongly towards smaller speckles.
        let t = pow(clamp01(u), 1.85)
        return min + (max - min) * t
    }

    static func makeGeometricBuckets(min: Double, max: Double, count: Int) -> [Double] {
        let c = Swift.max(2, count)
        guard max > min else { return Array(repeating: min, count: c) }
        let ratio = pow(max / min, 1.0 / Double(c - 1))
        var out: [Double] = []
        out.reserveCapacity(c)
        var v = min
        for _ in 0..<c {
            out.append(v)
            v *= ratio
        }
        out[c - 1] = max
        return out
    }

    static func bucketIndexForValue(_ v: Double, buckets: [Double]) -> Int {
        // buckets are ascending.
        if v <= buckets.first ?? v { return 0 }
        if v >= buckets.last ?? v { return max(0, buckets.count - 1) }

        var lo = 0
        var hi = buckets.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if v < buckets[mid] { hi = mid } else { lo = mid }
        }

        // Choose nearest of lo/hi.
        let dlo = abs(v - buckets[lo])
        let dhi = abs(v - buckets[hi])
        return (dhi < dlo) ? hi : lo
    }

    static func bucketIndexForAlpha(alpha: Double, maxAlpha: Double, bucketCount: Int) -> Int {
        let bc = max(2, bucketCount)
        let t = clamp01(alpha / max(0.000_001, maxAlpha))
        let idx = Int(floor(t * Double(bc - 1) + 0.000_001))
        return max(0, min(bc - 1, idx))
    }

    static func bucketAlphaValue(bucket: Int, maxAlpha: Double, bucketCount: Int) -> Double {
        let bc = max(2, bucketCount)
        let b = max(0, min(bc - 1, bucket))
        // Middle of the bucket.
        let t = (Double(b) + 0.55) / Double(bc)
        return clamp01(maxAlpha) * t
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
                .init(color: cfg.baselineColor.opacity(0.0), location: 1.0)
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

    static func computeBandWidthPt(rect: CGRect, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
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

            if curvePoints.count >= 2 {
                var prev = curvePoints[0]
                for i in 1..<curvePoints.count {
                    let cur = curvePoints[i]
                    let mid = CGPoint(x: (prev.x + cur.x) * 0.5, y: (prev.y + cur.y) * 0.5)
                    p.addQuadCurve(to: mid, control: prev)
                    prev = cur
                }
                p.addQuadCurve(to: last, control: last)
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

            var prev = curvePoints[0]
            for i in 1..<curvePoints.count {
                let cur = curvePoints[i]
                let mid = CGPoint(x: (prev.x + cur.x) * 0.5, y: (prev.y + cur.y) * 0.5)
                p.addQuadCurve(to: mid, control: prev)
                prev = cur
            }
            p.addQuadCurve(to: curvePoints.last ?? prev, control: curvePoints.last ?? prev)
        }
    }

    static func computeTangentsAndNormals(curvePoints: [CGPoint]) -> (tangents: [CGPoint], normals: [CGPoint]) {
        let n = curvePoints.count
        guard n > 1 else {
            return ([CGPoint(x: 1, y: 0)], [CGPoint(x: 0, y: -1)])
        }

        var tangents = Array(repeating: CGPoint(x: 1, y: 0), count: n)
        var normals = Array(repeating: CGPoint(x: 0, y: -1), count: n)

        for i in 0..<n {
            let a = curvePoints[max(0, i - 1)]
            let b = curvePoints[min(n - 1, i + 1)]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let len = sqrt(dx * dx + dy * dy)

            if len > 0.000_01 {
                let tx = dx / len
                let ty = dy / len
                tangents[i] = CGPoint(x: tx, y: ty)

                // Normal points “outward” (upwards) for a typical y(x) graph.
                normals[i] = CGPoint(x: ty, y: -tx)
            } else {
                tangents[i] = CGPoint(x: 1, y: 0)
                normals[i] = CGPoint(x: 0, y: -1)
            }
        }

        return (tangents, normals)
    }
}

// MARK: - Fuzz strength shaping

private extension RainForecastSurfaceRenderer {

    static func computeFuzzStrengthPerPoint(
        heights: [CGFloat],
        certainties: [Double],
        wetEps: CGFloat,
        rect: CGRect,
        displayScale: CGFloat,
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

            // Lower chance => stronger fuzz.
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

        // Detect transitions.
        var transitionIndices: [Int] = []
        transitionIndices.reserveCapacity(8)

        for i in 1..<n {
            if wetMask[i] != wetMask[i - 1] {
                transitionIndices.append(i)
            }
        }

        if transitionIndices.isEmpty { return }

        for idx in transitionIndices {
            let lo = max(0, idx - tailSamples)
            let hi = min(n - 1, idx + tailSamples)

            for j in lo...hi {
                let d = abs(j - idx)
                let w = 1.0 - (Double(d) / Double(tailSamples))
                // Strong but bounded boost.
                let boost = 1.0 + 0.85 * max(0.0, w)
                strength[j] = clamp01(strength[j] * boost)
            }
        }
    }
}

// MARK: - Utilities

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

        // Linear fill gaps.
        var i = fi
        while i < li {
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

        return out.map { $0.isFinite ? max(0.0, $0) : 0.0 }
    }

    static func robustReferenceMaxMMPerHour(values: [Double], defaultMax: Double, percentile: Double) -> Double {
        let p = clamp01(percentile)
        var v = values.filter { $0.isFinite && $0 > 0.0 }
        if v.isEmpty {
            return max(0.25, defaultMax)
        }
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

        // Left.
        if k > 0 {
            for i in 0..<min(k, n) {
                let t = Double(i) / Double(max(1, k))
                let s = pow(clamp01(t), p)
                heights[i] *= CGFloat(s)
            }
            // Right.
            for j in 0..<min(k, n) {
                let i = n - 1 - j
                let t = Double(j) / Double(max(1, k))
                let s = pow(clamp01(t), p)
                heights[i] *= CGFloat(s)
            }
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
            let t = Double(i) * denom / Double(max(1, targetCount - 1))
            let i0 = Int(floor(t))
            let i1 = min(n - 1, i0 + 1)
            let frac = t - Double(i0)
            let a = Double(values[i0])
            let b = Double(values[i1])
            out.append(CGFloat(a + (b - a) * frac))
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
            let t = Double(i) * denom / Double(max(1, targetCount - 1))
            let i0 = Int(floor(t))
            let i1 = min(n - 1, i0 + 1)
            let frac = t - Double(i0)
            let a = values[i0]
            let b = values[i1]
            out.append(a + (b - a) * frac)
        }

        return out
    }

    static func smooth(_ values: [CGFloat], windowRadius: Int, passes: Int) -> [CGFloat] {
        let n = values.count
        if n <= 2 { return values }
        let r = max(0, windowRadius)
        if r == 0 { return values }

        var cur = values
        let p = max(1, passes)

        for _ in 0..<p {
            var next = cur
            for i in 0..<n {
                let lo = max(0, i - r)
                let hi = min(n - 1, i + r)
                var sum: CGFloat = 0.0
                let count = CGFloat(hi - lo + 1)
                for j in lo...hi {
                    sum += cur[j]
                }
                next[i] = sum / max(1.0, count)
            }
            cur = next
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
            let desired = Double(budget) * (weights[i] / totalWeight)
            carry += desired
            let target = Int(floor(carry + 1e-9))
            let c = max(0, target - used)
            out[i] = c
            used += c
        }

        // Fix rounding drift.
        if used < budget {
            out[n - 1] += (budget - used)
        } else if used > budget {
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

    static func clamp01(_ x: Double) -> Double {
        if x < 0.0 { return 0.0 }
        if x > 1.0 { return 1.0 }
        return x.isFinite ? x : 0.0
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
