//
//  RainSurfaceDrawing+Fuzz.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Fuzz / haze / particulate drawing.
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
        let fade = max(0.0, min(1.0, cfg.coreFadeFraction))
        guard fade > 0.0001 else { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let blur = min(2.2, max(onePx, bandWidthPt * CGFloat(0.35 * fade)))
        let lineWidth = max(onePx, bandWidthPt * CGFloat(0.70 * fade))

        let bins = 8
        let paths = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, binCount: bins)

        context.drawLayer { layer in
            layer.blendMode = .destinationOut
            layer.addFilter(.blur(radius: blur))

            for b in 0..<bins {
                let rep = (Double(b) + 0.5) / Double(bins)
                let alpha = min(0.55, rep * 0.55)
                if alpha < 0.02 { continue }
                layer.stroke(paths[b], with: .color(Color.white.opacity(alpha)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
        }
    }

    static func drawCoreErosion(
        in context: inout GraphicsContext,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perSegmentStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        isTightBudget: Bool
    ) {
        let strength = max(0.0, min(1.0, cfg.fuzzErodeStrength))
        guard strength > 0.0001 else { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let inset = max(0.0, CGFloat(cfg.fuzzErodeRimInsetPixels) / displayScale)

        var insetPoints: [CGPoint] = []
        insetPoints.reserveCapacity(surfacePoints.count)
        for i in 0..<surfacePoints.count {
            let p = surfacePoints[i]
            let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
            insetPoints.append(CGPoint(x: p.x - n.x * inset, y: p.y - n.y * inset))
        }

        let strokeWidth = max(onePx, bandWidthPt * CGFloat(max(0.10, cfg.fuzzErodeStrokeWidthFactor)))
        let blur = isTightBudget ? 0.0 : min(2.3, max(onePx, bandWidthPt * CGFloat(max(0.0, cfg.fuzzErodeBlurFractionOfBand))))
        let edgePower = max(0.10, cfg.fuzzErodeEdgePower)

        let bins = 10
        let paths = buildBinnedSegmentPaths(points: insetPoints, perSegmentStrength: perSegmentStrength, binCount: bins)

        context.drawLayer { layer in
            layer.blendMode = .destinationOut
            if blur > 0.0001 { layer.addFilter(.blur(radius: blur)) }

            for b in 0..<bins {
                let rep = (Double(b) + 0.5) / Double(bins) // 0..1
                let a = strength * pow(rep, edgePower)
                if a < 0.02 { continue }
                layer.stroke(paths[b], with: .color(Color.white.opacity(min(0.95, a))), style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
            }
        }
    }

    static func drawCoreDissolvePerforation(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perPointStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        isTightBudget: Bool
    ) {
        guard surfacePoints.count == perPointStrength.count else { return }
        guard cfg.fuzzEnabled, cfg.canEnableFuzz else { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let baselineY = (surfacePoints.first?.y ?? 0) + 10_000 // dummy init; replaced below

        _ = baselineY

        // Budget scaled by strength + quality.
        let maxS = Double(perPointStrength.max() ?? 0)
        if maxS < 0.10 { return }

        let baseBudget = min(1300, max(140, Int(Double(cfg.fuzzSpeckleBudget) * 0.20)))
        let scaled = Int(Double(baseBudget) * min(1.0, maxS * 1.15) * max(0.35, cfg.fuzzErodeStrength))
        let budget = max(80, min(baseBudget, scaled))
        let attempts = isTightBudget ? budget * 2 : budget * 3

        let rMinPx = max(0.10, cfg.fuzzSpeckleRadiusPixels.lowerBound)
        let rMaxPx = max(rMinPx, min(cfg.fuzzSpeckleRadiusPixels.upperBound, 1.35))
        let microMaxPx = min(rMaxPx, max(rMinPx + 0.08, 0.95))

        // Prefer wet/strong indices (avoid perforating in flat dry zones).
        var strongWet: [Int] = []
        strongWet.reserveCapacity(surfacePoints.count / 3)

        // Use baselineY from the shape (top points) by finding max y among surface points.
        // (baseline is always >= surface y in chart coords)
        var inferredBaselineY: CGFloat = 0
        for p in surfacePoints { if p.y > inferredBaselineY { inferredBaselineY = p.y } }

        let wetEps = max(onePx * 0.5, 0.0001)
        for i in 0..<perPointStrength.count {
            let h = inferredBaselineY - surfacePoints[i].y
            if h > wetEps, perPointStrength[i] > 0.18 {
                strongWet.append(i)
            }
        }
        if strongWet.isEmpty { return }

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xD1550_1A2B3C4D))

        // Bucket holes into a few opacity bins to cut draw calls.
        let levels: [Double] = [0.10, 0.18, 0.28]
        var holePaths: [Path] = Array(repeating: Path(), count: levels.count)

        func pickIndex() -> Int {
            let j = Int(prng.nextUInt32() % UInt32(strongWet.count))
            return strongWet[j]
        }

        func radiusPt() -> CGFloat {
            let u = Double(prng.nextFloat01())
            let px = rMinPx + (microMaxPx - rMinPx) * pow(u, 2.5)
            return CGFloat(px) / displayScale
        }

        for _ in 0..<attempts {
            if holePaths.reduce(0, { $0 + $1.isEmpty ? 0 : 0 }) >= budget { break }

            let i = pickIndex()
            let s = Double(perPointStrength[i])
            if s < 0.12 { continue }

            let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
            let t = CGPoint(x: n.y, y: -n.x)

            // Inward distance (bias near rim).
            let u = Double(prng.nextFloat01())
            let insideBand = max(onePx, bandWidthPt * cfg.fuzzInsideWidthFactor)
            let dist = CGFloat(pow(u, cfg.fuzzDistancePowerInside)) * insideBand * 0.85

            let jitter = CGFloat((Double(prng.nextSignedFloat()) * cfg.fuzzAlongTangentJitter)) * bandWidthPt * 0.35
            let base = surfacePoints[i]
            let center = CGPoint(x: base.x - n.x * dist + t.x * jitter, y: base.y - n.y * dist + t.y * jitter)

            let r = radiusPt()
            if r < onePx * 0.25 { continue }

            // Removal alpha (destinationOut) binned.
            let removal = min(0.34, 0.10 + 0.30 * s)
            let bin: Int
            if removal < 0.14 { bin = 0 }
            else if removal < 0.22 { bin = 1 }
            else { bin = 2 }

            var p = holePaths[bin]
            p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            holePaths[bin] = p
        }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut

            for (idx, alpha) in levels.enumerated() {
                if holePaths[idx].isEmpty { continue }
                layer.fill(holePaths[idx], with: .color(Color.white.opacity(alpha)))
            }
        }
    }

    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perSegmentStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        let haze = max(0.0, min(1.0, cfg.fuzzHazeStrength))
        guard haze > 0.0001 else { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let blur = min(2.2, max(onePx, bandWidthPt * CGFloat(max(0.0, cfg.fuzzHazeBlurFractionOfBand))))
        let width = max(onePx, bandWidthPt * CGFloat(max(0.10, cfg.fuzzHazeStrokeWidthFactor)))

        // Slight outward offset to keep haze outside the core.
        let offset = max(0.0, bandWidthPt * 0.12)

        var outPts: [CGPoint] = []
        outPts.reserveCapacity(surfacePoints.count)
        for i in 0..<surfacePoints.count {
            let p = surfacePoints[i]
            let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
            outPts.append(CGPoint(x: p.x + n.x * offset, y: p.y + n.y * offset))
        }

        let bins = 8
        let paths = buildBinnedSegmentPaths(points: outPts, perSegmentStrength: perSegmentStrength, binCount: bins)

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: blur))

            for b in 0..<bins {
                let rep = (Double(b) + 0.5) / Double(bins)
                let a = haze * rep * 0.20
                if a < 0.01 { continue }
                layer.stroke(paths[b], with: .color(cfg.fuzzColor.opacity(a)), style: StrokeStyle(lineWidth: width, lineCap: .round))
            }
        }
    }

    static func drawFuzzSpeckles(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perPointStrength: [CGFloat],
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        isTightBudget: Bool
    ) {
        guard surfacePoints.count == perPointStrength.count else { return }
        guard surfacePoints.count > 2 else { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let wetEps = max(onePx * 0.5, 0.0001)

        let wPx = Double(chartRect.width * displayScale)
        let budgetByWidth = max(1200, min(9000, Int(wPx * 18.0)))

        let baseBudget = max(0, min(cfg.fuzzSpeckleBudget, budgetByWidth))
        let density = max(0.0, cfg.fuzzDensity)
        var budget = Int(Double(baseBudget) * density)
        budget = max(0, min(9000, budget))
        if isTightBudget { budget = Int(Double(budget) * 0.65) }

        if budget < 150 { return }

        let insideFrac = max(0.0, min(0.85, cfg.fuzzInsideSpeckleFraction))
        let insideBudget = Int(Double(budget) * insideFrac)
        let outsideBudget = max(0, budget - insideBudget)

        let beadCount = Int(Double(outsideBudget) * (isTightBudget ? 0.16 : 0.22))
        let outsideDustCount = max(0, outsideBudget - beadCount)

        // Radii in points.
        let rMinPt = CGFloat(max(0.10, cfg.fuzzSpeckleRadiusPixels.lowerBound)) / displayScale
        let rMaxPt = CGFloat(max(cfg.fuzzSpeckleRadiusPixels.upperBound, cfg.fuzzSpeckleRadiusPixels.lowerBound)) / displayScale
        let microMaxPt = min(rMaxPt, max(rMinPt + onePx * 0.25, CGFloat(min(cfg.fuzzSpeckleRadiusPixels.upperBound, 1.75)) / displayScale))

        // Indices for focused sampling.
        var strongAny: [Int] = []
        var strongWet: [Int] = []
        strongAny.reserveCapacity(surfacePoints.count / 3)
        strongWet.reserveCapacity(surfacePoints.count / 3)

        for i in 0..<perPointStrength.count {
            let s = perPointStrength[i]
            if s > 0.14 { strongAny.append(i) }

            let h = baselineY - surfacePoints[i].y
            if h > wetEps, s > 0.12 { strongWet.append(i) }
        }
        if strongAny.isEmpty { strongAny = Array(0..<perPointStrength.count) }

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0x51EC7_ABCDE123))

        func pick(_ list: [Int]) -> Int {
            let j = Int(prng.nextUInt32() % UInt32(max(1, list.count)))
            return list[j]
        }

        func sampleRadius(macroAllowed: Bool) -> CGFloat {
            if macroAllowed, !isTightBudget {
                let macroChance: UInt32 = 7 // ~2.7% with mod 256
                if (prng.nextUInt32() & 255) < macroChance {
                    // Macro grain (rare)
                    let u = CGFloat(prng.nextFloat01())
                    let t = pow(u, 1.15)
                    return microMaxPt + (rMaxPt - microMaxPt) * t
                }
            }

            // Micro grain (dominant)
            let u = CGFloat(prng.nextFloat01())
            let t = pow(u, 2.6)
            return rMinPt + (microMaxPt - rMinPt) * t
        }

        func bucketIndex(_ v: Double) -> Int {
            if v < 0.22 { return 0 }
            if v < 0.42 { return 1 }
            if v < 0.64 { return 2 }
            return 3
        }

        let maxOpacity = max(0.0, min(1.0, cfg.fuzzMaxOpacity))
        let levels: [Double] = [0.18, 0.30, 0.50, 0.78].map { $0 * maxOpacity }

        // OUTSIDE DUST
        do {
            var paths: [Path] = Array(repeating: Path(), count: levels.count)
            let attempts = outsideDustCount * (isTightBudget ? 2 : 3)

            var made = 0
            for _ in 0..<attempts {
                if made >= outsideDustCount { break }

                let useStrong = (prng.nextUInt32() & 255) < 210
                let i = useStrong ? pick(strongAny) : Int(prng.nextUInt32() % UInt32(perPointStrength.count))

                let s = Double(perPointStrength[i])
                if s < 0.06 { continue }

                let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
                let t = CGPoint(x: n.y, y: -n.x)

                let u = Double(prng.nextFloat01())
                let distFrac = pow(u, cfg.fuzzDistancePowerOutside)
                let dist = CGFloat(distFrac) * bandWidthPt

                let jitter = CGFloat((Double(prng.nextSignedFloat()) * cfg.fuzzAlongTangentJitter)) * bandWidthPt
                let base = surfacePoints[i]
                let center = CGPoint(x: base.x + n.x * dist + t.x * jitter, y: base.y + n.y * dist + t.y * jitter)

                let r = sampleRadius(macroAllowed: true)
                if r < onePx * 0.2 { continue }

                var a = maxOpacity * s * max(0.0, cfg.fuzzSpeckStrength)
                a *= (0.35 + 0.65 * (1.0 - distFrac))
                a *= (0.70 + 0.35 * Double(prng.nextFloat01()))
                if a < maxOpacity * 0.06 { continue }

                let bin = bucketIndex(a / max(0.0001, maxOpacity))
                var p = paths[bin]
                p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                paths[bin] = p
                made += 1
            }

            for (idx, alpha) in levels.enumerated() {
                if paths[idx].isEmpty { continue }
                context.fill(paths[idx], with: .color(cfg.fuzzColor.opacity(alpha)))
            }
        }

        // EDGE BEADS (textured luminous rim; avoids “stroked line” look)
        do {
            let beadAlphaLevels: [Double] = [0.10, 0.16, 0.24].map { $0 * max(0.0, min(1.0, cfg.rimOuterOpacity)) }
            var beadPaths: [Path] = Array(repeating: Path(), count: beadAlphaLevels.count)

            let attempts = beadCount * (isTightBudget ? 2 : 3)
            var made = 0

            for _ in 0..<attempts {
                if made >= beadCount { break }

                let i = pick(strongAny)
                let s = Double(perPointStrength[i])
                if s < 0.10 { continue }

                let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
                let t = CGPoint(x: n.y, y: -n.x)

                // Keep beads very close to edge.
                let u = Double(prng.nextFloat01())
                let dist = CGFloat(pow(u, 2.6)) * (bandWidthPt * 0.28)

                let jitter = CGFloat((Double(prng.nextSignedFloat()) * cfg.fuzzAlongTangentJitter)) * bandWidthPt * 0.55
                let base = surfacePoints[i]
                let center = CGPoint(x: base.x + n.x * dist + t.x * jitter, y: base.y + n.y * dist + t.y * jitter)

                // Tiny radii
                let r = min(sampleRadius(macroAllowed: false), microMaxPt * 0.85)
                if r < onePx * 0.15 { continue }

                let a = min(1.0, 0.30 + 0.70 * s) * (0.65 + 0.35 * Double(prng.nextFloat01()))
                let bin: Int
                if a < 0.45 { bin = 0 }
                else if a < 0.72 { bin = 1 }
                else { bin = 2 }

                var p = beadPaths[bin]
                p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                beadPaths[bin] = p
                made += 1
            }

            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                for (idx, alpha) in beadAlphaLevels.enumerated() {
                    if beadPaths[idx].isEmpty { continue }
                    layer.fill(beadPaths[idx], with: .color(cfg.rimColor.opacity(alpha)))
                }
            }
        }

        // INSIDE DUST (only for wet indices; prevents “floating fuzz” in dry gaps)
        if insideBudget > 60, !strongWet.isEmpty {
            let insideOpacity = maxOpacity * max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
            let insideLevels: [Double] = [0.16, 0.26, 0.40, 0.58].map { $0 * insideOpacity }
            var paths: [Path] = Array(repeating: Path(), count: insideLevels.count)

            let attempts = insideBudget * (isTightBudget ? 2 : 3)
            var made = 0

            for _ in 0..<attempts {
                if made >= insideBudget { break }

                let i = pick(strongWet)
                let s = Double(perPointStrength[i])
                if s < 0.08 { continue }

                let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
                let t = CGPoint(x: n.y, y: -n.x)

                let insideBand = max(onePx, bandWidthPt * cfg.fuzzInsideWidthFactor)
                let u = Double(prng.nextFloat01())
                let distFrac = pow(u, cfg.fuzzDistancePowerInside)
                let dist = CGFloat(distFrac) * insideBand

                let jitter = CGFloat((Double(prng.nextSignedFloat()) * cfg.fuzzAlongTangentJitter)) * bandWidthPt * 0.40
                let base = surfacePoints[i]
                let center = CGPoint(x: base.x - n.x * dist + t.x * jitter, y: base.y - n.y * dist + t.y * jitter)

                let r = min(sampleRadius(macroAllowed: false), microMaxPt * 0.92)
                if r < onePx * 0.15 { continue }

                var a = insideOpacity * s * max(0.0, cfg.fuzzSpeckStrength)
                a *= (0.40 + 0.60 * (1.0 - distFrac))
                a *= (0.72 + 0.35 * Double(prng.nextFloat01()))
                if a < insideOpacity * 0.07 { continue }

                let bin = bucketIndex(a / max(0.0001, insideOpacity))
                var p = paths[bin]
                p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                paths[bin] = p
                made += 1
            }

            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                for (idx, alpha) in insideLevels.enumerated() {
                    if paths[idx].isEmpty { continue }
                    layer.fill(paths[idx], with: .color(cfg.fuzzColor.opacity(alpha)))
                }
            }
        }
    }
}
