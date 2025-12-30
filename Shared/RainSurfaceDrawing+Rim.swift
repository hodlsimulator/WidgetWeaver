//
//  RainSurfaceDrawing+Rim.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Rim + glint treatment (kept subtle; fuzz owns the edge).
//

import SwiftUI

extension RainSurfaceDrawing {
    static func drawRim(
        in context: inout GraphicsContext,
        surfacePoints: [CGPoint],
        perSegmentStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        maxStrength: CGFloat
    ) {
        guard cfg.rimEnabled else { return }
        guard surfacePoints.count >= 2 else { return }

        // When fuzz is active, suppress rim to avoid a "stroke line" look.
        if cfg.fuzzEnabled, cfg.canEnableFuzz, maxStrength > 0.02 {
            return
        }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds
        let w = max(onePx, CGFloat(cfg.rimWidthPixels) / ds)
        let a = clamp01(cfg.rimOpacity)

        if a <= 0.0001 { return }

        var p = Path()
        p.move(to: surfacePoints[0])
        for i in 1..<surfacePoints.count { p.addLine(to: surfacePoints[i]) }

        context.blendMode = .plusLighter
        context.stroke(p, with: .color(cfg.rimColor.opacity(a)), lineWidth: w)
        context.blendMode = .normal
    }

    static func drawGlints(
        in context: inout GraphicsContext,
        geometry: RainSurfaceGeometry,
        surfacePoints: [CGPoint],
        perPointStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        maxStrength: CGFloat
    ) {
        guard cfg.glintEnabled else { return }
        guard surfacePoints.count >= 3 else { return }

        // Glints are a highlight pass; avoid when fuzz is active.
        if cfg.fuzzEnabled, cfg.canEnableFuzz, maxStrength > 0.02 {
            return
        }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds

        let count = max(0, cfg.glintCount)
        if count == 0 { return }

        let maxA = clamp01(cfg.glintMaxOpacity)
        if maxA <= 0.0001 { return }

        let minR = max(onePx, CGFloat(cfg.glintRadiusPixels.lowerBound) / ds)
        let maxR = max(minR, CGFloat(cfg.glintRadiusPixels.upperBound) / ds)

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0x91A7_91A7_0000_0001))

        // Prefer points with low fuzz (cheap).
        let candidates = surfacePoints.indices.filter { i in
            let s = (i < perPointStrength.count) ? perPointStrength[i] : 0.0
            return s < 0.08
        }
        if candidates.isEmpty { return }

        context.blendMode = .plusLighter

        for _ in 0..<count {
            let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]
            let p = surfacePoints[idx]

            let u = Double(prng.nextFloat01())
            let rr = minR + (maxR - minR) * CGFloat(pow(u, 2.0))
            let a = maxA * (0.55 + 0.45 * Double(prng.nextFloat01()))

            let rect = CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)
            context.fill(Path(ellipseIn: rect), with: .color(cfg.rimColor.opacity(a)))
        }

        context.blendMode = .normal
    }

    private static func clamp01(_ x: Double) -> Double {
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }
}
