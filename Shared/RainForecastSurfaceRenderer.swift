//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Rebuilt renderer for the nowcast “rain surface” chart.
//  Goal: match mockup look (pure black + soft blue core + heavy fuzzy uncertainty band).
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
        var cfg = configuration
        cfg.sourceMinuteCount = intensities.count

        let ds = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0
        guard rect.width > 1.0, rect.height > 1.0 else { return }

        let chartRect = rect
        let baselineY = chartRect.minY + chartRect.height * CGFloat(Self.clamp01(cfg.baselineFractionFromTop))

        // No data: baseline only.
        guard !intensities.isEmpty else {
            Self.drawBaseline(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                configuration: cfg,
                displayScale: ds
            )
            return
        }

        // Fill missing minutes (NaN/±inf) so the silhouette is coherent.
        let filledIntensities = Self.fillMissingLinearHoldEnds(intensities)

        // Scale intensity -> height using a robust max, so one spike doesn’t flatten everything else.
        let referenceMax = Self.robustReferenceMaxMMPerHour(
            values: filledIntensities,
            defaultMax: cfg.intensityReferenceMaxMMPerHour,
            percentile: cfg.robustMaxPercentile
        )

        let maxHeight = Self.maxUsableHeight(chartRect: chartRect, baselineY: baselineY, cfg: cfg)
        let sourceHeights = Self.makeMinuteHeights(
            intensities: filledIntensities,
            referenceMax: referenceMax,
            maxHeight: maxHeight,
            gamma: cfg.intensityGamma
        )

        var easedHeights = sourceHeights
        Self.applyEdgeEasing(
            to: &easedHeights,
            fraction: cfg.edgeEasingFraction,
            power: cfg.edgeEasingPower
        )

        let minuteCertainties = Self.makeMinuteCertainties(
            sourceCount: intensities.count,
            certainties01: certainties01
        )

        let targetCount = Self.denseSampleCount(
            chartRect: chartRect,
            displayScale: ds,
            sourceCount: easedHeights.count,
            cfg: cfg
        )

        var denseHeights = Self.resampleLinear(values: easedHeights, targetCount: targetCount)
        let denseCertainties = Self.resampleLinear(values: minuteCertainties, targetCount: targetCount)

        // Smooth the surface slightly (mockup has a very “rounded” silhouette).
        let smoothRadius = max(1, min(5, Int(round(Double(targetCount) / 180.0))))
        denseHeights = Self.smooth(denseHeights, windowRadius: smoothRadius, passes: 2)

        let curvePoints = Self.makeCurvePoints(
            chartRect: chartRect,
            baselineY: baselineY,
            heights: denseHeights
        )

        // Core mound fill.
        let corePath = Self.buildCoreFillPath(
            chartRect: chartRect,
            baselineY: baselineY,
            curvePoints: curvePoints
        )

        Self.drawCore(
            in: &context,
            corePath: corePath,
            chartRect: chartRect,
            baselineY: baselineY,
            configuration: cfg
        )

        // Fuzzy uncertainty band (key visual).
        if cfg.fuzzEnabled && cfg.canEnableFuzz {
            let bandWidthPt = Self.computeBandWidthPt(chartRect: chartRect, displayScale: ds, cfg: cfg)
            Self.drawFuzz(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                curvePoints: curvePoints,
                heights: denseHeights,
                certainties: denseCertainties,
                bandWidthPt: bandWidthPt,
                displayScale: ds,
                configuration: cfg
            )
        }

        // Baseline last so it stays crisp.
        Self.drawBaseline(
            in: &context,
            chartRect: chartRect,
            baselineY: baselineY,
            configuration: cfg,
            displayScale: ds
        )
    }
}

// MARK: - Core drawing

