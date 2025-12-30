//
//  RainSurfaceDrawing+Fuzz.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Fuzz, erosion, and perforation passes (no halo; silhouette owned by dust).
//

import SwiftUI

extension RainSurfaceDrawing {
    static func drawCoreEdgeFade(
        in context: inout GraphicsContext,
        surfacePoints: [CGPoint],
        perSegmentStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        guard surfacePoints.count >= 2 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds

        // Wider fade where fuzz is strong; keep it tight overall to avoid halo.
        let fadeW = max(onePx, bandWidthPt * 0.85)
        let maxA: CGFloat = 0.42

        // Slightly more aggressive than the previous pass.
        let levels: [CGFloat] = [
            min(maxA, 0.10),
            min(maxA, 0.18),
            min(maxA, 0.28)
        ]

        // Bucket segments into 3 levels (cheap).
        var paths: [Path] = Array(repeating: Path(), count: levels.count)

        for i in 0..<(surfacePoints.count - 1) {
            let s = perSegmentStrength[min(i, perSegmentStrength.count - 1)]
            if s <= 0.0001 { continue }

            let a = CGFloat(min(1.0, Double(s))) * maxA
            var bucket = 0
            if a > levels[2] { bucket = 2 }
            else if a > levels[1] { bucket = 1 }
            else if a > levels[0] { bucket = 0 }
            else { continue }

            paths[bucket].move(to: surfacePoints[i])
            paths[bucket].addLine(to: surfacePoints[i + 1])
        }

        // destinationOut: removes from core, turning the crisp edge into a particulate dissolve.
        context.blendMode = .destinationOut
        for k in 0..<levels.count {
            if paths[k].isEmpty { continue }
            context.stroke(
                paths[k],
                with: .color(.white.opacity(Double(levels[k]))),
                lineWidth: fadeW
            )
        }
        context.blendMode = .normal
    }

    static func drawCoreErosion(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perPointStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        guard surfacePoints.count >= 3 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds
        let strength = clamp(cfg.fuzzErodeStrength, 0.0, 2.0)

        if strength <= 0.0001 { return }

        // Erode just inside the rim so it breaks into fuzz instead of outlining.
        let inset = CGFloat(cfg.fuzzErodeRimInsetPixels) / ds
        let w = max(onePx, bandWidthPt * CGFloat(cfg.fuzzErodeStrokeWidthFactor))
        let blurW = max(onePx, bandWidthPt * CGFloat(cfg.fuzzErodeBlurFractionOfBand))

        let prngSeed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xE10D_E10D_0000_0001)
        var prng = RainSurfacePRNG(seed: prngSeed)

        var erosionPath = Path()

