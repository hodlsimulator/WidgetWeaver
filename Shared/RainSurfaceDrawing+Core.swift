//
//  RainSurfaceDrawing+Core.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Core fill construction + strength maps.
//

import SwiftUI

extension RainSurfaceDrawing {
    static func buildSurfacePoints(geometry: RainSurfaceGeometry) -> [CGPoint] {
        let n = geometry.sampleCount
        guard n > 0 else { return [] }

        var pts: [CGPoint] = []
        pts.reserveCapacity(n)

        for i in 0..<n {
            let x = geometry.xAt(i)
            let y = geometry.surfaceYAt(i)
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }

    static func buildCorePath(geometry: RainSurfaceGeometry, smoothingWindowRadius: Int, smoothingPasses: Int) -> Path {
        let n = geometry.sampleCount
        guard n > 0 else { return Path() }

        let baselineY = geometry.baselineY

        var yVals: [CGFloat] = []
        yVals.reserveCapacity(n)
        for i in 0..<n {
            yVals.append(geometry.surfaceYAt(i))
        }

        if smoothingWindowRadius > 0, n >= 3 {
            yVals = RainSurfaceMath.smooth(yVals, windowRadius: smoothingWindowRadius, passes: smoothingPasses)
        }

        var p = Path()
        let x0 = geometry.xAt(0)
        p.move(to: CGPoint(x: x0, y: baselineY))
        p.addLine(to: CGPoint(x: x0, y: yVals[0]))

        if n >= 2 {
            for i in 1..<n {
                p.addLine(to: CGPoint(x: geometry.xAt(i), y: yVals[i]))
            }
        }

        let x1 = geometry.xAt(n - 1)
        p.addLine(to: CGPoint(x: x1, y: baselineY))
        p.closeSubpath()
        return p
    }

    static func computeNormals(surfacePoints: [CGPoint]) -> [CGPoint] {
        let n = surfacePoints.count
        guard n > 1 else { return Array(repeating: CGPoint(x: 0, y: -1), count: n) }

        func normalize(_ v: CGPoint) -> CGPoint {
            let len = hypot(v.x, v.y)
            if len < 1e-6 { return CGPoint(x: 0, y: -1) }
            return CGPoint(x: v.x / len, y: v.y / len)
        }

        var normals: [CGPoint] = Array(repeating: CGPoint(x: 0, y: -1), count: n)

        for i in 0..<n {
            let p0 = surfacePoints[max(0, i - 1)]
            let p1 = surfacePoints[min(n - 1, i + 1)]
            let t = CGPoint(x: p1.x - p0.x, y: p1.y - p0.y)
            var nrm = CGPoint(x: -t.y, y: t.x)
            if nrm.y > 0 { nrm = CGPoint(x: -nrm.x, y: -nrm.y) } // ensure generally “upwards”
            normals[i] = normalize(nrm)
        }

        return normals
    }

    static func computePerSegmentStrength(perPointStrength: [CGFloat]) -> [CGFloat] {
        let n = perPointStrength.count
        guard n >= 2 else { return [] }

        var out: [CGFloat] = []
        out.reserveCapacity(n - 1)

        for i in 0..<(n - 1) {
            out.append(0.5 * (perPointStrength[i] + perPointStrength[i + 1]))
        }
        return out
    }

    static func computeFuzzStrengthPerPoint(
        geometry: RainSurfaceGeometry,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) -> [CGFloat] {
        let n = geometry.sampleCount
        guard n > 0 else { return [] }

        let baselineY = geometry.baselineY
        let onePx = 1.0 / max(1.0, displayScale)
        let wetEps = max(onePx * 0.5, 0.0001)

        // Wet mask (height > 0).
        var isWet: [Bool] = Array(repeating: false, count: n)
        var heights: [CGFloat] = Array(repeating: 0.0, count: n)
        var maxHeight: CGFloat = 0

        for i in 0..<n {
            let h = max(0.0, baselineY - surfacePoints[i].y)
            heights[i] = h
            isWet[i] = (h > wetEps)
            if h > maxHeight { maxHeight = h }
        }

        // Tail samples: minutes → dense samples.
        let minutes = max(0, cfg.fuzzTailMinutes)
        let sourceMinutes = max(1, geometry.sourceMinuteCount)
        let samplesPerMinute = Double(max(1, n - 1)) / Double(max(1, sourceMinutes - 1))
        let tailSamples = max(2, Int(round(Double(minutes) * samplesPerMinute)))
        let edgeWindowSamples = max(2, tailSamples / 2)

        // Distance to nearest dry for wet points (for edge emphasis).
        var distToDryLeft: [Int] = Array(repeating: Int.max / 4, count: n)
        var distToDryRight: [Int] = Array(repeating: Int.max / 4, count: n)

        var lastDry = -1
        for i in 0..<n {
            if !isWet[i] { lastDry = i }
            if isWet[i], lastDry >= 0 {
                distToDryLeft[i] = i - lastDry
            }
        }

        lastDry = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if !isWet[i] { lastDry = i }
            if isWet[i], lastDry >= 0 {
                distToDryRight[i] = lastDry - i
            }
        }

        // Nearest wet indices for tailing into dry samples.
        var leftWetIndex: [Int] = Array(repeating: -1, count: n)
        var rightWetIndex: [Int] = Array(repeating: -1, count: n)
        var distLeftWet: [Int] = Array(repeating: Int.max / 4, count: n)
        var distRightWet: [Int] = Array(repeating: Int.max / 4, count: n)

        var lastWet = -1
        for i in 0..<n {
            if isWet[i] { lastWet = i }
            leftWetIndex[i] = lastWet
            if lastWet >= 0 { distLeftWet[i] = i - lastWet }
        }

        lastWet = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if isWet[i] { lastWet = i }
            rightWetIndex[i] = lastWet
            if lastWet >= 0 { distRightWet[i] = lastWet - i }
        }

