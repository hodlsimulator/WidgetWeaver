//
//  RainSurfaceDrawing+Fuzz.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//

import SwiftUI

extension RainSurfaceDrawing {

    static func boostedFuzzColor(_ cfg: RainForecastSurfaceConfiguration) -> Color {
        let base = cfg.fuzzColor
        let boost = max(0.0, min(1.0, cfg.fuzzColorBoost))
        if boost <= 0.000_1 { return base }

        // Simple brighten by mixing toward white; keeps hue.
        let white = Color.white
        return Color(
            red: (1.0 - boost) * base.r + boost * white.r,
            green: (1.0 - boost) * base.g + boost * white.g,
            blue: (1.0 - boost) * base.b + boost * white.b
        )
    }

    // MARK: - Haze (optional, cheap)

    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        maxStrength: Double,
        isTightBudget: Bool
    ) {
        guard surfacePoints.count >= 3 else { return }
        guard perSegmentStrength.count == surfacePoints.count - 1 else { return }
        guard cfg.fuzzHazeStrength > 0.000_1 else { return }

        // Haze is expensive-ish due to blur; skip in tight budget mode.
        if isTightBudget { return }

        let strength = max(0.0, min(1.0, cfg.fuzzHazeStrength))
        if strength <= 0.000_1 { return }

        let boostedColor = boostedFuzzColor(cfg)

        let blurR = max(0.0, min(2.0, bandWidthPt * CGFloat(cfg.fuzzHazeBlurFractionOfBand)))
        let strokeW = max(0.5, bandWidthPt * CGFloat(cfg.fuzzHazeStrokeWidthFactor))

        let bins = 4
        var binPaths: [Path] = Array(repeating: Path(), count: bins)

        for i in 0..<(surfacePoints.count - 1) {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 { continue }
            let a = (0.18 + 0.82 * s) * strength
            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            var p = Path()
            p.move(to: surfacePoints[i])
            p.addLine(to: surfacePoints[i + 1])
            binPaths[bin].addPath(p)
        }

        if binPaths.allSatisfy({ $0.isEmpty }) { return }

        context.drawLayer { layer in
            let bleed = max(0.0, bandWidthPt * 3.0)
            var outside = Path()
            outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
            outside.addPath(corePath)
            layer.clip(to: outside, style: FillStyle(eoFill: true))

            layer.blendMode = .plusLighter
            if blurR > 0.001 { layer.addFilter(.blur(radius: blurR)) }

            for b in 0..<bins {
                if binPaths[b].isEmpty { continue }
                let a = Double(b + 1) / Double(bins)
                layer.stroke(
                    binPaths[b],
                    with: .color(boostedColor.opacity(a)),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Core erosion (destinationOut, blurred)

    static func drawCoreErosion(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        maxStrength: Double
    ) {
        guard surfacePoints.count >= 3 else { return }
        guard perSegmentStrength.count == surfacePoints.count - 1 else { return }
        guard cfg.fuzzErodeStrength > 0.000_1 else { return }

        let strength = max(0.0, min(1.0, cfg.fuzzErodeStrength))
        if strength <= 0.000_1 { return }

        let blurR = max(0.0, min(2.2, bandWidthPt * CGFloat(cfg.fuzzErodeBlurFractionOfBand)))
        let strokeW = max(0.5, bandWidthPt * CGFloat(cfg.fuzzErodeStrokeWidthFactor))

        let bins = 4
        var binPaths: [Path] = Array(repeating: Path(), count: bins)

        for i in 0..<(surfacePoints.count - 1) {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 { continue }
            let a = (0.14 + 0.86 * s) * strength
            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            var p = Path()
            p.move(to: surfacePoints[i])
            p.addLine(to: surfacePoints[i + 1])
            binPaths[bin].addPath(p)
        }

        if binPaths.allSatisfy({ $0.isEmpty }) { return }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            if blurR > 0.001 { layer.addFilter(.blur(radius: blurR)) }

            for b in 0..<bins {
                if binPaths[b].isEmpty { continue }
                let a = Double(b + 1) / Double(bins)
                layer.stroke(
                    binPaths[b],
                    with: .color(Color.white.opacity(a)),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Core dissolve (particulate; styling only)
    static func drawCoreDissolvePerforation(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGVector],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double,
        isTightBudget: Bool
    ) {
        guard surfacePoints.count >= 3, normals.count == surfacePoints.count else { return }
        guard perSegmentStrength.count == surfacePoints.count - 1 else { return }
        guard maxStrength > 0.01 else { return }

        // Cheap grainy "perforation" inside the upper band so the smooth core dissolves into dust.
        let scale = max(1.0, displayScale)
        let insideWidth = max(0.0, bandWidthPt * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor)) * 0.85)
        guard insideWidth > 0.25 else { return }

        let density = max(0.0, min(2.0, cfg.fuzzDensity))

        // Budget is hard-clamped and derived from the main speckle budget (degrades cleanly).
        let baseBudget = max(0, cfg.fuzzSpeckleBudget)
        let cap = isTightBudget ? 520 : 2400
        let strengthScale = max(0.0, min(1.0, 0.28 + 0.72 * maxStrength))
        let densityScale = max(0.0, min(1.0, 0.78 + 0.22 * Double(density)))
        var holeCount = Int((Double(baseBudget) * (isTightBudget ? 0.22 : 0.42) * strengthScale * densityScale).rounded(.toNearestOrAwayFromZero))
        holeCount = max(0, min(cap, holeCount))
        if holeCount <= 0 { return }

        // Hole radii are biased heavily toward micro grains.
        let rPx0 = max(0.10, min(2.0, cfg.fuzzSpeckleRadiusPixels.lowerBound * 0.55))
        let rPx1 = max(rPx0, min(2.4, cfg.fuzzSpeckleRadiusPixels.upperBound * 0.70))
        let r0 = rPx0 / scale
        let r1 = rPx1 / scale

        // Segment picker weighted by strength (no per-segment reseeding).
        let segCount = perSegmentStrength.count
        var segCDF: [Double] = Array(repeating: 0.0, count: segCount)
        var totalW: Double = 0.0
        for i in 0..<segCount {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 {
                segCDF[i] = totalW
                continue
            }
            let w = (0.06 + s) * (0.30 + 0.70 * s)
            totalW += w
            segCDF[i] = totalW
        }
        if totalW <= 0.000_001 { return }

        func pickSegment(_ u01: Double) -> Int {
            let target = u01 * totalW
            var lo = 0
            var hi = segCDF.count - 1
            while lo < hi {
                let mid = (lo + hi) >> 1
                if segCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
            }
            return max(0, min(segCount - 1, lo))
        }

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xD15_50A1_0A0A_5EED)
        var prng = RainSurfacePRNG(seed: seed)

        let bins = isTightBudget ? 3 : 5
        var binPaths: [Path] = Array(repeating: Path(), count: bins)

        func addDot(to path: inout Path, cx: CGFloat, cy: CGFloat, r: CGFloat) {
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }

        let powInside = max(0.10, cfg.fuzzDistancePowerInside)
        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        for _ in 0..<holeCount {
            let seg = pickSegment(prng.nextFloat01())
            let sSeg = RainSurfaceMath.clamp01(perSegmentStrength[seg])
            if sSeg <= 0.000_01 { continue }

            let t = CGFloat(prng.nextFloat01())
            let p0 = surfacePoints[seg]
            let p1 = surfacePoints[seg + 1]
            let px = p0.x + (p1.x - p0.x) * t
            let py = p0.y + (p1.y - p0.y) * t

            let n0 = normals[seg]
            let n1 = normals[seg + 1]
            let nxRaw = n0.dx + (n1.dx - n0.dx) * t
            let nyRaw = n0.dy + (n1.dy - n0.dy) * t
            let nrmLen = sqrt(nxRaw * nxRaw + nyRaw * nyRaw)
            let nn: CGVector = (nrmLen > 0.000_001) ? CGVector(dx: nxRaw / nrmLen, dy: nyRaw / nrmLen) : CGVector(dx: 0, dy: -1)
            let tan = CGVector(dx: -nn.dy, dy: nn.dx)

            let u = prng.nextFloat01()
            let d01 = pow(u, powInside * 1.15)
            let dist = CGFloat(d01) * insideWidth
            let signedDist = -dist

            let jitter = CGFloat(prng.nextSignedFloat()) * CGFloat(tangentJitter) * bandWidthPt * 0.35

            let cx = px + nn.dx * signedDist + tan.dx * jitter
            let cy = py + nn.dy * signedDist + tan.dy * jitter

            // Radius: overwhelmingly tiny grains.
            let rrT = CGFloat(pow(prng.nextFloat01(), 2.9))
            let rr = r0 + (r1 - r0) * rrT

            // Alpha: partial removal, stronger near the edge and where strength is higher.
            let distWeight: Double = {
                let denom = Double(insideWidth)
                if denom <= 0.000_001 { return 1.0 }
                let a = min(1.0, max(0.0, 1.0 - Double(abs(signedDist)) / denom))
                return pow(a, max(0.10, powInside))
            }()

            var a = (isTightBudget ? 0.22 : 0.34) * (0.30 + 0.70 * sSeg) * distWeight
            a *= (0.70 + 0.30 * maxStrength)
            a *= (0.86 + 0.14 * Double(density))
            a = max(0.0, min(0.55, a))

            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            addDot(to: &binPaths[bin], cx: cx, cy: cy, r: rr)
        }

        guard binPaths.contains(where: { !$0.isEmpty }) else { return }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            for b in 0..<bins {
                if binPaths[b].isEmpty { continue }
                let a = Double(b + 1) / Double(bins)
                layer.fill(binPaths[b], with: .color(Color.white.opacity(a)))
            }
        }
    }

    // MARK: - Fuzz speckles (primary)
    static func drawFuzzSpeckles(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGVector],
        perPointStrength: [Double],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double,
        isTightBudget: Bool
    ) {
        guard surfacePoints.count >= 3, normals.count == surfacePoints.count else { return }
        guard maxStrength > 0.01 else { return }

        let scale = max(1.0, displayScale)

        let outsideWidth = max(0.000_1, bandWidthPt)
        let insideWidth = max(0.0, bandWidthPt * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor)))
        let density = max(0.0, min(2.0, cfg.fuzzDensity))

        let boostedColor = boostedFuzzColor(cfg)

        var baseAlpha = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzSpeckStrength))
        if isTightBudget { baseAlpha = min(1.0, baseAlpha * 1.04) }
        if baseAlpha <= 0.000_1 { return }

        // Much finer grain: allow very small pixel radii and bias heavily toward micro grains.
        let rPx0 = max(0.10, min(3.0, cfg.fuzzSpeckleRadiusPixels.lowerBound))
        let rPx1 = max(rPx0, min(6.0, cfg.fuzzSpeckleRadiusPixels.upperBound))
        let r0 = rPx0 / scale
        let r1 = rPx1 / scale

        let budget0 = max(0, min(12_000, cfg.fuzzSpeckleBudget))
        let strengthScale = max(0.0, min(1.0, 0.34 + 0.66 * maxStrength))
        let densityScale = max(0.0, min(1.0, 0.76 + 0.24 * density))

        var baseCount = Int((Double(budget0) * strengthScale * densityScale).rounded(.toNearestOrAwayFromZero))
        let baseCap = isTightBudget ? min(2_200, budget0) : budget0
        baseCount = min(baseCap, max(0, baseCount))
        if baseCount <= 0 { return }

        let segCount = perSegmentStrength.count
        guard segCount >= 2 else { return }

        // Plateau dampener: reduce outside speckles on long, high, flat ridges (pepper control).
        let baselineDist = max(1.0, Double(baselineY - chartRect.minY))
        let slopeDenomPx = max(6.0, Double(bandWidthPt) * Double(scale) * 0.85)

        @inline(__always)
        func plateauDampForSegment(_ i: Int) -> Double {
            let p0 = surfacePoints[i]
            let p1 = surfacePoints[i + 1]
            let avgY = 0.5 * (Double(p0.y) + Double(p1.y))
            let h = max(0.0, Double(baselineY) - avgY)
            let hFrac = RainSurfaceMath.clamp01(h / baselineDist)

            let dyPx = abs(Double(p1.y - p0.y)) * Double(scale)
            let slopeNorm = RainSurfaceMath.clamp01(dyPx / slopeDenomPx)

            let high = RainSurfaceMath.smoothstep(0.55, 0.90, hFrac)
            let flat = 1.0 - RainSurfaceMath.smoothstep(0.06, 0.22, slopeNorm)
            let plateau = high * flat

            return max(0.25, 1.0 - plateau * 0.72)
        }

        var segDamp: [Double] = Array(repeating: 1.0, count: segCount)
        for i in 0..<segCount {
            segDamp[i] = plateauDampForSegment(i)
        }

        // Segment picker weighted by strength (with plateau dampening to reduce ridge pepper).
        var segCDF: [Double] = Array(repeating: 0.0, count: segCount)
        var totalW: Double = 0.0
        let floorForNonZero: Double = isTightBudget ? 0.060 : 0.045

        for i in 0..<segCount {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 {
                segCDF[i] = totalW
                continue
            }
            let w = (floorForNonZero + s) * (0.35 + 0.65 * s) * segDamp[i]
            totalW += w
            segCDF[i] = totalW
        }
        if totalW <= 0.000_001 { return }

        func pickSegment(_ u01: Double) -> Int {
            let target = u01 * totalW
            var lo = 0
            var hi = segCDF.count - 1
            while lo < hi {
                let mid = (lo + hi) >> 1
                if segCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
            }
            return max(0, min(segCount - 1, lo))
        }

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xC0FFEE_BAAD_F00D)
        var prng = RainSurfacePRNG(seed: seed)

        let xBleed = bandWidthPt * 1.6
        let yBleedTop = bandWidthPt * 2.9
        let yBleedBottom = bandWidthPt * 1.2

        let bins = isTightBudget ? 4 : 6
        var outsideBins: [Path] = Array(repeating: Path(), count: bins)

        let insideOpacity = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
        let useInsideSpeckles = (insideWidth > 0.000_01) && (insideOpacity > 0.000_1)
        var insideBins: [Path] = useInsideSpeckles ? Array(repeating: Path(), count: bins) : []

        // Inside speckles are the "weld" that keeps fuzz from floating; keep them even in tight budgets.
        let insideFractionBase = max(0.0, min(1.0, cfg.fuzzInsideSpeckleFraction))
        let insideFraction = useInsideSpeckles ? max(0.0, min(1.0, insideFractionBase + (isTightBudget ? 0.10 : 0.0))) : 0.0

        let powOutside = max(0.10, cfg.fuzzDistancePowerOutside)
        let powInside = max(0.10, cfg.fuzzDistancePowerInside)
        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        // Macro grains: rare, slightly larger, and softer. Removed first in tight budgets.
        var macroCount = 0
        let macroCap = isTightBudget ? 0 : 120
        let macroChance = isTightBudget ? 0.0 : 0.035

        func addDot(to path: inout Path, cx: CGFloat, cy: CGFloat, r: CGFloat) {
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }

        for _ in 0..<baseCount {
            let seg = pickSegment(prng.nextFloat01())
            let sSeg = RainSurfaceMath.clamp01(perSegmentStrength[seg])
            if sSeg <= 0.000_01 { continue }

            let t = CGFloat(prng.nextFloat01())
            let p0 = surfacePoints[seg]
            let p1 = surfacePoints[seg + 1]
            let px = p0.x + (p1.x - p0.x) * t
            let py = p0.y + (p1.y - p0.y) * t

            let n0 = normals[seg]
            let n1 = normals[seg + 1]
            let nxRaw = n0.dx + (n1.dx - n0.dx) * t
            let nyRaw = n0.dy + (n1.dy - n0.dy) * t
            let nrmLen = sqrt(nxRaw * nxRaw + nyRaw * nyRaw)
            let nn: CGVector = (nrmLen > 0.000_001) ? CGVector(dx: nxRaw / nrmLen, dy: nyRaw / nrmLen) : CGVector(dx: 0, dy: -1)
            let tan = CGVector(dx: -nn.dy, dy: nn.dx)

            let insidePick = (prng.nextFloat01() < insideFraction) && useInsideSpeckles
            let width = insidePick ? insideWidth : outsideWidth

            let u = prng.nextFloat01()
            let d01 = pow(u, insidePick ? powInside : (powOutside * 1.08))
            let dist = CGFloat(d01) * width
            let signedDist = insidePick ? -dist : dist

            let jitter = CGFloat(prng.nextSignedFloat()) * CGFloat(tangentJitter) * bandWidthPt * 0.55

            let cx = px + nn.dx * signedDist + tan.dx * jitter
            let cy = py + nn.dy * signedDist + tan.dy * jitter

            if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
            if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

            // Radius biased heavily toward the small end.
            let rrT = CGFloat(pow(prng.nextFloat01(), 2.7))
            var rr = r0 + (r1 - r0) * rrT

            var alphaMul: Double = 1.0
            if !insidePick, macroCount < macroCap, prng.nextFloat01() < macroChance {
                macroCount += 1
                rr *= 1.85
                alphaMul *= 0.52
            }

            let denom = Double(width)
            let distWeight: Double = {
                if denom <= 0.000_001 { return 1.0 }
                let a = min(1.0, max(0.0, 1.0 - Double(abs(signedDist)) / denom))
                let pp = insidePick ? powInside : powOutside
                return pow(a, max(0.10, pp))
            }()

            var a = baseAlpha * (0.20 + 0.80 * sSeg) * distWeight * alphaMul
            if insidePick {
                a *= insideOpacity
                a *= 0.78
            } else {
                // Plateau dampener is primarily for outside speckles.
                a *= segDamp[seg]
            }
            a *= (0.80 + 0.20 * density)
            a = max(0.0, min(1.0, a))

            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            if insidePick, useInsideSpeckles {
                addDot(to: &insideBins[bin], cx: cx, cy: cy, r: rr)
            } else {
                addDot(to: &outsideBins[bin], cx: cx, cy: cy, r: rr)
            }
        }

        // Edge beads: dense, edge-hugging continuity (with plateau dampening to avoid ridge pepper).
        if surfacePoints.count >= 3, perPointStrength.count == surfacePoints.count {
            let m = perPointStrength.count
            var ptCDF: [Double] = Array(repeating: 0.0, count: m)
            var totalPt: Double = 0.0
            let ptFloor = isTightBudget ? 0.070 : 0.050

            @inline(__always)
            func pointDamp(_ i: Int) -> Double {
                let p = surfacePoints[i]
                let h = max(0.0, Double(baselineY) - Double(p.y))
                let hFrac = RainSurfaceMath.clamp01(h / baselineDist)

                let yPrev = Double(surfacePoints[max(0, i - 1)].y)
                let yNext = Double(surfacePoints[min(m - 1, i + 1)].y)
                let dyPx = abs(yNext - yPrev) * Double(scale)
                let slopeNorm = RainSurfaceMath.clamp01(dyPx / slopeDenomPx)

                let high = RainSurfaceMath.smoothstep(0.55, 0.90, hFrac)
                let flat = 1.0 - RainSurfaceMath.smoothstep(0.06, 0.22, slopeNorm)
                let plateau = high * flat

                return max(0.35, 1.0 - plateau * 0.65)
            }

            for i in 0..<m {
                let s = RainSurfaceMath.clamp01(perPointStrength[i])
                if s <= 0.000_01 {
                    ptCDF[i] = totalPt
                    continue
                }
                totalPt += (ptFloor + s) * (0.40 + 0.60 * s) * pointDamp(i)
                ptCDF[i] = totalPt
            }

            if totalPt > 0.000_001 {
                func pickPoint(_ u01: Double) -> Int {
                    let target = u01 * totalPt
                    var lo = 0
                    var hi = ptCDF.count - 1
                    while lo < hi {
                        let mid = (lo + hi) >> 1
                        if ptCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
                    }
                    return max(0, min(ptCDF.count - 1, lo))
                }

                let beadCap = isTightBudget ? 820 : 6_200
                let beadBase = Int((Double(surfacePoints.count) * (isTightBudget ? 3.7 : 8.9) * (0.48 + 0.52 * maxStrength) * (0.82 + 0.18 * density)).rounded(.toNearestOrAwayFromZero))
                let beadCount = min(beadCap, max(0, beadBase))

                if beadCount > 0 {
                    for _ in 0..<beadCount {
                        let i = pickPoint(prng.nextFloat01())
                        let s = RainSurfaceMath.clamp01(perPointStrength[i])
                        if s <= 0.000_01 { continue }

                        let p = surfacePoints[i]
                        let nn = normals[i]
                        let tan = CGVector(dx: -nn.dy, dy: nn.dx)

                        let d = CGFloat(pow(prng.nextFloat01(), 2.9)) * outsideWidth * 0.58
                        let jitter = CGFloat(prng.nextSignedFloat()) * bandWidthPt * 0.20

                        let cx = p.x + nn.dx * d + tan.dx * jitter
                        let cy = p.y + nn.dy * d + tan.dy * jitter

                        if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
                        if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

                        let rrT = CGFloat(pow(prng.nextFloat01(), 2.8))
                        var rr = (r0 * 0.34) + (r1 * 0.62 - r0 * 0.34) * rrT
                        var a = baseAlpha * (0.55 + 0.45 * s) * (0.84 + 0.16 * density) * pointDamp(i)

                        if !isTightBudget, prng.nextFloat01() < 0.06 {
                            rr *= 1.55
                            a *= 0.62
                        }

                        a = max(0.0, min(1.0, a))
                        let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
                        addDot(to: &outsideBins[bin], cx: cx, cy: cy, r: rr)
                    }
                }
            }
        }

        if outsideBins.contains(where: { !$0.isEmpty }) {
            context.drawLayer { layer in
                let bleed = max(0.0, bandWidthPt * 3.0)
                var outside = Path()
                outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
                outside.addPath(corePath)
                layer.clip(to: outside, style: FillStyle(eoFill: true))
                layer.blendMode = .plusLighter

                // No halo: keep the blur very small and skip it in tight budgets.
                let microBlur: CGFloat = isTightBudget ? 0.0 : min(0.90, bandWidthPt * 0.028)
                if microBlur > 0.001 { layer.addFilter(.blur(radius: microBlur)) }

                for b in 0..<bins {
                    if outsideBins[b].isEmpty { continue }
                    let a = (Double(b + 1) / Double(bins)) * baseAlpha
                    let aa = max(0.0, min(1.0, a))
                    layer.fill(outsideBins[b], with: .color(boostedColor.opacity(aa)))
                }
            }
        }

        if useInsideSpeckles, insideBins.contains(where: { !$0.isEmpty }) {
            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .plusLighter
                for b in 0..<bins {
                    if insideBins[b].isEmpty { continue }
                    let a = (Double(b + 1) / Double(bins)) * baseAlpha * insideOpacity * 0.78
                    let aa = max(0.0, min(1.0, a))
                    layer.fill(insideBins[b], with: .color(boostedColor.opacity(aa)))
                }
            }
        }
    }
}
//
//  RainSurfaceDrawing+Fuzz.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//

