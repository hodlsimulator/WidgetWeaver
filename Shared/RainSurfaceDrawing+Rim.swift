//
//  RainSurfaceDrawing+Rim.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI

extension RainSurfaceDrawing {
    // MARK: - Rim (no stroke-line look)
    static func drawRim(
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
        guard surfacePoints.count >= 2 else { return }

        let scale = max(1.0, displayScale)

        func outsideClip(_ layer: inout GraphicsContext) {
            let bleed = max(0.0, bandWidthPt * 3.0)
            var outside = Path()
            outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
            outside.addPath(corePath)
            layer.clip(to: outside, style: FillStyle(eoFill: true))
        }

        let outerW = max(1.0, CGFloat(cfg.rimOuterWidthPixels) / scale)
        let outerA = max(0.0, min(1.0, cfg.rimOuterOpacity))

        if outerA > 0.000_1, outerW > 0.25 {
            let bins = isTightBudget ? 4 : 6
            let binned = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, bins: bins)

            context.drawLayer { layer in
                outsideClip(&layer)
                layer.blendMode = .plusLighter

                let blur = isTightBudget ? 0.0 : max(0.0, min(3.0, outerW * 0.18))
                if blur > 0.001 { layer.addFilter(.blur(radius: blur)) }

                for i in 0..<bins {
                    let s = binned.avg[i]
                    if s <= 0.000_01 { continue }
                    let a = outerA * (0.30 + 0.70 * s) * (0.70 + 0.30 * maxStrength)
                    if a <= 0.000_1 { continue }
                    layer.stroke(binned.paths[i], with: .color(cfg.rimColor.opacity(a)), lineWidth: outerW)
                }
            }
        }

        let beadBaseOpacity = max(0.0, min(1.0, cfg.rimInnerOpacity)) * 0.20

        if beadBaseOpacity > 0.000_1,
           perPointStrength.count == surfacePoints.count,
           normals.count == surfacePoints.count
        {
            var cdf: [Double] = Array(repeating: 0.0, count: perPointStrength.count)
            var total: Double = 0.0
            let floorForNonZero = isTightBudget ? 0.070 : 0.050

            for i in 0..<perPointStrength.count {
                let s = RainSurfaceMath.clamp01(perPointStrength[i])
                if s <= 0.000_01 {
                    cdf[i] = total
                    continue
                }
                total += (floorForNonZero + s) * (0.45 + 0.55 * s)
                cdf[i] = total
            }

            if total > 0.000_001 {
                func pick(_ u01: Double) -> Int {
                    let target = u01 * total
                    var lo = 0
                    var hi = cdf.count - 1
                    while lo < hi {
                        let mid = (lo + hi) >> 1
                        if cdf[mid] >= target { hi = mid } else { lo = mid + 1 }
                    }
                    return max(0, min(cdf.count - 1, lo))
                }

                // Fixed: valid hex literal (previously contained non-hex “R”).
                let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xA11CEE11_8100_0001)
                var prng = RainSurfacePRNG(seed: seed)

                let beadCap = isTightBudget ? 320 : 2400
                let beadBase = Int((Double(surfacePoints.count) * (isTightBudget ? 1.6 : 3.6) * (0.45 + 0.55 * maxStrength)).rounded(.toNearestOrAwayFromZero))
                let beadCount = min(beadCap, max(0, beadBase))

                let r0 = 0.20 / scale
                let r1 = 0.55 / scale
                let jitterT = (isTightBudget ? 0.10 : 0.14) * bandWidthPt

                let bins = isTightBudget ? 3 : 5
                var beadBins: [Path] = Array(repeating: Path(), count: bins)

                for _ in 0..<beadCount {
                    let i = pick(prng.nextFloat01())
                    let s = RainSurfaceMath.clamp01(perPointStrength[i])
                    if s <= 0.000_01 { continue }

                    let p = surfacePoints[i]
                    let n = normals[i]
                    let tan = CGVector(dx: -n.dy, dy: n.dx)

                    let d = CGFloat(pow(prng.nextFloat01(), 2.6)) * bandWidthPt * 0.18
                    let jt = CGFloat(prng.nextSignedFloat()) * jitterT

                    // Fixed: break into simple CGFloat sub-expressions (avoids type-check timeout).
                    let nx: CGFloat = n.dx
                    let ny: CGFloat = n.dy
                    let tx: CGFloat = tan.dx
                    let ty: CGFloat = tan.dy

                    let nxd: CGFloat = nx * d
                    let nyd: CGFloat = ny * d
                    let txj: CGFloat = tx * jt
                    let tyj: CGFloat = ty * jt

                    let cx: CGFloat = p.x + nxd + txj
                    let cy: CGFloat = p.y + nyd + tyj

                    var rr = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())
                    var a = beadBaseOpacity * (0.45 + 0.55 * s) * (0.75 + 0.25 * maxStrength)

                    if !isTightBudget, prng.nextFloat01() < 0.10 {
                        rr *= 1.70
                        a *= 0.58
                    }

                    a = max(0.0, min(1.0, a))
                    let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
                    beadBins[bin].addEllipse(in: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2))
                }

                context.drawLayer { layer in
                    outsideClip(&layer)
                    layer.blendMode = .plusLighter

                    for b in 0..<bins {
                        if beadBins[b].isEmpty { continue }
                        let a = (Double(b + 1) / Double(bins)) * beadBaseOpacity
                        let aa = max(0.0, min(1.0, a))
                        layer.fill(beadBins[b], with: .color(cfg.rimColor.opacity(aa)))
                    }
                }
            }
        }
    }
}
