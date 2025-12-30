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

        // Tight, local fade: remove the crisp vector rim without creating a fog halo.
        let bandPx = Double(max(onePx, bandWidthPt) * ds)
        let fadePx = min(18.0, max(2.2, bandPx * 0.42))
        let fadeW = CGFloat(fadePx) / ds

        let speckBoost = min(2.0, max(0.35, cfg.fuzzSpeckStrength))
        let baseA = min(0.80, max(0.18, 0.42 * speckBoost))

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xEADF_ADE0_0000_0001))

        let levels: [CGFloat] = [
            CGFloat(min(0.85, baseA * 0.34)),
            CGFloat(min(0.85, baseA * 0.52)),
            CGFloat(min(0.85, baseA * 0.70)),
            CGFloat(min(0.85, baseA * 0.88)),
        ]

        var paths: [Path] = Array(repeating: Path(), count: levels.count)

        for i in 0..<(surfacePoints.count - 1) {
            let s = (i < perSegmentStrength.count) ? perSegmentStrength[i] : 0.0
            if s <= 0.0001 { continue }

            // Break continuity: avoid a single smooth stroke that reads like an outline.
            let keepP = min(1.0, 0.32 + 0.68 * Double(s))
            if prng.nextFloat01() > keepP { continue }

            let p0 = surfacePoints[i]
            let p1 = surfacePoints[i + 1]

            let aUnit = Double(s)
            let bucket: Int
            if aUnit > 0.80 { bucket = 3 }
            else if aUnit > 0.55 { bucket = 2 }
            else if aUnit > 0.30 { bucket = 1 }
            else { bucket = 0 }

            paths[bucket].move(to: p0)
            paths[bucket].addLine(to: p1)
        }

        let prevBlend = context.blendMode
        context.blendMode = .destinationOut

        let widths: [CGFloat] = [
            max(onePx, fadeW * 0.55),
            max(onePx, fadeW * 0.80),
            max(onePx, fadeW * 1.05),
            max(onePx, fadeW * 1.25),
        ]

        for k in 0..<levels.count {
            if paths[k].isEmpty { continue }
            context.stroke(
                paths[k],
                with: .color(.white.opacity(levels[k])),
                style: StrokeStyle(lineWidth: widths[k], lineCap: .round, lineJoin: .round)
            )
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
        guard surfacePoints.count >= 4 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds

        let strength = min(max(cfg.fuzzErodeStrength, 0.0), 2.0)
        if strength <= 0.0001 { return }

        let bandPx = Double(max(onePx, bandWidthPt) * ds)

        // Micro-cuts: small, jittered tangential strokes just inside the rim.
        let insetPx = min(2.4, max(0.7, cfg.fuzzErodeRimInsetPixels))
        let widthPx = min(2.4, max(0.8, bandPx * 0.07 * cfg.fuzzErodeStrokeWidthFactor))
        let lenPxBase = min(10.5, max(2.2, bandPx * 0.16))

        var budget = max(220, min(1_600, cfg.fuzzSpeckleBudget / 5))
        if cfg.fuzzSpeckleBudget <= 2_200 { budget = min(budget, 700) }

        // Candidates: only where fuzz is non-trivial.
        var candidates: [Int] = []
        candidates.reserveCapacity(surfacePoints.count)
        for i in 0..<surfacePoints.count {
            let s = (i < perPointStrength.count) ? perPointStrength[i] : 0.0
            if s > 0.10 { candidates.append(i) }
        }
        if candidates.isEmpty { return }

        let levels: [CGFloat] = [0.28, 0.46, 0.64]
        var cutPaths: [Path] = Array(repeating: Path(), count: levels.count)

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xE10D_E10D_0000_0001))

        for _ in 0..<budget {
            let pick = Int(prng.nextFloat01() * Double(candidates.count))
            let idx = candidates[min(max(0, pick), candidates.count - 1)]

            let s = (idx < perPointStrength.count) ? perPointStrength[idx] : 0.0
            if s <= 0.06 { continue }

            let keepP = min(1.0, 0.40 + 0.60 * Double(s))
            if prng.nextFloat01() > keepP { continue }

            let p = surfacePoints[idx]
            let nrm = normals[min(idx, normals.count - 1)]
            let t = CGPoint(x: -nrm.y, y: nrm.x)

            let u = prng.nextFloat01()
            let distPx = insetPx + pow(u, 1.75) * min(6.5, bandPx * 0.22)
            let dist = CGFloat(distPx) / ds

            let tangentJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.12
            let q = CGPoint(
                x: p.x - nrm.x * dist + t.x * CGFloat(tangentJ),
                y: p.y - nrm.y * dist + t.y * CGFloat(tangentJ)
            )

            let lenPx = min(14.0, lenPxBase * (0.65 + 0.95 * Double(s)))
            let len = CGFloat(lenPx) / ds

            let a0 = CGPoint(x: q.x - t.x * len * 0.5, y: q.y - t.y * len * 0.5)
            let a1 = CGPoint(x: q.x + t.x * len * 0.5, y: q.y + t.y * len * 0.5)

            let bucket: Int
            if s > 0.80 { bucket = 2 }
            else if s > 0.45 { bucket = 1 }
            else { bucket = 0 }

            cutPaths[bucket].move(to: a0)
            cutPaths[bucket].addLine(to: a1)
        }

        let prevBlend = context.blendMode
        context.blendMode = .destinationOut

        let w = max(onePx, CGFloat(widthPx) / ds)
        for i in 0..<levels.count {
            if cutPaths[i].isEmpty { continue }
            let a = min(0.92, Double(levels[i]) * strength)
            context.stroke(
                cutPaths[i],
                with: .color(.white.opacity(a)),
                style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
            )
        }

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
        guard surfacePoints.count >= 4 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds

        let density = min(max(cfg.fuzzDensity, 0.0), 2.0)
        let speckBoost = min(2.0, max(0.35, cfg.fuzzSpeckStrength))

        let bandPx = Double(max(onePx, bandWidthPt) * ds)
        let insideBandPx = min(14.0, max(2.8, bandPx * Double(RainSurfaceDrawing.clamp01(cfg.fuzzInsideWidthFactor)) * 0.48))
        let insideBand = CGFloat(insideBandPx) / ds

        var budget = max(700, min(3_000, cfg.fuzzSpeckleBudget / 3))
        budget = Int(Double(budget) * (0.75 + 0.55 * density) * (0.78 + 0.42 * speckBoost))
        budget = max(650, min(3_200, budget))

        var candidates: [Int] = []
        candidates.reserveCapacity(surfacePoints.count)
        for i in 0..<surfacePoints.count {
            let s = (i < perPointStrength.count) ? perPointStrength[i] : 0.0
            if s > 0.12 { candidates.append(i) }
        }
        if candidates.isEmpty { return }

        let cfgMinR = CGFloat(cfg.fuzzSpeckleRadiusPixels.lowerBound) / ds
        let cfgMaxR = CGFloat(cfg.fuzzSpeckleRadiusPixels.upperBound) / ds

        let minR = max(onePx * 0.35, min(cfgMinR, onePx * 1.25))
        let maxR = max(minR, min(cfgMaxR, onePx * 1.15))

        let levels: [CGFloat] = [0.26, 0.42, 0.58, 0.76]
        var holePaths: [Path] = Array(repeating: Path(), count: levels.count)
        var slitPaths: [Path] = Array(repeating: Path(), count: levels.count)

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xD155_01E5_0000_0001))

        for _ in 0..<budget {
            let pick = Int(prng.nextFloat01() * Double(candidates.count))
            let idx = candidates[min(max(0, pick), candidates.count - 1)]

            let s = (idx < perPointStrength.count) ? perPointStrength[idx] : 0.0
            if s <= 0.08 { continue }

            let keepP = min(1.0, 0.35 + 0.65 * Double(s))
            if prng.nextFloat01() > keepP { continue }

            let p = surfacePoints[idx]
            let nrm = normals[min(idx, normals.count - 1)]
            let t = CGPoint(x: -nrm.y, y: nrm.x)

            let u = prng.nextFloat01()
            let power = max(1.2, cfg.fuzzDistancePowerInside + 0.9)
            let dist = insideBand * CGFloat(pow(u, power)) * CGFloat(0.92)

            let tangentJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.10
            let q = CGPoint(
                x: p.x - nrm.x * dist + t.x * CGFloat(tangentJ),
                y: p.y - nrm.y * dist + t.y * CGFloat(tangentJ)
            )

            let rrUnit = prng.nextFloat01()
            let rr = minR + (maxR - minR) * CGFloat(pow(rrUnit, 1.45))

            let bucket: Int
            if s > 0.80 { bucket = 3 }
            else if s > 0.55 { bucket = 2 }
            else if s > 0.30 { bucket = 1 }
            else { bucket = 0 }

            holePaths[bucket].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))

            // Occasional micro-slit to avoid uniform stipple.
            if prng.nextFloat01() < (0.08 + 0.22 * Double(s)) {
                let slitLen = max(onePx, rr * 2.0 * CGFloat(0.75 + 0.90 * s))
                let a0 = CGPoint(x: q.x - t.x * slitLen * 0.5, y: q.y - t.y * slitLen * 0.5)
                let a1 = CGPoint(x: q.x + t.x * slitLen * 0.5, y: q.y + t.y * slitLen * 0.5)
                slitPaths[bucket].move(to: a0)
                slitPaths[bucket].addLine(to: a1)
            }
        }

        let prevBlend = context.blendMode
        context.blendMode = .destinationOut

        for i in 0..<levels.count {
            if !holePaths[i].isEmpty {
                context.fill(holePaths[i], with: .color(.white.opacity(levels[i])))
            }
            if !slitPaths[i].isEmpty {
                context.stroke(
                    slitPaths[i],
                    with: .color(.white.opacity(min(0.92, levels[i] * 1.05))),
                    style: StrokeStyle(lineWidth: max(onePx, onePx * 0.85), lineCap: .round, lineJoin: .round)
                )
            }
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

        let maxOpacityBase = RainSurfaceDrawing.clamp01(cfg.fuzzMaxOpacity)
        if maxOpacityBase <= 0.0001 { return }

        let density = min(max(cfg.fuzzDensity, 0.0), 2.0)
        let speckBoost = min(2.0, max(0.35, cfg.fuzzSpeckStrength))
        let maxOpacity = min(0.95, maxOpacityBase * (0.72 + 0.48 * speckBoost))

        let budgetBase = max(900, min(9_000, cfg.fuzzSpeckleBudget))
        let bandPx = Double(max(onePx, bandWidthPt) * ds)

        // Budget independent of area; clamped and density-scaled.
        var budget = Int(Double(budgetBase) * (0.58 + 0.84 * density))
        budget = max(1_200, min(9_000, budget))
        if cfg.fuzzSpeckleBudget <= 2_200 {
            budget = min(budget, 3_200)
        }

        let insideFracRaw = RainSurfaceDrawing.clamp01(cfg.fuzzInsideSpeckleFraction)
        let insideFrac = min(0.80, max(0.45, insideFracRaw))

        var insideBudget = Int(Double(budget) * insideFrac)
        insideBudget = max(520, min(8_000, insideBudget))

        var outsideBudget = max(0, budget - insideBudget)
        outsideBudget = max(650, min(8_000, outsideBudget))

        // Dominant silhouette beads first; outside dust is secondary.
        let beadCount = max(240, min(6_500, Int(Double(outsideBudget) * 0.76)))
        let dustCount = max(180, outsideBudget - beadCount)

        // Candidates: any point with non-trivial fuzz.
        var candidates: [Int] = []
        candidates.reserveCapacity(surfacePoints.count)
        for i in 0..<surfacePoints.count {
            let s = (i < perPointStrength.count) ? perPointStrength[i] : 0.0
            if s > 0.06 { candidates.append(i) }
        }
        if candidates.isEmpty { return }

        let cfgMinR = CGFloat(cfg.fuzzSpeckleRadiusPixels.lowerBound) / ds
        let cfgMaxR = CGFloat(cfg.fuzzSpeckleRadiusPixels.upperBound) / ds

        // Micro-grain radii (points), capped to avoid macro blobs.
        let beadMinR = max(onePx * 0.30, cfgMinR)
        let beadMaxR = max(beadMinR, min(cfgMaxR, CGFloat(1.25) / ds))

        let dustMinR = max(onePx * 0.32, cfgMinR)
        let dustMaxR = max(dustMinR, min(cfgMaxR, CGFloat(1.90) / ds))

        let insideMinR = max(onePx * 0.30, cfgMinR)
        let insideMaxR = max(insideMinR, min(cfgMaxR, CGFloat(1.55) / ds))

        // Tight bands (pixels) to prevent floating specks and halos.
        let beadBandPx = min(7.5, max(1.6, bandPx * 0.20))
        let dustBandPx = min(20.0, max(4.0, bandPx * 0.54))
        let insideBandPx = min(14.0, max(3.0, bandPx * Double(RainSurfaceDrawing.clamp01(cfg.fuzzInsideWidthFactor)) * 0.42))

        let beadBand = CGFloat(beadBandPx) / ds
        let dustBand = CGFloat(dustBandPx) / ds
        let insideBand = CGFloat(insideBandPx) / ds

        let insideOpacity = RainSurfaceDrawing.clamp01(cfg.fuzzInsideOpacityFactor)

        let outsideLevels: [CGFloat] = [
            CGFloat(0.12 * maxOpacity),
            CGFloat(0.22 * maxOpacity),
            CGFloat(0.34 * maxOpacity),
            CGFloat(0.48 * maxOpacity),
        ]

        let beadLevels: [CGFloat] = [
            CGFloat(0.40 * maxOpacity),
            CGFloat(0.66 * maxOpacity),
            CGFloat(0.92 * maxOpacity),
        ]

        let insideLevels: [CGFloat] = [
            CGFloat(0.18 * maxOpacity * insideOpacity),
            CGFloat(0.30 * maxOpacity * insideOpacity),
            CGFloat(0.44 * maxOpacity * insideOpacity),
            CGFloat(0.62 * maxOpacity * insideOpacity),
        ]

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0x5EEC_41E5_0000_0001))

        // Outside dust + beads (not clipped).
        var dustPaths: [Path] = Array(repeating: Path(), count: outsideLevels.count)
        var beadPaths: [Path] = Array(repeating: Path(), count: beadLevels.count)

        if beadCount > 0 {
            let power = max(2.8, cfg.fuzzDistancePowerOutside + 1.0)
            for _ in 0..<beadCount {
                let idx = candidates[Int(prng.nextFloat01() * Double(candidates.count))]
                let s = (idx < perPointStrength.count) ? perPointStrength[idx] : 0.0
                if s <= 0.06 { continue }

                let keepP = min(1.0, 0.40 + 0.60 * Double(s))
                if prng.nextFloat01() > keepP { continue }

                let p = surfacePoints[idx]
                let nrm = normals[min(idx, normals.count - 1)]
                let t = CGPoint(x: -nrm.y, y: nrm.x)

                let u = prng.nextFloat01()
                let dist = beadBand * CGFloat(pow(u, power)) * CGFloat(0.98)

                let tangentJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.10
                let q = CGPoint(
                    x: p.x + nrm.x * dist + t.x * CGFloat(tangentJ),
                    y: p.y + nrm.y * dist + t.y * CGFloat(tangentJ)
                )

                let rr = beadMinR + (beadMaxR - beadMinR) * CGFloat(pow(prng.nextFloat01(), 1.85))

                let bucket: Int
                if s > 0.80 { bucket = 2 }
                else if s > 0.50 { bucket = 1 }
                else { bucket = 0 }

                beadPaths[bucket].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            }
        }

        if dustCount > 0 {
            let power = max(1.8, cfg.fuzzDistancePowerOutside)
            for _ in 0..<dustCount {
                let idx = candidates[Int(prng.nextFloat01() * Double(candidates.count))]
                let s = (idx < perPointStrength.count) ? perPointStrength[idx] : 0.0
                if s <= 0.06 { continue }

                let keepP = min(1.0, 0.28 + 0.72 * Double(s))
                if prng.nextFloat01() > keepP { continue }

                let p = surfacePoints[idx]
                let nrm = normals[min(idx, normals.count - 1)]
                let t = CGPoint(x: -nrm.y, y: nrm.x)

                let u = prng.nextFloat01()
                let dist = dustBand * CGFloat(pow(u, power)) * CGFloat(0.96)

                let tangentJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.16
                let q = CGPoint(
                    x: p.x + nrm.x * dist + t.x * CGFloat(tangentJ),
                    y: p.y + nrm.y * dist + t.y * CGFloat(tangentJ)
                )

                let rr = dustMinR + (dustMaxR - dustMinR) * CGFloat(pow(prng.nextFloat01(), 1.55))

                let aUnit = Double(s) * (0.55 + 0.45 * prng.nextFloat01())
                let b: Int
                if aUnit > 0.80 { b = 3 }
                else if aUnit > 0.55 { b = 2 }
                else if aUnit > 0.30 { b = 1 }
                else { b = 0 }

                dustPaths[b].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            }
        }

        // Inside weld: clipped to core; dense micro speckles just inside the rim.
        var insidePaths: [Path] = Array(repeating: Path(), count: insideLevels.count)

        if insideBudget > 0 {
            let power = max(1.6, cfg.fuzzDistancePowerInside + 0.8)
            for _ in 0..<insideBudget {
                let idx = candidates[Int(prng.nextFloat01() * Double(candidates.count))]
                let s = (idx < perPointStrength.count) ? perPointStrength[idx] : 0.0
                if s <= 0.06 { continue }

                let keepP = min(1.0, 0.34 + 0.66 * Double(s))
                if prng.nextFloat01() > keepP { continue }

                let p = surfacePoints[idx]
                let nrm = normals[min(idx, normals.count - 1)]
                let t = CGPoint(x: -nrm.y, y: nrm.x)

                let u = prng.nextFloat01()
                let dist = insideBand * CGFloat(pow(u, power)) * CGFloat(0.96)

                let tangentJ = prng.nextSignedFloat() * cfg.fuzzAlongTangentJitter * Double(bandWidthPt) * 0.10
                let q = CGPoint(
                    x: p.x - nrm.x * dist + t.x * CGFloat(tangentJ),
                    y: p.y - nrm.y * dist + t.y * CGFloat(tangentJ)
                )

                let rr = insideMinR + (insideMaxR - insideMinR) * CGFloat(pow(prng.nextFloat01(), 1.70))

                let aUnit = Double(s) * (0.60 + 0.40 * prng.nextFloat01())
                let b: Int
                if aUnit > 0.78 { b = 3 }
                else if aUnit > 0.52 { b = 2 }
                else if aUnit > 0.30 { b = 1 }
                else { b = 0 }

                insidePaths[b].addEllipse(in: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2))
            }
        }

        // Draw order:
        // 1) outside dust (normal)
        // 2) rim beads (plusLighter)
        // 3) inside weld (clipped; normal)
        let prevBlend = context.blendMode

        context.blendMode = .normal
        for i in 0..<outsideLevels.count {
            if dustPaths[i].isEmpty { continue }
            context.fill(dustPaths[i], with: .color(cfg.fuzzColor.opacity(outsideLevels[i])))
        }

        context.blendMode = .plusLighter
        for i in 0..<beadLevels.count {
            if beadPaths[i].isEmpty { continue }
            context.fill(beadPaths[i], with: .color(cfg.fuzzColor.opacity(beadLevels[i])))
        }

        context.blendMode = .normal
        context.drawLayer { layer in
            layer.clip(to: corePath)
            for i in 0..<insideLevels.count {
                if insidePaths[i].isEmpty { continue }
                layer.fill(insidePaths[i], with: .color(cfg.fuzzColor.opacity(insideLevels[i])))
            }
        }

        context.blendMode = prevBlend
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
        // Intentionally no-op: the target look is particulate, not a blurred halo.
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
