//
//  RainSurfaceDrawing+Core.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension RainSurfaceDrawing {
    static func isTightBudgetMode(_ cfg: RainForecastSurfaceConfiguration) -> Bool {
        (cfg.maxDenseSamples <= 280) || (cfg.fuzzSpeckleBudget <= 900)
    }

    static func fuzzBandWidthPixels(chartRect: CGRect, cfg: RainForecastSurfaceConfiguration, displayScale: CGFloat) -> CGFloat {
        let pxFromFraction = chartRect.height * cfg.fuzzWidthFraction * max(1.0, displayScale)
        let clamped = min(max(pxFromFraction, cfg.fuzzWidthPixelsClamp.lowerBound), cfg.fuzzWidthPixelsClamp.upperBound)
        return max(6.0, clamped)
    }

    // Styling-only strength:
    // - Height is intensity-driven only.
    // - Certainty/probability affects styling only.
    // - Tail is styling-only after the last wet minute (geometry provides x-window).
    static func computeFuzzStrengthPerPoint(
        geometry: RainSurfaceGeometry,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat
    ) -> [Double] {
        let n = geometry.sampleCount
        guard n > 0 else { return [] }

        let scale = max(1.0, geometry.displayScale)
        let onePx = 1.0 / max(1.0, scale)

        let wetByHeight: [Bool] = geometry.heights.map { $0 > (onePx * 0.5) }

        let thr = RainSurfaceMath.clamp01(cfg.fuzzChanceThreshold)
        let trans = max(0.000_1, cfg.fuzzChanceTransition)
        let floorBase = RainSurfaceMath.clamp01(cfg.fuzzChanceFloor)
        let expn = max(0.10, cfg.fuzzChanceExponent)

        let baselineDist = max(1.0, geometry.baselineY - geometry.chartRect.minY)
        let lowPower = max(0.10, cfg.fuzzLowHeightPower)
        let lowBoostMax = max(0.0, cfg.fuzzLowHeightBoost)

        let bandPt = bandWidthPx / scale
        let slopeDenom = max(0.08, bandPt * 0.65)
        let slopeBoostMax = max(0.0, min(0.85, 0.22 + 0.58 * lowBoostMax))

        var baseStrength: [Double] = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            let chance = RainSurfaceMath.clamp01(geometry.certaintyAt(i))
            let floorS = (chance <= 0.000_5) ? 0.0 : floorBase

            let u = RainSurfaceMath.clamp01((chance - thr) / trans)
            let mapped = floorS + (1.0 - floorS) * pow(u, expn)

            let h = Double(geometry.heights[i])
            let hFrac = RainSurfaceMath.clamp01(h / Double(baselineDist))

            let low = pow(max(0.0, 1.0 - hFrac), lowPower)
            let lowBoost = lowBoostMax * low

            let yPrev = Double(geometry.surfaceYAt(max(0, i - 1)))
            let yNext = Double(geometry.surfaceYAt(min(n - 1, i + 1)))
            let slopePx = abs(yNext - yPrev) * Double(scale)
            let slopeNorm = RainSurfaceMath.clamp01(slopePx / Double(slopeDenom))
            let slopeBoost = slopeBoostMax * pow(slopeNorm, 1.10)

            baseStrength[i] = RainSurfaceMath.clamp01(mapped + lowBoost + slopeBoost)
        }

        let tailMin = RainSurfaceMath.clamp01(cfg.fuzzChanceMinStrength)
        let lastWetDense = wetByHeight.lastIndex(where: { $0 })
        var tailBase = tailMin
        if let lastWetDense {
            tailBase = max(tailBase, baseStrength[lastWetDense])
        }

        let tailStartX = geometry.tailStartX
        let tailEndX = geometry.tailEndX

        func tailMultiplier(forX x: CGFloat) -> Double {
            guard let s = tailStartX, let e = tailEndX, e > s else { return 0.0 }
            if x <= s { return 0.0 }
            if x >= e { return 0.0 }
            let t = Double((x - s) / (e - s))
            let u = RainSurfaceMath.clamp01(t)
            let fade = 1.0 - RainSurfaceMath.smoothstep01(u)
            return pow(max(0.0, fade), 0.70)
        }

        var out: [Double] = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            if wetByHeight[i] {
                out[i] = baseStrength[i]
            } else {
                let x = geometry.xAt(i)
                let tm = tailMultiplier(forX: x)
                if tm > 0.0 {
                    out[i] = RainSurfaceMath.clamp01(tailBase * tm)
                } else {
                    out[i] = 0.0
                }
            }
        }
        return out
    }

    static func computePerSegmentStrength(perPoint: [Double]) -> [Double] {
        guard perPoint.count >= 2 else { return [] }
        var s: [Double] = []
        s.reserveCapacity(perPoint.count - 1)
        for i in 0..<(perPoint.count - 1) {
            s.append(0.5 * (perPoint[i] + perPoint[i + 1]))
        }
        return s
    }

    // Outward normal for a left-to-right surface polyline where the interior is below the curve.
    // Ensures dy <= 0 (points “up” in screen coordinates).
    static func computeOutwardNormals(points: [CGPoint]) -> [CGVector] {
        let n = points.count
        guard n >= 2 else { return Array(repeating: CGVector(dx: 0, dy: -1), count: n) }

        func normalised(_ v: CGVector) -> CGVector {
            let len = sqrt(v.dx * v.dx + v.dy * v.dy)
            if len < 0.000_001 { return CGVector(dx: 0, dy: -1) }
            return CGVector(dx: v.dx / len, dy: v.dy / len)
        }

        var normals: [CGVector] = Array(repeating: CGVector(dx: 0, dy: -1), count: n)

        for i in 0..<n {
            let p0 = points[max(0, i - 1)]
            let p1 = points[min(n - 1, i + 1)]
            let tx = p1.x - p0.x
            let ty = p1.y - p0.y

            var nn = normalised(CGVector(dx: ty, dy: -tx))

            if nn.dy > 0 {
                nn = CGVector(dx: -nn.dx, dy: -nn.dy)
            }
            normals[i] = nn
        }
        return normals
    }

    static func boostedFuzzColor(_ cfg: RainForecastSurfaceConfiguration) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(cfg.fuzzColor)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            let rr = min(1.0, r * 1.00)
            let gg = min(1.0, g * 1.06)
            let bb = min(1.0, b * 1.18)
            return Color(red: Double(rr), green: Double(gg), blue: Double(bb), opacity: Double(a))
        }
        return cfg.fuzzColor
        #else
        return cfg.fuzzColor
        #endif
    }

    static func buildBinnedSegmentPaths(
        points: [CGPoint],
        perSegmentStrength: [Double],
        bins: Int
    ) -> (paths: [Path], avg: [Double]) {
        let n = points.count
        guard bins >= 2, n >= 2, perSegmentStrength.count == n - 1 else {
            return (
                Array(repeating: Path(), count: max(2, bins)),
                Array(repeating: 0.0, count: max(2, bins))
            )
        }

        var paths = Array(repeating: Path(), count: bins)
        var sum = Array(repeating: 0.0, count: bins)
        var cnt = Array(repeating: 0, count: bins)

        for i in 0..<(n - 1) {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 { continue }

            let b = min(bins - 1, max(0, Int(floor(s * Double(bins)))))
            var seg = Path()
            seg.move(to: points[i])
            seg.addLine(to: points[i + 1])
            paths[b].addPath(seg)
            sum[b] += s
            cnt[b] += 1
        }

        var avg = Array(repeating: 0.0, count: bins)
        for i in 0..<bins {
            if cnt[i] > 0 { avg[i] = sum[i] / Double(cnt[i]) }
        }
        return (paths, avg)
    }

    // MARK: - Core styling
    static func drawCoreTopLift(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePath: Path,
        chartRect: CGRect,
        baselineY: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double,
        fuzzAllowed: Bool,
        isTightBudget: Bool
    ) {
        let mix = max(0.0, min(1.0, Double(cfg.coreTopMix)))
        let wantsWeld = fuzzAllowed && (cfg.fuzzMaxOpacity > 0.000_1) && (maxStrength > 0.01)

        guard mix > 0.000_1 || wantsWeld else { return }

        let h = max(1.0, baselineY - chartRect.minY)

        let topAlpha = min(1.0, max(0.0, (0.16 + 0.08 * maxStrength) * mix))
        let midAlpha = min(1.0, max(0.0, (0.07 + 0.05 * maxStrength) * mix))
        let midLoc = min(0.88, 0.58)

        let grad = Gradient(stops: [
            .init(color: cfg.coreTopColor.opacity(topAlpha), location: 0.0),
            .init(color: cfg.coreTopColor.opacity(midAlpha), location: midLoc),
            .init(color: cfg.coreTopColor.opacity(0.0), location: 1.0)
        ])

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter

            if mix > 0.000_1 {
                var rect = Path()
                rect.addRect(CGRect(x: chartRect.minX, y: chartRect.minY, width: chartRect.width, height: h))
                layer.fill(
                    rect,
                    with: .linearGradient(
                        grad,
                        startPoint: CGPoint(x: chartRect.midX, y: chartRect.minY),
                        endPoint: CGPoint(x: chartRect.midX, y: baselineY)
                    )
                )
            }

            if wantsWeld, !isTightBudget {
                let w = max(0.65, min(10.0, bandWidthPt * CGFloat(max(0.30, cfg.fuzzInsideHazeStrokeWidthFactor)) * 0.55))
                let a = min(0.16, max(0.020, cfg.fuzzMaxOpacity * 0.10 * (0.70 + 0.30 * maxStrength)))
                layer.stroke(surfacePath, with: .color(boostedFuzzColor(cfg).opacity(a)), lineWidth: w)
            }
        }
    }

    static func drawCoreEdgeFade(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePath: Path,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let f = max(0.0, min(0.40, Double(cfg.coreFadeFraction)))
        guard f > 0.000_1 else { return }

        let w = max(0.65, min(14.0, bandWidthPt * CGFloat(f) * 1.15))
        let blur = max(0.0, min(7.0, w * 0.90))
        let baseA = min(0.18, max(0.03, f * (0.80 + 0.30 * maxStrength)))

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            if blur > 0.001 { layer.addFilter(.blur(radius: blur)) }
            layer.stroke(surfacePath, with: .color(Color.white.opacity(baseA)), lineWidth: w)
        }
    }

    // MARK: - Baseline grain
    static func drawBaselineGrain(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        baselineY: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat,
        maxStrength: Double,
        isTightBudget: Bool
    ) {
        let scale = max(1.0, displayScale)

        let baseCount = isTightBudget ? 190 : 420
        let widthFactor = Double(min(1.0, max(0.15, (chartRect.width * scale) / 360.0)))
        let strengthFactor = 0.50 + 0.50 * maxStrength
        let countCap = isTightBudget ? 240 : 540
        let count = max(0, min(countCap, Int(Double(baseCount) * widthFactor * strengthFactor)))

        guard count > 0 else { return }

        let bandH = max(2.0, min(14.0, (7.0 + 7.0 * maxStrength) / scale))
        let r0 = (0.22 / scale)
        let r1 = (0.92 / scale)

        let baseA = min(0.16, max(0.018, (cfg.baselineLineOpacity * 0.11) + (cfg.fuzzMaxOpacity * 0.040)))
        let color = cfg.fuzzColor.opacity(baseA)

        var p = Path()
        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xBADA55_51A5E_0001)
        var prng = RainSurfacePRNG(seed: seed)

        for _ in 0..<count {
            let x = chartRect.minX + CGFloat(prng.nextFloat01()) * chartRect.width
            let y = baselineY - CGFloat(prng.nextFloat01()) * bandH
            let r = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())
            p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter
            layer.fill(p, with: .color(color))
        }
    }

    // MARK: - Gloss
    static func drawGloss(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePath: Path,
        chartRect: CGRect,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let maxA = max(0.0, min(0.35, cfg.glossMaxOpacity))
        guard maxA > 0.000_1 else { return }

        let hFrac = max(0.10, min(0.90, cfg.glossHeightFraction))
        let glossH = max(1.0, chartRect.height * CGFloat(hFrac))

        let grad = Gradient(stops: [
            .init(color: Color.white.opacity(maxA), location: 0.0),
            .init(color: Color.white.opacity(maxA * 0.35), location: 0.45),
            .init(color: Color.white.opacity(0.0), location: 1.0),
        ])

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter
            var rect = Path()
            rect.addRect(CGRect(x: chartRect.minX, y: chartRect.minY, width: chartRect.width, height: glossH))
            layer.fill(
                rect,
                with: .linearGradient(
                    grad,
                    startPoint: CGPoint(x: chartRect.midX, y: chartRect.minY),
                    endPoint: CGPoint(x: chartRect.midX, y: chartRect.minY + glossH)
                )
            )
        }
    }

    // MARK: - Glints
    static func drawGlints(
        in context: inout GraphicsContext,
        surfacePoints: [CGPoint],
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let count = max(0, min(64, cfg.glintCount))
        guard count > 0 else { return }

        let maxA = max(0.0, min(0.40, cfg.glintMaxOpacity))
        guard maxA > 0.000_1 else { return }

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed ^ cfg.glintSeed, 0xD1CE_F00D_0000_0001)
        var prng = RainSurfacePRNG(seed: seed)

        let r0 = 0.25 / scale
        let r1 = 1.10 / scale

        var p = Path()
        for _ in 0..<count {
            let idx = Int(floor(prng.nextFloat01() * Double(max(1, surfacePoints.count - 1))))
            let base = surfacePoints[max(0, min(surfacePoints.count - 1, idx))]
            let x = base.x + CGFloat(prng.nextSignedFloat()) * (2.0 / scale)
            let y = base.y + CGFloat(prng.nextSignedFloat()) * (1.2 / scale)
            let r = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())
            p.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.fill(p, with: .color(Color.white.opacity(maxA)))
        }
    }
}
