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
        if n <= 0 { return [] }
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            pts.append(geometry.surfacePointAt(i))
        }
        return pts
    }

    static func computeNormals(surfacePoints: [CGPoint]) -> [CGPoint] {
        let n = surfacePoints.count
        if n == 0 { return [] }
        if n == 1 { return [CGPoint(x: 0, y: -1)] }

        var normals: [CGPoint] = Array(repeating: CGPoint(x: 0, y: -1), count: n)

        for i in 0..<n {
            let p0 = surfacePoints[max(0, i - 1)]
            let p1 = surfacePoints[min(n - 1, i + 1)]
            let dx = p1.x - p0.x
            let dy = p1.y - p0.y
            let len = max(0.000_001, sqrt(dx * dx + dy * dy))

            // Tangent normalised.
            let tx = dx / len
            let ty = dy / len

            // Normal pointing “up” (approx).
            var nx = -ty
            var ny = tx

            // Bias upwards slightly.
            if ny > 0 { ny = -ny; nx = -nx }

            let nLen = max(0.000_001, sqrt(nx * nx + ny * ny))
            normals[i] = CGPoint(x: nx / nLen, y: ny / nLen)
        }

        return normals
    }

    static func computeFuzzStrengthPerSegment(perPointStrength: [CGFloat]) -> [CGFloat] {
        let n = perPointStrength.count
        if n <= 1 { return [] }
        var out: [CGFloat] = Array(repeating: 0.0, count: n - 1)
        for i in 0..<(n - 1) {
            out[i] = (perPointStrength[i] + perPointStrength[i + 1]) * 0.5
        }
        return out
    }

    // MARK: - Strength map (certainty/chance only affects styling)

    static func computeFuzzStrengthPerPoint(
        geometry: RainSurfaceGeometry,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat
    ) -> [CGFloat] {
        let n = geometry.sampleCount
        if n <= 0 { return [] }

        let onePx = 1.0 / max(1.0, displayScale)
        let wetEps = max(onePx * 0.5, CGFloat(cfg.wetEpsilon))

        // Wet detection must be HEIGHT only (never certainty).
        var heights: [CGFloat] = Array(repeating: 0.0, count: n)
        var isWet: [Bool] = Array(repeating: false, count: n)

        var maxHeight: CGFloat = 0.0
        for i in 0..<n {
            let y = geometry.surfaceYAt(i)
            let h = geometry.baselineY - y
            heights[i] = h
            if h > wetEps {
                isWet[i] = true
                if h > maxHeight { maxHeight = h }
            }
        }

        // Distance to nearest DRY from each side (for edge emphasis inside wet).
        var distToDryLeft: [Int] = Array(repeating: Int.max / 4, count: n)
        var distToDryRight: [Int] = Array(repeating: Int.max / 4, count: n)

        var lastDry = -1
        for i in 0..<n {
            if !isWet[i] { lastDry = i }
            distToDryLeft[i] = (lastDry < 0) ? (Int.max / 4) : (i - lastDry)
        }
        lastDry = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if !isWet[i] { lastDry = i }
            distToDryRight[i] = (lastDry < 0) ? (Int.max / 4) : (lastDry - i)
        }

        // Nearest wet distance for DRY tailing.
        var distLeftWet: [Int] = Array(repeating: Int.max / 4, count: n)
        var distRightWet: [Int] = Array(repeating: Int.max / 4, count: n)
        var leftWetIndex: [Int] = Array(repeating: -1, count: n)
        var rightWetIndex: [Int] = Array(repeating: -1, count: n)

        var lastWet = -1
        for i in 0..<n {
            if isWet[i] { lastWet = i }
            if lastWet >= 0 {
                distLeftWet[i] = i - lastWet
                leftWetIndex[i] = lastWet
            }
        }
        lastWet = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if isWet[i] { lastWet = i }
            if lastWet >= 0 {
                distRightWet[i] = lastWet - i
                rightWetIndex[i] = lastWet
            }
        }

        // Tail settings (in samples).
        let tailMinutes = max(0.0, cfg.fuzzTailMinutes)
        let samplesPerMinute: Double = (n <= 1) ? 1.0 : Double(n - 1) / Double(max(1.0, cfg.sourceMinutes - 1.0))
        let tailSamples = max(2, Int(round(tailMinutes * samplesPerMinute)))

        let threshold = max(0.0, min(1.0, cfg.fuzzChanceThreshold))
        let transition = max(0.01, min(1.0, cfg.fuzzChanceTransition))
        let chanceExp = max(0.10, cfg.fuzzChanceExponent)
        let chanceFloor = max(0.0, min(0.6, cfg.fuzzChanceFloor))
        let minStrength = max(0.0, min(0.25, cfg.fuzzMinStrength))

        // Plateau suppression parameters (keep alive).
        let slopeRef = max(onePx * 1.25, bandWidthPt * CGFloat(max(0.10, cfg.fuzzSlopeReferenceBandFraction)))
        let edgeWindowSamples = max(2, Int(round(Double(cfg.fuzzEdgeWindowPx) / max(1.0, Double(geometry.dx)))))

        // Base wet strength (certainty-driven, then modulated by edge/height).
        var baseWet: [CGFloat] = Array(repeating: 0.0, count: n)

        for i in 0..<n where isWet[i] {
            let certainty = clamp01(geometry.certaintyAt(i))

            // Lower certainty => more fuzz. Mapping is intentionally aggressive so low-certainty zones
            // commonly reach strong values (≥ ~0.6), while plateaus still stay alive.
            let x = (threshold - certainty) / transition
            let raw = smoothstep01(x)

            // Reach high strength sooner without requiring configuration changes.
            let invExp = 1.0 / max(0.10, chanceExp)
            let mapped = pow(raw, invExp)

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
            // reduce ridge pepper, but keep the edge alive.
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

                let minSlope = 0.82 - 0.12 * plateau // 0.70 … 0.82
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
                s *= (1.0 + 2.25 * pow(edge, 0.85))

                // A hard edge-floor so the boundary reads as particulate even at high certainty.
                let edgeFloor = 0.28 + 0.52 * edge
                s = max(s, edgeFloor)
            }

            // Visibility floor so fuzz systems don’t get gated off in wet regions.
            let visibilityFloor = max(0.10, chanceFloor * 0.55)
            s = max(s, visibilityFloor)

            baseWet[i] = CGFloat(min(1.0, max(0.0, s)))
        }

        // Tail strength into dry samples (bidirectional; both sides of gaps).
        func tailWeight(dist: Int) -> CGFloat {
            if dist <= 0 { return 1 }
            if dist >= tailSamples { return 0 }
            let t = 1.0 - Double(dist) / Double(tailSamples)
            let w = smoothstep01(t)
            return CGFloat(pow(w, 0.55))
        }

        var out: [CGFloat] = baseWet

        // Dry tails: for dry samples within tailSamples of wet on either side,
        // apply the nearest wet strength with smooth falloff. Combine both sides with max().
        if tailSamples > 0 {
            for i in 0..<n where !isWet[i] {
                var s: CGFloat = 0.0

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

                    s *= (1.0 + 0.95 * CGFloat(pow(edge, 0.80)))

                    // Hard floor in the immediate tail so the silhouette remains particulate.
                    let edgeFloor = CGFloat(0.22 + 0.48 * edge)
                    s = max(s, edgeFloor * tailWeight(dist: d))
                }

                out[i] = min(1.0, max(0.0, s))
            }
        }

        _ = normals
        _ = bandWidthPt
        return out
    }

    // Build segment paths binned by strength, so we can apply multiple opacities without per-segment draw calls.
    static func buildBinnedSegmentPaths(
        points: [CGPoint],
        perSegmentStrength: [CGFloat],
        binCount: Int
    ) -> [Path] {
        let n = min(points.count - 1, perSegmentStrength.count)
        if n <= 0 || binCount <= 0 { return [] }

        var paths: [Path] = Array(repeating: Path(), count: binCount)

        for i in 0..<n {
            let s = Double(max(0.0, min(1.0, perSegmentStrength[i])))
            let idx = min(binCount - 1, max(0, Int(floor(s * Double(binCount - 1)))))
            var p = paths[idx]
            p.move(to: points[i])
            p.addLine(to: points[i + 1])
            paths[idx] = p
        }

        return paths
    }

    // MARK: - Core fill

    static func drawCoreFill(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        cfg: RainForecastSurfaceConfiguration,
        maxStrength: CGFloat,
        displayScale: CGFloat
    ) {
        // Core fill must remain vector-clean internally; fuzz passes will dissolve the edge.
        let topMix = max(0.0, min(1.0, cfg.coreTopMix))
        let bottomMix = max(0.0, min(1.0, cfg.coreBottomMix))

        // Base colour from configuration.
        let top = cfg.coreTopColor
        let bottom = cfg.coreBottomColor

        // A subtle vertical gradient in the core (no blur).
        let rect = corePath.boundingRect
        let g = Gradient(stops: [
            .init(color: top.opacity(Double(topMix)), location: 0.0),
            .init(color: bottom.opacity(Double(bottomMix)), location: 1.0)
        ])
        let shading = GraphicsContext.Shading.linearGradient(
            g,
            startPoint: CGPoint(x: rect.midX, y: rect.minY),
            endPoint: CGPoint(x: rect.midX, y: rect.maxY)
        )

        context.fill(corePath, with: shading)

        _ = surfacePoints
        _ = normals
        _ = maxStrength
        _ = displayScale
    }

    // MARK: - Helpers

    static func clamp01(_ x: Double) -> Double {
        max(0.0, min(1.0, x))
    }

    static func smoothstep01(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * (3.0 - 2.0 * t)
    }
}
