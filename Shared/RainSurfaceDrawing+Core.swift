//
//  RainSurfaceDrawing+Core.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//

import SwiftUI

extension RainSurfaceDrawing {

    // MARK: - Geometry to path

    static func buildCorePath(
        chartRect: CGRect,
        baselineY: CGFloat,
        xPositions: [CGFloat],
        heights: [CGFloat],
        topSmoothing: Int
    ) -> Path {
        let n = min(xPositions.count, heights.count)
        guard n >= 2 else { return Path() }

        // Smooth heights in place (tiny window; avoids hard kinks).
        let smoothedHeights: [CGFloat] = {
            if topSmoothing <= 0 { return Array(heights.prefix(n)) }
            let arr = heights.prefix(n).map { Double($0) }
            let sm = RainSurfaceMath.smooth(arr, radius: topSmoothing, passes: 1).map { CGFloat($0) }
            return sm
        }()

        var p = Path()
        p.move(to: CGPoint(x: xPositions[0], y: baselineY))

        for i in 0..<n {
            let x = xPositions[i]
            let y = baselineY - smoothedHeights[i]
            if i == 0 {
                p.addLine(to: CGPoint(x: x, y: y))
            } else {
                p.addLine(to: CGPoint(x: x, y: y))
            }
        }

        p.addLine(to: CGPoint(x: xPositions[n - 1], y: baselineY))
        p.closeSubpath()
        return p
    }

