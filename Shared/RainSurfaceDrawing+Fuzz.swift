//
//  RainSurfaceDrawing+Fuzz.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI

extension RainSurfaceDrawing {
    // MARK: - Fuzz haze
    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        guard surfacePoints.count >= 2 else { return }

        let boosted = boostedFuzzColor(cfg)

        let baseOpacity = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzHazeStrength))
        guard baseOpacity > 0.000_1 else { return }

        let blur = max(0.0, min(8.0, bandWidthPt * CGFloat(max(0.0, cfg.fuzzHazeBlurFractionOfBand))))
        let strokeW = max(0.60, min(22.0, bandWidthPt * CGFloat(max(0.20, cfg.fuzzHazeStrokeWidthFactor))))

        let bins = 6
        let binned = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, bins: bins)

        context.drawLayer { layer in
            let bleed = max(0.0, bandWidthPt * 3.0)
            var outside = Path()
            outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
            outside.addPath(corePath)
            layer.clip(to: outside, style: FillStyle(eoFill: true))
            layer.blendMode = .plusLighter
            if blur > 0.001 { layer.addFilter(.blur(radius: blur)) }

            for i in 0..<bins {
                let s = binned.avg[i]
                if s <= 0.000_01 { continue }
                let a = baseOpacity * (0.10 + 0.90 * s) * (0.72 + 0.28 * maxStrength)
                if a <= 0.000_1 { continue }
                layer.stroke(binned.paths[i], with: .color(boosted.opacity(a)), lineWidth: strokeW)
            }
        }

        let insideOpacity = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
        if insideOpacity > 0.000_1 {
            let insideW = max(0.55, min(18.0, bandWidthPt * CGFloat(max(0.20, cfg.fuzzInsideHazeStrokeWidthFactor))))
            let blurInside = max(0.0, min(6.0, blur * 0.60))

            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .plusLighter
                if blurInside > 0.001 { layer.addFilter(.blur(radius: blurInside)) }
                for i in 0..<bins {
                    let s = binned.avg[i]
                    if s <= 0.000_01 { continue }
                    let a = baseOpacity * insideOpacity * 0.55 * (0.15 + 0.85 * s) * (0.72 + 0.28 * maxStrength)
                    if a <= 0.000_1 { continue }
                    layer.stroke(binned.paths[i], with: .color(boosted.opacity(a)), lineWidth: insideW)
                }
            }
        }
    }

    // MARK: - Core erosion (optional)
    static func drawCoreErosion(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        guard surfacePoints.count >= 2 else { return }
        guard maxStrength > 0.02 else { return }

        let baseStrength = max(0.0, min(1.0, cfg.fuzzErodeStrength))
        guard baseStrength > 0.000_1 else { return }

        let blur = max(0.0, min(10.0, bandWidthPt * CGFloat(max(0.0, cfg.fuzzErodeBlurFractionOfBand))))
        let strokeW = max(0.75, min(26.0, bandWidthPt * CGFloat(max(0.20, cfg.fuzzErodeStrokeWidthFactor))))

        let bins = 6
        let binned = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, bins: bins)

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            if blur > 0.001 { layer.addFilter(.blur(radius: blur)) }

            let edgePow = max(0.10, cfg.fuzzErodeEdgePower)
            for i in 0..<bins {
                let s = binned.avg[i]
                if s <= 0.000_01 { continue }
                let w = pow(s, edgePow)
                let a = baseStrength * (0.08 + 0.30 * w) * (0.70 + 0.30 * maxStrength)
                if a <= 0.000_1 { continue }
                layer.stroke(binned.paths[i], with: .color(Color.white.opacity(a)), lineWidth: strokeW)
            }
        }
    }

    // MARK: - Fuzz speckles (primary)
    static func drawFuzzSpeckles(
        in context: inout GraphicsContext,
        chartRect: CGRect,
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
        if isTightBudget { baseAlpha = min(1.0, baseAlpha * 1.08) }

        let rPx0 = max(0.22, min(3.0, cfg.fuzzSpeckleRadiusPixels.lowerBound))
        let rPx1 = max(rPx0, min(6.0, cfg.fuzzSpeckleRadiusPixels.upperBound))
        var r0 = rPx0 / scale
        var r1 = rPx1 / scale
        if isTightBudget {
            r0 *= 1.30
            r1 *= 1.22
        }

        let budget0 = max(0, min(6500, cfg.fuzzSpeckleBudget))
        let strengthScale = max(0.0, min(1.0, 0.35 + 0.65 * maxStrength))
        let densityScale = max(0.0, min(1.0, 0.78 + 0.22 * density))
        var baseCount = Int((Double(budget0) * strengthScale * densityScale).rounded(.toNearestOrAwayFromZero))
        let baseCap = isTightBudget ? 520 : 6500
        baseCount = min(baseCap, max(0, baseCount))
        if baseCount <= 0 { return }

        let segCount = perSegmentStrength.count
        guard segCount >= 2 else { return }

        var segCDF: [Double] = Array(repeating: 0.0, count: segCount)
        var totalW: Double = 0.0
        let floorForNonZero: Double = isTightBudget ? 0.060 : 0.045

        for i in 0..<segCount {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 {
                segCDF[i] = totalW
                continue
            }
            let w = (floorForNonZero + s) * (0.35 + 0.65 * s)
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

        let useInsideSpeckles = (!isTightBudget) && (insideWidth > 0.000_01) && (cfg.fuzzInsideOpacityFactor > 0.000_1)
        var insideBins: [Path] = useInsideSpeckles ? Array(repeating: Path(), count: bins) : []

        let insideFraction = useInsideSpeckles ? max(0.0, min(1.0, cfg.fuzzInsideSpeckleFraction)) : 0.0

        let powOutside = max(0.10, cfg.fuzzDistancePowerOutside)
        let powInside = max(0.10, cfg.fuzzDistancePowerInside)
        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        var macroCount = 0
        let macroCap = isTightBudget ? 0 : 180
        let macroChance = isTightBudget ? 0.0 : 0.060

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

            var rr = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())

            var alphaMul: Double = 1.0
            if !insidePick, macroCount < macroCap, prng.nextFloat01() < macroChance {
                macroCount += 1
                rr *= 2.20
                alphaMul *= 0.55
            }

            let denom = Double(width)
            let distWeight: Double = {
                if denom <= 0.000_001 { return 1.0 }
                let a = min(1.0, max(0.0, 1.0 - Double(abs(signedDist)) / denom))
                let pp = insidePick ? powInside : powOutside
                return pow(a, max(0.10, pp))
            }()

            var a = baseAlpha * (0.24 + 0.76 * sSeg) * distWeight * alphaMul
            if insidePick {
                a *= max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
            }
            a *= (0.82 + 0.18 * density)
            a = max(0.0, min(1.0, a))

            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            if insidePick, useInsideSpeckles {
                addDot(to: &insideBins[bin], cx: cx, cy: cy, r: rr)
            } else {
                addDot(to: &outsideBins[bin], cx: cx, cy: cy, r: rr)
            }
        }

        // Edge beads: dense, edge-hugging continuity.
        if surfacePoints.count >= 3, perPointStrength.count == surfacePoints.count {
            let m = perPointStrength.count
            var ptCDF: [Double] = Array(repeating: 0.0, count: m)
            var totalPt: Double = 0.0
            let ptFloor = isTightBudget ? 0.070 : 0.050

            for i in 0..<m {
                let s = RainSurfaceMath.clamp01(perPointStrength[i])
                if s <= 0.000_01 {
                    ptCDF[i] = totalPt
                    continue
                }
                totalPt += (ptFloor + s) * (0.40 + 0.60 * s)
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

                let beadCap = isTightBudget ? 720 : 5200
                let beadBase = Int((Double(surfacePoints.count) * (isTightBudget ? 3.2 : 7.8) * (0.45 + 0.55 * maxStrength) * (0.82 + 0.18 * density)).rounded(.toNearestOrAwayFromZero))
                let beadCount = min(beadCap, max(0, beadBase))

                if beadCount > 0 {
                    for _ in 0..<beadCount {
                        let i = pickPoint(prng.nextFloat01())
                        let s = RainSurfaceMath.clamp01(perPointStrength[i])
                        if s <= 0.000_01 { continue }

                        let p = surfacePoints[i]
                        let nn = normals[i]
                        let tan = CGVector(dx: -nn.dy, dy: nn.dx)

                        let d = CGFloat(pow(prng.nextFloat01(), 2.8)) * outsideWidth * 0.58
                        let jitter = CGFloat(prng.nextSignedFloat()) * bandWidthPt * 0.20

                        let cx = p.x + nn.dx * d + tan.dx * jitter
                        let cy = p.y + nn.dy * d + tan.dy * jitter

                        if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
                        if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

                        var rr = (r0 * 0.44) + (r1 * 0.55 - r0 * 0.44) * CGFloat(prng.nextFloat01())
                        var a = baseAlpha * (0.55 + 0.45 * s) * (0.85 + 0.15 * density)

                        if !isTightBudget, prng.nextFloat01() < 0.08 {
                            rr *= 1.70
                            a *= 0.60
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

                let microBlur: CGFloat = isTightBudget ? 0.0 : min(1.25, bandWidthPt * 0.050)
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
                    let a = (Double(b + 1) / Double(bins)) * baseAlpha * max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor)) * 0.55
                    let aa = max(0.0, min(1.0, a))
                    layer.fill(insideBins[b], with: .color(boostedColor.opacity(aa)))
                }
            }
        }
    }
}
