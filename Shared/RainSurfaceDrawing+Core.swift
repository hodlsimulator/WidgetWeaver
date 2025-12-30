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
            pts.append(CGPoint(x: geometry.xAt(i), y: geometry.surfaceYAt(i)))
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

            // Outward normal for a surface whose fill is below the polyline.
            var nx = ty
            var ny = -tx

            let len = max(CGFloat(0.000_001), CGFloat(sqrt(Double(nx * nx + ny * ny))))
            nx /= len
            ny /= len

            // Ensure normal points upward-ish (avoid flipping on numerical noise).
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

        // Compute a maxHeight estimate from the current surface.
        var maxH: CGFloat = 0.0
        for i in 0..<n {
            let h = max(0.0, geometry.baselineY - surfacePoints[i].y)
            if h > maxH { maxH = h }
        }
        if maxH <= 0.0 {
            return Array(repeating: 0.0, count: n)
        }

        // Wet mask (height-based; intensity-only).
        var isWet: [Bool] = Array(repeating: false, count: n)
        for i in 0..<n {
            let h = geometry.baselineY - surfacePoints[i].y
            isWet[i] = (h > wetEps)
        }

        // Precompute distance-to-dry on both sides (in samples).
        var distToDryLeft: [Int] = Array(repeating: 0, count: n)
        var distToDryRight: [Int] = Array(repeating: 0, count: n)

        var lastDry = -1
        for i in 0..<n {
            if !isWet[i] {
                lastDry = i
                distToDryLeft[i] = 0
            } else {
                distToDryLeft[i] = (lastDry < 0) ? n : (i - lastDry)
            }
        }

        lastDry = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if !isWet[i] {
                lastDry = i
                distToDryRight[i] = 0
            } else {
                distToDryRight[i] = (lastDry < 0) ? n : (lastDry - i)
            }
        }

        // Edge window (in samples) derived from pixel intent.
        let edgeWindowPt = CGFloat(max(2.0, cfg.fuzzEdgeWindowPx)) / ds
        let dx = max(onePx, geometry.dx)
        let edgeWindowSamples = max(2, Int(round(edgeWindowPt / dx)))

        // Strength for wet points before tails are pushed into dry zones.
        var baseWet: [CGFloat] = Array(repeating: 0.0, count: n)

        let threshold = cfg.fuzzChanceThreshold
        let transition = max(0.000_1, cfg.fuzzChanceTransition)
        let exponent = max(0.10, cfg.fuzzChanceExponent)
        let floorS = clamp01(cfg.fuzzChanceFloor)
        let minS = clamp01(cfg.fuzzChanceMinStrength)

        let slopeRef = max(onePx, bandWidthPt * CGFloat(max(0.05, cfg.fuzzSlopeReferenceBandFraction)))

        for i in 0..<n {
            guard isWet[i] else { continue }

            let chance = clamp01(geometry.certaintyAt(i))
            let x = (threshold - chance) / transition
            let t = smoothstep01(clamp01(x))
            let mapped = pow(t, exponent)

            var s = floorS + (1.0 - floorS) * mapped
            s = max(s, minS)

            // Low heights (near baseline) get more breakup/dust.
            let h = max(0.0, geometry.baselineY - surfacePoints[i].y)
            let hn = Double(min(1.0, h / maxH))
            let low = pow(max(0.0, 1.0 - hn), cfg.fuzzLowHeightPower)
            s *= (1.0 + cfg.fuzzLowHeightBoost * low)

            // Plateau dampening: reduce ridge pepper, but only for interior points.
            if hn > 0.35 {
                let dyPrev = abs(surfacePoints[i].y - surfacePoints[max(0, i - 1)].y)
                let dyNext = abs(surfacePoints[min(n - 1, i + 1)].y - surfacePoints[i].y)
                let localSlope = max(dyPrev, dyNext)
                let slopeN = clamp01(Double(localSlope / slopeRef))
                let plateau = pow(max(0.0, 1.0 - slopeN), 1.8)

                let distToDry = min(distToDryLeft[i], distToDryRight[i])
                if distToDry > Int(Double(edgeWindowSamples) * 0.65) {
                    // Interior: dampen more.
                    s *= (0.45 + 0.55 * (1.0 - plateau))
                } else {
                    // Near edges: dampen lightly (edges must stay alive).
                    s *= (0.70 + 0.30 * (1.0 - plateau))
                }
            }

            baseWet[i] = CGFloat(min(1.0, max(0.0, s)))
        }

        // Edge emphasis inside wet areas (hug wet/dry boundaries).
        for i in 0..<n {
            guard isWet[i] else { continue }
            let distToDry = min(distToDryLeft[i], distToDryRight[i])
            if distToDry <= edgeWindowSamples {
                let edgeT = 1.0 - Double(distToDry) / Double(max(1, edgeWindowSamples))
                let edgeN = smoothstep01(clamp01(edgeT))
                var s = Double(baseWet[i])

                // Stronger near the boundary.
                s *= (1.0 + 2.05 * edgeN)

                // Extra pop very close to baseline-ish heights.
                let h = max(0.0, geometry.baselineY - surfacePoints[i].y)
                let hn = Double(min(1.0, h / maxH))
                if hn < 0.30 {
                    let nearBase = pow(max(0.0, 1.0 - hn / 0.30), 1.35)
                    s *= (1.0 + 0.85 * nearBase * edgeN)
                }

                baseWet[i] = CGFloat(min(1.0, max(0.0, s)))
            }
        }

        // Bidirectional tail into adjacent dry regions (both sides of gaps).
        let sourceMinutes = max(1, cfg.sourceMinuteCount)
        let samplesPerMinute = Double(max(1, n - 1)) / Double(max(1, sourceMinutes - 1))
        let tailSamples = max(1, Int(round(cfg.fuzzTailMinutes * samplesPerMinute)))

        // Distances to nearest wet on left/right.
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
            if isWet[i] { out[i] = baseWet[i] }
        }

        func tailWeight(_ dist: Int) -> Double {
            if dist <= 0 { return 1.0 }
            if dist >= tailSamples { return 0.0 }
            let t = 1.0 - Double(dist) / Double(tailSamples)
            return smoothstep01(clamp01(t))
        }

        for i in 0..<n {
            guard !isWet[i] else { continue }

            var s: Double = 0.0

            if distLeftWet[i] <= tailSamples, nearestWetLeft[i] >= 0 {
                let w = tailWeight(distLeftWet[i])
                let near = Double(baseWet[nearestWetLeft[i]])
                s = max(s, near * w)
                // Ensure visible tails even when the nearest wet was "high certainty".
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

        // Visibility floor: keep the edge alive even on strong wet plateaus.
        for i in 0..<n {
            guard isWet[i] else { continue }
            out[i] = max(out[i], CGFloat(minS))
        }

        return out
    }

    static func computePerSegmentStrength(perPointStrength: [CGFloat]) -> [CGFloat] {
        let n = perPointStrength.count
        guard n >= 2 else { return [] }

        var out: [CGFloat] = []
        out.reserveCapacity(n - 1)

        for i in 0..<(n - 1) {
            let a = perPointStrength[i]
            let b = perPointStrength[i + 1]
            out.append((a + b) * 0.5)
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
            top.append(CGPoint(x: geometry.xAt(i), y: geometry.surfaceYAt(i)))
        }

        // Mild smoothing for visual cohesion.
        if smoothingWindowRadius > 0, smoothingPasses > 0 {
            let ys = top.map { $0.y }
            let smoothed = RainSurfaceMath.smooth(ys, windowRadius: smoothingWindowRadius, passes: smoothingPasses)
            if smoothed.count == top.count {
                for i in 0..<top.count { top[i].y = smoothed[i] }
            }
        }

        var p = Path()
        p.move(to: CGPoint(x: geometry.chartRect.minX, y: geometry.baselineY))
        p.addLine(to: top[0])
        for i in 1..<top.count { p.addLine(to: top[i]) }
        p.addLine(to: CGPoint(x: geometry.chartRect.maxX, y: geometry.baselineY))
        p.closeSubpath()
        return p
    }

    // MARK: - Small math helpers

    private static func clamp01(_ x: Double) -> Double {
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }

    private static func smoothstep01(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * (3.0 - 2.0 * t)
    }
}