private extension RainForecastSurfaceRenderer {
    static func drawCore(
        in context: inout GraphicsContext,
        corePath: Path,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        let top = cfg.coreTopColor
        let body = cfg.coreBodyColor

        // Vertical gradient (mockup has bright top, deep blue base).
        let mid = Color.blend(a: top, b: body, t: 0.55)
        let g = Gradient(stops: [
            .init(color: top, location: 0.0),
            .init(color: mid, location: 0.30),
            .init(color: body, location: 1.0),
        ])

        context.fill(
            corePath,
            with: .linearGradient(
                g,
                startPoint: CGPoint(x: chartRect.midX, y: chartRect.minY),
                endPoint: CGPoint(x: chartRect.midX, y: baselineY)
            )
        )

        // Optional “gloss” highlight near the top ridge.
        if cfg.glossEnabled && cfg.glossMaxOpacity > 0.0001 {
            let opacity = CGFloat(clamp01(cfg.glossMaxOpacity))
            let glossColor = Color.white.opacity(Double(opacity))
            let glossY = chartRect.minY + (baselineY - chartRect.minY) * 0.26

            var p = Path()
            p.addRoundedRect(in: CGRect(x: chartRect.minX, y: glossY, width: chartRect.width, height: (baselineY - chartRect.minY) * 0.20), cornerSize: CGSize(width: 24, height: 24))
            context.blendMode = .screen
            context.fill(p, with: .color(glossColor.opacity(0.10)))
            context.blendMode = .normal
        }

        // Core fade (subtle edge softening).
        if cfg.coreFadeFraction > 0.0001 {
            let fade = CGFloat(clamp01(cfg.coreFadeFraction))
            let w = max(1.0, chartRect.width)
            let fadeW = w * fade

            let fadeGradient = Gradient(stops: [
                .init(color: Color.black.opacity(0.0), location: 0.0),
                .init(color: Color.black.opacity(0.10), location: Double(clamp01(Double(fadeW / w)))),
                .init(color: Color.black.opacity(0.10), location: Double(clamp01(Double(1.0 - fadeW / w)))),
                .init(color: Color.black.opacity(0.0), location: 1.0),
            ])

            // Slight darkening at extreme ends to match mockup’s soft tails.
            context.blendMode = .multiply
            context.fill(
                corePath,
                with: .linearGradient(
                    fadeGradient,
                    startPoint: CGPoint(x: chartRect.minX, y: chartRect.midY),
                    endPoint: CGPoint(x: chartRect.maxX, y: chartRect.midY)
                )
            )
            context.blendMode = .normal
        }
    }
}

// MARK: - Fuzz drawing

