//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum RainSurfaceDrawing {

    static func drawSurface(
        in context: inout GraphicsContext,
        geometry: RainSurfaceGeometry,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let chartRect = geometry.chartRect
        guard geometry.sampleCount > 1 else { return }

        // If the surface is effectively absent, skip heavy styling work.
        let scale = max(1.0, displayScale)
        let maxHeightPt = geometry.heights.max() ?? 0.0
        let maxHeightPx = maxHeightPt * scale
        guard maxHeightPx >= 0.18 else { return }

        let bandWidthPx = fuzzBandWidthPixels(chartRect: chartRect, cfg: cfg, displayScale: displayScale)

        // Per-point styling strength (0..1), derived from probability + height semantics.
        let perPointStrength = computeFuzzStrengthPerPoint(
            geometry: geometry,
            cfg: cfg,
            bandWidthPx: bandWidthPx
        )
        let maxStrength = perPointStrength.max() ?? 0.0

        // Surface points + outward normals.
        let surfacePoints: [CGPoint] = (0..<geometry.sampleCount).map { geometry.surfacePointAt($0) }
        let normals = computeOutwardNormals(points: surfacePoints)
        let perSeg = computePerSegmentStrength(perPoint: perPointStrength)

        let isTightBudget = isTightBudgetMode(cfg)

        let fuzzAllowed =
            cfg.canEnableFuzz &&
            cfg.fuzzEnabled &&
            (cfg.fuzzMaxOpacity > 0.000_1) &&
            (cfg.fuzzSpeckStrength > 0.000_1 || cfg.fuzzHazeStrength > 0.000_1) &&
            (maxStrength > 0.015)

        // Slightly inset the solid core so fuzz owns the boundary (cheap, no raster).
        let insetPt = max(0.0, cfg.fuzzErodeRimInsetPixels) / scale
        var insetTopPoints: [CGPoint] = surfacePoints
        if fuzzAllowed, insetPt > 0.000_1, insetTopPoints.count == geometry.sampleCount, normals.count == geometry.sampleCount {
            let edgePow = max(0.10, cfg.fuzzErodeEdgePower)
            for i in 0..<insetTopPoints.count {
                let s = pow(RainSurfaceMath.clamp01(perPointStrength[i]), edgePow)
                let d = insetPt * CGFloat(s)
                var p = insetTopPoints[i]
                let n = normals[i]
                p.x += n.dx * d
                p.y += n.dy * d
                if p.y > geometry.baselineY { p.y = geometry.baselineY }
                insetTopPoints[i] = p
            }
        }

        let corePath = geometry.filledPath(usingInsetTopPoints: insetTopPoints)
        if corePath.isEmpty { return }

        let surfacePath = geometry.surfacePolylinePath()

        // ---- Core fill -------------------------------------------------------------------------
        context.fill(corePath, with: .color(cfg.coreBodyColor))

        // Subtle internal lift (clipped), keeping background black.
        drawCoreTopLift(
            in: &context,
            corePath: corePath,
            surfacePath: surfacePath,
            chartRect: chartRect,
            baselineY: geometry.baselineY,
            cfg: cfg,
            bandWidthPx: bandWidthPx,
            displayScale: displayScale,
            maxStrength: maxStrength,
            fuzzAllowed: fuzzAllowed
        )

        // Extra fade-out at the top edge inside the core helps weld, but costs a filtered layer.
        // Skip in tight budgets to avoid WidgetKit placeholder regressions.
        if !isTightBudget {
            drawCoreEdgeFade(
                in: &context,
                corePath: corePath,
                surfacePath: surfacePath,
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                displayScale: displayScale,
                maxStrength: maxStrength
            )
        }

        // ---- Fuzz (outside-heavy particulate band + inside weld) --------------------------------
        // In tight budgets: avoid haze + erosion layers; rely on speckles + inside weld stroke (cheap).
        if fuzzAllowed, !isTightBudget, cfg.fuzzHazeStrength > 0.000_1, maxStrength > 0.02 {
            drawFuzzHaze(
                in: &context,
                chartRect: chartRect,
                corePath: corePath,
                surfacePoints: surfacePoints,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                displayScale: displayScale,
                maxStrength: maxStrength
            )
        }

        if fuzzAllowed, !isTightBudget, cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.000_1, maxStrength > 0.02 {
            drawCoreErosion(
                in: &context,
                corePath: corePath,
                surfacePoints: surfacePoints,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                displayScale: displayScale,
                maxStrength: maxStrength
            )
        }

        if fuzzAllowed, cfg.fuzzSpeckStrength > 0.000_1, cfg.fuzzSpeckleBudget > 0, maxStrength > 0.03 {
            drawFuzzSpeckles(
                in: &context,
                chartRect: chartRect,
                corePath: corePath,
                surfacePoints: surfacePoints,
                normals: normals,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                displayScale: displayScale,
                maxStrength: maxStrength
            )
        }

        // Faint under-grain near baseline (clipped to the core).
        drawBaselineGrain(
            in: &context,
            chartRect: chartRect,
            corePath: corePath,
            baselineY: geometry.baselineY,
            cfg: cfg,
            displayScale: displayScale,
            maxStrength: maxStrength
        )

        // ---- Gloss (optional) ------------------------------------------------------------------
        if cfg.glossEnabled, cfg.glossMaxOpacity > 0.000_1 {
            drawGloss(
                in: &context,
                corePath: corePath,
                surfacePath: surfacePath,
                chartRect: chartRect,
                cfg: cfg,
                displayScale: displayScale
            )
        }

        // ---- Glints (optional) -----------------------------------------------------------------
        if cfg.glintEnabled, cfg.glintMaxOpacity > 0.000_1, cfg.glintCount > 0 {
            drawGlints(
                in: &context,
                surfacePoints: surfacePoints,
                cfg: cfg,
                displayScale: displayScale
            )
        }

        // ---- Rim (crisp edge) ------------------------------------------------------------------
        if cfg.rimEnabled, maxHeightPx > 0.24 {
            drawRim(
                in: &context,
                surfacePath: surfacePath,
                cfg: cfg,
                displayScale: displayScale
            )
        }
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard cfg.baselineEnabled else { return }

        let scale = max(1.0, displayScale)
        let y = RainSurfaceMath.alignToPixelCenter(
            baselineY + (cfg.baselineOffsetPixels / scale),
            displayScale: displayScale
        )
        let w = max(1.0, cfg.baselineWidthPixels / scale)

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: y))
        p.addLine(to: CGPoint(x: chartRect.maxX, y: y))

        let fade = max(0.0, min(0.49, cfg.baselineEndFadeFraction))
        let leftA = fade
        let rightA = 1.0 - fade

        let color = cfg.baselineColor.opacity(cfg.baselineLineOpacity)
        let grad = Gradient(stops: [
            .init(color: color.opacity(0.0), location: 0.0),
            .init(color: color, location: leftA),
            .init(color: color, location: rightA),
            .init(color: color.opacity(0.0), location: 1.0)
        ])

        context.stroke(
            p,
            with: .linearGradient(
                grad,
                startPoint: CGPoint(x: chartRect.minX, y: y),
                endPoint: CGPoint(x: chartRect.maxX, y: y)
            ),
            lineWidth: w
        )
    }
}