        func clamp01(_ x: Double) -> Double { min(max(x, 0.0), 1.0) }

        func smoothstep01(_ x: Double) -> Double {
            let t = clamp01(x)
            return t * t * (3.0 - 2.0 * t)
        }

        // Base strength on wet samples.
        var baseWet: [CGFloat] = Array(repeating: 0, count: n)

        let threshold = cfg.fuzzChanceThreshold
        let transition = max(0.0001, cfg.fuzzChanceTransition)
        let chanceExp = max(0.10, cfg.fuzzChanceExponent)
        let chanceFloor = clamp01(cfg.fuzzChanceFloor)
        let minStrength = clamp01(cfg.fuzzChanceMinStrength)

        let slopeRef: CGFloat = {
            let w = max(onePx, geometry.chartRect.width)
            if maxHeight <= 0.0001 { return 1.0 }
            return max(onePx, maxHeight / (w * 0.22))
        }()

        for i in 0..<n where isWet[i] {
            let chance = clamp01(geometry.certaintyAt(i))
            // Lower chance => more fuzz.
            let x = (threshold - chance) / transition
            let mapped = pow(smoothstep01(x), chanceExp)
            var s = chanceFloor + (1.0 - chanceFloor) * mapped
            s = max(minStrength, min(1.0, s))

            let h = heights[i]
            let hn = (maxHeight > 0.0001) ? min(1.0, Double(h / maxHeight)) : 1.0

            // Low-height boost (stronger at tapered ends).
            if maxHeight > 0.0001 {
                let low = pow(max(0.0, 1.0 - hn), max(0.1, cfg.fuzzLowHeightPower))
                let boost = 1.0 + max(0.0, cfg.fuzzLowHeightBoost) * low
                s *= boost
            }

            // Slope dampener (suppresses pepper on long flat ridges) –
            // only apply once the surface is reasonably “up” (avoid killing tapered ends).
            if hn > 0.35 {
                let i0 = max(0, i - 1)
                let i1 = min(n - 1, i + 1)
                let h0 = heights[i0]
                let h1 = heights[i1]
                let dh = abs(h1 - h0)

                let slope = Double(dh / max(onePx, CGFloat(2) * geometry.dx))
                let denom = Double(max(onePx, slopeRef))
                let sn = min(1.0, max(0.0, slope / max(0.000_001, denom)))

                var plateau = 0.0
                if maxHeight > 0.0001 {
                    plateau = smoothstep01((hn - 0.48) / (0.86 - 0.48))
                    plateau = pow(plateau, 1.35)
                }

                let minSlope = 0.55 - 0.20 * plateau // 0.35 … 0.55
                let slopeFactor = minSlope + (1.0 - minSlope) * pow(sn, 0.75)
                s *= slopeFactor
            }

            // Edge emphasis inside wet region (boost near wet/dry boundaries).
            let dl = distToDryLeft[i]
            let dr = distToDryRight[i]
            let d = min(dl, dr)
            if d < edgeWindowSamples {
                let t = 1.0 - Double(d) / Double(edgeWindowSamples)
                let edge = smoothstep01(t)
                s *= (1.0 + 1.15 * pow(edge, 0.85))
            }

            // Visibility floor so fuzz systems don’t get gated off in common high-certainty cases.
            let visibilityFloor = max(0.045, chanceFloor * 0.35)
            s = max(s, visibilityFloor)

            baseWet[i] = CGFloat(min(1.0, max(0.0, s)))
        }