private extension RainForecastSurfaceRenderer {
    static func drawFuzz(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        curvePoints: [CGPoint],
        heights: [CGFloat],
        certainties: [Double],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        guard curvePoints.count >= 2, heights.count == curvePoints.count else { return }
        guard bandWidthPt > 0.001 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds
        let wetEps = max(onePx * 0.55, 0.000_1)

        // Normals/tangents along the curve for particle emission.
        let (tangents, normals) = computeTangentsAndNormals(curvePoints: curvePoints)

        // Strength per point (0...1) representing “uncertainty”.
        var strength = computeFuzzStrengthPerPoint(
            heights: heights,
            certainties: certainties,
            bandWidthPt: bandWidthPt,
            wetEps: wetEps,
            chartRect: chartRect,
            displayScale: ds,
            cfg: cfg
        )

        // Suppress far-away dry zones so the whole baseline doesn’t get peppered.
        let samplesPerPx = Double(max(1, curvePoints.count - 1)) / Double(max(1.0, chartRect.width * ds))
        let edgeWindowSamples = max(1, Int(round(max(0.0, cfg.fuzzEdgeWindowPx) * samplesPerPx)))

        let wetMask = heights.map { $0 > wetEps }
        let distToWet = distanceToNearestTrue(wetMask)
        for i in 0..<strength.count {
            if !wetMask[i] && distToWet[i] > edgeWindowSamples {
                strength[i] = 0.0
            }
        }

        // Tail boost around wet↔dry transitions (makes the fuzz “bloom” at the ends).
        if cfg.fuzzTailMinutes > 0.001 {
            applyTailBoost(
                strength: &strength,
                heights: heights,
                wetEps: wetEps,
                sourceMinuteCount: max(2, cfg.sourceMinuteCount),
                tailMinutes: cfg.fuzzTailMinutes
            )
        }

        let maxStrength = strength.max() ?? 0.0
        guard maxStrength > 0.0005 else { return }

        // Total particle budget.
        let density = max(0.0, cfg.fuzzDensity)
        let budget = max(0, Int(round(Double(cfg.fuzzSpeckleBudget) * density)))
        guard budget > 0 else { return }

        // Weighting for distributing particles along the curve.
        var weights: [Double] = Array(repeating: 0.0, count: strength.count)
        weights.withUnsafeMutableBufferPointer { buf in
            for i in 0..<buf.count {
                let s = Double(strength[i])
                // Square gives a nicer concentration without making it spiky.
                buf[i] = s * s
            }
        }
        let totalW = weights.reduce(0.0, +)
        guard totalW > 0.0 else { return }

        // Convert pixel-based radius range to points.
        let rPx = cfg.fuzzSpeckleRadiusPixels
        let minR = CGFloat(max(0.05, rPx.lowerBound)) / ds
        let maxR = CGFloat(max(minR, rPx.upperBound)) / ds

        let insideFraction = clamp01(cfg.fuzzInsideSpeckleFraction)
        let insideWidth = max(0.0, cfg.fuzzInsideWidthFactor)
        let insideOpacityFactor = max(0.0, cfg.fuzzInsideOpacityFactor)

        let distPowOut = max(0.10, cfg.fuzzDistancePowerOutside)
        let distPowIn = max(0.10, cfg.fuzzDistancePowerInside)
        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        let baseOpacity = clamp01(cfg.fuzzMaxOpacity) * max(0.0, cfg.fuzzSpeckStrength)

        // Deterministic PRNG.
        var rng = SplitMix64(seed: cfg.noiseSeed ^ UInt64(curvePoints.count &* 9973) ^ UInt64(budget &* 31337))

        // Clip to the view bounds so fuzz never bleeds outside the chart frame.
        context.drawLayer { layer in
            layer.clip(to: Path(chartRect))

            // Optional haze pass (kept very subtle; mockup is mostly particle-driven).
            if cfg.fuzzHazeStrength > 0.0001 {
                let hazeAlpha = clamp01(cfg.fuzzHazeStrength) * baseOpacity * 0.35
                let blur = max(0.0, bandWidthPt * CGFloat(max(0.0, cfg.fuzzHazeBlurFractionOfBand)))
                let strokeW = max(onePx, bandWidthPt * CGFloat(max(0.1, cfg.fuzzHazeStrokeWidthFactor)))
                let hazePath = buildCurveStrokePath(curvePoints: curvePoints)

                layer.drawLayer { hazeLayer in
                    if blur > 0.0001 {
                        hazeLayer.addFilter(.blur(radius: blur))
                    }
                    hazeLayer.stroke(
                        hazePath,
                        with: .color(cfg.fuzzColor.opacity(Double(hazeAlpha))),
                        lineWidth: strokeW
                    )
                }
            }

            // Allocate particle counts per point (stable rounding).
            let counts = allocateCounts(budget: budget, weights: weights, totalWeight: totalW)

            // Emit particles.
            for i in 0..<curvePoints.count {
                let count = counts[i]
                if count <= 0 { continue }

                let p0 = curvePoints[i]
                let t = tangents[i]
                let n = normals[i]
                let s = Double(strength[i])
                if s <= 0.00001 { continue }

                for _ in 0..<count {
                    let u = rng.nextDouble01()
                    let v = rng.nextDouble01()
                    let w = rng.nextDouble01()
                    let inside = u < insideFraction

                    let distUnit = inside
                        ? pow(v, distPowIn)
                        : pow(v, distPowOut)

                    let maxDist = inside
                        ? (bandWidthPt * CGFloat(insideWidth))
                        : bandWidthPt

                    let signedDist = inside ? (-maxDist * CGFloat(distUnit)) : (maxDist * CGFloat(distUnit))

                    let tanJ = CGFloat(rng.nextSignedDouble()) * bandWidthPt * CGFloat(tangentJitter) * 0.65

                    // Small “grain jitter” gives a less uniform cloud.
                    let grainJx = CGFloat(rng.nextSignedDouble()) * (maxR * 0.40)
                    let grainJy = CGFloat(rng.nextSignedDouble()) * (maxR * 0.40)

                    var x = p0.x + n.x * signedDist + t.x * tanJ + grainJx
                    var y = p0.y + n.y * signedDist + t.y * tanJ + grainJy

                    // Keep fuzz above the baseline line.
                    y = min(y, baselineY - onePx * 0.5)

                    // Radius.
                    let rr = minR + (maxR - minR) * CGFloat(w)

                    // Opacity falls with distance from the silhouette.
                    let distN = min(1.0, max(0.0, abs(signedDist) / max(0.0001, bandWidthPt)))
                    let falloff = pow(Double(1.0 - distN), 2.2)

                    var alpha = baseOpacity * s * falloff

                    if inside {
                        alpha *= insideOpacityFactor
                    }

                    // Random micro-variation.
                    alpha *= (0.75 + 0.50 * rng.nextDouble01())

                    if alpha <= 0.0005 { continue }

                    // Visible range clamp.
                    alpha = min(alpha, 0.85)

                    let rect = CGRect(x: x - rr, y: y - rr, width: rr * 2.0, height: rr * 2.0)
                    layer.fill(
                        Path(ellipseIn: rect),
                        with: .color(cfg.fuzzColor.opacity(alpha))
                    )
                }
            }
        }
    }