// MARK: - Internals

private extension RainSurfaceDrawing {

    static func isTightBudgetMode(_ cfg: RainForecastSurfaceConfiguration) -> Bool {
        // Widget-style budgets typically cap dense samples hard.
        // Keep the existing signal (maxDenseSamples <= 280) as the primary trigger.
        return (cfg.maxDenseSamples <= 280) || (cfg.fuzzSpeckleBudget <= 900)
    }

    static func fuzzBandWidthPixels(chartRect: CGRect, cfg: RainForecastSurfaceConfiguration, displayScale: CGFloat) -> CGFloat {
        let pxFromFraction = chartRect.height * cfg.fuzzWidthFraction * max(1.0, displayScale)
        let clamped = min(max(pxFromFraction, cfg.fuzzWidthPixelsClamp.lowerBound), cfg.fuzzWidthPixelsClamp.upperBound)
        return max(6.0, clamped)
    }

    // NOTE: geometry.certaintyAt(i) is treated as a probability/chance (0..1).
    // Height always comes from intensity; chance affects styling only.
    static func computeFuzzStrengthPerPoint(
        geometry: RainSurfaceGeometry,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat
    ) -> [Double] {
        let n = geometry.sampleCount
        guard n > 0 else { return [] }

        let scale = max(1.0, geometry.displayScale)
        let dxPx = geometry.dx * scale
        let onePx = 1.0 / max(1.0, scale)

        // "Wet" is height-driven only.
        let wetByHeight: [Bool] = geometry.heights.map { $0 > (onePx * 0.5) }

        // Distance in samples to nearest wet point (for tails).
        var distToWet = Array(repeating: Int.max / 4, count: n)
        var lastWet = -1
        for i in 0..<n {
            if wetByHeight[i] { lastWet = i }
            if lastWet >= 0 { distToWet[i] = i - lastWet }
        }
        lastWet = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if wetByHeight[i] { lastWet = i }
            if lastWet >= 0 { distToWet[i] = min(distToWet[i], lastWet - i) }
        }

        // Tail distance in pixels: short, readable, and capped by the band width.
        let tailDistancePx: CGFloat = max(min(bandWidthPx * 2.1, 180.0), 28.0)
        let safeDxPx = max(0.000_001, dxPx)

        func tailPresence(_ dSamples: Int) -> Double {
            let dPx = Double(CGFloat(dSamples)) * Double(safeDxPx)
            let t = RainSurfaceMath.smoothstep(0.0, Double(tailDistancePx), dPx)
            return max(0.0, 1.0 - t)
        }

