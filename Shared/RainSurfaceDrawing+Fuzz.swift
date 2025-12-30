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
        corePath: Path,
        chartRect: CGRect,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: CGFloat,
        isTightBudget: Bool
    ) {
        guard cfg.fuzzEnabled, cfg.canEnableFuzz else { return }
        guard cfg.fuzzHazeEnabled else { return }

        // Keep haze extremely constrained to avoid any grey wash / halo on black.
        let a = max(0.0, min(0.04, cfg.fuzzHazeMaxOpacity)) * Double(maxStrength)
        if a <= 0.0001 { return }

        // In this revision, haze is effectively disabled (no wide-area fog).
        _ = context
        _ = corePath
        _ = chartRect
        _ = cfg
        _ = bandWidthPt
        _ = displayScale
        _ = maxStrength
        _ = isTightBudget
        _ = a
    }

    // MARK: - Core Edge Fade (destinationOut band along rim)

    static func drawCoreEdgeFade(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [CGFloat],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPt: CGFloat,
        displayScale: CGFloat,
        maxStrength: CGFloat,
        isTightBudget: Bool
    ) {
        guard cfg.fuzzEnabled, cfg.canEnableFuzz else { return }
        guard cfg.fuzzCoreFadeEnabled else { return }
        guard maxStrength > 0.04 else { return }
        guard surfacePoints.count > 2 else { return }
        guard cfg.fuzzInsideOpacityFactor > 0.0001 else { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let fadeFrac = max(0.0, min(0.45, cfg.coreFadeFraction))
        let fadeW = max(onePx, bandWidthPt * CGFloat(0.85 + 3.10 * fadeFrac))

        // Stronger fade where fuzz strength is high (tails, low heights, low certainty).
        let levels: [Double] = [0.10, 0.18, 0.28]
        var paths: [Path] = Array(repeating: Path(), count: levels.count)

        for i in 0..<perSegmentStrength.count {
            let s = Double(max(0.0, min(1.0, perSegmentStrength[i])))
            if s < 0.018 { continue }

            let bin = min(levels.count - 1, max(0, Int(floor(s * Double(levels.count - 1)))))
            var p = paths[bin]
            p.move(to: surfacePoints[i])
            p.addLine(to: surfacePoints[i + 1])
            paths[bin] = p

            _ = fadeW
        }

        let opacityFactor = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
        let strengthScale = 0.72 + 0.90 * sqrt(max(0.0, Double(maxStrength)))

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut

            for (idx, alpha0) in levels.enumerated() {
                if paths[idx].isEmpty { continue }

                let a = min(0.42, alpha0 * opacityFactor * strengthScale)
                if a <= 0.0001 { continue }

                let w = fadeW * CGFloat(0.86 + 0.72 * Double(idx))

                layer.stroke(
                    paths[idx],
                    with: .color(Color.white.opacity(a)),
                    style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
                )
            }
        }

        _ = isTightBudget
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
        guard maxStrength > 0.07 else { return }
        guard surfacePoints.count > 2 else { return }

        let onePx = 1.0 / max(1.0, displayScale)

        // Keep erosion tight and local to the rim (no background lift).
        let blurFrac = max(0.0, min(0.45, cfg.fuzzErodeBlurFractionOfBand))
        let blurW = max(onePx, bandWidthPt * blurFrac)

        // Tight budgets: keep erosion, reduce passes and blur.
        let passes = isTightBudget ? 1 : 2

        let widthFactor = max(0.22, min(1.10, cfg.fuzzErodeStrokeWidthFactor))
        let width = max(onePx, bandWidthPt * CGFloat(widthFactor))

        let rimInset = max(0.0, cfg.fuzzErodeRimInsetPixels) / displayScale

        // Strength-gated paths so high-certainty plateaus do not get uniformly “bitten”.
        let bins = isTightBudget ? 3 : 4
        let minSeg: CGFloat = isTightBudget ? 0.035 : 0.028

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xE0DE_900D_1234))

        func jitteredPoints() -> [CGPoint] {
            let n = surfacePoints.count
            var out = surfacePoints
            if normals.count != n { return out }

            for i in 0..<n {
                let sL = (i > 0 && i - 1 < perSegmentStrength.count) ? perSegmentStrength[i - 1] : 0
                let sR = (i < perSegmentStrength.count) ? perSegmentStrength[i] : 0
                let s = max(0.0, min(1.0, 0.5 * (sL + sR)))

                if s < minSeg {
                    out[i] = surfacePoints[i]
                    continue
                }

                let nrm = normals[i]
                let tan = CGPoint(x: nrm.y, y: -nrm.x)

                // Jitter scales with strength so low-strength segments stay cleaner.
                let jScale = CGFloat(0.22 + 0.72 * Double(s))
                let jitterT = CGFloat(Double(prng.nextSignedFloat())) * bandWidthPt * 0.20 * jScale
                let jitterN = CGFloat(Double(prng.nextSignedFloat())) * bandWidthPt * 0.18 * jScale

                let base = surfacePoints[i]
                out[i] = CGPoint(
                    x: base.x + tan.x * jitterT - nrm.x * rimInset + nrm.x * jitterN,
                    y: base.y + tan.y * jitterT - nrm.y * rimInset + nrm.y * jitterN
                )
            }
            return out
        }

        let strengths: [CGFloat] = perSegmentStrength.map { s in
            let v = max(0.0, min(1.0, s))
            return (v < minSeg) ? 0.0 : v
        }

        let baseA = max(0.0, min(1.0, cfg.fuzzErodeStrength))
        let strengthScale = sqrt(max(0.0, Double(maxStrength)))

        // Bin-specific alphas: stronger bins remove more.
        let aLo = min(0.38, 0.14 + 0.34 * baseA * strengthScale)
        let aMid = min(0.52, 0.20 + 0.46 * baseA * strengthScale)
        let aHi = min(0.66, 0.26 + 0.58 * baseA * strengthScale)

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut

            for pass in 0..<passes {
                let pts = jitteredPoints()
                let paths = buildBinnedSegmentPaths(points: pts, perSegmentStrength: strengths, binCount: bins)

                // Skip bin 0 (too weak).
                for idx in 1..<paths.count {
                    if paths[idx].isEmpty { continue }

                    let frac = Double(idx) / Double(max(1, paths.count - 1))
                    let a: Double
                    if frac < 0.55 { a = aLo }
                    else if frac < 0.82 { a = aMid }
                    else { a = aHi }

                    let w = width * CGFloat(0.85 + 0.35 * frac)

                    layer.stroke(
                        paths[idx],
                        with: .color(Color.white.opacity(a)),
                        style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
                    )

                    if !isTightBudget, blurW > onePx * 0.65, pass == 0 {
                        layer.stroke(
                            paths[idx],
                            with: .color(Color.white.opacity(a * 0.32)),
                            style: StrokeStyle(lineWidth: w + blurW, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Core Dissolve Perforation (tiny holes inside rim band)

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
        guard cfg.fuzzPerforationEnabled else { return }
        guard maxStrength > 0.08 else { return }
        guard surfacePoints.count == normals.count else { return }
        guard surfacePoints.count == perPointStrength.count else { return }

        let baseBudget = max(0, min(2800, Int(Double(cfg.fuzzSpeckleBudget) * 0.70)))
        let strengthBoost = 0.60 + 0.60 * sqrt(max(0.0, Double(maxStrength)))
        var budget = Int(Double(baseBudget) * strengthBoost)
        budget = isTightBudget ? Int(Double(budget) * 0.55) : budget
        budget = max(0, min(2800, budget))
        if budget < 120 { return }

        // Only perforate when fuzz is meaningfully strong.
        let attempts = budget * 3

        let onePx = 1.0 / max(1.0, displayScale)
        let rMinPx = max(0.15, cfg.fuzzSpeckleRadiusPixels.lowerBound)
        let microMaxPx = min(1.55, max(rMinPx + 0.20, min(cfg.fuzzSpeckleRadiusPixels.upperBound, 1.55)))

        // Pick wet-ish points only.
        let baselineY = (surfacePoints.map { $0.y }.max() ?? 0.0) + 0.0001
        let wetEps = max(onePx * 0.5, 0.0001)

        var strongWet: [Int] = []
        strongWet.reserveCapacity(256)

        for i in 0..<surfacePoints.count {
            let h = baselineY - surfacePoints[i].y
            if h > wetEps, perPointStrength[i] > 0.10 {
                strongWet.append(i)
            }
        }
        if strongWet.isEmpty { return }

        let levels: [Double] = [0.18, 0.30, 0.42, 0.52]
        var holePaths: [Path] = Array(repeating: Path(), count: levels.count)

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xBADC_0FFE_EE55_1122))

        let insideBand = max(onePx, bandWidthPt * cfg.fuzzInsideWidthFactor)

        func pick(_ arr: [Int]) -> Int {
            let idx = Int(prng.nextUInt64() % UInt64(arr.count))
            return arr[idx]
        }

        var made = 0
        for _ in 0..<attempts {
            if made >= budget { break }

            let i = pick(strongWet)
            let s = Double(perPointStrength[i])
            if s < 0.10 { continue }

            let u = Double(prng.nextFloat01())
            let dist = CGFloat(pow(u, cfg.fuzzDistancePowerInside)) * insideBand * 0.75

            // Tangent jitter keeps perforation organic but still rim-adjacent.
            let n = normals[i]
            let t = CGPoint(x: n.y, y: -n.x)
            let jitterT = CGFloat(Double(prng.nextSignedFloat())) * bandWidthPt * 0.20
            let center = CGPoint(
                x: surfacePoints[i].x - n.x * dist + t.x * jitterT,
                y: surfacePoints[i].y - n.y * dist + t.y * jitterT
            )

            let rPx = rMinPx + (microMaxPx - rMinPx) * pow(Double(prng.nextFloat01()), 1.25)
            let r = max(onePx * 0.18, CGFloat(rPx) / displayScale)

            let removal = min(0.58, 0.18 + 0.58 * s)
            let bin: Int
            if removal < 0.22 { bin = 0 }
            else if removal < 0.34 { bin = 1 }
            else if removal < 0.46 { bin = 2 }
            else { bin = 3 }

            var p = holePaths[bin]
            p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            holePaths[bin] = p

            made += 1
        }

        if made == 0 { return }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut

            for (idx, alpha) in levels.enumerated() {
                if holePaths[idx].isEmpty { continue }
                layer.fill(holePaths[idx], with: .color(Color.white.opacity(alpha)))
            }
        }
    }

    // MARK: - Speckles (outside dust + edge beads + inside weld)

    static func drawFuzzSpeckles(
        in context: inout GraphicsContext,
        corePath: Path,
        chartRect: CGRect,
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
        guard surfacePoints.count == normals.count else { return }
        guard surfacePoints.count == perPointStrength.count else { return }
        guard maxStrength > 0.02 else { return }

        let wPx = Double(chartRect.width * displayScale)
        let budgetByWidth = max(1200, min(9500, Int(wPx * 22.0)))

        let baseBudget = max(0, min(cfg.fuzzSpeckleBudget, budgetByWidth))
        let density = max(0.0, cfg.fuzzDensity)
        let strengthBoost = 0.85 + 0.95 * sqrt(max(0.0, Double(maxStrength)))
        var budget = Int(Double(baseBudget) * density * strengthBoost)
        budget = max(0, min(9800, budget))
        if isTightBudget { budget = Int(Double(budget) * 0.65) }

        if budget < 200 { return }

        let insideFrac = max(0.0, min(0.90, cfg.fuzzInsideSpeckleFraction + 0.08))
        var insideBudget = Int(Double(budget) * insideFrac)
        insideBudget = max(0, min(budget, insideBudget))
        var outsideBudget = budget - insideBudget

        // Allocate part of outside budget to “edge beads” (dominant particulate silhouette).
        var beadCount = Int(Double(outsideBudget) * (isTightBudget ? 0.34 : 0.48))
        beadCount = max(0, min(outsideBudget, min(2400, beadCount)))
        outsideBudget -= beadCount

        let onePx = 1.0 / max(1.0, displayScale)

        // Radii (keep micro; “fine grain” is particle size, not visibility).
        let rMinPx = max(0.25, cfg.fuzzSpeckleRadiusPixels.lowerBound)
        let rMaxPx = max(rMinPx, cfg.fuzzSpeckleRadiusPixels.upperBound)

        let microCapPx = min(rMaxPx, 1.20)
        let macroAllowed = cfg.fuzzMacroEnabled && !isTightBudget

        func sampleRadius(macroAllowed: Bool) -> (r: CGFloat, isMacro: Bool) {
            let u = Double(prng.nextFloat01())
            let isMacro = macroAllowed && u > 0.965
            let maxPx = isMacro ? min(rMaxPx, 2.30) : microCapPx
            let rr = rMinPx + (maxPx - rMinPx) * pow(u, 1.35)
            return (max(onePx * 0.18, CGFloat(rr) / displayScale), isMacro)
        }

        // Candidate indices
        var strongWet: [Int] = []
        var tailDry: [Int] = []
        strongWet.reserveCapacity(512)
        tailDry.reserveCapacity(512)

        // Wet detection must be height-only; use baseline inferred from geometry rect.
        let baselineY = chartRect.maxY
        let wetEps = max(onePx * 0.5, 0.0001)

        for i in 0..<surfacePoints.count {
            let h = baselineY - surfacePoints[i].y
            if h > wetEps {
                if perPointStrength[i] > 0.06 { strongWet.append(i) }
            } else {
                // In dry region, keep candidates where strength indicates tail influence.
                if perPointStrength[i] > 0.10 { tailDry.append(i) }
            }
        }

        if strongWet.isEmpty && tailDry.isEmpty { return }

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xC0FF_EE12_0123_4567))

        // Opacity levels
        let baseMaxOpacity = max(0.0, min(1.0, cfg.fuzzMaxOpacity))
        let maxOpacity = min(0.52, baseMaxOpacity * (0.95 + 0.70 * sqrt(max(0.0, Double(maxStrength)))))
        let levels: [Double] = [0.22, 0.40, 0.64, 0.96].map { $0 * maxOpacity }
        var paths: [Path] = Array(repeating: Path(), count: levels.count)

        func bucketIndex(_ a: Double) -> Int {
            if a < 0.28 { return 0 }
            if a < 0.48 { return 1 }
            if a < 0.70 { return 2 }
            return 3
        }

        func pick(_ arr: [Int]) -> Int {
            let idx = Int(prng.nextUInt64() % UInt64(arr.count))
            return arr[idx]
        }

        // OUTSIDE DUST
        if outsideBudget > 0, (!strongWet.isEmpty || !tailDry.isEmpty) {
            let attempts = outsideBudget * (isTightBudget ? 2 : 4)
            var made = 0

            for _ in 0..<attempts {
                if made >= outsideBudget { break }

                // Prefer wet points (edge-owned), but allow tail-dry points for transitions.
                let useTail = (!tailDry.isEmpty) && (prng.nextUInt64() & 255) < 34
                let i = useTail ? pick(tailDry) : pick(strongWet.isEmpty ? tailDry : strongWet)

                let s = Double(perPointStrength[i])
                if s < 0.05 { continue }

                // Ridge pepper suppression (do not go to zero).
                let tailN = min(1.0, max(0.0, (s - 0.10) / 0.70))
                if tailN < 0.02, s < 0.16 {
                    if (prng.nextUInt64() & 255) < 200 { continue }
                }

                let n = normals[i]
                let t = CGPoint(x: n.y, y: -n.x)

                // Distance outward: biased close to rim (avoid floating fuzz).
                let u = Double(prng.nextFloat01())
                let distFrac = pow(u, cfg.fuzzDistancePowerOutside)
                var dist = CGFloat(distFrac) * bandWidthPt

                // Tighten further in tails.
                dist *= CGFloat(0.55 + 0.30 * (1.0 - tailN))

                // Keep the cloud close; avoid “floating” dust.
                dist = min(dist, bandWidthPt * 0.78)

                let along = CGFloat(Double(prng.nextSignedFloat())) * bandWidthPt * CGFloat(cfg.fuzzAlongTangentJitter)
                let base = surfacePoints[i]
                let center = CGPoint(x: base.x + n.x * dist + t.x * along, y: base.y + n.y * dist + t.y * along)

                let sr = sampleRadius(macroAllowed: macroAllowed)
                let r = sr.r
                if r < onePx * 0.18 { continue }

                var aUnit = s * max(0.0, cfg.fuzzSpeckStrength)
                aUnit *= (0.72 + 0.28 * (1.0 - distFrac))
                aUnit *= (0.80 + 0.20 * Double(prng.nextFloat01()))

                // Avoid over-flooding with extremely faint specks.
                if aUnit < 0.05 { continue }

                let bin = bucketIndex(min(1.0, aUnit))
                var p = paths[bin]
                p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                paths[bin] = p

                made += 1
            }

            // Draw outside dust un-clipped (must define silhouette).
            for (idx, alpha) in levels.enumerated() {
                if paths[idx].isEmpty { continue }
                context.fill(paths[idx], with: .color(cfg.fuzzColor.opacity(alpha)))
            }
        }

        // EDGE BEADS (dominant silhouette)
        if beadCount > 0, (!strongWet.isEmpty || !tailDry.isEmpty) {
            let beadLevels: [Double] = [0.34, 0.58, 0.86].map { $0 * maxOpacity }
            var beadPaths: [Path] = Array(repeating: Path(), count: beadLevels.count)

            let attempts = beadCount * (isTightBudget ? 2 : 3)
            var made = 0

            for _ in 0..<attempts {
                if made >= beadCount { break }

                let preferTail = !tailDry.isEmpty && (prng.nextUInt64() & 255) < 74
                let i = preferTail ? pick(tailDry) : pick(strongWet.isEmpty ? tailDry : strongWet)

                let s = Double(perPointStrength[i])
                if s < 0.08 { continue }

                let n = normals[i]
                let t = CGPoint(x: n.y, y: -n.x)

                // Very close to rim: “beads” define the edge.
                let u = Double(prng.nextFloat01())
                let dist = CGFloat(pow(u, 2.2)) * bandWidthPt * 0.14
                let along = CGFloat(Double(prng.nextSignedFloat())) * bandWidthPt * 0.16
                let base = surfacePoints[i]
                let center = CGPoint(x: base.x + n.x * dist + t.x * along, y: base.y + n.y * dist + t.y * along)

                // Radius (micro only for beads).
                let rr = (0.24 + 0.92 * pow(Double(prng.nextFloat01()), 1.65)) * microCapPx
                let r = max(onePx * 0.18, CGFloat(rr) / displayScale)

                let tailN = min(1.0, max(0.0, (s - 0.12) / 0.75))
                var aUnit = min(1.0, 0.62 + 1.05 * s)
                aUnit *= (0.78 + 0.22 * Double(prng.nextFloat01()))
                aUnit *= (0.78 + 0.22 * tailN)

                if aUnit < 0.16 { continue }

                let bin: Int
                if aUnit < 0.30 { bin = 0 }
                else if aUnit < 0.52 { bin = 1 }
                else { bin = 2 }

                var p = beadPaths[bin]
                p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
                beadPaths[bin] = p
                made += 1
            }

            let oldBlend = context.blendMode
            context.blendMode = .plusLighter
            for (idx, alpha) in beadLevels.enumerated() {
                if beadPaths[idx].isEmpty { continue }
                context.fill(beadPaths[idx], with: .color(cfg.rimColor.opacity(alpha)))
            }
            context.blendMode = oldBlend
        }

        // INSIDE DUST (weld band)
        if insideBudget > 0, !strongWet.isEmpty {
            let insideOpacity = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
            let insideBoost = 0.90 + 0.70 * sqrt(max(0.0, Double(maxStrength)))
            let insideLevels: [Double] = [0.24, 0.40, 0.60, 0.86].map { $0 * maxOpacity * insideOpacity * insideBoost }
            var insidePaths: [Path] = Array(repeating: Path(), count: insideLevels.count)

            let attempts = insideBudget * (isTightBudget ? 3 : 4)
            var made = 0

            for _ in 0..<attempts {
                if made >= insideBudget { break }

                let i = pick(strongWet)
                let s = Double(perPointStrength[i])
                if s < 0.08 { continue }

                let n = (i < normals.count) ? normals[i] : CGPoint(x: 0, y: -1)
                let t = CGPoint(x: n.y, y: -n.x)

                let u = Double(prng.nextFloat01())
                let insideBand = max(onePx, bandWidthPt * cfg.fuzzInsideWidthFactor)
                let distFrac = pow(u, cfg.fuzzDistancePowerInside)
                let dist = CGFloat(distFrac) * insideBand

                let jitter = CGFloat((Double(prng.nextSignedFloat()) * cfg.fuzzAlongTangentJitter)) * bandWidthPt * 0.30
                let base = surfacePoints[i]
                let center = CGPoint(x: base.x - n.x * dist + t.x * jitter, y: base.y - n.y * dist + t.y * jitter)

                let sr = sampleRadius(macroAllowed: false)
                let r = sr.r
                if r < onePx * 0.20 { continue }

                var aUnit = s * max(0.0, cfg.fuzzSpeckStrength)
                aUnit *= (0.70 + 0.55 * (1.0 - distFrac))
                aUnit *= (0.80 + 0.20 * Double(prng.nextFloat01()))
                if aUnit < 0.04 { continue }

                let bin = bucketIndex(min(1.0, aUnit))
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

        _ = perSegmentStrength
    }
}