    static func computeFuzzStrengthPerPoint(
        heights: [CGFloat],
        certainties: [Double],
        bandWidthPt: CGFloat,
        wetEps: CGFloat,
        chartRect: CGRect,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) -> [CGFloat] {
        let n = heights.count
        guard n > 0 else { return [] }

        let maxH = heights.max() ?? 0.0
        let invMaxH: CGFloat = (maxH > 0.000_01) ? (1.0 / maxH) : 0.0

        // Smooth certainties slightly to avoid “striping”.
        let smoothRadius = max(0, min(3, Int(round(Double(n) / 220.0))))
        let smoothedCert = smoothDoubles(certainties, windowRadius: smoothRadius, passes: 1)

        let thr = clamp01(cfg.fuzzChanceThreshold)
        let trans = max(0.000_1, cfg.fuzzChanceTransition)
        let exp = max(0.10, cfg.fuzzChanceExponent)
        let floorBase = clamp01(cfg.fuzzChanceFloor)
        let minStrength = clamp01(cfg.fuzzChanceMinStrength)
        let lowHPow = max(0.10, cfg.fuzzLowHeightPower)
        let lowHBoost = max(0.0, cfg.fuzzLowHeightBoost)

        var out: [CGFloat] = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            let h = heights[i]
            let c = (i < smoothedCert.count) ? smoothedCert[i] : 1.0

            // Chance-driven term: fuzz grows as certainty drops below threshold.
            let t = (thr - c) / trans
            let x = clamp01(t)
            var s = pow(x, exp)

            // Floor provides a gentle “always there” fuzz near wet edges.
            s = max(s, floorBase)

            // Dry interior points get suppressed later by the edge-window logic.
            if h <= wetEps {
                s *= 0.55
            }

            // Low-height boost: strongest fuzz near tails/base (matches mockup).
            if invMaxH > 0.0 {
                let hn = clamp01(Double(h * invMaxH))
                let low = pow(1.0 - hn, lowHPow)
                s *= (1.0 + lowHBoost * low)
            }

            s = max(s, minStrength)
            out[i] = CGFloat(clamp01(s))
        }

        return out
    }
}

// MARK: - Geometry + helpers

private extension RainForecastSurfaceRenderer {
    static func maxUsableHeight(chartRect: CGRect, baselineY: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let topY = chartRect.minY + chartRect.height * CGFloat(clamp01(cfg.topHeadroomFraction))
        let available = max(0.0, baselineY - topY)
        return available * CGFloat(clamp01(cfg.typicalPeakFraction))
    }

