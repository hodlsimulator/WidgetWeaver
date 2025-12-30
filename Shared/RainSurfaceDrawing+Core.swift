//
//  RainSurfaceDrawing+Core.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Core geometry helpers + per-point fuzz strength mapping.
//

import SwiftUI

extension RainSurfaceDrawing {

    static func buildSurfacePoints(geometry: RainSurfaceGeometry) -> [CGPoint] {
        let n = geometry.sampleCount
        guard n > 0 else { return [] }

        var pts: [CGPoint] = []
        pts.reserveCapacity(n)

        for i in 0..<n {
            pts.append(geometry.surfacePointAt(i))
        }
        return pts
    }

    static func computeNormals(surfacePoints: [CGPoint]) -> [CGPoint] {
        let n = surfacePoints.count
        guard n >= 2 else { return Array(repeating: CGPoint(x: 0, y: -1), count: n) }

        var normals: [CGPoint] = Array(repeating: .zero, count: n)

        for i in 0..<n {
            let p0 = surfacePoints[max(0, i - 1)]
            let p1 = surfacePoints[min(n - 1, i + 1)]

            let tx = p1.x - p0.x
            let ty = p1.y - p0.y

            var nx = -ty
            var ny = tx

            let len = max(0.000_001, sqrt(nx * nx + ny * ny))
            nx /= len
            ny /= len

            // Force outward normal to point "up" (negative Y) so outside fuzz goes away from the fill.
            if ny > 0.0 {
                nx = -nx
                ny = -ny
            }
            normals[i] = CGPoint(x: nx, y: ny)
        }

        return normals
    }

    /// Returns per-point strength [0,1] controlling all fuzz/dissolve work.
    ///
    /// Semantics:
    /// - Height comes only from intensity (already baked into geometry).
    /// - Certainty/chance affects styling only (this mapping).
    static func computeFuzzStrengthPerPoint(
        geometry: RainSurfaceGeometry,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) -> [CGFloat] {
        let n = min(geometry.sampleCount, surfacePoints.count)
        guard n > 0 else { return [] }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds
        let wetEps = max(onePx * 0.55, 0.000_1)

        // Max height estimate.
        var maxH: CGFloat = 0.0
        for i in 0..<n {
            let h = geometry.baselineY - surfacePoints[i].y
            if h > maxH { maxH = h }
        }
        if maxH <= 0.0 { return Array(repeating: 0.0, count: n) }

        // Wet mask (height-based only; intensity-only).
        var isWet: [Bool] = Array(repeating: false, count: n)
        for i in 0..<n {
            let h = geometry.baselineY - surfacePoints[i].y
            isWet[i] = (h > wetEps)
        }

        // Distance to dry on both sides (in samples).
        var distToDryLeft: [Int] = Array(repeating: 0, count: n)
        var distToDryRight: [Int] = Array(repeating: 0, count: n)

        var lastDry = -1
        for i in 0..<n {
            if !isWet[i] { lastDry = i }
            distToDryLeft[i] = (lastDry < 0) ? (n + 1) : (i - lastDry)
        }

        lastDry = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if !isWet[i] { lastDry = i }
            distToDryRight[i] = (lastDry < 0) ? (n + 1) : (lastDry - i)
        }

        // Edge window in samples.
        let edgeWindowPx = max(1.0, cfg.fuzzEdgeWindowPx)
        let edgeWindowPt = CGFloat(edgeWindowPx) / ds
        let dx = max(onePx, geometry.dx)
        let edgeWindowSamples = max(2, Int(round(edgeWindowPt / dx)))

        // Tail samples (dense samples corresponding to minutes).
        let sourceMinutes = max(1, cfg.sourceMinuteCount)
        let tailMinutes = max(0.0, cfg.fuzzTailMinutes)
        let tailSamples = max(2, Int(round(Double(n) * tailMinutes / Double(sourceMinutes))))

        // Slope reference.
        let slopeRef = max(onePx, bandWidthPt * CGFloat(RainSurfaceMath.clamp01(cfg.fuzzSlopeReferenceBandFraction)))

        // Base wet strengths.
        var baseWet: [CGFloat] = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            guard isWet[i] else { continue }

            let certainty = geometry.certaintyAt(i) // [0,1]
            let chance = 1.0 - certainty            // high chance == low certainty
            let threshold = RainSurfaceDrawing.clamp01(cfg.fuzzChanceThreshold)
            let transition = max(0.000_1, cfg.fuzzChanceTransition)

            let t0 = threshold - transition
            let t1 = threshold + transition
            let x = (chance - t0) / max(0.000_1, (t1 - t0))

            // Make low-certainty ramp FAST to strong fuzz.
            var s = RainSurfaceMath.smoothstep01(RainSurfaceDrawing.clamp01(x))
            s = pow(s, max(0.20, cfg.fuzzChanceExponent))

            // Visibility floor inside wet regions (edge must never be sterile).
            let floorS = RainSurfaceDrawing.clamp01(cfg.fuzzChanceFloor)
            s = floorS + (1.0 - floorS) * s
            s = max(s, RainSurfaceDrawing.clamp01(cfg.fuzzChanceMinStrength))

            // Low height boost (light rain breaks apart more).
            let h = max(0.0, geometry.baselineY - surfacePoints[i].y)
            let hN = RainSurfaceDrawing.clamp01(Double(h / maxH))
            let lowBoost = pow(max(0.0, 1.0 - hN), max(0.20, cfg.fuzzLowHeightPower)) * max(0.0, cfg.fuzzLowHeightBoost)
            s *= (1.0 + lowBoost)