        // Build short eroding marks along the rim, offset inward by normal.
        for i in 0..<surfacePoints.count {
            let s = (i < perPointStrength.count) ? perPointStrength[i] : 0.0
            if s <= 0.01 { continue }

            let u = Double(s)

            // Along-tangent jitter to avoid a continuous "stroke" removal.
            let jitter = CGFloat((prng.nextSignedFloat()) * Float(cfg.fuzzAlongTangentJitter)) * bandWidthPt * 0.25

            let p = surfacePoints[i]
            let nrm = normals[min(i, normals.count - 1)]
            let inward = CGPoint(x: -nrm.x, y: -nrm.y)

            let q = CGPoint(x: p.x + inward.x * inset + jitter, y: p.y + inward.y * inset)

            // Tiny circles punched out of the core.
            let r = max(onePx, bandWidthPt * 0.16 * CGFloat(0.55 + 0.70 * u))
            erosionPath.addEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2))

            // Occasional scratch along the inward normal.
            if prng.nextFloat01() < Float(0.18 + 0.42 * u) {
                let scratchLen = max(onePx, bandWidthPt * 0.28 * CGFloat(0.35 + 0.90 * u))
                let s0 = CGPoint(x: q.x, y: q.y)
                let s1 = CGPoint(x: q.x + inward.x * scratchLen, y: q.y + inward.y * scratchLen)
                erosionPath.move(to: s0)
                erosionPath.addLine(to: s1)
            }
        }

        if erosionPath.isEmpty { return }

        context.saveGState()
        context.clip(to: corePath)

        context.blendMode = .destinationOut

        // Base removal.
        context.stroke(
            erosionPath,
            with: .color(.white.opacity(0.24 * strength)),
            lineWidth: w
        )

        // Soft removal pass (kept tight; not a halo).
        if blurW > onePx {
            context.stroke(
                erosionPath,
                with: .color(.white.opacity(0.18 * strength)),
                lineWidth: w + blurW
            )
        }

        context.blendMode = .normal
        context.restoreGState()
    }

    static func drawCoreDissolvePerforation(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perPointStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        // Perforation is the "break into dust" cue: small punched holes near the rim.
        guard surfacePoints.count >= 3 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds
        let insideBand = bandWidthPt * CGFloat(clamp01(cfg.fuzzInsideWidthFactor))

        // Budget is clamped hard for widget safety.
        let baseBudget = min(2_800, max(900, cfg.fuzzSpeckleBudget / 2))
        var budget = Int(Double(baseBudget) * clamp(cfg.fuzzDensity, 0.0, 2.0))
        budget = max(700, min(3_200, budget))

        let prngSeed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xD155_01E5_0000_0001)
        var prng = RainSurfacePRNG(seed: prngSeed)

        // Removal strength buckets.
        let levels: [CGFloat] = [
            0.20,
            0.34,
            0.48
        ]

        // Collect indices worth perforating.
        var candidates: [Int] = []
        candidates.reserveCapacity(surfacePoints.count)
        for i in 0..<surfacePoints.count {
            let s = (i < perPointStrength.count) ? perPointStrength[i] : 0.0
            if s > 0.10 { candidates.append(i) }
        }
        if candidates.isEmpty { return }

        var bucketPaths: [Path] = Array(repeating: Path(), count: levels.count)

        let attempts = budget * 2
        let minR = max(onePx * 0.55, CGFloat(cfg.fuzzSpeckleRadiusPixels.lowerBound) / ds)
        let maxR = max(minR, CGFloat(cfg.fuzzSpeckleRadiusPixels.upperBound) / ds * 0.95)

        for _ in 0..<attempts {
            if prng.nextFloat01() > Float(Double(budget) / Double(attempts)) { continue }

            let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]
            let p = surfacePoints[idx]
            let nrm = normals[min(idx, normals.count - 1)]
            let s = Double(perPointStrength[min(idx, perPointStrength.count - 1)])
            if s <= 0.0001 { continue }

            // Distance inside the core, scaled by strength.
            let u = Double(prng.nextFloat01())
            let dist = insideBand * CGFloat(pow(u, cfg.fuzzDistancePowerInside)) * CGFloat(0.85 + 0.25 * s)
            let q = CGPoint(x: p.x - nrm.x * dist, y: p.y - nrm.y * dist)

            // Small perforation circles.
            let rrUnit = Double(prng.nextFloat01())
            let rr = minR + (maxR - minR) * CGFloat(pow(rrUnit, 1.55))

            // Bucket by removal alpha (stronger near edges/tails).
            let a = min(0.60, 0.20 + 0.45 * s)
            var bucket = 0
            if a > Double(levels[2]) { bucket = 2 }
            else if a > Double(levels[1]) { bucket = 1 }
            else if a > Double(levels[0]) { bucket = 0 }
            else { continue }

            bucketPaths[bucket].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))

            // Occasionally add a tiny slit (helps avoid uniform stipple).
            if prng.nextFloat01() < Float(0.10 + 0.25 * s) {
                let slitLen = max(onePx, rr * 2.0 * CGFloat(0.7 + 0.9 * s))
                let t = CGPoint(x: -nrm.y, y: nrm.x)
                let a0 = CGPoint(x: q.x - t.x * slitLen * 0.5, y: q.y - t.y * slitLen * 0.5)
                let a1 = CGPoint(x: q.x + t.x * slitLen * 0.5, y: q.y + t.y * slitLen * 0.5)
                bucketPaths[bucket].move(to: a0)
                bucketPaths[bucket].addLine(to: a1)
            }
        }

        context.saveGState()
        context.clip(to: corePath)

        context.blendMode = .destinationOut
        for k in 0..<levels.count {
            if bucketPaths[k].isEmpty { continue }
            context.fill(bucketPaths[k], with: .color(.white.opacity(Double(levels[k]))))
        }
        context.blendMode = .normal

        context.restoreGState()
    }

    static func drawFuzzSpeckles(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perPointStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        guard surfacePoints.count >= 3 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds

        let maxOpacity = clamp01(cfg.fuzzMaxOpacity)
        if maxOpacity <= 0.0001 { return }

        let density = clamp(cfg.fuzzDensity, 0.0, 2.0)
        let budgetBase = max(900, min(9_000, cfg.fuzzSpeckleBudget))
        let wPx = Double(max(1.0, bandWidthPt * ds))

        // Budget grows with band width (in pixels), but is clamped.
        let budgetByWidth = max(1_400, min(9_000, Int(wPx * 20.0)))
        var budget = Int(Double(min(budgetBase, budgetByWidth)) * (0.55 + 0.85 * density))
        budget = max(1_200, min(9_000, budget))

        let insideFrac = clamp01(cfg.fuzzInsideSpeckleFraction)
        var insideBudget = Int(Double(budget) * insideFrac)
        insideBudget = max(450, min(8_000, insideBudget))
        var outsideBudget = budget - insideBudget
        outsideBudget = max(700, min(8_000, outsideBudget))

        // More rim beads: silhouette owned by dust.
        let beadCount = max(220, Int(Double(outsideBudget) * 0.42))
        let dustCount = max(200, outsideBudget - beadCount)

        let insideOpacity = clamp01(cfg.fuzzInsideOpacityFactor)

        let insideLevels: [CGFloat] = [
            CGFloat(0.24 * maxOpacity * insideOpacity),
            CGFloat(0.40 * maxOpacity * insideOpacity),
            CGFloat(0.60 * maxOpacity * insideOpacity),
            CGFloat(0.86 * maxOpacity * insideOpacity)
        ]
        let outsideLevels: [CGFloat] = [
            CGFloat(0.20 * maxOpacity),
            CGFloat(0.34 * maxOpacity),
            CGFloat(0.54 * maxOpacity),
            CGFloat(0.80 * maxOpacity)
        ]
        let beadLevels: [CGFloat] = [
            CGFloat(0.44 * maxOpacity),
            CGFloat(0.74 * maxOpacity),
            CGFloat(0.98 * maxOpacity)
        ]

        let prngSeed = RainSurfacePRNG.combine(cfg.noiseSeed, 0x5EEC_41E5_0000_0001)
        var prng = RainSurfacePRNG(seed: prngSeed)

        // Index candidates: any point with non-trivial strength (wet or tail).
        var candidates: [Int] = []
        candidates.reserveCapacity(surfacePoints.count)
        for i in 0..<surfacePoints.count {
            let s = (i < perPointStrength.count) ? perPointStrength[i] : 0.0
            if s > 0.06 { candidates.append(i) }
        }
        if candidates.isEmpty { return }

        // Radial range in points.
        let minR = max(onePx * 0.55, CGFloat(cfg.fuzzSpeckleRadiusPixels.lowerBound) / ds)
        let maxR = max(minR, CGFloat(cfg.fuzzSpeckleRadiusPixels.upperBound) / ds)

        // Outside dust + beads (not clipped).
        var dustPaths: [Path] = Array(repeating: Path(), count: outsideLevels.count)
        var beadPaths: [Path] = Array(repeating: Path(), count: beadLevels.count)

        let outsideBand = bandWidthPt
        let beadBand = bandWidthPt * 0.14

        // Beads: tightly hug the rim, plusLighter so they read as particulate glow.
        if beadCount > 0 {
            for _ in 0..<beadCount {
                let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]
                let s = Double(perPointStrength[min(idx, perPointStrength.count - 1)])
                if s <= 0.0001 { continue }

                let p = surfacePoints[idx]
                let nrm = normals[min(idx, normals.count - 1)]

                // Short distance outside.
                let u = Double(prng.nextFloat01())
                let dist = beadBand * CGFloat(pow(u, 2.35))
                let q = CGPoint(x: p.x + nrm.x * dist, y: p.y + nrm.y * dist)

                // Small bead radius.
                let rrU = Double(prng.nextFloat01())
                let rr = minR + (maxR - minR) * CGFloat(pow(rrU, 2.10)) * CGFloat(0.55 + 0.70 * s)

                let aUnit = min(1.0, (s * clamp(cfg.fuzzSpeckStrength, 0.0, 2.5)) * (0.65 + 0.55 * Double(prng.nextFloat01())))
                var b = 0
                if aUnit > 0.82 { b = 2 }
                else if aUnit > 0.52 { b = 1 }
                else { b = 0 }

                beadPaths[b].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            }
        }

        // Dust: outside band around the rim (strong near edges/tails, sparse on ridge).
        if dustCount > 0 {
            for _ in 0..<dustCount {
                let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]
                let s = Double(perPointStrength[min(idx, perPointStrength.count - 1)])
                if s <= 0.0001 { continue }

                // Skip some ridge points to avoid a uniform halo.
                if s < 0.14, prng.nextFloat01() < 0.45 { continue }

                let p = surfacePoints[idx]
                let nrm = normals[min(idx, normals.count - 1)]

                // Distance outside, shaped by strength (stronger = tighter, more local).
                let u = Double(prng.nextFloat01())
                let distFrac = pow(u, cfg.fuzzDistancePowerOutside)
                let tight = 0.55 + 0.40 * (1.0 - s)
                let dist = outsideBand * CGFloat(distFrac) * CGFloat(tight)

                // Along-tangent jitter.
                let tangentJ = CGFloat((prng.nextSignedFloat()) * Float(cfg.fuzzAlongTangentJitter)) * outsideBand * 0.22
                let t = CGPoint(x: -nrm.y, y: nrm.x)

                let q = CGPoint(
                    x: p.x + nrm.x * dist + t.x * tangentJ,
                    y: p.y + nrm.y * dist + t.y * tangentJ
                )

                let rrU = Double(prng.nextFloat01())
                let rr = minR + (maxR - minR) * CGFloat(pow(rrU, 1.65)) * CGFloat(0.60 + 0.60 * s)

                let aUnit = min(1.0, (s * clamp(cfg.fuzzSpeckStrength, 0.0, 2.5)) * (0.55 + 0.65 * Double(prng.nextFloat01())))
                var b = -1
                if aUnit > 0.72 { b = 3 }
                else if aUnit > 0.44 { b = 2 }
                else if aUnit > 0.24 { b = 1 }
                else if aUnit > 0.10 { b = 0 }
                if b < 0 { continue }

                dustPaths[b].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            }
        }

        // Inside weld: clipped to core; soft speckles inside the rim.
        var insidePaths: [Path] = Array(repeating: Path(), count: insideLevels.count)
        let insideBand = bandWidthPt * CGFloat(clamp01(cfg.fuzzInsideWidthFactor))

        if insideBudget > 0 {
            for _ in 0..<insideBudget {
                let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]
                let s = Double(perPointStrength[min(idx, perPointStrength.count - 1)])
                if s <= 0.04 { continue }

                let p = surfacePoints[idx]
                let nrm = normals[min(idx, normals.count - 1)]

                // Distance inside.
                let u = Double(prng.nextFloat01())
                let dist = insideBand * CGFloat(pow(u, cfg.fuzzDistancePowerInside)) * CGFloat(0.85 + 0.30 * s)
                let q = CGPoint(x: p.x - nrm.x * dist, y: p.y - nrm.y * dist)

                let rrU = Double(prng.nextFloat01())
                let rr = minR + (maxR - minR) * CGFloat(pow(rrU, 1.55)) * CGFloat(0.65 + 0.50 * s)

                let aUnit = min(1.0, (s * clamp(cfg.fuzzSpeckStrength, 0.0, 2.5)) * (0.55 + 0.55 * Double(prng.nextFloat01())))
                var b = -1
                if aUnit > 0.76 { b = 3 }
                else if aUnit > 0.48 { b = 2 }
                else if aUnit > 0.28 { b = 1 }
                else if aUnit > 0.12 { b = 0 }
                if b < 0 { continue }

                insidePaths[b].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            }
        }

        // Draw: outside first, then beads, then inside weld.
        context.saveGState()

        // Outside dust
        for i in 0..<outsideLevels.count {
            if dustPaths[i].isEmpty { continue }
            context.fill(dustPaths[i], with: .color(cfg.fuzzColor.opacity(Double(outsideLevels[i]))))
        }

        // Beads (additive for sparkle)
        context.blendMode = .plusLighter
        for i in 0..<beadLevels.count {
            if beadPaths[i].isEmpty { continue }
            context.fill(beadPaths[i], with: .color(cfg.rimColor.opacity(Double(beadLevels[i]))))
        }
        context.blendMode = .normal

        // Inside weld
        context.saveGState()
        context.clip(to: corePath)
        for i in 0..<insideLevels.count {
            if insidePaths[i].isEmpty { continue }
            context.fill(insidePaths[i], with: .color(cfg.fuzzColor.opacity(Double(insideLevels[i]))))
        }
        context.restoreGState()

        context.restoreGState()
    }

    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perPointStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        // Intentional no-op: haze is kept off for the nowcast style (no halo).
        _ = context
        _ = corePath
        _ = surfacePoints
        _ = normals
        _ = perPointStrength
        _ = bandWidthPt
        _ = displayScale
        _ = cfg
    }

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        if x <= lo { return lo }
        if x >= hi { return hi }
        return x
    }

    private static func clamp01(_ x: Double) -> Double {
        clamp(x, 0.0, 1.0)
    }
}