    static func makeMinuteHeights(
        intensities: [Double],
        referenceMax: Double,
        maxHeight: CGFloat,
        gamma: Double
    ) -> [CGFloat] {
        guard !intensities.isEmpty else { return [] }
        let ref = max(0.000_001, referenceMax)
        let g = max(0.10, gamma)

        // Gamma is applied directly (gamma < 1 lifts mid-tones, gamma > 1 compresses them).
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
        // Resample to sourceCount.
        return resampleLinear(values: certainties01.map { clamp01($0) }, targetCount: sourceCount)
    }

    static func denseSampleCount(
        chartRect: CGRect,
        displayScale: CGFloat,
        sourceCount: Int,
        cfg: RainForecastSurfaceConfiguration
    ) -> Int {
        let wPx = Double(max(1.0, chartRect.width * displayScale))
        let desired = max(sourceCount, Int(wPx * 1.85))
        return max(2, min(cfg.maxDenseSamples, desired))
    }

    static func makeCurvePoints(chartRect: CGRect, baselineY: CGFloat, heights: [CGFloat]) -> [CGPoint] {
        let n = heights.count
        guard n > 0 else { return [] }
        let denom = CGFloat(max(1, n - 1))
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let t = CGFloat(i) / denom
            let x = chartRect.minX + chartRect.width * t
            let y = baselineY - max(0.0, heights[i].isFinite ? heights[i] : 0.0)
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }

