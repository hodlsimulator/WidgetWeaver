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

        var normals: [CGPoint] = Array(repeating: CGPoint(x: 0, y: -1), count: n)

        for i in 0..<n {
            let pPrev = surfacePoints[max(0, i - 1)]
            let pNext = surfacePoints[min(n - 1, i + 1)]
            let dx = pNext.x - pPrev.x
            let dy = pNext.y - pPrev.y

            // Outward normal should point “up” in screen space (negative y).
            var nx = dy
            var ny = -dx

            let len = sqrt(nx * nx + ny * ny)
            if len > 0.000_001 {
                nx /= len
                ny /= len
            } else {
                nx = 0.0
                ny = -1.0
            }

            if ny > 0.0 {
                nx = -nx
                ny = -ny
            }

            normals[i] = CGPoint(x: nx, y: ny)
        }

        return normals
    }

    static func buildCorePath(
        geometry: RainSurfaceGeometry,
        smoothingWindowRadius: Int,
        smoothingPasses: Int
    ) -> Path {
        let n = geometry.sampleCount
        guard n > 0 else { return Path() }

        var heights = geometry.heights
        if smoothingWindowRadius > 0, smoothingPasses > 0, heights.count > 2 {
            heights = RainSurfaceMath.smooth(heights, windowRadius: smoothingWindowRadius, passes: smoothingPasses)
        }

        let baseY = geometry.baselineY

        var p = Path()
        p.move(to: CGPoint(x: geometry.xAt(0), y: baseY))
        p.addLine(to: CGPoint(x: geometry.xAt(0), y: baseY - heights[0]))

        if n > 1 {
            for i in 1..<n {
                let x = geometry.xAt(i)
                let y = baseY - heights[i]
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }

        p.addLine(to: CGPoint(x: geometry.xAt(n - 1), y: baseY))
        p.closeSubpath()
        return p
    }

    static func computePerSegmentStrength(perPointStrength: [CGFloat]) -> [CGFloat] {
        let n = perPointStrength.count
        guard n >= 2 else { return [] }
        var out: [CGFloat] = Array(repeating: 0.0, count: n - 1)
        for i in 0..<(n - 1) {
            out[i] = (perPointStrength[i] + perPointStrength[i + 1]) * 0.5
        }
        return out
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

        let maxH = geometry.heights.max() ?? 0.0
        let invMaxH: CGFloat = (maxH > 0.000_01) ? (1.0 / maxH) : 0.0

        // Smooth certainties to avoid striping from dense resampling.
        var cert: [Double] = []
        cert.reserveCapacity(n)
        for i in 0..<n {
            cert.append(geometry.certaintyAt(i))
        }

        let dx = max(onePx, geometry.dx)
        let windowPt = CGFloat(max(0.0, cfg.fuzzEdgeWindowPx)) / ds
        var smoothRadius = Int(round(windowPt / dx))
        smoothRadius = max(0, min(6, smoothRadius))

        if smoothRadius > 0, n > 2 {
            cert = RainSurfaceMath.smooth(cert, windowRadius: smoothRadius, passes: 1)
        }

        let thr = RainSurfaceMath.clamp01(cfg.fuzzChanceThreshold)
        let trans = max(0.000_1, cfg.fuzzChanceTransition)
        let exp = max(0.10, cfg.fuzzChanceExponent)

        let floorBase = RainSurfaceMath.clamp01(cfg.fuzzChanceFloor)
        let minStrength = RainSurfaceMath.clamp01(cfg.fuzzChanceMinStrength)

        let lowHPow = max(0.10, cfg.fuzzLowHeightPower)
        let lowHBoost = max(0.0, cfg.fuzzLowHeightBoost)

        var strength: [CGFloat] = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            let c = RainSurfaceMath.clamp01(cert[i])
            let u = 1.0 - c

            // Chance mapping: ease-out so fuzz becomes strong quickly in uncertain zones.
            let a = thr - trans
            let b = thr + trans
            let t = RainSurfaceMath.smoothstep(a, b, u)
            let mapped = 1.0 - pow(1.0 - t, exp)

            var s = max(minStrength, mapped)

            // Visibility floor only when rain exists (prevents peppering dry baseline).
            let h = geometry.heights[i]
            if h > wetEps {
                s = max(s, floorBase)
            }

            // Low-height boost: fuzzy dissolution reads strongest near the base/tails.
            if invMaxH > 0.0 {
                let hn = RainSurfaceMath.clamp01(h * invMaxH)
                let low = pow(Double(1.0 - hn), lowHPow)
                s *= (1.0 + lowHBoost * low)
            }

            strength[i] = CGFloat(RainSurfaceMath.clamp01(s))
        }

        // Tail boost at wet↔dry transitions (styling only).
        let sourceCount = max(2, cfg.sourceMinuteCount)
        let pointsPerMinute = Double(max(1, n - 1)) / Double(max(1, sourceCount - 1))
        let tailPts = max(0, Int(round(max(0.0, cfg.fuzzTailMinutes) * pointsPerMinute)))

        if tailPts > 0, n > 3 {
            var tail: [CGFloat] = Array(repeating: 0.0, count: n)

            for i in 0..<(n - 1) {
                let aWet = geometry.heights[i] > wetEps
                let bWet = geometry.heights[i + 1] > wetEps

                if !aWet && bWet {
                    // Entering wet: boost forward.
                    for k in 0..<tailPts {
                        let j = i + 1 + k
                        if j >= n { break }
                        let tt = 1.0 - (Double(k) / Double(max(1, tailPts)))
                        tail[j] = max(tail[j], CGFloat(tt))
                    }
                } else if aWet && !bWet {
                    // Exiting wet: boost backward.
                    for k in 0..<tailPts {
                        let j = i - k
                        if j < 0 { break }
                        let tt = 1.0 - (Double(k) / Double(max(1, tailPts)))
                        tail[j] = max(tail[j], CGFloat(tt))
                    }
                }
            }

            for i in 0..<n {
                if tail[i] > 0.0001 {
                    // Keep tails strong enough to be visible even if certainty is high.
                    strength[i] = max(strength[i], min(1.0, tail[i] * 0.72))
                }
            }
        }

        // Light smoothing to prevent segment-wise “bands”, without sterilising the edge.
        if n > 6 {
            let sm = RainSurfaceMath.smooth(strength, windowRadius: 1, passes: 1)
            for i in 0..<n {
                strength[i] = max(strength[i], sm[i] * 0.92)
            }
        }

        return strength
    }
}