        // Chance -> strength mapping (below threshold => fuzzier).
        let thr = RainSurfaceMath.clamp01(cfg.fuzzChanceThreshold)
        let trans = max(0.000_1, cfg.fuzzChanceTransition)
        let floorS = RainSurfaceMath.clamp01(cfg.fuzzChanceFloor)
        let expn = max(0.10, cfg.fuzzChanceExponent)
        let tailMin = RainSurfaceMath.clamp01(cfg.fuzzChanceMinStrength)

        // Low-height + slope boosts emphasise tails/shoulders.
        let baselineDist = max(1.0, geometry.baselineY - geometry.chartRect.minY)
        let lowPower = max(0.10, cfg.fuzzLowHeightPower)
        let lowBoostMax = max(0.0, cfg.fuzzLowHeightBoost)

        let bandPt = bandWidthPx / scale
        let slopeDenom = max(0.08, bandPt * 0.65)
        let slopeBoostMax = max(0.0, min(0.82, 0.22 + 0.58 * lowBoostMax))

        var strength: [Double] = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            let chance = RainSurfaceMath.clamp01(geometry.certaintyAt(i))

            // 0 when chance >= thr, 1 when far below thr (by trans).
            let u = RainSurfaceMath.clamp01((thr - chance) / trans)
            let mapped = floorS + (1.0 - floorS) * pow(u, expn)

            // Height fraction: 0 near baseline, 1 near top.
            let h = Double(geometry.heights[i])
            let hFrac = RainSurfaceMath.clamp01(h / Double(baselineDist))

            // Low-height boost rises near baseline.
            let low = pow(max(0.0, 1.0 - hFrac), lowPower)
            let lowBoost = lowBoostMax * low

            // Slope boost: stronger where the surface changes quickly (shoulders / taper).
            let yPrev = Double(geometry.surfaceYAt(max(0, i - 1)))
            let yNext = Double(geometry.surfaceYAt(min(n - 1, i + 1)))
            let slopePx = abs(yNext - yPrev) * Double(scale)
            let slopeNorm = RainSurfaceMath.clamp01(slopePx / Double(slopeDenom))
            let slopeBoost = slopeBoostMax * pow(slopeNorm, 1.10)

            var s = mapped + lowBoost + slopeBoost
            s = RainSurfaceMath.clamp01(s)