    static func buildCoreFillPath(chartRect: CGRect, baselineY: CGFloat, curvePoints: [CGPoint]) -> Path {
        guard let first = curvePoints.first, let last = curvePoints.last else { return Path() }

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: baselineY))
        p.addLine(to: first)

        if curvePoints.count == 1 {
            p.addLine(to: CGPoint(x: chartRect.maxX, y: baselineY))
            p.closeSubpath()
            return p
        }

        // Smooth-ish quad spline through points.
        var prev = curvePoints[0]
        for i in 1..<curvePoints.count {
            let cur = curvePoints[i]
            let mid = CGPoint(x: (prev.x + cur.x) * 0.5, y: (prev.y + cur.y) * 0.5)
            p.addQuadCurve(to: mid, control: prev)
            prev = cur
        }
        p.addQuadCurve(to: last, control: last)

        p.addLine(to: CGPoint(x: chartRect.maxX, y: baselineY))
        p.closeSubpath()
        return p
    }

    static func buildCurveStrokePath(curvePoints: [CGPoint]) -> Path {
        guard let first = curvePoints.first else { return Path() }
        var p = Path()
        p.move(to: first)
        if curvePoints.count == 1 { return p }

        var prev = curvePoints[0]
        for i in 1..<curvePoints.count {
            let cur = curvePoints[i]
            let mid = CGPoint(x: (prev.x + cur.x) * 0.5, y: (prev.y + cur.y) * 0.5)
            p.addQuadCurve(to: mid, control: prev)
            prev = cur
        }
        p.addQuadCurve(to: curvePoints.last!, control: curvePoints.last!)
        return p
    }

    static func computeTangentsAndNormals(curvePoints: [CGPoint]) -> (tangents: [CGPoint], normals: [CGPoint]) {
        let n = curvePoints.count
        guard n > 1 else {
            return ([CGPoint(x: 1, y: 0)], [CGPoint(x: 0, y: -1)])
        }

        var tangents: [CGPoint] = Array(repeating: CGPoint(x: 1, y: 0), count: n)
        var normals: [CGPoint] = Array(repeating: CGPoint(x: 0, y: -1), count: n)

        for i in 0..<n {
            let a = curvePoints[max(0, i - 1)]
            let b = curvePoints[min(n - 1, i + 1)]
            var tx = b.x - a.x
            var ty = b.y - a.y

            let tlen = max(0.000_001, sqrt(tx * tx + ty * ty))
            tx /= tlen
            ty /= tlen
            tangents[i] = CGPoint(x: tx, y: ty)

            // Normal is perpendicular. Choose the one pointing “out” of the filled shape (upwards).
            var nx = ty
            var ny = -tx
            let nlen = max(0.000_001, sqrt(nx * nx + ny * ny))
            nx /= nlen
            ny /= nlen
            if ny > 0.0 { nx = -nx; ny = -ny }
            normals[i] = CGPoint(x: nx, y: ny)
        }

        return (tangents, normals)
    }

    static func allocateCounts(budget: Int, weights: [Double], totalWeight: Double) -> [Int] {
        guard budget > 0, totalWeight > 0 else { return Array(repeating: 0, count: weights.count) }

        var counts: [Int] = Array(repeating: 0, count: weights.count)
        var accum = 0.0
        var used = 0

        for i in 0..<weights.count {
            let exact = Double(budget) * (weights[i] / totalWeight)
            accum += exact
            let newUsed = min(budget, Int(floor(accum + 1e-9)))
            let c = max(0, newUsed - used)
            counts[i] = c
            used = newUsed
        }

        // If rounding left slack, sprinkle remaining particles on the strongest points.
        if used < budget {
            let remaining = budget - used
            let sorted = weights.enumerated().sorted { $0.element > $1.element }
            var r = remaining
            var idx = 0
            while r > 0 && idx < sorted.count {
                let i = sorted[idx].offset
                counts[i] += 1
                r -= 1
                idx += 1
                if idx >= sorted.count { idx = 0 }
            }
        }

        return counts
    }

    static func distanceToNearestTrue(_ mask: [Bool]) -> [Int] {
        let n = mask.count
        guard n > 0 else { return [] }
        let big = 1_000_000

        var dist = Array(repeating: big, count: n)

        var last = -big
        for i in 0..<n {
            if mask[i] { last = i }
            dist[i] = i - last
        }

        last = big
        for i in stride(from: n - 1, through: 0, by: -1) {
            if mask[i] { last = i }
            dist[i] = min(dist[i], last - i)
        }

        return dist
    }

    static func applyTailBoost(
        strength: inout [CGFloat],
        heights: [CGFloat],
        wetEps: CGFloat,
        sourceMinuteCount: Int,
        tailMinutes: Double
    ) {
        let n = strength.count
        guard n > 3 else { return }

        let pointsPerMinute = Double(max(1, n - 1)) / Double(max(1, sourceMinuteCount - 1))
        let tailPts = max(0, Int(round(max(0.0, tailMinutes) * pointsPerMinute)))
        guard tailPts > 0 else { return }

        // Boost strength near transitions.
        for i in 0..<(n - 1) {
            let aWet = heights[i] > wetEps
            let bWet = heights[i + 1] > wetEps

            if !aWet && bWet {
                // Entering wet (forward).
                for k in 0...tailPts {
                    let j = min(n - 1, i + k)
                    strength[j] = max(strength[j], 0.85)
                }
            } else if aWet && !bWet {
                // Exiting wet (backward).
                for k in 0...tailPts {
                    let j = max(0, i - k)
                    strength[j] = max(strength[j], 0.85)
                }
            }
        }
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
        guard cfg.baselineLineOpacity > 0.0001 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds

        let lineY = baselineY + CGFloat(cfg.baselineOffsetPixels) / ds
        let width = max(onePx, CGFloat(cfg.baselineWidthPixels) / ds)

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: alignToPixelCenter(lineY, onePx: onePx)))
        p.addLine(to: CGPoint(x: chartRect.maxX, y: alignToPixelCenter(lineY, onePx: onePx)))

        let fade = CGFloat(clamp01(cfg.baselineEndFadeFraction))
        if fade > 0.0001 {
            let w = max(1.0, chartRect.width)
            let fadeW = chartRect.width * fade

            let g = Gradient(stops: [
                .init(color: cfg.baselineColor.opacity(0.0), location: 0.0),
                .init(color: cfg.baselineColor.opacity(cfg.baselineLineOpacity), location: Double(clamp01(Double(fadeW / w)))),
                .init(color: cfg.baselineColor.opacity(cfg.baselineLineOpacity), location: Double(clamp01(Double(1.0 - fadeW / w)))),
                .init(color: cfg.baselineColor.opacity(0.0), location: 1.0),
            ])

            context.stroke(
                p,
                with: .linearGradient(
                    g,
                    startPoint: CGPoint(x: chartRect.minX, y: lineY),
                    endPoint: CGPoint(x: chartRect.maxX, y: lineY)
                ),
                lineWidth: width
            )
        } else {
            context.stroke(
                p,
                with: .color(cfg.baselineColor.opacity(cfg.baselineLineOpacity)),
                lineWidth: width
            )
        }
    }

    static func alignToPixelCenter(_ v: CGFloat, onePx: CGFloat) -> CGFloat {
        guard onePx > 0 else { return v }
        return (v / onePx).rounded() * onePx + onePx * 0.5
    }
}