        // Tail strength into dry samples (bidirectional; both sides of gaps).
        func tailWeight(dist: Int) -> CGFloat {
            if dist <= 0 { return 1 }
            if dist >= tailSamples { return 0 }
            let t = 1.0 - Double(dist) / Double(tailSamples)
            let w = smoothstep01(t)
            return CGFloat(pow(w, 0.85))
        }

        var out: [CGFloat] = Array(repeating: 0, count: n)
        for i in 0..<n {
            if isWet[i] {
                out[i] = baseWet[i]
                continue
            }

            var s: CGFloat = 0

            let dl = distLeftWet[i]
            if dl <= tailSamples {
                let wi = leftWetIndex[i]
                if wi >= 0 {
                    s = max(s, baseWet[wi] * tailWeight(dist: dl))
                }
            }

            let dr = distRightWet[i]
            if dr <= tailSamples {
                let wi = rightWetIndex[i]
                if wi >= 0 {
                    s = max(s, baseWet[wi] * tailWeight(dist: dr))
                }
            }

            // Extra emphasis close to boundaries so both ends of gaps read “fuzzy”.
            let d = min(dl, dr)
            if s > 0.0001, d < edgeWindowSamples {
                let t = 1.0 - Double(d) / Double(edgeWindowSamples)
                let edge = smoothstep01(t)
                s *= (1.0 + 0.55 * CGFloat(pow(edge, 0.85)))
            }

            out[i] = min(1.0, max(0.0, s))
        }

        _ = normals
        _ = bandWidthPt
        return out
    }

    // Build segment paths binned by strength (reduces draw calls).
    static func buildBinnedSegmentPaths(points: [CGPoint], perSegmentStrength: [CGFloat], binCount: Int) -> [Path] {
        let n = min(perSegmentStrength.count, max(0, points.count - 1))
        let bins = max(1, binCount)

        var paths: [Path] = Array(repeating: Path(), count: bins)
        guard n > 0 else { return paths }

        for i in 0..<n {
            let s = max(0.0, min(1.0, perSegmentStrength[i]))
            let idx = min(bins - 1, max(0, Int(floor(s * CGFloat(bins - 1) + 0.0001))))
            var p = paths[idx]
            p.move(to: points[i])
            p.addLine(to: points[i + 1])
            paths[idx] = p
        }

        return paths
    }
}
