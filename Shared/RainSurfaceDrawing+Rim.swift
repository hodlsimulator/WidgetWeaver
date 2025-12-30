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
        if cfg.fuzzEnabled, cfg.canEnableFuzz, maxStrength > 0.02 { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds
        let w = max(onePx, CGFloat(cfg.rimWidthPixels) / ds)

        let a = RainSurfaceMath.clamp01(cfg.rimOpacity)
        if a <= 0.0001 { return }

        var p = Path()
        p.move(to: surfacePoints[0])
        for i in 1..<surfacePoints.count {
            p.addLine(to: surfacePoints[i])
        }

        let prevBlend = context.blendMode
        context.blendMode = .plusLighter

        context.stroke(
            p,
            with: .color(cfg.rimColor.opacity(a)),
            style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        )

        context.blendMode = prevBlend

        _ = perSegmentStrength
        _ = bandWidthPt
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
        guard surfacePoints.count >= 2 else { return }

        // Avoid when fuzz is active.
        if cfg.fuzzEnabled, cfg.canEnableFuzz, maxStrength > 0.02 { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds

        let count = max(0, cfg.glintCount)
        if count == 0 { return }

        let maxA = RainSurfaceMath.clamp01(cfg.glintMaxOpacity)
        if maxA <= 0.0001 { return }

        let minR = max(onePx, CGFloat(cfg.glintRadiusPixels.lowerBound) / ds)
        let maxR = max(minR, CGFloat(cfg.glintRadiusPixels.upperBound) / ds)

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0x91A7_91A7_0000_0001))

        // Prefer points with low fuzz.
        let candidates = surfacePoints.indices.filter { i in
            let s = (i < perPointStrength.count) ? perPointStrength[i] : 0.0
            return s < 0.08
        }
        if candidates.isEmpty { return }

        let prevBlend = context.blendMode
        context.blendMode = .plusLighter

        for _ in 0..<count {
            let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]
            let p = surfacePoints[idx]

            let rrUnit = prng.nextFloat01()
            let rr = minR + (maxR - minR) * CGFloat(pow(rrUnit, 1.35))

            let aUnit = prng.nextFloat01()
            let a = maxA * (0.30 + 0.70 * aUnit)

            let q = CGPoint(
                x: p.x + CGFloat(prng.nextSignedFloat()) * rr * 0.35,
                y: p.y + CGFloat(prng.nextSignedFloat()) * rr * 0.20
            )

            context.fill(
                Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2)),
                with: .color(Color.white.opacity(a))
            )
        }

        context.blendMode = prevBlend

        _ = geometry
        _ = bandWidthPt
    }
}