// MARK: - Data prep

private extension RainForecastSurfaceRenderer {
    static func fillMissingLinearHoldEnds(_ values: [Double]) -> [Double] {
        let n = values.count
        guard n > 0 else { return [] }

        var out = values
        let isKnown: (Double) -> Bool = { $0.isFinite }

        guard let firstKnown = values.firstIndex(where: isKnown) else {
            return Array(repeating: 0.0, count: n)
        }

        // Hold start.
        for i in 0..<firstKnown {
            out[i] = values[firstKnown]
        }

        var lastKnown = firstKnown
        var i = firstKnown + 1

        while i < n {
            if isKnown(values[i]) {
                let a = lastKnown
                let b = i
                if b - a > 1 {
                    let va = values[a]
                    let vb = values[b]
                    for j in (a + 1)..<b {
                        let t = Double(j - a) / Double(b - a)
                        out[j] = va + (vb - va) * t
                    }
                }
                out[i] = values[i]
                lastKnown = i
            }
            i += 1
        }

        // Hold end.
        for k in (lastKnown + 1)..<n {
            out[k] = values[lastKnown]
        }

        // Sanitise negatives.
        for idx in 0..<n {
            if !out[idx].isFinite { out[idx] = 0.0 }
            if out[idx] < 0.0 { out[idx] = 0.0 }
        }

        return out
    }

    static func robustReferenceMaxMMPerHour(values: [Double], defaultMax: Double, percentile p: Double) -> Double {
        let finitePositive = values.filter { $0.isFinite && $0 > 0.0 }
        guard !finitePositive.isEmpty else { return max(0.000_001, defaultMax) }

        let pp = clamp01(p)
        let sorted = finitePositive.sorted()
        let idx = min(sorted.count - 1, max(0, Int(round(pp * Double(sorted.count - 1)))))
        let v = sorted[idx]

        return max(0.000_001, max(defaultMax, v))
    }
}

// MARK: - Resampling + smoothing

private extension RainForecastSurfaceRenderer {
    static func resampleLinear(values: [CGFloat], targetCount: Int) -> [CGFloat] {
        guard targetCount > 0 else { return [] }
        guard values.count > 1 else { return Array(repeating: values.first ?? 0.0, count: targetCount) }
        if values.count == targetCount { return values }

        let n = values.count
        let denom = Double(max(1, targetCount - 1))
        let srcDenom = Double(max(1, n - 1))

        var out: [CGFloat] = []
        out.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let t = Double(i) / denom
            let pos = t * srcDenom
            let i0 = max(0, min(n - 1, Int(floor(pos))))
            let i1 = max(0, min(n - 1, i0 + 1))
            let frac = pos - Double(i0)
            let a = values[i0]
            let b = values[i1]
            out.append(a + (b - a) * CGFloat(frac))
        }