import SwiftUI

extension RainSurfaceDrawing {

    static func boostedFuzzColor(_ cfg: RainForecastSurfaceConfiguration) -> Color {
        let base = cfg.fuzzColor
        let boost = max(0.0, min(1.0, cfg.fuzzColorBoost))
        if boost <= 0.000_1 { return base }

        // Simple brighten by mixing toward white; keeps hue.
        let white = Color.white
        return Color(
            red: (1.0 - boost) * base.r + boost * white.r,
            green: (1.0 - boost) * base.g + boost * white.g,
            blue: (1.0 - boost) * base.b + boost * white.b
        )
    }

    // MARK: - Haze (optional, cheap)

    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        maxStrength: Double,
        isTightBudget: Bool
    ) {
        guard surfacePoints.count >= 3 else { return }
        guard perSegmentStrength.count == surfacePoints.count - 1 else { return }
        guard cfg.fuzzHazeStrength > 0.000_1 else { return }

        // Haze is expensive-ish due to blur; skip in tight budget mode.
        if isTightBudget { return }

        let strength = max(0.0, min(1.0, cfg.fuzzHazeStrength))
        if strength <= 0.000_1 { return }

        let boostedColor = boostedFuzzColor(cfg)

        let blurR = max(0.0, min(2.0, bandWidthPt * CGFloat(cfg.fuzzHazeBlurFractionOfBand)))
        let strokeW = max(0.5, bandWidthPt * CGFloat(cfg.fuzzHazeStrokeWidthFactor))

        let bins = 4
        var binPaths: [Path] = Array(repeating: Path(), count: bins)

        for i in 0..<(surfacePoints.count - 1) {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 { continue }
            let a = (0.18 + 0.82 * s) * strength
            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            var p = Path()
            p.move(to: surfacePoints[i])
            p.addLine(to: surfacePoints[i + 1])
            binPaths[bin].addPath(p)
        }

        if binPaths.allSatisfy({ $0.isEmpty }) { return }

        context.drawLayer { layer in
            let bleed = max(0.0, bandWidthPt * 3.0)
            var outside = Path()
            outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
            outside.addPath(corePath)
            layer.clip(to: outside, style: FillStyle(eoFill: true))

            layer.blendMode = .plusLighter
            if blurR > 0.001 { layer.addFilter(.blur(radius: blurR)) }

            for b in 0..<bins {
                if binPaths[b].isEmpty { continue }
                let a = Double(b + 1) / Double(bins)
                layer.stroke(
                    binPaths[b],
                    with: .color(boostedColor.opacity(a)),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Core erosion (destinationOut, blurred)

    static func drawCoreErosion(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        maxStrength: Double
    ) {
        guard surfacePoints.count >= 3 else { return }
        guard perSegmentStrength.count == surfacePoints.count - 1 else { return }
        guard cfg.fuzzErodeStrength > 0.000_1 else { return }

        let strength = max(0.0, min(1.0, cfg.fuzzErodeStrength))
        if strength <= 0.000_1 { return }

        let blurR = max(0.0, min(2.2, bandWidthPt * CGFloat(cfg.fuzzErodeBlurFractionOfBand)))
        let strokeW = max(0.5, bandWidthPt * CGFloat(cfg.fuzzErodeStrokeWidthFactor))

        let bins = 4
        var binPaths: [Path] = Array(repeating: Path(), count: bins)

        for i in 0..<(surfacePoints.count - 1) {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 { continue }
            let a = (0.14 + 0.86 * s) * strength
            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            var p = Path()
            p.move(to: surfacePoints[i])
            p.addLine(to: surfacePoints[i + 1])
            binPaths[bin].addPath(p)
        }

        if binPaths.allSatisfy({ $0.isEmpty }) { return }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            if blurR > 0.001 { layer.addFilter(.blur(radius: blurR)) }

            for b in 0..<bins {
                if binPaths[b].isEmpty { continue }
                let a = Double(b + 1) / Double(bins)
                layer.stroke(
                    binPaths[b],
                    with: .color(Color.white.opacity(a)),
                    style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Core dissolve (particulate; styling only)
    static func drawCoreDissolvePerforation(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGVector],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double,
        isTightBudget: Bool
    ) {
        guard surfacePoints.count >= 3, normals.count == surfacePoints.count else { return }
        guard perSegmentStrength.count == surfacePoints.count - 1 else { return }
        guard maxStrength > 0.01 else { return }

        // Cheap grainy "perforation" inside the upper band so the smooth core dissolves into dust.
        let scale = max(1.0, displayScale)
        let insideWidth = max(0.0, bandWidthPt * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor)) * 0.85)
        guard insideWidth > 0.25 else { return }

        let density = max(0.0, min(2.0, cfg.fuzzDensity))

        // Budget is hard-clamped and derived from the main speckle budget (degrades cleanly).
        let baseBudget = max(0, cfg.fuzzSpeckleBudget)
        let cap = isTightBudget ? 520 : 2400
        let strengthScale = max(0.0, min(1.0, 0.28 + 0.72 * maxStrength))
        let densityScale = max(0.0, min(1.0, 0.78 + 0.22 * Double(density)))
        var holeCount = Int((Double(baseBudget) * (isTightBudget ? 0.22 : 0.42) * strengthScale * densityScale).rounded(.toNearestOrAwayFromZero))
        holeCount = max(0, min(cap, holeCount))
        if holeCount <= 0 { return }

        // Hole radii are biased heavily toward micro grains.
        let rPx0 = max(0.10, min(2.0, cfg.fuzzSpeckleRadiusPixels.lowerBound * 0.55))
        let rPx1 = max(rPx0, min(2.4, cfg.fuzzSpeckleRadiusPixels.upperBound * 0.70))
        let r0 = rPx0 / scale
        let r1 = rPx1 / scale

        // Segment picker weighted by strength (no per-segment reseeding).
        let segCount = perSegmentStrength.count
        var segCDF: [Double] = Array(repeating: 0.0, count: segCount)
        var totalW: Double = 0.0
        for i in 0..<segCount {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 {
                segCDF[i] = totalW
                continue
            }
            let w = (0.06 + s) * (0.30 + 0.70 * s)
            totalW += w
            segCDF[i] = totalW
        }
        if totalW <= 0.000_001 { return }

        func pickSegment(_ u01: Double) -> Int {
            let target = u01 * totalW
            var lo = 0
            var hi = segCDF.count - 1
            while lo < hi {
                let mid = (lo + hi) >> 1
                if segCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
            }
            return max(0, min(segCount - 1, lo))
        }

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xD15_50A1_0A0A_5EED)
        var prng = RainSurfacePRNG(seed: seed)

        let bins = isTightBudget ? 3 : 5
        var binPaths: [Path] = Array(repeating: Path(), count: bins)

        func addDot(to path: inout Path, cx: CGFloat, cy: CGFloat, r: CGFloat) {
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }

        let powInside = max(0.10, cfg.fuzzDistancePowerInside)
        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        for _ in 0..<holeCount {
            let seg = pickSegment(prng.nextFloat01())
            let sSeg = RainSurfaceMath.clamp01(perSegmentStrength[seg])
            if sSeg <= 0.000_01 { continue }

            let t = CGFloat(prng.nextFloat01())
            let p0 = surfacePoints[seg]
            let p1 = surfacePoints[seg + 1]
            let px = p0.x + (p1.x - p0.x) * t
            let py = p0.y + (p1.y - p0.y) * t

            let n0 = normals[seg]
            let n1 = normals[seg + 1]
            let nxRaw = n0.dx + (n1.dx - n0.dx) * t
            let nyRaw = n0.dy + (n1.dy - n0.dy) * t
            let nrmLen = sqrt(nxRaw * nxRaw + nyRaw * nyRaw)
            let nn: CGVector = (nrmLen > 0.000_001) ? CGVector(dx: nxRaw / nrmLen, dy: nyRaw / nrmLen) : CGVector(dx: 0, dy: -1)
            let tan = CGVector(dx: -nn.dy, dy: nn.dx)

            let u = prng.nextFloat01()
            let d01 = pow(u, powInside * 1.15)
            let dist = CGFloat(d01) * insideWidth
            let signedDist = -dist

            let jitter = CGFloat(prng.nextSignedFloat()) * CGFloat(tangentJitter) * bandWidthPt * 0.35

            let cx = px + nn.dx * signedDist + tan.dx * jitter
            let cy = py + nn.dy * signedDist + tan.dy * jitter

            // Radius: overwhelmingly tiny grains.
            let rrT = CGFloat(pow(prng.nextFloat01(), 2.9))
            let rr = r0 + (r1 - r0) * rrT

            // Alpha: partial removal, stronger near the edge and where strength is higher.
            let distWeight: Double = {
                let denom = Double(insideWidth)
                if denom <= 0.000_001 { return 1.0 }
                let a = min(1.0, max(0.0, 1.0 - Double(abs(signedDist)) / denom))
                return pow(a, max(0.10, powInside))
            }()

            var a = (isTightBudget ? 0.22 : 0.34) * (0.30 + 0.70 * sSeg) * distWeight
            a *= (0.70 + 0.30 * maxStrength)
            a *= (0.86 + 0.14 * Double(density))
            a = max(0.0, min(0.55, a))

            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            addDot(to: &binPaths[bin], cx: cx, cy: cy, r: rr)
        }

        guard binPaths.contains(where: { !$0.isEmpty }) else { return }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            for b in 0..<bins {
                if binPaths[b].isEmpty { continue }
                let a = Double(b + 1) / Double(bins)
                layer.fill(binPaths[b], with: .color(Color.white.opacity(a)))
            }
        }
    }

    // MARK: - Fuzz speckles (primary)
    static func drawFuzzSpeckles(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGVector],
        perPointStrength: [Double],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double,
        isTightBudget: Bool
    ) {
        guard surfacePoints.count >= 3, normals.count == surfacePoints.count else { return }
        guard maxStrength > 0.01 else { return }

        let scale = max(1.0, displayScale)

        let outsideWidth = max(0.000_1, bandWidthPt)
        let insideWidth = max(0.0, bandWidthPt * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor)))
        let density = max(0.0, min(2.0, cfg.fuzzDensity))

        let boostedColor = boostedFuzzColor(cfg)

        var baseAlpha = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzSpeckStrength))
        if isTightBudget { baseAlpha = min(1.0, baseAlpha * 1.04) }
        if baseAlpha <= 0.000_1 { return }

        // Much finer grain: allow very small pixel radii and bias heavily toward micro grains.
        let rPx0 = max(0.10, min(3.0, cfg.fuzzSpeckleRadiusPixels.lowerBound))
        let rPx1 = max(rPx0, min(6.0, cfg.fuzzSpeckleRadiusPixels.upperBound))
        let r0 = rPx0 / scale
        let r1 = rPx1 / scale

        let budget0 = max(0, min(12_000, cfg.fuzzSpeckleBudget))
        let strengthScale = max(0.0, min(1.0, 0.34 + 0.66 * maxStrength))
        let densityScale = max(0.0, min(1.0, 0.76 + 0.24 * density))

        var baseCount = Int((Double(budget0) * strengthScale * densityScale).rounded(.toNearestOrAwayFromZero))
        let baseCap = isTightBudget ? min(2_200, budget0) : budget0
        baseCount = min(baseCap, max(0, baseCount))
        if baseCount <= 0 { return }

        let segCount = perSegmentStrength.count
        guard segCount >= 2 else { return }

        // Plateau dampener: reduce outside speckles on long, high, flat ridges (pepper control).
        let baselineDist = max(1.0, Double(baselineY - chartRect.minY))
        let slopeDenomPx = max(6.0, Double(bandWidthPt) * Double(scale) * 0.85)

        @inline(__always)
        func plateauDampForSegment(_ i: Int) -> Double {
            let p0 = surfacePoints[i]
            let p1 = surfacePoints[i + 1]
            let avgY = 0.5 * (Double(p0.y) + Double(p1.y))
            let h = max(0.0, Double(baselineY) - avgY)
            let hFrac = RainSurfaceMath.clamp01(h / baselineDist)

            let dyPx = abs(Double(p1.y - p0.y)) * Double(scale)
            let slopeNorm = RainSurfaceMath.clamp01(dyPx / slopeDenomPx)

            let high = RainSurfaceMath.smoothstep(0.55, 0.90, hFrac)
            let flat = 1.0 - RainSurfaceMath.smoothstep(0.06, 0.22, slopeNorm)
            let plateau = high * flat

            return max(0.25, 1.0 - plateau * 0.72)
        }

        var segDamp: [Double] = Array(repeating: 1.0, count: segCount)
        for i in 0..<segCount {
            segDamp[i] = plateauDampForSegment(i)
        }

        // Segment picker weighted by strength (with plateau dampening to reduce ridge pepper).
        var segCDF: [Double] = Array(repeating: 0.0, count: segCount)
        var totalW: Double = 0.0
        let floorForNonZero: Double = isTightBudget ? 0.060 : 0.045

        for i in 0..<segCount {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 {
                segCDF[i] = totalW
                continue
            }
            let w = (floorForNonZero + s) * (0.35 + 0.65 * s) * segDamp[i]
            totalW += w
            segCDF[i] = totalW
        }
        if totalW <= 0.000_001 { return }

        func pickSegment(_ u01: Double) -> Int {
            let target = u01 * totalW
            var lo = 0
            var hi = segCDF.count - 1
            while lo < hi {
                let mid = (lo + hi) >> 1
                if segCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
            }
            return max(0, min(segCount - 1, lo))
        }

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xC0FFEE_BAAD_F00D)
        var prng = RainSurfacePRNG(seed: seed)

        let xBleed = bandWidthPt * 1.6
        let yBleedTop = bandWidthPt * 2.9
        let yBleedBottom = bandWidthPt * 1.2

        let bins = isTightBudget ? 4 : 6
        var outsideBins: [Path] = Array(repeating: Path(), count: bins)

        let insideOpacity = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
        let useInsideSpeckles = (insideWidth > 0.000_01) && (insideOpacity > 0.000_1)
        var insideBins: [Path] = useInsideSpeckles ? Array(repeating: Path(), count: bins) : []

        // Inside speckles are the "weld" that keeps fuzz from floating; keep them even in tight budgets.
        let insideFractionBase = max(0.0, min(1.0, cfg.fuzzInsideSpeckleFraction))
        let insideFraction = useInsideSpeckles ? max(0.0, min(1.0, insideFractionBase + (isTightBudget ? 0.10 : 0.0))) : 0.0

        let powOutside = max(0.10, cfg.fuzzDistancePowerOutside)
        let powInside = max(0.10, cfg.fuzzDistancePowerInside)
        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        // Macro grains: rare, slightly larger, and softer. Removed first in tight budgets.
        var macroCount = 0
        let macroCap = isTightBudget ? 0 : 120
        let macroChance = isTightBudget ? 0.0 : 0.035

        func addDot(to path: inout Path, cx: CGFloat, cy: CGFloat, r: CGFloat) {
            path.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }

        for _ in 0..<baseCount {
            let seg = pickSegment(prng.nextFloat01())
            let sSeg = RainSurfaceMath.clamp01(perSegmentStrength[seg])
            if sSeg <= 0.000_01 { continue }

            let t = CGFloat(prng.nextFloat01())
            let p0 = surfacePoints[seg]
            let p1 = surfacePoints[seg + 1]
            let px = p0.x + (p1.x - p0.x) * t
            let py = p0.y + (p1.y - p0.y) * t

            let n0 = normals[seg]
            let n1 = normals[seg + 1]
            let nxRaw = n0.dx + (n1.dx - n0.dx) * t
            let nyRaw = n0.dy + (n1.dy - n0.dy) * t
            let nrmLen = sqrt(nxRaw * nxRaw + nyRaw * nyRaw)
            let nn: CGVector = (nrmLen > 0.000_001) ? CGVector(dx: nxRaw / nrmLen, dy: nyRaw / nrmLen) : CGVector(dx: 0, dy: -1)
            let tan = CGVector(dx: -nn.dy, dy: nn.dx)

            let insidePick = (prng.nextFloat01() < insideFraction) && useInsideSpeckles
            let width = insidePick ? insideWidth : outsideWidth

            let u = prng.nextFloat01()
            let d01 = pow(u, insidePick ? powInside : (powOutside * 1.08))
            let dist = CGFloat(d01) * width
            let signedDist = insidePick ? -dist : dist

            let jitter = CGFloat(prng.nextSignedFloat()) * CGFloat(tangentJitter) * bandWidthPt * 0.55

            let cx = px + nn.dx * signedDist + tan.dx * jitter
            let cy = py + nn.dy * signedDist + tan.dy * jitter

            if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
            if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

            // Radius biased heavily toward the small end.
            let rrT = CGFloat(pow(prng.nextFloat01(), 2.7))
            var rr = r0 + (r1 - r0) * rrT

            var alphaMul: Double = 1.0
            if !insidePick, macroCount < macroCap, prng.nextFloat01() < macroChance {
                macroCount += 1
                rr *= 1.85
                alphaMul *= 0.52
            }

            let denom = Double(width)
            let distWeight: Double = {
                if denom <= 0.000_001 { return 1.0 }
                let a = min(1.0, max(0.0, 1.0 - Double(abs(signedDist)) / denom))
                let pp = insidePick ? powInside : powOutside
                return pow(a, max(0.10, pp))
            }()

            var a = baseAlpha * (0.20 + 0.80 * sSeg) * distWeight * alphaMul
            if insidePick {
                a *= insideOpacity
                a *= 0.78
            } else {
                // Plateau dampener is primarily for outside speckles.
                a *= segDamp[seg]
            }
            a *= (0.80 + 0.20 * density)
            a = max(0.0, min(1.0, a))

            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            if insidePick, useInsideSpeckles {
                addDot(to: &insideBins[bin], cx: cx, cy: cy, r: rr)
            } else {
                addDot(to: &outsideBins[bin], cx: cx, cy: cy, r: rr)
            }
        }

        // Edge beads: dense, edge-hugging continuity (with plateau dampening to avoid ridge pepper).
        if surfacePoints.count >= 3, perPointStrength.count == surfacePoints.count {
            let m = perPointStrength.count
            var ptCDF: [Double] = Array(repeating: 0.0, count: m)
            var totalPt: Double = 0.0
            let ptFloor = isTightBudget ? 0.070 : 0.050

            @inline(__always)
            func pointDamp(_ i: Int) -> Double {
                let p = surfacePoints[i]
                let h = max(0.0, Double(baselineY) - Double(p.y))
                let hFrac = RainSurfaceMath.clamp01(h / baselineDist)

                let yPrev = Double(surfacePoints[max(0, i - 1)].y)
                let yNext = Double(surfacePoints[min(m - 1, i + 1)].y)
                let dyPx = abs(yNext - yPrev) * Double(scale)
                let slopeNorm = RainSurfaceMath.clamp01(dyPx / slopeDenomPx)

                let high = RainSurfaceMath.smoothstep(0.55, 0.90, hFrac)
                let flat = 1.0 - RainSurfaceMath.smoothstep(0.06, 0.22, slopeNorm)
                let plateau = high * flat

                return max(0.35, 1.0 - plateau * 0.65)
            }

            for i in 0..<m {
                let s = RainSurfaceMath.clamp01(perPointStrength[i])
                if s <= 0.000_01 {
                    ptCDF[i] = totalPt
                    continue
                }
                totalPt += (ptFloor + s) * (0.40 + 0.60 * s) * pointDamp(i)
                ptCDF[i] = totalPt
            }

            if totalPt > 0.000_001 {
                func pickPoint(_ u01: Double) -> Int {
                    let target = u01 * totalPt
                    var lo = 0
                    var hi = ptCDF.count - 1
                    while lo < hi {
                        let mid = (lo + hi) >> 1
                        if ptCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
                    }
                    return max(0, min(ptCDF.count - 1, lo))
                }

                let beadCap = isTightBudget ? 820 : 6_200
                let beadBase = Int((Double(surfacePoints.count) * (isTightBudget ? 3.7 : 8.9) * (0.48 + 0.52 * maxStrength) * (0.82 + 0.18 * density)).rounded(.toNearestOrAwayFromZero))
                let beadCount = min(beadCap, max(0, beadBase))

                if beadCount > 0 {
                    for _ in 0..<beadCount {
                        let i = pickPoint(prng.nextFloat01())
                        let s = RainSurfaceMath.clamp01(perPointStrength[i])
                        if s <= 0.000_01 { continue }

                        let p = surfacePoints[i]
                        let nn = normals[i]
                        let tan = CGVector(dx: -nn.dy, dy: nn.dx)

                        let d = CGFloat(pow(prng.nextFloat01(), 2.9)) * outsideWidth * 0.58
                        let jitter = CGFloat(prng.nextSignedFloat()) * bandWidthPt * 0.20

                        let cx = p.x + nn.dx * d + tan.dx * jitter
                        let cy = p.y + nn.dy * d + tan.dy * jitter

                        if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
                        if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

                        let rrT = CGFloat(pow(prng.nextFloat01(), 2.8))
                        var rr = (r0 * 0.34) + (r1 * 0.62 - r0 * 0.34) * rrT
                        var a = baseAlpha * (0.55 + 0.45 * s) * (0.84 + 0.16 * density) * pointDamp(i)

                        if !isTightBudget, prng.nextFloat01() < 0.06 {
                            rr *= 1.55
                            a *= 0.62
                        }

                        a = max(0.0, min(1.0, a))
                        let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
                        addDot(to: &outsideBins[bin], cx: cx, cy: cy, r: rr)
                    }
                }
            }
        }

        if outsideBins.contains(where: { !$0.isEmpty }) {
            context.drawLayer { layer in
                let bleed = max(0.0, bandWidthPt * 3.0)
                var outside = Path()
                outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
                outside.addPath(corePath)
                layer.clip(to: outside, style: FillStyle(eoFill: true))
                layer.blendMode = .plusLighter

                // No halo: keep the blur very small and skip it in tight budgets.
                let microBlur: CGFloat = isTightBudget ? 0.0 : min(0.90, bandWidthPt * 0.028)
                if microBlur > 0.001 { layer.addFilter(.blur(radius: microBlur)) }

                for b in 0..<bins {
                    if outsideBins[b].isEmpty { continue }
                    let a = (Double(b + 1) / Double(bins)) * baseAlpha
                    let aa = max(0.0, min(1.0, a))
                    layer.fill(outsideBins[b], with: .color(boostedColor.opacity(aa)))
                }
            }
        }

        if useInsideSpeckles, insideBins.contains(where: { !$0.isEmpty }) {
            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .plusLighter
                for b in 0..<bins {
                    if insideBins[b].isEmpty { continue }
                    let a = (Double(b + 1) / Double(bins)) * baseAlpha * insideOpacity * 0.78
                    let aa = max(0.0, min(1.0, a))
                    layer.fill(insideBins[b], with: .color(boostedColor.opacity(aa)))
                }
            }
        }
    }
}
