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

        // 3 buckets (cheap).
        let levels: [CGFloat] = [
            min(maxA, 0.10),
            min(maxA, 0.18),
            min(maxA, 0.28)
        ]

        var paths: [Path] = Array(repeating: Path(), count: levels.count)

        for i in 0..<(surfacePoints.count - 1) {
            let s = perSegmentStrength[min(i, perSegmentStrength.count - 1)]
            if s <= 0.0001 { continue }

            let a = CGFloat(min(1.0, Double(s))) * maxA
            var bucket: Int?

            if a > levels[2] { bucket = 2 }
            else if a > levels[1] { bucket = 1 }
            else if a > levels[0] { bucket = 0 }

            guard let b = bucket else { continue }

            paths[b].move(to: surfacePoints[i])
            paths[b].addLine(to: surfacePoints[i + 1])
        }

        let prevBlend = context.blendMode
        context.blendMode = .destinationOut

        let style = StrokeStyle(lineWidth: fadeW, lineCap: .round, lineJoin: .round)
        for k in 0..<levels.count {
            context.stroke(paths[k], with: .color(.white.opacity(Double(levels[k]))), style: style)
        }

        context.blendMode = prevBlend
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

        let strength = min(max(cfg.fuzzErodeStrength, 0.0), 2.0)
        if strength <= 0.0001 { return }

        // Erode just inside the rim so it breaks into fuzz instead of outlining.
        let inset = CGFloat(cfg.fuzzErodeRimInsetPixels) / ds
        let w = max(onePx, bandWidthPt * CGFloat(cfg.fuzzErodeStrokeWidthFactor))
        let blurW = max(onePx, bandWidthPt * CGFloat(cfg.fuzzErodeBlurFractionOfBand))

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xE10D_E10D_0000_0001))

        var erosionPath = Path()

        let n = surfacePoints.count
        for i in 0..<(n - 1) {
            let s0 = perPointStrength[min(i, perPointStrength.count - 1)]
            let s1 = perPointStrength[min(i + 1, perPointStrength.count - 1)]
            let s = CGFloat((s0 + s1) * 0.5)
            if s <= 0.04 { continue }

            // More marks where fuzz is strong.
            let keepP = min(1.0, 0.18 + 0.92 * Double(s))
            if prng.nextFloat01() > keepP { continue }

            let pA = surfacePoints[i]
            let pB = surfacePoints[i + 1]
            let mid = CGPoint(x: (pA.x + pB.x) * 0.5, y: (pA.y + pB.y) * 0.5)

            let nrm = normals[min(i, normals.count - 1)]
            let t = CGPoint(x: -nrm.y, y: nrm.x)

            let alongJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.22
            let base = CGPoint(
                x: mid.x - nrm.x * inset + t.x * CGFloat(alongJ),
                y: mid.y - nrm.y * inset + t.y * CGFloat(alongJ)
            )

            let len = max(onePx, w * (0.9 + 2.6 * s))
            let a0 = CGPoint(x: base.x - t.x * len * 0.5, y: base.y - t.y * len * 0.5)
            let a1 = CGPoint(x: base.x + t.x * len * 0.5, y: base.y + t.y * len * 0.5)

            erosionPath.move(to: a0)
            erosionPath.addLine(to: a1)
        }

        let prevBlend = context.blendMode
        context.blendMode = .destinationOut

        // No blur filter: emulate “softness” by slightly wider stroke.
        context.stroke(
            erosionPath,
            with: .color(.white.opacity(0.18 * strength)),
            style: StrokeStyle(
                lineWidth: w + blurW,
                lineCap: .round,
                lineJoin: .round
            )
        )

        context.blendMode = prevBlend

        _ = corePath
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

        let insideBand = bandWidthPt * CGFloat(RainSurfaceDrawing.clamp01(cfg.fuzzInsideWidthFactor))

        // Budget is clamped hard for widget safety.
        let baseBudget = min(2_800, max(900, cfg.fuzzSpeckleBudget / 2))
        let density = min(max(cfg.fuzzDensity, 0.0), 2.0)
        var budget = Int(Double(baseBudget) * density)
        budget = max(700, min(3_200, budget))

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xD155_01E5_0000_0001))

        // Removal strength buckets (destinationOut alpha).
        let levels: [CGFloat] = [0.20, 0.34, 0.48]

        // Candidate indices with non-trivial strength.
        var candidates: [Int] = []
        candidates.reserveCapacity(surfacePoints.count)
        for i in 0..<surfacePoints.count {
            if perPointStrength[min(i, perPointStrength.count - 1)] > 0.10 {
                candidates.append(i)
            }
        }
        if candidates.isEmpty { return }

        let minR = max(onePx * 0.55, CGFloat(cfg.fuzzSpeckleRadiusPixels.lowerBound) / ds)
        let maxR = max(minR, CGFloat(cfg.fuzzSpeckleRadiusPixels.upperBound) / ds * 0.95)

        var holePaths: [Path] = Array(repeating: Path(), count: levels.count)
        var slitPaths: [Path] = Array(repeating: Path(), count: levels.count)

        for _ in 0..<budget {
            let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]

            let s = Double(perPointStrength[min(idx, perPointStrength.count - 1)])
            if s <= 0.0001 { continue }

            // Weight density by strength.
            if prng.nextFloat01() > min(1.0, 0.10 + 0.95 * s) { continue }

            let p = surfacePoints[idx]
            let nrm = normals[min(idx, normals.count - 1)]
            let t = CGPoint(x: -nrm.y, y: nrm.x)

            let u = prng.nextFloat01()
            let dist = insideBand
                * CGFloat(pow(u, max(0.10, cfg.fuzzDistancePowerInside)))
                * CGFloat(0.85 + 0.25 * s)

            let alongJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.10

            let q = CGPoint(
                x: p.x - nrm.x * dist + t.x * CGFloat(alongJ),
                y: p.y - nrm.y * dist + t.y * CGFloat(alongJ)
            )

            let rrUnit = prng.nextFloat01()
            let rr = minR + (maxR - minR) * CGFloat(pow(rrUnit, 1.55))

            // Bucket by removal alpha (stronger near edges/tails).
            let a = min(0.60, 0.20 + 0.45 * s)

            var bucket = 0
            if a > Double(levels[2]) { bucket = 2 }
            else if a > Double(levels[1]) { bucket = 1 }
            else if a > Double(levels[0]) { bucket = 0 }

            holePaths[bucket].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))

            // Occasionally add a tiny slit to avoid uniform stipple.
            if prng.nextFloat01() < (0.10 + 0.25 * s) {
                let slitLen = max(onePx, rr * 2.0 * CGFloat(0.7 + 0.9 * s))
                let a0 = CGPoint(x: q.x - t.x * slitLen * 0.5, y: q.y - t.y * slitLen * 0.5)
                let a1 = CGPoint(x: q.x + t.x * slitLen * 0.5, y: q.y + t.y * slitLen * 0.5)
                slitPaths[bucket].move(to: a0)
                slitPaths[bucket].addLine(to: a1)
            }
        }

        let prevBlend = context.blendMode
        context.blendMode = .destinationOut

        for k in 0..<levels.count {
            let a = Double(levels[k])
            context.fill(holePaths[k], with: .color(.white.opacity(a)))
            context.stroke(
                slitPaths[k],
                with: .color(.white.opacity(a * 0.95)),
                style: StrokeStyle(
                    lineWidth: max(onePx, minR * 1.1),
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }

        context.blendMode = prevBlend

        _ = corePath
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

        let maxOpacity = RainSurfaceDrawing.clamp01(cfg.fuzzMaxOpacity)
        if maxOpacity <= 0.0001 { return }

        let density = min(max(cfg.fuzzDensity, 0.0), 2.0)

        let budgetBase = max(900, min(9_000, cfg.fuzzSpeckleBudget))
        let wPx = Double(max(1.0, bandWidthPt * ds))
        let budgetByWidth = max(1_400, min(9_000, Int(wPx * 20.0)))

        var budget = Int(Double(min(budgetBase, budgetByWidth)) * (0.55 + 0.85 * density))
        budget = max(1_200, min(9_000, budget))

        let insideFrac = RainSurfaceDrawing.clamp01(cfg.fuzzInsideSpeckleFraction)
        var insideBudget = Int(Double(budget) * insideFrac)
        insideBudget = max(450, min(8_000, insideBudget))

        var outsideBudget = budget - insideBudget
        outsideBudget = max(700, min(8_000, outsideBudget))

        // More rim beads: silhouette owned by dust.
        let beadCount = max(220, Int(Double(outsideBudget) * 0.42))
        let dustCount = max(200, outsideBudget - beadCount)

        let insideOpacity = RainSurfaceDrawing.clamp01(cfg.fuzzInsideOpacityFactor)

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

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0x5EEC_41E5_0000_0001))

        // Index candidates: any point with non-trivial strength (wet or tail).
        var candidates: [Int] = []
        candidates.reserveCapacity(surfacePoints.count)
        for i in 0..<surfacePoints.count {
            if perPointStrength[min(i, perPointStrength.count - 1)] > 0.06 {
                candidates.append(i)
            }
        }
        if candidates.isEmpty { return }

        // Speck radii (in points).
        let minR = max(onePx * 0.55, CGFloat(cfg.fuzzSpeckleRadiusPixels.lowerBound) / ds)
        let maxR = max(minR, CGFloat(cfg.fuzzSpeckleRadiusPixels.upperBound) / ds)

        // Build outside dust + beads (not clipped).
        var dustPaths: [Path] = Array(repeating: Path(), count: outsideLevels.count)
        var beadPaths: [Path] = Array(repeating: Path(), count: beadLevels.count)

        let outsideBand = bandWidthPt
        let beadBand = bandWidthPt * 0.14

        // Beads: tightly hug the rim, plusLighter so they read as particulate edge ownership.
        if beadCount > 0 {
            for _ in 0..<beadCount {
                let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]
                let p = surfacePoints[idx]
                let nrm = normals[min(idx, normals.count - 1)]
                let t = CGPoint(x: -nrm.y, y: nrm.x)

                let s = Double(perPointStrength[min(idx, perPointStrength.count - 1)])
                if s <= 0.0001 { continue }

                let u = prng.nextFloat01()
                let dist = beadBand * CGFloat(pow(u, max(0.10, cfg.fuzzDistancePowerOutside))) * CGFloat(0.22 + 0.78 * s)

                let alongJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.18

                let q = CGPoint(
                    x: p.x + nrm.x * dist + t.x * CGFloat(alongJ),
                    y: p.y + nrm.y * dist + t.y * CGFloat(alongJ)
                )

                let rrUnit = prng.nextFloat01()
                let rr = minR + (maxR * 0.65 - minR) * CGFloat(pow(rrUnit, 1.35))

                let aUnit = min(1.0, (0.18 + 0.82 * s) * (0.35 + 0.65 * prng.nextFloat01()))
                let b: Int
                if aUnit > 0.82 { b = 2 }
                else if aUnit > 0.52 { b = 1 }
                else { b = 0 }

                beadPaths[b].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            }
        }

        // Dust: outside band around the rim (strong near edges/tails).
        if dustCount > 0 {
            for _ in 0..<dustCount {
                let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]
                let p = surfacePoints[idx]
                let nrm = normals[min(idx, normals.count - 1)]
                let t = CGPoint(x: -nrm.y, y: nrm.x)

                let s = Double(perPointStrength[min(idx, perPointStrength.count - 1)])
                if s <= 0.0001 { continue }

                let u = prng.nextFloat01()
                let dist = outsideBand * CGFloat(pow(u, max(0.10, cfg.fuzzDistancePowerOutside))) * CGFloat(0.40 + 0.60 * s)

                let alongJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.26

                let q = CGPoint(
                    x: p.x + nrm.x * dist + t.x * CGFloat(alongJ),
                    y: p.y + nrm.y * dist + t.y * CGFloat(alongJ)
                )

                let rrUnit = prng.nextFloat01()
                let rr = minR + (maxR - minR) * CGFloat(pow(rrUnit, 1.25))

                let aUnit = min(1.0, (0.12 + 0.88 * s) * (0.35 + 0.65 * prng.nextFloat01()))
                var b = -1
                if aUnit > 0.72 { b = 3 }
                else if aUnit > 0.44 { b = 2 }
                else if aUnit > 0.24 { b = 1 }
                else if aUnit > 0.10 { b = 0 }
                if b < 0 { continue }

                dustPaths[b].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            }
        }

        // Inside weld: clipped to core; dense speckles just inside the rim.
        var insidePaths: [Path] = Array(repeating: Path(), count: insideLevels.count)
        let insideBand = bandWidthPt * CGFloat(RainSurfaceDrawing.clamp01(cfg.fuzzInsideWidthFactor))

        if insideBudget > 0 {
            for _ in 0..<insideBudget {
                let idx = candidates[Int(prng.nextUInt64() % UInt64(candidates.count))]
                let p = surfacePoints[idx]
                let nrm = normals[min(idx, normals.count - 1)]
                let t = CGPoint(x: -nrm.y, y: nrm.x)

                let s = Double(perPointStrength[min(idx, perPointStrength.count - 1)])
                if s <= 0.0001 { continue }

                let u = prng.nextFloat01()
                let dist = insideBand * CGFloat(pow(u, max(0.10, cfg.fuzzDistancePowerInside))) * CGFloat(0.85 + 0.35 * s)

                let alongJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.12

                let q = CGPoint(
                    x: p.x - nrm.x * dist + t.x * CGFloat(alongJ),
                    y: p.y - nrm.y * dist + t.y * CGFloat(alongJ)
                )

                let rrUnit = prng.nextFloat01()
                let rr = minR + (maxR * 0.85 - minR) * CGFloat(pow(rrUnit, 1.35))

                let aUnit = min(1.0, (0.18 + 0.82 * s) * (0.35 + 0.65 * prng.nextFloat01()))
                var b = -1
                if aUnit > 0.76 { b = 3 }
                else if aUnit > 0.48 { b = 2 }
                else if aUnit > 0.28 { b = 1 }
                else if aUnit > 0.12 { b = 0 }
                if b < 0 { continue }

                insidePaths[b].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            }
        }

        // Draw: outside first, then beads, then inside weld (clipped).
        let prevBlend = context.blendMode

        // Outside dust (normal).
        context.blendMode = .normal
        for i in 0..<outsideLevels.count {
            context.fill(dustPaths[i], with: .color(cfg.fuzzColor.opacity(Double(outsideLevels[i]))))
        }

        // Beads: plusLighter so they read as the silhouette.
        context.blendMode = .plusLighter
        for i in 0..<beadLevels.count {
            context.fill(beadPaths[i], with: .color(cfg.fuzzColor.opacity(Double(beadLevels[i]))))
        }

        context.blendMode = prevBlend

        // Inside weld (clip isolated in a layer so clip doesn't leak).
        context.drawLayer { inner in
            inner.clip(to: corePath)
            inner.blendMode = .plusLighter
            for i in 0..<insideLevels.count {
                inner.fill(insidePaths[i], with: .color(cfg.fuzzColor.opacity(Double(insideLevels[i]))))
            }
        }
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
        // Intentionally no-op: haze risks turning the black background grey (halo/fog).
        _ = context
        _ = corePath
        _ = surfacePoints
        _ = normals
        _ = perPointStrength
        _ = bandWidthPt
        _ = displayScale
        _ = cfg
    }
}
