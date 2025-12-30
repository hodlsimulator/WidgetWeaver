//
//  RainSurfaceDrawing+Fuzz.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import SwiftUI

extension RainSurfaceDrawing {

    // MARK: - Fuzz Haze (kept near-zero for widget-safe, black background)
    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [CGFloat],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        maxStrength: CGFloat,
        isTightBudget: Bool
    ) {
        let hazeStrength = max(0.0, min(1.0, cfg.fuzzHazeStrength))
        guard hazeStrength > 0.0001 else { return }
        guard maxStrength > 0.10 else { return }
        guard !isTightBudget else { return }

        // Intentionally minimal. (At this ref, haze is disabled by default in nowcast.)
        // Keeping a stub avoids accidental regressions reintroducing background lift.
        _ = (context, chartRect, corePath, surfacePoints, perSegmentStrength, cfg, bandWidthPt)
    }

    // MARK: - Core Edge Fade (softens “solid fill” dominance near rim)
    static func drawCoreEdgeFade(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [CGFloat],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: CGFloat
    ) {
        guard cfg.fuzzEnabled, cfg.canEnableFuzz else { return }
        guard cfg.fuzzInsideOpacityFactor > 0.0001 else { return }
        guard maxStrength > 0.10 else { return }
        guard !surfacePoints.isEmpty else { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let fadeW = max(onePx, bandWidthPt * 0.85)

        // Build a gradient “mask” via destinationOut strokes clipped to the core.
        // Stronger where fuzz strength is high (tails, low heights, low certainty).
        let levels: [Double] = [0.06, 0.10, 0.16]
        var paths: [Path] = Array(repeating: Path(), count: levels.count)

        for i in 1..<surfacePoints.count {
            let s = (i < perSegmentStrength.count) ? Double(perSegmentStrength[i]) : 0.0
            if s < 0.04 { continue }

            let w = fadeW * CGFloat(0.55 + 0.70 * s)
            if w <= onePx * 0.2 { continue }

            // Bin by strength to reduce draw calls.
            let bin: Int
            if s < 0.20 { bin = 0 }
            else if s < 0.45 { bin = 1 }
            else { bin = 2 }

            var p = paths[bin]
            p.move(to: surfacePoints[i - 1])
            p.addLine(to: surfacePoints[i])
            paths[bin] = p
        }

        let opacityFactor = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut

            for (idx, alpha0) in levels.enumerated() {
                if paths[idx].isEmpty { continue }
                let a = min(0.35, alpha0 * opacityFactor * Double(maxStrength))
                let w = fadeW * CGFloat(0.70 + 0.45 * Double(idx))
                layer.stroke(
                    paths[idx],
                    with: .color(Color.white.opacity(a)),
                    style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: - Core Erosion (vector “dusty” breakup along rim; widget-safe)
    static func drawCoreErosion(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perSegmentStrength: [CGFloat],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: CGFloat,
        isTightBudget: Bool
    ) {
        guard cfg.fuzzEnabled, cfg.canEnableFuzz else { return }
        guard cfg.fuzzErodeEnabled else { return }
        guard maxStrength > 0.10 else { return }
        guard surfacePoints.count > 2 else { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let blurW = max(onePx, bandWidthPt * max(0.0, min(0.50, cfg.fuzzErodeBlurFractionOfBand)))

        // Tight budgets: keep erosion but reduce passes and width.
        let passes = isTightBudget ? 1 : 2
        let width = max(onePx, bandWidthPt * max(0.18, min(0.60, cfg.fuzzErodeStrokeWidthFactor)))

        var edgePath = Path()
        edgePath.move(to: surfacePoints[0])
        for i in 1..<surfacePoints.count { edgePath.addLine(to: surfacePoints[i]) }

        // The erosion is done by “scrubbing” the rim with destinationOut strokes,
        // with tiny normal jitter via PRNG to avoid a clean vector edge.
        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xE0DE_900D_1234))
        let rimInset = max(0.0, cfg.fuzzErodeRimInsetPixels) / displayScale

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut

            for _ in 0..<passes {
                var p = Path()
                p.move(to: surfacePoints[0])

                for i in 1..<surfacePoints.count {
                    let s = (i < perSegmentStrength.count) ? Double(perSegmentStrength[i]) : 0.0
                    if s < 0.04 {
                        p.addLine(to: surfacePoints[i])
                        continue
                    }

                    let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
                    let jitterT = Double(prng.nextSignedFloat()) * 0.20
                    let jitterN = Double(prng.nextSignedFloat()) * 0.18

                    let t = CGPoint(x: n.y, y: -n.x)
                    let along = CGFloat(jitterT) * bandWidthPt * 0.18
                    let outward = CGFloat(jitterN) * bandWidthPt * 0.18

                    let pt = surfacePoints[i]
                    let moved = CGPoint(
                        x: pt.x + t.x * along - n.x * rimInset + n.x * outward,
                        y: pt.y + t.y * along - n.y * rimInset + n.y * outward
                    )
                    p.addLine(to: moved)
                }

                // Removal amount: strength-biased and clamped.
                let baseA = max(0.0, min(1.0, cfg.fuzzErodeStrength))
                let a = min(0.40, 0.10 + 0.34 * baseA * Double(maxStrength))

                layer.stroke(
                    p,
                    with: .color(Color.white.opacity(a)),
                    style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
                )

                if blurW > onePx * 0.5 {
                    layer.stroke(
                        p,
                        with: .color(Color.white.opacity(a * 0.35)),
                        style: StrokeStyle(lineWidth: width + blurW, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }

    // MARK: - Core Dissolve Perforation (tiny destinationOut holes near rim)
    static func drawCoreDissolvePerforation(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perPointStrength: [CGFloat],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: CGFloat,
        isTightBudget: Bool
    ) {
        guard cfg.fuzzEnabled, cfg.canEnableFuzz else { return }
        guard maxStrength > 0.12 else { return }
        guard surfacePoints.count == perPointStrength.count else { return }
        guard surfacePoints.count > 2 else { return }

        let onePx = 1.0 / max(1.0, displayScale)

        let baseBudget = max(0, min(2200, cfg.fuzzSpeckleBudget / 2))
        let budget = isTightBudget ? Int(Double(baseBudget) * 0.55) : baseBudget
        if budget < 120 { return }

        // Only perforate when fuzz is meaningfully strong.
        let attempts = budget * 2

        // Radius in device pixels (very tiny).
        let rMinPx = max(0.12, cfg.fuzzSpeckleRadiusPixels.lowerBound)
        let microMaxPx = min(1.05, max(rMinPx + 0.20, min(cfg.fuzzSpeckleRadiusPixels.upperBound, 1.35)))

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
        var made = 0


        func pickIndex() -> Int {
            let j = Int(prng.nextUInt64() % UInt64(strongWet.count))
            return strongWet[j]
        }

        func radiusPt() -> CGFloat {
            let u = Double(prng.nextFloat01())
            let px = rMinPx + (microMaxPx - rMinPx) * pow(u, 2.5)
            return CGFloat(px) / displayScale
        }

        for _ in 0..<attempts {
            if made >= budget { break }

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
            made += 1
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

    // MARK: - Speckles (outside dust + inside weld; fine grain)
    static func drawFuzzSpeckles(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGPoint],
        perPointStrength: [CGFloat],
        perSegmentStrength: [CGFloat],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: CGFloat,
        isTightBudget: Bool
    ) {
        guard cfg.fuzzEnabled, cfg.canEnableFuzz else { return }
        guard maxStrength > 0.06 else { return }
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
            let j = Int(prng.nextUInt64() % UInt64(max(1, list.count)))
            return list[j]
        }

        func sampleRadius(macroAllowed: Bool) -> CGFloat {
            if macroAllowed, !isTightBudget {
                let macroChance: UInt32 = 7 // ~2.7% with mod 256
                if (prng.nextUInt64() & 255) < UInt64(macroChance) {
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

                let useStrong = (prng.nextUInt64() & 255) < 210
                let i = useStrong ? pick(strongAny) : Int(prng.nextUInt64() % UInt64(perPointStrength.count))

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
            if beadCount > 0 {
                let beadLevels: [Double] = [0.28, 0.48, 0.72].map { $0 * maxOpacity }
                var beadPaths: [Path] = Array(repeating: Path(), count: beadLevels.count)

                let attempts = beadCount * (isTightBudget ? 2 : 3)
                var made = 0
                for _ in 0..<attempts {
                    if made >= beadCount { break }

                    let i = pick(strongAny)
                    let s = Double(perPointStrength[i])
                    if s < 0.10 { continue }

                    let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
                    let t = CGPoint(x: n.y, y: -n.x)

                    let u = Double(prng.nextFloat01())
                    let dist = CGFloat(pow(u, 1.7)) * bandWidthPt * 0.28
                    let jitter = CGFloat((Double(prng.nextSignedFloat()) * 0.50)) * bandWidthPt * 0.18

                    let base = surfacePoints[i]
                    let center = CGPoint(x: base.x + n.x * dist + t.x * jitter, y: base.y + n.y * dist + t.y * jitter)

                    let uR = CGFloat(prng.nextFloat01())
                    let r = max(onePx * 0.30, (rMinPt + (microMaxPt - rMinPt) * pow(uR, 2.2)) * 0.85)
                    if r < onePx * 0.22 { continue }

                    var a = maxOpacity * min(1.0, 0.55 + 0.85 * s)
                    a *= (0.65 + 0.35 * Double(prng.nextFloat01()))
                    if a < maxOpacity * 0.08 { continue }

                    let bin: Int
                    if a < maxOpacity * 0.26 { bin = 0 }
                    else if a < maxOpacity * 0.45 { bin = 1 }
                    else { bin = 2 }

                    var p = beadPaths[bin]
                    p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                    beadPaths[bin] = p
                    made += 1
                }

                for (idx, alpha) in beadLevels.enumerated() {
                    if beadPaths[idx].isEmpty { continue }
                    context.fill(beadPaths[idx], with: .color(cfg.rimColor.opacity(alpha)))
                }
            }
        }

        // INSIDE DUST (weld band)
        do {
            if insideBudget > 0, !strongWet.isEmpty {
                let insideLevels: [Double] = [0.14, 0.24, 0.40, 0.62].map { $0 * maxOpacity * max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor)) }
                var insidePaths: [Path] = Array(repeating: Path(), count: insideLevels.count)

                let attempts = insideBudget * (isTightBudget ? 2 : 3)
                var made = 0

                for _ in 0..<attempts {
                    if made >= insideBudget { break }

                    let i = pick(strongWet)
                    let s = Double(perPointStrength[i])
                    if s < 0.10 { continue }

                    let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
                    let t = CGPoint(x: n.y, y: -n.x)

                    let u = Double(prng.nextFloat01())
                    let insideBand = max(onePx, bandWidthPt * cfg.fuzzInsideWidthFactor)
                    let distFrac = pow(u, cfg.fuzzDistancePowerInside)
                    let dist = CGFloat(distFrac) * insideBand

                    let jitter = CGFloat((Double(prng.nextSignedFloat()) * cfg.fuzzAlongTangentJitter)) * bandWidthPt * 0.30
                    let base = surfacePoints[i]
                    let center = CGPoint(x: base.x - n.x * dist + t.x * jitter, y: base.y - n.y * dist + t.y * jitter)

                    let r = sampleRadius(macroAllowed: false)
                    if r < onePx * 0.20 { continue }

                    var a = maxOpacity * s * max(0.0, cfg.fuzzSpeckStrength) * max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
                    a *= (0.55 + 0.45 * (1.0 - distFrac))
                    a *= (0.75 + 0.35 * Double(prng.nextFloat01()))
                    if a < maxOpacity * 0.07 { continue }

                    let bin = bucketIndex(a / max(0.0001, maxOpacity))
                    var p = insidePaths[bin]
                    p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                    insidePaths[bin] = p
                    made += 1
                }

                context.drawLayer { layer in
                    layer.clip(to: corePath)
                    for (idx, alpha) in insideLevels.enumerated() {
                        if insidePaths[idx].isEmpty { continue }
                        layer.fill(insidePaths[idx], with: .color(cfg.fuzzColor.opacity(alpha)))
                    }
                }
            }
        }

        _ = perSegmentStrength
    }
}