    static func buildSurfacePoints(
        chartRect: CGRect,
        baselineY: CGFloat,
        xPositions: [CGFloat],
        heights: [CGFloat],
        topSmoothing: Int
    ) -> [CGPoint] {
        let n = min(xPositions.count, heights.count)
        guard n >= 2 else { return [] }

        let smoothedHeights: [CGFloat] = {
            if topSmoothing <= 0 { return Array(heights.prefix(n)) }
            let arr = heights.prefix(n).map { Double($0) }
            let sm = RainSurfaceMath.smooth(arr, radius: topSmoothing, passes: 1).map { CGFloat($0) }
            return sm
        }()

        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            pts.append(CGPoint(x: xPositions[i], y: baselineY - smoothedHeights[i]))
        }
        return pts
    }

    static func computeNormals(for surfacePoints: [CGPoint]) -> [CGVector] {
        let n = surfacePoints.count
        guard n >= 2 else { return [] }

        var normals: [CGVector] = Array(repeating: CGVector(dx: 0, dy: -1), count: n)

        func safeNormal(_ dx: CGFloat, _ dy: CGFloat) -> CGVector {
            let len = sqrt(dx * dx + dy * dy)
            if len <= 0.000_001 { return CGVector(dx: 0, dy: -1) }
            // Outward normal (pointing "outside" of the filled core).
            return CGVector(dx: -dy / len, dy: dx / len)
        }

        for i in 0..<n {
            let pPrev = surfacePoints[max(0, i - 1)]
            let pNext = surfacePoints[min(n - 1, i + 1)]
            let dx = pNext.x - pPrev.x
            let dy = pNext.y - pPrev.y
            normals[i] = safeNormal(dx, dy)
        }

        return normals
    }

    static func computePerSegmentStrength(perPoint: [Double]) -> [Double] {
        guard perPoint.count >= 2 else { return [] }
        var out: [Double] = Array(repeating: 0.0, count: perPoint.count - 1)
        for i in 0..<(perPoint.count - 1) {
            out[i] = 0.5 * (perPoint[i] + perPoint[i + 1])
        }
        return out
    }

    // MARK: - Inset + fade (core owns less, fuzz owns more)

    static func insetTopPoints(
        surfacePoints: [CGPoint],
        normals: [CGVector],
        perPointStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat
    ) -> [CGPoint] {
        let n = surfacePoints.count
        guard n >= 2, normals.count == n, perPointStrength.count == n else { return surfacePoints }

        let maxInset = max(0.0, cfg.coreInsetMax) * bandWidthPt
        if maxInset <= 0.000_1 { return surfacePoints }

        var out: [CGPoint] = surfacePoints
        for i in 0..<n {
            let s = RainSurfaceMath.clamp01(perPointStrength[i])
            if s <= 0.000_1 { continue }
            let inset = maxInset * CGFloat(s)
            out[i] = CGPoint(
                x: out[i].x + normals[i].dx * inset,
                y: out[i].y + normals[i].dy * inset
            )
        }
        return out
    }

    static func drawCoreEdgeFade(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat
    ) {
        guard surfacePoints.count >= 3 else { return }
        guard perSegmentStrength.count == surfacePoints.count - 1 else { return }

        let fadeFrac = max(0.0, cfg.coreFadeFraction)
        let fadeWidth = max(0.0, min(10.0, bandWidthPt * CGFloat(fadeFrac)))
        guard fadeWidth > 0.000_1 else { return }

        let bins = 4
        var binPaths: [Path] = Array(repeating: Path(), count: bins)

        // Build stroke segments binned by strength.
        for i in 0..<(surfacePoints.count - 1) {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 { continue }

            let a = 0.20 + 0.80 * s
            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            var p = Path()
            p.move(to: surfacePoints[i])
            p.addLine(to: surfacePoints[i + 1])
            binPaths[bin].addPath(p)
        }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            layer.addFilter(.blur(radius: max(0.35, fadeWidth * 0.55)))

            for b in 0..<bins {
                if binPaths[b].isEmpty { continue }
                let a = Double(b + 1) / Double(bins)
                let w = max(0.65, fadeWidth * 0.85)

                layer.stroke(
                    binPaths[b],
                    with: .color(Color.white.opacity(a)),
                    style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Fuzz strength mapping
    // - Tail is styling-only into dry regions at every wet↔dry boundary (derived from height only).

    static func computeFuzzStrengthPerPoint(
        geometry: RainSurfaceGeometry,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat
    ) -> [Double] {
        let n = geometry.sampleCount
        guard n >= 2 else { return Array(repeating: 0.0, count: max(0, n)) }

        let heights = geometry.heights
        let certainties = geometry.certainties

        // Wet/dry for tail detection is height-only (silhouette semantics).
        let scale = max(1.0, Double(geometry.displayScale))
        let heightEps = max(0.25, 0.75 / scale) // points
        var wetByHeight: [Bool] = Array(repeating: false, count: n)
        var anyWet = false
        for i in 0..<n {
            let h = Double(heights[i])
            let w = h.isFinite && h > heightEps
            wetByHeight[i] = w
            anyWet = anyWet || w
        }
        guard anyWet else { return Array(repeating: 0.0, count: n) }

        let bandWidth = max(1.0, Double(bandWidthPt))
        let slopeDenomPx = max(1.0, Double(bandWidthPt) * scale * 0.85)

        // Base strength on wet samples only (chance + geometry heuristics).
        var baseStrength: [Double] = Array(repeating: 0.0, count: n)
        baseStrength.withUnsafeMutableBufferPointer { out in
            for i in 0..<n {
                let chance = RainSurfaceMath.clamp01(Double(certainties[i]))

                let thr = max(0.0, min(1.0, cfg.fuzzChanceThreshold))
                let trans = max(0.000_1, min(1.0, cfg.fuzzChanceTransition))

                let u = RainSurfaceMath.clamp01((chance - thr) / trans)
                let exp = max(0.10, cfg.fuzzChanceExponent)
                let mapped = pow(u, exp)

                let floorBase = max(0.0, min(1.0, cfg.fuzzChanceFloor))
                let floorS: Double = (chance <= 0.000_001) ? 0.0 : floorBase

                var s = floorS + (1.0 - floorS) * mapped
                s = RainSurfaceMath.clamp01(s)

                // Low-height boost (helps tapered starts/ends).
                let hFrac = RainSurfaceMath.clamp01(Double(heights[i]) / bandWidth)
                let lowBoost = (1.0 - RainSurfaceMath.smoothstep(0.22, 0.62, hFrac)) * cfg.fuzzLowHeightBoost

                // Local slope proxy (edge complexity).
                let yPrev = Double(heights[max(0, i - 1)])
                let yNext = Double(heights[min(n - 1, i + 1)])
                let slopePx = abs(yNext - yPrev) * scale
                let slopeNorm = RainSurfaceMath.clamp01(slopePx / slopeDenomPx)
                let slopeBoost = pow(slopeNorm, 0.70) * cfg.fuzzSlopeBoost

                s = RainSurfaceMath.clamp01(s + lowBoost + slopeBoost)
                out[i] = s
            }
        }

        // Tail strength into dry regions at every wet↔dry boundary (styling only).
        let tailMinutes = max(0.0, min(24.0, cfg.fuzzTailMinutes))
        let minutes = max(0, geometry.sourceMinuteCount)
        let samplesPerMinute: Double = {
            if minutes >= 2 {
                return Double(max(1, n - 1)) / Double(minutes - 1)
            } else {
                return Double(max(1, n - 1))
            }
        }()

        var tailSamples = Int((tailMinutes * samplesPerMinute).rounded(.toNearestOrAwayFromZero))
        if tailMinutes <= 0.000_001 { tailSamples = 0 }
        tailSamples = max(0, min(n - 1, tailSamples))

        var nearestWetLeft: [Int] = Array(repeating: -1, count: n)
        var lastWet = -1
        for i in 0..<n {
            if wetByHeight[i] { lastWet = i }
            nearestWetLeft[i] = lastWet
        }

        var nearestWetRight: [Int] = Array(repeating: -1, count: n)
        var nextWet = -1
        var i = n - 1
        while i >= 0 {
            if wetByHeight[i] { nextWet = i }
            nearestWetRight[i] = nextWet
            if i == 0 { break }
            i -= 1
        }

        let minTailStrength = max(0.0, min(1.0, cfg.fuzzChanceMinStrength))
        let tailPow = 0.75

        @inline(__always)
        func tailWeight(_ dist: Int) -> Double {
            guard tailSamples > 0 else { return 0.0 }
            if dist <= 0 { return 1.0 }
            if dist >= tailSamples { return 0.0 }
            let t = Double(dist) / Double(tailSamples)
            // Smooth, strong near the boundary; fast fade toward the tail end.
            let w = 1.0 - RainSurfaceMath.smoothstep01(t)
            return pow(max(0.0, w), tailPow)
        }

        var out: [Double] = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            if wetByHeight[i] {
                out[i] = baseStrength[i]
                continue
            }

            // Dry samples: only receive styling strength if within tail distance of wet data.
            var s: Double = 0.0

            if tailSamples > 0 {
                let l = nearestWetLeft[i]
                if l >= 0 {
                    let d = i - l
                    if d > 0, d <= tailSamples {
                        let w = tailWeight(d)
                        let base = max(minTailStrength, baseStrength[l])
                        s = max(s, base * w)
                    }
                }

                let r = nearestWetRight[i]
                if r >= 0 {
                    let d = r - i
                    if d > 0, d <= tailSamples {
                        let w = tailWeight(d)
                        let base = max(minTailStrength, baseStrength[r])
                        s = max(s, base * w)
                    }
                }
            }

            out[i] = RainSurfaceMath.clamp01(s)
        }

        return out
    }
}