        return out
    }

    static func resampleLinear(values: [Double], targetCount: Int) -> [Double] {
        guard targetCount > 0 else { return [] }
        guard values.count > 1 else { return Array(repeating: values.first ?? 0.0, count: targetCount) }
        if values.count == targetCount { return values }

        let n = values.count
        let denom = Double(max(1, targetCount - 1))
        let srcDenom = Double(max(1, n - 1))

        var out: [Double] = []
        out.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let t = Double(i) / denom
            let pos = t * srcDenom
            let i0 = max(0, min(n - 1, Int(floor(pos))))
            let i1 = max(0, min(n - 1, i0 + 1))
            let frac = pos - Double(i0)
            let a = values[i0]
            let b = values[i1]
            out.append(a + (b - a) * frac)
        }

        return out
    }

    static func smooth(_ values: [CGFloat], windowRadius: Int, passes: Int) -> [CGFloat] {
        let v0 = values.map { $0.isFinite ? $0 : 0.0 }
        guard v0.count > 2, windowRadius > 0, passes > 0 else { return v0 }

        var v = v0
        let n = v.count
        let r = windowRadius

        for _ in 0..<passes {
            var out = Array(repeating: CGFloat(0.0), count: n)
            for i in 0..<n {
                var acc: CGFloat = 0.0
                var wsum: CGFloat = 0.0
                for k in -r...r {
                    let j = min(n - 1, max(0, i + k))
                    let w = CGFloat(r + 1 - abs(k)) // triangular weights
                    acc += v[j] * w
                    wsum += w
                }
                out[i] = (wsum > 0.0) ? (acc / wsum) : 0.0
            }
            v = out
        }

        return v
    }

    static func smoothDoubles(_ values: [Double], windowRadius: Int, passes: Int) -> [Double] {
        let v0 = values.map { $0.isFinite ? $0 : 0.0 }
        guard v0.count > 2, windowRadius > 0, passes > 0 else { return v0 }

        var v = v0
        let n = v.count
        let r = windowRadius

        for _ in 0..<passes {
            var out = Array(repeating: 0.0, count: n)
            for i in 0..<n {
                var acc: Double = 0.0
                var wsum: Double = 0.0
                for k in -r...r {
                    let j = min(n - 1, max(0, i + k))
                    let w = Double(r + 1 - abs(k))
                    acc += v[j] * w
                    wsum += w
                }
                out[i] = (wsum > 0.0) ? (acc / wsum) : 0.0
            }
            v = out
        }

        return v
    }
}

// MARK: - Band width + easing

private extension RainForecastSurfaceRenderer {
    static func computeBandWidthPt(chartRect: CGRect, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let wPx = Double(max(1.0, chartRect.width * displayScale))
        let fraction = max(0.001, cfg.fuzzWidthFraction)
        let unclampedPx = wPx * fraction

        let clampRange = cfg.fuzzWidthPixelsClamp
        let clampedPx = min(max(unclampedPx, clampRange.lowerBound), clampRange.upperBound)

        return CGFloat(clampedPx) / max(1.0, displayScale)
    }

    static func applyEdgeEasing(to heights: inout [CGFloat], fraction: Double, power: Double) {
        let n = heights.count
        guard n > 2 else { return }

        let f = max(0.0, min(0.49, fraction))
        guard f > 0.000_01 else { return }

        var ramp = Int(round(Double(n) * f))
        ramp = max(1, min(ramp, (n - 1) / 2))
        guard ramp >= 1 else { return }

        let p = max(0.10, power)

        func ease(_ t: Double) -> Double {
            let tt = clamp01(t)
            return pow(tt, p)
        }

        // Left.
        for i in 0..<ramp {
            let t = Double(i) / Double(ramp)
            heights[i] *= CGFloat(ease(t))
        }

        // Right.
        for i in 0..<ramp {
            let t = Double(i) / Double(ramp)
            let idx = (n - 1) - i
            heights[idx] *= CGFloat(ease(t))
        }
    }
}

// MARK: - PRNG + utilities

private extension RainForecastSurfaceRenderer {
    static func clamp01(_ x: Double) -> Double {
        if !x.isFinite { return 0.0 }
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }
}

// SplitMix64 (fast deterministic RNG).
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &+ 0x9E3779B97F4A7C15
    }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble01() -> Double {
        let x = nextUInt64() >> 11
        return Double(x) * (1.0 / 9007199254740992.0)
    }

    mutating func nextSignedDouble() -> Double {
        (nextDouble01() * 2.0) - 1.0
    }
}

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