            // Edge emphasis inside wet areas (hug wet/dry boundaries).
            let distToDry = min(distToDryLeft[i], distToDryRight[i])
            if distToDry <= edgeWindowSamples {
                let u = 1.0 - Double(distToDry) / Double(max(1, edgeWindowSamples))
                let edge = pow(RainSurfaceMath.smoothstep01(RainSurfaceDrawing.clamp01(u)), 1.25)
                s *= (1.0 + 1.15 * edge)
            }

            // Plateau dampening (interior only; edges must stay alive).
            if s > 0.35 {
                let dyPrev = abs(surfacePoints[i].y - surfacePoints[max(0, i - 1)].y)
                let dyNext = abs(surfacePoints[min(n - 1, i + 1)].y - surfacePoints[i].y)
                let localSlope = max(dyPrev, dyNext)
                let slopeN = RainSurfaceDrawing.clamp01(Double(localSlope / slopeRef))
                let plateau = pow(max(0.0, 1.0 - slopeN), 1.8)

                if distToDry > Int(Double(edgeWindowSamples) * 0.65) {
                    // Interior: dampen more.
                    s *= (0.45 + 0.55 * (1.0 - plateau))
                } else {
                    // Near edges: dampen lightly.
                    s *= (0.70 + 0.30 * (1.0 - plateau))
                }
            }

            baseWet[i] = CGFloat(min(1.0, max(0.0, s)))
        }

        // Distance to nearest wet on left/right (for tails on both sides of gaps).
        var distLeftWet: [Int] = Array(repeating: n + 1, count: n)
        var nearestWetLeft: [Int] = Array(repeating: -1, count: n)

        var lastWet = -1
        for i in 0..<n {
            if isWet[i] {
                lastWet = i
                distLeftWet[i] = 0
                nearestWetLeft[i] = i
            } else if lastWet >= 0 {
                distLeftWet[i] = i - lastWet
                nearestWetLeft[i] = lastWet
            }
        }

        var distRightWet: [Int] = Array(repeating: n + 1, count: n)
        var nearestWetRight: [Int] = Array(repeating: -1, count: n)

        lastWet = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if isWet[i] {
                lastWet = i
                distRightWet[i] = 0
                nearestWetRight[i] = i
            } else if lastWet >= 0 {
                distRightWet[i] = lastWet - i
                nearestWetRight[i] = lastWet
            }
        }

        var out: [CGFloat] = Array(repeating: 0.0, count: n)

        // Start with wet strengths.
        for i in 0..<n {
            out[i] = baseWet[i]
        }

        // Tail weighting.
        func tailWeight(_ dist: Int) -> Double {
            if dist <= 0 { return 1.0 }
            if dist >= tailSamples { return 0.0 }
            let t = 1.0 - Double(dist) / Double(tailSamples)
            return RainSurfaceMath.smoothstep01(RainSurfaceDrawing.clamp01(t))
        }

        // Apply tails to dry points, from BOTH sides.
        if tailSamples > 0 {
            for i in 0..<n where !isWet[i] {
                var s: Double = 0.0

                if distLeftWet[i] <= tailSamples, nearestWetLeft[i] >= 0 {
                    let w = tailWeight(distLeftWet[i])
                    let near = Double(baseWet[nearestWetLeft[i]])
                    s = max(s, near * w)
                    // Ensure visible tails even when adjacent wet is high certainty.
                    s = max(s, 0.35 * w)
                }

                if distRightWet[i] <= tailSamples, nearestWetRight[i] >= 0 {
                    let w = tailWeight(distRightWet[i])
                    let near = Double(baseWet[nearestWetRight[i]])
                    s = max(s, near * w)
                    s = max(s, 0.35 * w)
                }

                out[i] = CGFloat(min(1.0, max(0.0, s)))
            }
        }

        // Final visibility floor (wet stays alive even on strong plateaus).
        for i in 0..<n where isWet[i] {
            out[i] = max(out[i], 0.06)
        }

        return out
    }

    static func computePerSegmentStrength(perPointStrength: [CGFloat]) -> [CGFloat] {
        let n = perPointStrength.count
        guard n >= 2 else { return [] }

        var out: [CGFloat] = []
        out.reserveCapacity(n - 1)

        for i in 0..<(n - 1) {
            out.append((perPointStrength[i] + perPointStrength[i + 1]) * 0.5)
        }
        return out
    }

    static func buildCorePath(
        geometry: RainSurfaceGeometry,
        smoothingWindowRadius: Int,
        smoothingPasses: Int
    ) -> Path {
        let n = geometry.sampleCount
        guard n >= 2 else { return Path() }

        var top: [CGPoint] = []
        top.reserveCapacity(n)

        for i in 0..<n {
            top.append(geometry.surfacePointAt(i))
        }

        // Optional smoothing (cheap; uses existing RainSurfaceMath.smooth).
        if smoothingWindowRadius > 0, smoothingPasses > 0 {
            let ys = top.map { $0.y }
            let smoothed = RainSurfaceMath.smooth(ys, windowRadius: smoothingWindowRadius, passes: smoothingPasses)
            if smoothed.count == top.count {
                for i in 0..<top.count {
                    top[i].y = smoothed[i]
                }
            }
        }

        return geometry.coreAreaPath(insetTop: top)
    }
}
