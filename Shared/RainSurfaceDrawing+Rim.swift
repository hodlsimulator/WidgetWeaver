//
//  RainSurfaceDrawing+Rim.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
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
        guard cfg.rimEnabled else { return }
        guard maxStrength > 0.06 else { return }
        guard surfacePoints.count > 2 else { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let innerW = max(onePx, CGFloat(cfg.rimInnerWidthPixels) / displayScale)
        let outerW = max(onePx, CGFloat(cfg.rimOuterWidthPixels) / displayScale)

        var p = Path()
        p.move(to: surfacePoints[0])
        for i in 1..<surfacePoints.count { p.addLine(to: surfacePoints[i]) }

        let innerA = max(0.0, min(1.0, cfg.rimInnerOpacity)) * Double(maxStrength)
        let outerA = max(0.0, min(1.0, cfg.rimOuterOpacity)) * Double(maxStrength)

        if outerA > 0.0001 {
            context.stroke(
                p,
                with: .color(cfg.rimColor.opacity(outerA)),
                style: StrokeStyle(lineWidth: outerW, lineCap: .round, lineJoin: .round)
            )
        }

        if innerA > 0.0001 {
            context.stroke(
                p,
                with: .color(cfg.rimColor.opacity(innerA)),
                style: StrokeStyle(lineWidth: innerW, lineCap: .round, lineJoin: .round)
            )
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
        guard surfacePoints.count > 4 else { return }

        // Candidate indices: strong, wet, and not too close to ends.
        let onePx = 1.0 / max(1.0, displayScale)
        let wetEps = max(onePx * 0.5, 0.0001)

        var candidates: [Int] = []
        candidates.reserveCapacity(12)

        for i in 3..<(surfacePoints.count - 3) {
            let h = baselineY - surfacePoints[i].y
            if h <= wetEps { continue }

            let s = perPointStrength[i]
            if s < 0.35 { continue }

            // Avoid cramped glints on steep spikes by preferring moderate slopes.
            let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
            let up = max(0.0, -n.y)
            if up < 0.25 { continue }

            candidates.append(i)
        }
        if candidates.isEmpty { return }

        let count = max(0, min(cfg.glintCount, 6))
        if count == 0 { return }

        let maxA = max(0.0, min(1.0, cfg.glintMaxOpacity))
        let glintW = max(onePx, bandWidthPt * 0.16)
        let glintL = max(onePx * 4.0, bandWidthPt * 0.65)

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0x9117_1234_55AA_7788))
        var p = Path()

        for _ in 0..<count {
            let idx = Int(prng.nextUInt64() % UInt64(candidates.count))
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

            // Orientation aligned to tangent.
            let halfL = glintL * CGFloat(0.45 + 0.55 * Double(prng.nextFloat01()))
            let halfW = glintW * CGFloat(0.70 + 0.30 * Double(prng.nextFloat01()))

            let a = CGPoint(x: c.x - t.x * halfL - n.x * halfW, y: c.y - t.y * halfL - n.y * halfW)
            let b = CGPoint(x: c.x + t.x * halfL - n.x * halfW, y: c.y + t.y * halfL - n.y * halfW)
            let d = CGPoint(x: c.x - t.x * halfL + n.x * halfW, y: c.y - t.y * halfL + n.y * halfW)
            let e = CGPoint(x: c.x + t.x * halfL + n.x * halfW, y: c.y + t.y * halfL + n.y * halfW)

            p.move(to: a)
            p.addLine(to: b)
            p.addLine(to: e)
            p.addLine(to: d)
            p.closeSubpath()
        }

        if p.isEmpty { return }

        // Use rimColor for glints (glintColor does not exist in configuration at this ref).
        context.fill(p, with: .color(cfg.rimColor.opacity(maxA * 0.35)))

        _ = chartRect
    }
}
