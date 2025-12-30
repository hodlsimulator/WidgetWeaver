//
//  RainSurfaceDrawing+Rim.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Rim + optional glints.
//

import SwiftUI

extension RainSurfaceDrawing {
    static func drawRim(
        in context: inout GraphicsContext,
        surfacePoints: [CGPoint],
        maxStrength: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        guard surfacePoints.count >= 2 else { return }

        let onePx = 1.0 / max(1.0, displayScale)

        // Build a single polyline path for the rim strokes (kept subtle).
        var poly = Path()
        poly.move(to: surfacePoints[0])
        for i in 1..<surfacePoints.count {
            poly.addLine(to: surfacePoints[i])
        }

        let innerW = max(onePx, CGFloat(cfg.rimInnerWidthPixels) / displayScale)
        let outerW = max(onePx, CGFloat(cfg.rimOuterWidthPixels) / displayScale)

        let innerA = max(0.0, min(1.0, cfg.rimInnerOpacity)) * (0.55 + 0.45 * Double(maxStrength))
        let outerA = max(0.0, min(1.0, cfg.rimOuterOpacity)) * (0.55 + 0.45 * Double(maxStrength))

        // Outer glow (blurred, very low alpha to avoid lifting black background).
        if outerA > 0.0001 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.addFilter(.blur(radius: min(2.0, outerW * 0.55)))
                layer.stroke(poly, with: .color(cfg.rimColor.opacity(outerA)), style: StrokeStyle(lineWidth: outerW, lineCap: .round, lineJoin: .round))
            }
        }

        // Inner highlight (thin, minimal).
        if innerA > 0.0001 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.stroke(poly, with: .color(cfg.rimColor.opacity(innerA)), style: StrokeStyle(lineWidth: innerW, lineCap: .round, lineJoin: .round))
            }
        }
    }

    static func drawGlints(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perPointStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        guard cfg.glintEnabled else { return }
        guard surfacePoints.count == perPointStrength.count else { return }
        guard surfacePoints.count > 6 else { return }

        let onePx = 1.0 / max(1.0, displayScale)

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, cfg.glintSeed ^ 0x91BADD_12345678))

        // Pick a few indices in strong regions.
        var candidates: [Int] = []
        candidates.reserveCapacity(surfacePoints.count / 3)

        for i in 0..<perPointStrength.count {
            if perPointStrength[i] > 0.32 {
                candidates.append(i)
            }
        }
        if candidates.isEmpty { return }

        let count = max(0, min(cfg.glintCount, 6))
        if count == 0 { return }

        let maxA = max(0.0, min(1.0, cfg.glintMaxOpacity))
        let glintW = max(onePx, bandWidthPt * 0.16)
        let glintL = max(onePx * 4.0, bandWidthPt * 0.65)

        var p = Path()

        for _ in 0..<count {
            let idx = Int(prng.nextUInt32() % UInt32(candidates.count))
            let i = candidates[idx]

            let base = surfacePoints[i]
            let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
            let t = CGPoint(x: n.y, y: -n.x)

            // Place slightly outward and along tangent.
            let offsetN = CGFloat(0.10 + 0.25 * Double(prng.nextFloat01())) * bandWidthPt
            let offsetT = CGFloat(Double(prng.nextSignedFloat())) * bandWidthPt * 0.35

            let c = CGPoint(
                x: base.x + n.x * offsetN + t.x * offsetT,
                y: base.y + n.y * offsetN + t.y * offsetT
            )

            // Small capsule-ish glint built from a rounded rect rotated along tangent.
            // Approximate by drawing a thin line segment (blurred).
            let a = Double(perPointStrength[i])
            let half = glintL * CGFloat(0.45 + 0.30 * Double(prng.nextFloat01()))
            let a0 = CGPoint(x: c.x - t.x * half, y: c.y - t.y * half)
            let a1 = CGPoint(x: c.x + t.x * half, y: c.y + t.y * half)

            p.move(to: a0)
            p.addLine(to: a1)

            _ = a
        }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: min(1.6, glintW * 0.75)))
            layer.stroke(p, with: .color(cfg.rimColor.opacity(maxA)), style: StrokeStyle(lineWidth: glintW, lineCap: .round))
        }

        _ = chartRect
        _ = baselineY
    }
}