            if wetByHeight[i] {
                strength[i] = s
            } else {
                // Styling-only tail after rain ends (height remains baseline).
                let tp = tailPresence(distToWet[i])
                strength[i] = RainSurfaceMath.clamp01(max(s, tailMin) * tp)
            }
        }

        return strength
    }

    static func computePerSegmentStrength(perPoint: [Double]) -> [Double] {
        guard perPoint.count >= 2 else { return [] }
        var s: [Double] = []
        s.reserveCapacity(perPoint.count - 1)
        for i in 0..<(perPoint.count - 1) {
            s.append(0.5 * (perPoint[i] + perPoint[i + 1]))
        }
        return s
    }

    static func computeOutwardNormals(points: [CGPoint]) -> [CGVector] {
        let n = points.count
        guard n >= 2 else {
            return Array(repeating: CGVector(dx: 0, dy: -1), count: n)
        }

        func normalised(_ v: CGVector) -> CGVector {
            let len = sqrt(v.dx * v.dx + v.dy * v.dy)
            if len < 0.000_001 { return CGVector(dx: 0, dy: -1) }
            return CGVector(dx: v.dx / len, dy: v.dy / len)
        }

        var normals: [CGVector] = Array(repeating: CGVector(dx: 0, dy: -1), count: n)

        for i in 0..<n {
            let p0 = points[max(0, i - 1)]
            let p1 = points[min(n - 1, i + 1)]
            let tx = p1.x - p0.x
            let ty = p1.y - p0.y

            // Perpendicular to tangent.
            var nn = normalised(CGVector(dx: -ty, dy: tx))

            // Ensure "outward" is mostly upward (negative y).
            if nn.dy > 0 {
                nn = CGVector(dx: -nn.dx, dy: -nn.dy)
            }
            normals[i] = nn
        }

        return normals
    }

    static func boostedFuzzColor(_ cfg: RainForecastSurfaceConfiguration) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(cfg.fuzzColor)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            let rr = min(1.0, r * 1.00)
            let gg = min(1.0, g * 1.06)
            let bb = min(1.0, b * 1.18)
            return Color(red: Double(rr), green: Double(gg), blue: Double(bb), opacity: Double(a))
        }
        return cfg.fuzzColor
        #else
        return cfg.fuzzColor
        #endif
    }

    static func buildBinnedSegmentPaths(
        points: [CGPoint],
        perSegmentStrength: [Double],
        bins: Int
    ) -> (paths: [Path], avg: [Double]) {
        let n = points.count
        guard bins >= 2, n >= 2, perSegmentStrength.count == n - 1 else {
            return (
                Array(repeating: Path(), count: max(2, bins)),
                Array(repeating: 0.0, count: max(2, bins))
            )
        }

        var paths = Array(repeating: Path(), count: bins)
        var sum = Array(repeating: 0.0, count: bins)
        var cnt = Array(repeating: 0, count: bins)

        for i in 0..<(n - 1) {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 { continue }

            let b = min(bins - 1, max(0, Int(floor(s * Double(bins)))))
            var seg = Path()
            seg.move(to: points[i])
            seg.addLine(to: points[i + 1])
            paths[b].addPath(seg)

            sum[b] += s
            cnt[b] += 1
        }

        var avg = Array(repeating: 0.0, count: bins)
        for i in 0..<bins {
            if cnt[i] > 0 {
                avg[i] = sum[i] / Double(cnt[i])
            } else {
                avg[i] = 0.0
            }
        }

        return (paths, avg)
    }

    // MARK: - Core styling

    static func drawCoreTopLift(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePath: Path,
        chartRect: CGRect,
        baselineY: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double,
        fuzzAllowed: Bool
    ) {
        let mix = Double(max(0.0, min(1.0, cfg.coreTopMix)))
        let scale = max(1.0, displayScale)

        // Even when mix==0, a tiny weld stroke inside the core can help keep speckles attached.
        let wantsWeld = fuzzAllowed && (cfg.fuzzMaxOpacity > 0.000_1) && (maxStrength > 0.015)

        guard mix > 0.000_1 || wantsWeld else { return }

        let h = max(1.0, baselineY - chartRect.minY)

        let topAlpha = min(1.0, max(0.0, (0.18 + 0.10 * maxStrength) * mix))
        let midAlpha = min(1.0, max(0.0, (0.08 + 0.06 * maxStrength) * mix))
        let midLoc = min(0.85, 0.55 + 0.20 * (1.0 / max(1.0, Double(h / 120.0))))

        let grad = Gradient(stops: [
            .init(color: cfg.coreTopColor.opacity(topAlpha), location: 0.0),
            .init(color: cfg.coreTopColor.opacity(midAlpha), location: midLoc),
            .init(color: cfg.coreTopColor.opacity(0.0), location: 1.0)
        ])

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter

            if mix > 0.000_1 {
                var rect = Path()
                rect.addRect(CGRect(x: chartRect.minX, y: chartRect.minY, width: chartRect.width, height: h))
                layer.fill(
                    rect,
                    with: .linearGradient(
                        grad,
                        startPoint: CGPoint(x: chartRect.midX, y: chartRect.minY),
                        endPoint: CGPoint(x: chartRect.midX, y: baselineY)
                    )
                )
            }

            // Inside weld: cheap stroke clipped to the core, so only the inner half remains.
            if wantsWeld {
                let bandPt = bandWidthPx / scale
                let boosted = boostedFuzzColor(cfg)

                let w = max(0.65, min(10.0, bandPt * CGFloat(max(0.30, cfg.fuzzInsideHazeStrokeWidthFactor)) * 0.58))
                let a = min(0.18, max(0.028, cfg.fuzzMaxOpacity * 0.11 * (0.70 + 0.30 * maxStrength)))
                layer.stroke(
                    surfacePath,
                    with: .color(boosted.opacity(a)),
                    lineWidth: w
                )
            }
        }
    }

    static func drawCoreEdgeFade(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePath: Path,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let f = max(0.0, min(0.40, cfg.coreFadeFraction))
        guard f > 0.000_1 else { return }

        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let w = max(0.65, min(14.0, bandPt * f * 1.25))
        let blur = max(0.0, min(8.0, w * 0.90))
        let baseA = min(0.22, max(0.04, Double(f) * (0.85 + 0.35 * maxStrength)))

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }
            layer.stroke(
                surfacePath,
                with: .color(Color.white.opacity(baseA)),
                lineWidth: w
            )
        }
    }

    // MARK: - Baseline grain

    static func drawBaselineGrain(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        baselineY: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let scale = max(1.0, displayScale)
        let isTightBudget = isTightBudgetMode(cfg)

        let baseCount = isTightBudget ? 140 : 340
        let widthFactor = Double(min(1.0, max(0.15, (chartRect.width * scale) / 360.0)))
        let strengthFactor = 0.45 + 0.55 * maxStrength
        let count = max(0, min(isTightBudget ? 180 : 460, Int(Double(baseCount) * widthFactor * strengthFactor)))
        guard count > 0 else { return }

        let bandH = max(2.0, min(12.0, (6.0 + 6.0 * maxStrength) / scale))
        let r0 = (0.22 / scale)
        let r1 = (0.88 / scale)

        let baseA = min(0.20, max(0.02, (cfg.baselineLineOpacity * 0.10) + (cfg.fuzzMaxOpacity * 0.045)))
        let color = cfg.fuzzColor.opacity(baseA)

        var p = Path()
        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xBADA55_51A5E_0001)
        var prng = RainSurfacePRNG(seed: seed)

        for _ in 0..<count {
            let x = chartRect.minX + CGFloat(prng.nextFloat01()) * chartRect.width
            let y = baselineY - (CGFloat(prng.nextFloat01()) * bandH)
            let rr = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())
            p.addEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
        }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter
            layer.fill(p, with: .color(color))
        }
    }

    // MARK: - Fuzz haze

    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let baseA = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzHazeStrength))
        guard baseA > 0.000_1 else { return }

        let blur = max(0.0, min(8.0, bandPt * CGFloat(max(0.0, cfg.fuzzHazeBlurFractionOfBand))))
        let strokeW = max(0.60, min(22.0, bandPt * CGFloat(max(0.20, cfg.fuzzHazeStrokeWidthFactor))))
        let bins = 6
        let binned = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, bins: bins)
        let boosted = boostedFuzzColor(cfg)

        // Outside haze (clipped to outside of the core).
        context.drawLayer { layer in
            let bleed = max(0.0, bandPt * 3.0)
            var outside = Path()
            outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
            outside.addPath(corePath)

            layer.clip(to: outside, style: FillStyle(eoFill: true))
            layer.blendMode = .plusLighter

            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            for i in 0..<bins {
                let s = RainSurfaceMath.clamp01(binned.avg[i])
                if s <= 0.000_01 { continue }
                let a = baseA * (0.30 + 0.70 * s) * (0.55 + 0.45 * maxStrength)
                if a <= 0.000_01 { continue }
                layer.stroke(
                    binned.paths[i],
                    with: .color(boosted.opacity(a)),
                    lineWidth: strokeW
                )
            }
        }

        // Inside haze (very subtle; clipped to core).
        if cfg.fuzzInsideOpacityFactor > 0.000_1 {
            let insideOpacity = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
            let insideW = max(0.55, min(18.0, bandPt * CGFloat(max(0.20, cfg.fuzzInsideHazeStrokeWidthFactor))))
            let blurInside = max(0.0, min(6.0, blur * 0.62))

            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .plusLighter

                if blurInside > 0.001 {
                    layer.addFilter(.blur(radius: blurInside))
                }

                for i in 0..<bins {
                    let s = RainSurfaceMath.clamp01(binned.avg[i])
                    if s <= 0.000_01 { continue }
                    let a = baseA * insideOpacity * (0.22 + 0.78 * s) * 0.55
                    if a <= 0.000_01 { continue }
                    layer.stroke(
                        binned.paths[i],
                        with: .color(boosted.opacity(a)),
                        lineWidth: insideW
                    )
                }
            }
        }
    }

    // MARK: - Core erosion

    static func drawCoreErosion(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let baseA = max(0.0, min(1.0, cfg.fuzzErodeStrength * (0.55 + 0.45 * maxStrength)))
        guard baseA > 0.000_1 else { return }

        let blur = max(0.0, min(10.0, bandPt * 0.40))
        let strokeW = max(0.75, min(26.0, bandPt * 1.10))
        let bins = 6
        let binned = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, bins: bins)

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            let edgePow = max(0.10, cfg.fuzzErodeEdgePower)

            for i in 0..<bins {
                let s = RainSurfaceMath.clamp01(binned.avg[i])
                if s <= 0.000_01 { continue }
                let a = baseA * pow(s, edgePow)
                if a <= 0.000_01 { continue }
                layer.stroke(
                    binned.paths[i],
                    with: .color(Color.white.opacity(a)),
                    lineWidth: strokeW
                )
            }
        }
    }

    // MARK: - Fuzz speckles

    static func drawFuzzSpeckles(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGVector],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        guard surfacePoints.count >= 3, normals.count == surfacePoints.count else { return }
        if maxStrength <= 0.03 { return }

        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let outsideWidth = max(0.000_1, bandPt)
        let insideWidth = max(0.0, bandPt * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor)))

        let isTightBudget = isTightBudgetMode(cfg)
        let density = max(0.0, min(2.0, cfg.fuzzDensity))

        let boostedColor = boostedFuzzColor(cfg)

        // Base alpha for speckle material (opacity is also bucketed by bins).
        var baseSpeckAlpha = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzSpeckStrength))
        if isTightBudget {
            // Fewer speckles in tight mode; slightly stronger material keeps density.
            baseSpeckAlpha = min(1.0, baseSpeckAlpha * 1.10)
        }

        // Speckle radius (pixels -> points).
        let rPx0 = max(0.22, min(3.0, cfg.fuzzSpeckleRadiusPixels.lowerBound))
        let rPx1 = max(rPx0, min(6.0, cfg.fuzzSpeckleRadiusPixels.upperBound))
        var r0 = rPx0 / scale
        var r1 = rPx1 / scale
        if isTightBudget {
            // Fewer samples: slightly larger grains keep the band visually dense.
            r0 *= 1.35
            r1 *= 1.25
        }

        // Dynamic speckle count: scale by overall strength.
        let baseBudget0 = max(0, min(6500, cfg.fuzzSpeckleBudget))
        let strengthScale = max(0.0, min(1.0, 0.32 + 0.68 * maxStrength))
        let densityScale = max(0.0, min(1.0, 0.78 + 0.22 * density))
        var baseCount = Int((Double(baseBudget0) * strengthScale * densityScale).rounded(.toNearestOrAwayFromZero))

        // Hard clamps (critical for widget-extension safety).
        let tightBaseCap = 460
        let looseBaseCap = 6500
        baseCount = min(isTightBudget ? tightBaseCap : looseBaseCap, max(0, baseCount))
        if baseCount <= 0 { return }

        // Build segment CDF.
        // A small floor keeps density along slopes without concentrating only at peaks.
        let segCount = perSegmentStrength.count
        guard segCount >= 1 else { return }

        var segCDF: [Double] = Array(repeating: 0.0, count: segCount)
        var totalW: Double = 0.0
        let floorW: Double = isTightBudget ? 0.055 : 0.040

        for i in 0..<segCount {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            let w = floorW + s
            totalW += w
            segCDF[i] = totalW
        }
        if totalW <= 0.000_001 { return }

        @inline(__always)
        func pickSegmentIndex(u01: Double) -> Int {
            let target = u01 * totalW
            var lo = 0
            var hi = segCDF.count - 1
            while lo < hi {
                let mid = (lo + hi) >> 1
                if segCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
            }
            return max(0, min(segCount - 1, lo))
        }

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xC0FFEE_BAAD_F00D)
        var prng = RainSurfacePRNG(seed: seed)

        let xBleed = bandPt * 1.6
        let yBleedTop = bandPt * 2.9
        let yBleedBottom = bandPt * 1.2

        let bins = isTightBudget ? 4 : 6
        var outsideBins: [Path] = Array(repeating: Path(), count: bins)

        // In tight budgets: skip inside speckle layer entirely (saves a transparency layer).
        let useInsideSpeckles = (!isTightBudget) && (insideWidth > 0.000_01) && (cfg.fuzzInsideOpacityFactor > 0.000_1)
        var insideBins: [Path] = useInsideSpeckles ? Array(repeating: Path(), count: bins) : []

        let insideFraction = useInsideSpeckles ? max(0.0, min(1.0, cfg.fuzzInsideSpeckleFraction)) : 0.0

        let powOutside = max(0.10, cfg.fuzzDistancePowerOutside)
        let powInside = max(0.10, cfg.fuzzDistancePowerInside)
        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        // Macro grains (removed first under tight budgets).
        var macroCount = 0
        let macroCap = isTightBudget ? 0 : 180
        let macroChance = isTightBudget ? 0.0 : 0.055

        // Base speckle field (distributed through the band).
        for _ in 0..<baseCount {
            let segIdx = pickSegmentIndex(u01: prng.nextFloat01())
            let p0 = surfacePoints[segIdx]
            let p1 = surfacePoints[segIdx + 1]
            let sSeg = RainSurfaceMath.clamp01(perSegmentStrength[segIdx])

            let t = CGFloat(prng.nextFloat01())
            let px = p0.x + (p1.x - p0.x) * t
            let py = p0.y + (p1.y - p0.y) * t

            // Interpolated normal.
            let n0 = normals[segIdx]
            let n1 = normals[segIdx + 1]
            let nxRaw = n0.dx + (n1.dx - n0.dx) * t
            let nyRaw = n0.dy + (n1.dy - n0.dy) * t
            let nrmLen = sqrt(nxRaw * nxRaw + nyRaw * nyRaw)
            let nn = (nrmLen > 0.000_001) ? CGVector(dx: nxRaw / nrmLen, dy: nyRaw / nrmLen) : CGVector(dx: 0, dy: -1)
            let tan = CGVector(dx: -nn.dy, dy: nn.dx)

            let insidePick = (prng.nextFloat01() < insideFraction) && useInsideSpeckles
            let width = insidePick ? insideWidth : outsideWidth

            let u = prng.nextFloat01()
            let d01 = pow(u, insidePick ? powInside : (powOutside * 1.08))
            let dist = CGFloat(d01) * width
            let signedDist = insidePick ? -dist : dist

            let jitter = CGFloat(prng.nextSignedFloat()) * CGFloat(tangentJitter) * bandPt * 0.55
            let cx = px + nn.dx * signedDist + tan.dx * jitter
            let cy = py + nn.dy * signedDist + tan.dy * jitter

            if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
            if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

            var rr = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())
            var alphaMul: Double = 1.0

            if !insidePick, macroCount < macroCap, prng.nextFloat01() < macroChance {
                macroCount += 1
                rr *= 2.20
                alphaMul *= 0.55
            }

            let denom = Double(width)
            let distWeight: Double = {
                if denom <= 0.000_001 { return 1.0 }
                let a = min(1.0, max(0.0, 1.0 - Double(abs(signedDist)) / denom))
                let pp = insidePick ? powInside : powOutside
                return pow(a, max(0.10, pp))
            }()

            var alpha = baseSpeckAlpha * (0.22 + 0.78 * sSeg) * distWeight * alphaMul
            if insidePick {
                alpha *= max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
            }
            alpha *= (0.80 + 0.20 * density)
            alpha = max(0.0, min(1.0, alpha))

            let bin = min(bins - 1, max(0, Int(floor(alpha * Double(bins)))))
            let rect = CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)

            if insidePick, useInsideSpeckles {
                insideBins[bin].addEllipse(in: rect)
            } else {
                outsideBins[bin].addEllipse(in: rect)
            }
        }

        // Dense edge beads (hug the silhouette; cheap way to read ends/slopes).
        if surfacePoints.count >= 3, outsideWidth > 0.000_1 {
            var perPointS: [Double] = Array(repeating: 0.0, count: surfacePoints.count)
            if perSegmentStrength.count >= 1 {
                perPointS[0] = RainSurfaceMath.clamp01(perSegmentStrength[0])
                for i in 1..<(surfacePoints.count - 1) {
                    let a = RainSurfaceMath.clamp01(perSegmentStrength[i - 1])
                    let b = RainSurfaceMath.clamp01(perSegmentStrength[min(perSegmentStrength.count - 1, i)])
                    perPointS[i] = 0.5 * (a + b)
                }
                perPointS[surfacePoints.count - 1] = RainSurfaceMath.clamp01(perSegmentStrength[perSegmentStrength.count - 1])
            }

            // Point CDF with a small floor to keep beads along slopes.
            var ptCDF: [Double] = Array(repeating: 0.0, count: perPointS.count)
            var totalPt: Double = 0.0
            let ptFloor: Double = isTightBudget ? 0.060 : 0.045
            for i in 0..<perPointS.count {
                let w = ptFloor + perPointS[i]
                totalPt += w
                ptCDF[i] = totalPt
            }

            @inline(__always)
            func pickPointIndex(u01: Double) -> Int {
                if totalPt <= 0.000_001 { return 0 }
                let target = u01 * totalPt
                var lo = 0
                var hi = ptCDF.count - 1
                while lo < hi {
                    let mid = (lo + hi) >> 1
                    if ptCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
                }
                return max(0, min(ptCDF.count - 1, lo))
            }

            // Hard clamp bead count.
            let beadCap = isTightBudget ? 620 : 4200
            let beadBase = Int(
                (Double(surfacePoints.count) *
                 (isTightBudget ? 2.8 : 7.2) *
                 (0.40 + 0.60 * maxStrength) *
                 (0.80 + 0.20 * density))
                .rounded(.toNearestOrAwayFromZero)
            )
            let beadBudget = min(beadCap, max(0, beadBase))

            if beadBudget > 0 {
                for _ in 0..<beadBudget {
                    let i = pickPointIndex(u01: prng.nextFloat01())
                    let p = surfacePoints[i]
                    let nn = normals[i]
                    let tan = CGVector(dx: -nn.dy, dy: nn.dx)

                    let u = prng.nextFloat01()
                    let d = CGFloat(pow(u, max(0.10, powOutside))) * outsideWidth

                    let jitter = CGFloat(prng.nextSignedFloat()) * CGFloat(tangentJitter) * bandPt * 0.42
                    let cx = p.x + nn.dx * d + tan.dx * jitter
                    let cy = p.y + nn.dy * d + tan.dy * jitter

                    if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
                    if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

                    var rr = (r0 * 0.46) + (r1 * 0.62 - r0 * 0.46) * CGFloat(prng.nextFloat01())

                    let s = RainSurfaceMath.clamp01(perPointS[i])
                    var a = baseSpeckAlpha * (0.52 + 0.48 * s)

                    let edgeW: Double = {
                        if outsideWidth <= 0.000_001 { return 1.0 }
                        let t = max(0.0, min(1.0, 1.0 - Double(d / max(0.000_1, outsideWidth * 0.60))))
                        return pow(t, 1.70)
                    }()
                    a *= edgeW
                    a *= (0.84 + 0.16 * density)

                    if !isTightBudget, prng.nextFloat01() < 0.07 {
                        rr *= 1.75
                        a *= 0.55
                    }

                    a = max(0.0, min(1.0, a))
                    let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))

                    outsideBins[bin].addEllipse(in: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2))
                }
            }
        }

        // Draw: outside first (plusLighter, clipped), then inside (clipped).
        if outsideBins.contains(where: { !$0.isEmpty }) {
            context.drawLayer { layer in
                let bleed = max(0.0, bandPt * 3.0)
                var outside = Path()
                outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
                outside.addPath(corePath)

                layer.clip(to: outside, style: FillStyle(eoFill: true))
                layer.blendMode = .plusLighter

                // Tight budgets: no blur filters.
                let microBlur: CGFloat = isTightBudget ? 0.0 : min(1.25, bandPt * 0.050)
                if microBlur > 0.001 {
                    layer.addFilter(.blur(radius: microBlur))
                }

                for b in 0..<bins {
                    if outsideBins[b].isEmpty { continue }
                    let t = Double(b + 1) / Double(bins)
                    let a = max(0.0, min(1.0, baseSpeckAlpha * t))
                    layer.fill(outsideBins[b], with: .color(boostedColor.opacity(a)))
                }
            }
        }

        if useInsideSpeckles, !insideBins.isEmpty, insideBins.contains(where: { !$0.isEmpty }) {
            let insideOpacity = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
            if insideOpacity > 0.000_01 {
                context.drawLayer { layer in
                    layer.clip(to: corePath)
                    layer.blendMode = .plusLighter

                    let microBlur: CGFloat = 0.0
                    if microBlur > 0.001 {
                        layer.addFilter(.blur(radius: microBlur))
                    }

                    for b in 0..<bins {
                        if insideBins[b].isEmpty { continue }
                        let t = Double(b + 1) / Double(bins)
                        let a = max(0.0, min(1.0, baseSpeckAlpha * insideOpacity * t))
                        layer.fill(insideBins[b], with: .color(boostedColor.opacity(a)))
                    }
                }
            }
        }
    }

    // MARK: - Rim

    static func drawRim(
        in context: inout GraphicsContext,
        surfacePath: Path,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let innerW = max(0.5, cfg.rimInnerWidthPixels / scale)
        let outerW = max(innerW, cfg.rimOuterWidthPixels / scale)

        let isTightBudget = isTightBudgetMode(cfg)

        let oldBlend = context.blendMode
        context.blendMode = .plusLighter

        // Tight budgets: no blur layers (avoid placeholder regressions).
        if cfg.rimOuterOpacity > 0.000_1 {
            if isTightBudget {
                context.stroke(
                    surfacePath,
                    with: .color(cfg.rimColor.opacity(cfg.rimOuterOpacity)),
                    lineWidth: outerW
                )
            } else {
                context.drawLayer { layer in
                    layer.blendMode = .plusLighter
                    let blur = max(0.0, min(3.0, outerW * 0.18))
                    if blur > 0.001 {
                        layer.addFilter(.blur(radius: blur))
                    }
                    layer.stroke(
                        surfacePath,
                        with: .color(cfg.rimColor.opacity(cfg.rimOuterOpacity)),
                        lineWidth: outerW
                    )
                }
            }
        }

        if cfg.rimInnerOpacity > 0.000_1 {
            context.stroke(
                surfacePath,
                with: .color(cfg.rimColor.opacity(cfg.rimInnerOpacity)),
                lineWidth: innerW
            )
            // Secondary tight stroke increases perceived crispness without a halo.
            context.stroke(
                surfacePath,
                with: .color(cfg.rimColor.opacity(cfg.rimInnerOpacity * 0.55)),
                lineWidth: max(0.5, innerW * 0.55)
            )
        }

        context.blendMode = oldBlend
    }

    // MARK: - Optional gloss

    static func drawGloss(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePath: Path,
        chartRect: CGRect,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let depth = max(1.0, cfg.glossDepthPixels / scale)
        let blur = max(0.0, cfg.glossBlurPixels / scale)

        let a0 = max(0.0, min(1.0, cfg.glossMaxOpacity))
        if a0 <= 0.000_1 { return }

        let offset = (chartRect.height * cfg.glossVerticalOffsetFraction).isFinite ? (chartRect.height * cfg.glossVerticalOffsetFraction) : 0.0

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter
            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            let shifted = surfacePath.offsetBy(dx: 0, dy: offset)
            layer.stroke(
                shifted,
                with: .color(cfg.coreTopColor.opacity(a0)),
                lineWidth: depth
            )
        }
    }

    // MARK: - Optional glints

    static func drawGlints(
        in context: inout GraphicsContext,
        surfacePoints: [CGPoint],
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard !surfacePoints.isEmpty else { return }

        let scale = max(1.0, displayScale)
        let sigma = max(0.5, cfg.glintSigmaPixels / scale)
        let offsetY = cfg.glintVerticalOffsetPixels / scale

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xA11CE5A10DDC0FFE)
        var prng = RainSurfacePRNG(seed: seed)

        let n = max(1, min(24, cfg.glintCount))
        let a0 = max(0.0, min(1.0, cfg.glintMaxOpacity))
        if a0 <= 0.000_1 { return }

        // Keep glints cheap: a few soft dots.
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            if sigma > 0.001 {
                layer.addFilter(.blur(radius: max(0.0, sigma * 0.60)))
            }

            for _ in 0..<n {
                let idx = Int(prng.nextFloat01() * Double(surfacePoints.count))
                let p = surfacePoints[max(0, min(surfacePoints.count - 1, idx))]
                let rr = max(0.8, (sigma * (0.45 + 0.55 * prng.nextFloat01())))

                var dot = Path()
                dot.addEllipse(in: CGRect(
                    x: p.x - rr,
                    y: (p.y + offsetY) - rr,
                    width: rr * 2,
                    height: rr * 2
                ))
                layer.fill(dot, with: .color(cfg.rimColor.opacity(a0 * (0.55 + 0.45 * prng.nextFloat01()))))
            }
        }
    }
}
