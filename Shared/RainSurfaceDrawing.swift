//
// RainSurfaceDrawing.swift
// WidgetWeaver
//
// Created by . . on 12/23/25.
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

        // If the surface is effectively absent, do nothing (prevents “dry charts” paying fuzz/rim costs).
        let scale = max(1.0, displayScale)
        let maxHeightPt = geometry.heights.max() ?? 0
        let maxHeightPx = maxHeightPt * scale
        if maxHeightPx < 0.18 {
            return
        }

        // ---- Per-point styling strength (0..1), derived from probability + height semantics ----------
        let bandWidthPx = fuzzBandWidthPixels(chartRect: chartRect, cfg: cfg, displayScale: displayScale)
        let perPointStrength = computeFuzzStrengthPerPoint(
            geometry: geometry,
            cfg: cfg,
            bandWidthPx: bandWidthPx
        )
        let maxStrength = perPointStrength.max() ?? 0.0

        // ---- Surface points + outward normals -----------------------------------------------------
        let surfacePoints: [CGPoint] = (0..<geometry.sampleCount).map { geometry.surfacePointAt($0) }
        let normals = computeOutwardNormals(points: surfacePoints)

        // ---- Slightly inset the solid core so fuzz visually owns the boundary ---------------------
        // Only do this when we actually intend to draw fuzz.
        let fuzzAllowed = cfg.canEnableFuzz && cfg.fuzzEnabled && (cfg.fuzzMaxOpacity > 0.0001) && (maxStrength > 0.02)

        let insetPt = (max(0.0, cfg.fuzzErodeRimInsetPixels) / scale)
        var insetTopPoints: [CGPoint] = surfacePoints
        if fuzzAllowed, insetPt > 0.0001, insetTopPoints.count == geometry.sampleCount {
            for i in 0..<insetTopPoints.count {
                let s = CGFloat(RainSurfaceMath.clamp01(perPointStrength[i]))
                let d = insetPt * (0.45 + 0.55 * s)
                var p = surfacePoints[i]
                let nrm = normals[i]
                p.x += nrm.dx * d
                p.y += nrm.dy * d
                if p.y > geometry.baselineY { p.y = geometry.baselineY }
                insetTopPoints[i] = p
            }
        }

        let corePath = geometry.filledPath(usingInsetTopPoints: insetTopPoints)
        if corePath.isEmpty { return }

        let surfacePath = geometry.surfacePolylinePath()

        // ---- Core fill ----------------------------------------------------------------------------
        context.fill(corePath, with: .color(cfg.coreBodyColor))

        // Subtle internal top glow (clipped to core). Keeps mid-tones visible without lifting black.
        let topMix = max(0.0, min(1.0, Double(cfg.coreTopMix)))
        if topMix > 0.001 {
            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .plusLighter

                let y0 = chartRect.minY
                let y1 = min(chartRect.maxY, chartRect.minY + chartRect.height * 0.78)

                var rect = Path()
                rect.addRect(CGRect(x: chartRect.minX, y: y0, width: chartRect.width, height: y1 - y0))

                let a0 = max(0.0, min(1.0, topMix * 0.90))
                let a1 = max(0.0, min(1.0, topMix * 0.40))

                let grad = Gradient(stops: [
                    .init(color: cfg.coreTopColor.opacity(a0), location: 0.00),
                    .init(color: cfg.coreTopColor.opacity(a1), location: 0.38),
                    .init(color: cfg.coreTopColor.opacity(0.0), location: 1.00),
                ])

                layer.fill(
                    rect,
                    with: .linearGradient(
                        grad,
                        startPoint: CGPoint(x: chartRect.midX, y: y0),
                        endPoint: CGPoint(x: chartRect.midX, y: y1)
                    )
                )
            }
        }

        // Optional top alpha fade (destinationOut). Keep small for a crisp edge.
        if cfg.coreFadeFraction > 0.0001 {
            let fadeH = max(1.0, chartRect.height * cfg.coreFadeFraction)
            let y0 = chartRect.minY
            let y1 = min(chartRect.maxY, chartRect.minY + fadeH)

            var fadeRect = Path()
            fadeRect.addRect(CGRect(x: chartRect.minX, y: y0, width: chartRect.width, height: y1 - y0))

            let stops = Gradient(stops: [
                .init(color: Color.white.opacity(1.0), location: 0.0),
                .init(color: Color.white.opacity(0.0), location: 1.0),
            ])

            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .destinationOut
                layer.fill(
                    fadeRect,
                    with: .linearGradient(
                        stops,
                        startPoint: CGPoint(x: chartRect.midX, y: y0),
                        endPoint: CGPoint(x: chartRect.midX, y: y1)
                    )
                )
            }
        }

        // ---- Fuzz: erosion + tight haze + dense speckles ------------------------------------------
        if fuzzAllowed {
            let perSeg = segmentStrengths(from: perPointStrength)

            // Erosion is the most expensive piece; keep it conditional.
            if cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.0001, maxStrength > 0.05 {
                drawCoreErosion(
                    in: &context,
                    corePath: corePath,
                    surfacePoints: surfacePoints,
                    perSegmentStrength: perSeg,
                    cfg: cfg,
                    bandWidthPx: bandWidthPx,
                    displayScale: displayScale
                )
            }

            // Tight haze only (no big aura). Outside + faint inside weld.
            if cfg.fuzzHazeStrength > 0.0001, maxStrength > 0.03 {
                drawFuzzHaze(
                    in: &context,
                    chartRect: chartRect,
                    corePath: corePath,
                    surfacePoints: surfacePoints,
                    perSegmentStrength: perSeg,
                    cfg: cfg,
                    bandWidthPx: bandWidthPx,
                    displayScale: displayScale,
                    inside: false
                )

                if cfg.fuzzInsideOpacityFactor > 0.001, maxStrength > 0.06 {
                    drawFuzzHaze(
                        in: &context,
                        chartRect: chartRect,
                        corePath: corePath,
                        surfacePoints: surfacePoints,
                        perSegmentStrength: perSeg,
                        cfg: cfg,
                        bandWidthPx: bandWidthPx,
                        displayScale: displayScale,
                        inside: true
                    )
                }
            }

            // Granular speckles (primary “glow” look).
            if cfg.fuzzSpeckStrength > 0.0001, cfg.fuzzSpeckleBudget > 0, maxStrength > 0.04 {
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
        }

        // ---- Gloss (optional) ---------------------------------------------------------------------
        if cfg.glossEnabled, cfg.glossMaxOpacity > 0.0001 {
            drawGloss(
                in: &context,
                corePath: corePath,
                surfacePath: surfacePath,
                chartRect: chartRect,
                cfg: cfg,
                displayScale: displayScale
            )
        }

        // ---- Glints (optional) --------------------------------------------------------------------
        if cfg.glintEnabled, cfg.glintMaxOpacity > 0.0001, cfg.glintCount > 0 {
            drawGlints(
                in: &context,
                surfacePoints: surfacePoints,
                cfg: cfg,
                displayScale: displayScale
            )
        }

        // ---- Rim (crisp edge) ---------------------------------------------------------------------
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
            .init(color: color.opacity(0.0), location: 1.0),
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

    static func fuzzBandWidthPixels(chartRect: CGRect, cfg: RainForecastSurfaceConfiguration, displayScale: CGFloat) -> CGFloat {
        let pxFromFraction = chartRect.height * cfg.fuzzWidthFraction * max(1.0, displayScale)
        let clamped = min(max(pxFromFraction, cfg.fuzzWidthPixelsClamp.lowerBound), cfg.fuzzWidthPixelsClamp.upperBound)
        return max(6.0, clamped)
    }

    // NOTE: geometry.certaintyAt(i) is treated as a *probability/chance* (0..1).
    // High chance => stronger styling. Low chance => weak styling (no fuzz on dry charts).
    // A short “tail presence” derived from HEIGHT keeps endings readable even if chance drops quickly.
    static func computeFuzzStrengthPerPoint(
        geometry: RainSurfaceGeometry,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat
    ) -> [Double] {
        let n = geometry.sampleCount
        guard n > 0 else { return [] }

        let scale = max(1.0, geometry.displayScale)
        let dxPx = geometry.dx * scale

        let epsilonHeightPt: CGFloat = max(0.06, 0.35 / scale)
        let maxHeightPt = geometry.heights.max() ?? 0
        let maxHeightPx = maxHeightPt * scale
        if maxHeightPx < 0.20 {
            return Array(repeating: 0.0, count: n)
        }

        // Height semantics define where the surface exists.
        var wetByHeight: [Bool] = Array(repeating: false, count: n)
        var anyWet = false
        for i in 0..<n {
            let w = geometry.heights[i] > epsilonHeightPt
            wetByHeight[i] = w
            anyWet = anyWet || w
        }
        if !anyWet {
            return Array(repeating: 0.0, count: n)
        }

        // Distance to nearest wet-by-height sample.
        var distToWet = Array(repeating: Int.max / 4, count: n)
        var last = -1
        for i in 0..<n {
            if wetByHeight[i] { last = i }
            if last >= 0 { distToWet[i] = i - last }
        }
        last = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if wetByHeight[i] { last = i }
            if last >= 0 { distToWet[i] = min(distToWet[i], last - i) }
        }

        let tailDistancePx: CGFloat = max(bandWidthPx * 2.3, 28.0)
        let safeDxPx = max(0.000_001, dxPx)

        func tailPresence(_ dSamples: Int) -> Double {
            let dPx = Double(CGFloat(dSamples)) * Double(safeDxPx)
            let t = RainSurfaceMath.smoothstep(0.0, Double(tailDistancePx), dPx)
            return max(0.0, 1.0 - t)
        }

        // Chance -> styling mapping.
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
        let slopeBoostMax = max(0.0, min(0.62, 0.18 + 0.46 * lowBoostMax))

        let density = max(0.0, min(2.0, cfg.fuzzDensity))

        var strength: [Double] = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            let presence = tailPresence(distToWet[i])
            if presence <= 0.0001 {
                strength[i] = 0.0
                continue
            }

            let chance = RainSurfaceMath.clamp01(geometry.certaintyAt(i))

            // Map chance upward from threshold (dry => 0).
            let x = RainSurfaceMath.clamp01((chance - thr) / trans)
            let mapped = floorS + (1.0 - floorS) * pow(x, expn)

            // Tail readability even if chance is low immediately after wet ends.
            let tailOverride = tailMin * presence

            var s = max(mapped, tailOverride) * presence

            // Low height boost (near baseline, ends).
            let h = geometry.heights[i]
            let h01 = Double(max(0.0, min(1.0, h / baselineDist)))
            let low = pow(1.0 - h01, lowPower)
            s *= (1.0 + lowBoostMax * low)

            // Shoulder boost.
            let hPrev = geometry.heights[max(0, i - 1)]
            let hNext = geometry.heights[min(n - 1, i + 1)]
            let slope = Double(abs(hNext - hPrev)) / Double(slopeDenom)
            let slopeT = min(1.0, max(0.0, slope))
            s *= (1.0 + slopeBoostMax * pow(slopeT, 0.85))

            // Density scaling (keeps budgets stable; mostly affects overall strength).
            s *= (0.72 + 0.28 * density)

            strength[i] = RainSurfaceMath.clamp01(s)
        }

        // Smooth to avoid seam artefacts.
        strength = RainSurfaceMath.smooth(strength, windowRadius: 2, passes: 1).map { RainSurfaceMath.clamp01($0) }
        return strength
    }

    static func segmentStrengths(from perPoint: [Double]) -> [Double] {
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

        func norm(_ v: CGVector) -> CGVector {
            let len = sqrt(v.dx * v.dx + v.dy * v.dy)
            if len < 0.000_001 { return CGVector(dx: 0, dy: -1) }
            return CGVector(dx: v.dx / len, dy: v.dy / len)
        }

        var normals: [CGVector] = Array(repeating: CGVector(dx: 0, dy: -1), count: n)
        for i in 0..<n {
            let p0 = points[max(0, i - 1)]
            let p1 = points[min(n - 1, i + 1)]
            let t = CGVector(dx: p1.x - p0.x, dy: p1.y - p0.y)

            // Right-side normal for a left->right polyline: (dy, -dx)
            var nn = norm(CGVector(dx: t.dy, dy: -t.dx))

            // Ensure it generally points outward (upward) for the top curve.
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
            let gg = min(1.0, g * 1.05)
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
        guard bins >= 2, points.count >= 2, perSegmentStrength.count == points.count - 1 else {
            return (Array(repeating: Path(), count: max(2, bins)), Array(repeating: 0.0, count: max(2, bins)))
        }

        var paths = Array(repeating: Path(), count: bins)
        var sum = Array(repeating: 0.0, count: bins)
        var cnt = Array(repeating: 0, count: bins)

        var currentBin: Int? = nil
        var currentPath = Path()

        for i in 0..<perSegmentStrength.count {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            let bin = min(bins - 1, max(0, Int(floor(s * Double(bins)))))

            if currentBin == nil || currentBin != bin {
                if let cb = currentBin {
                    paths[cb].addPath(currentPath)
                }
                currentBin = bin
                currentPath = Path()
                currentPath.move(to: points[i])
            }
            currentPath.addLine(to: points[i + 1])

            sum[bin] += s
            cnt[bin] += 1
        }

        if let cb = currentBin {
            paths[cb].addPath(currentPath)
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

    static func drawCoreErosion(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale
        let insideWidth = bandPt * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor))

        let w = max(0.65, min(14.0, insideWidth * 0.55))
        let blur = max(0.0, min(10.0, insideWidth * 0.30))

        let baseAlpha = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzErodeStrength))
        if baseAlpha < 0.0001 { return }

        let bins = 6
        let binned = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, bins: bins)

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            for i in 0..<bins {
                let s = max(0.0, min(1.0, binned.avg[i]))
                if s <= 0.0001 { continue }

                let shaped = pow(s, max(0.10, cfg.fuzzErodeEdgePower))
                let a = max(0.0, min(1.0, baseAlpha * (0.18 + 0.82 * shaped)))
                if a <= 0.0001 { continue }

                layer.stroke(
                    binned.paths[i],
                    with: .color(Color.white.opacity(a)),
                    lineWidth: w
                )
            }
        }
    }

    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        inside: Bool
    ) {
        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let baseAlpha0 = cfg.fuzzMaxOpacity * cfg.fuzzHazeStrength
        if baseAlpha0 < 0.0001 { return }

        // Tight haze only (no big halo).
        let blur = max(
            0.0,
            min(
                12.0,
                bandPt * CGFloat(max(0.02, min(0.35, cfg.fuzzHazeBlurFractionOfBand))) * (inside ? 0.55 : 0.70)
            )
        )
        let strokeW = max(
            0.6,
            min(
                18.0,
                bandPt * CGFloat(inside ? cfg.fuzzInsideHazeStrokeWidthFactor : cfg.fuzzHazeStrokeWidthFactor) * (inside ? 0.85 : 0.90)
            )
        )

        let bins = 6
        let binned = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, bins: bins)
        let hazeColor = boostedFuzzColor(cfg)

        context.drawLayer { layer in
            if inside {
                layer.clip(to: corePath)
            } else {
                let bleed = max(0.0, bandPt * 3.0)
                var outside = Path()
                outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
                outside.addPath(corePath)
                layer.clip(to: outside, style: FillStyle(eoFill: true))
            }

            layer.blendMode = .plusLighter
            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            for i in 0..<bins {
                let s = max(0.0, min(1.0, binned.avg[i]))
                if s <= 0.0001 { continue }

                let shaped = pow(s, 1.05)
                var a = baseAlpha0 * (0.10 + 0.90 * shaped)
                if inside {
                    a *= max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor)) * 0.65
                } else {
                    a *= 0.55
                }
                a = max(0.0, min(1.0, a))
                if a <= 0.0001 { continue }

                layer.stroke(
                    binned.paths[i],
                    with: .color(hazeColor.opacity(a)),
                    lineWidth: strokeW
                )
            }
        }
    }

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
        guard surfacePoints.count >= 2, normals.count == surfacePoints.count else { return }
        if maxStrength <= 0.04 { return }

        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale
        let outsideWidth = max(0.000_1, bandPt)
        let insideWidth = max(0.0, bandPt * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor)))

        let isTightBudget = (cfg.fuzzSpeckleBudget <= 900) || (cfg.maxDenseSamples <= 280)

        let density = max(0.0, min(2.0, cfg.fuzzDensity))
        let boostedColor = boostedFuzzColor(cfg)
        let baseSpeckAlpha = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzSpeckStrength))

        let rPx0 = max(0.25, min(3.0, cfg.fuzzSpeckleRadiusPixels.lowerBound))
        let rPx1 = max(rPx0, min(5.0, cfg.fuzzSpeckleRadiusPixels.upperBound))
        let r0 = rPx0 / scale
        let r1 = rPx1 / scale

        // Dynamic speckle count: scale by overall strength so “mostly dry” renders are cheap.
        let baseBudget0 = max(0, min(6500, cfg.fuzzSpeckleBudget))
        let strengthScale = max(0.0, min(1.0, 0.20 + 0.80 * maxStrength))
        let densityScale = max(0.0, min(1.0, 0.75 + 0.25 * density))
        var baseCount = Int((Double(baseBudget0) * strengthScale * densityScale).rounded(.toNearestOrAwayFromZero))

        if isTightBudget {
            baseCount = min(900, baseCount)
        } else {
            baseCount = min(6500, baseCount)
        }
        if baseCount <= 0 { return }

        // Build segment CDF weighted by strength (no floor; dry segments contribute zero).
        let segCount = perSegmentStrength.count
        var segCDF: [Double] = Array(repeating: 0.0, count: segCount)
        var totalW: Double = 0.0
        for i in 0..<segCount {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_001 {
                segCDF[i] = totalW
                continue
            }
            let w = pow(s, 0.90)
            totalW += w
            segCDF[i] = totalW
        }
        if totalW <= 0.000_001 { return }

        func pickSegmentIndex(_ u01: Double) -> Int {
            let target = u01 * totalW
            var lo = 0
            var hi = segCDF.count - 1
            while lo < hi {
                let mid = (lo + hi) >> 1
                if segCDF[mid] >= target {
                    hi = mid
                } else {
                    lo = mid + 1
                }
            }
            return max(0, min(segCount - 1, lo))
        }

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xC0FFEE_BAAD_F00D)
        var prng = RainSurfacePRNG(seed: seed)

        let xBleed = bandPt * 1.6
        let yBleedTop = bandPt * 2.9
        let yBleedBottom = bandPt * 1.2

        let bins = 6
        var outsideBins: [Path] = Array(repeating: Path(), count: bins)
        var insideBins: [Path] = Array(repeating: Path(), count: bins)

        let insideFraction = max(0.0, min(1.0, cfg.fuzzInsideSpeckleFraction))
        let powOutside = max(0.10, cfg.fuzzDistancePowerOutside)
        let powInside = max(0.10, cfg.fuzzDistancePowerInside)
        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        // Base speckle field (distributed through the band).
        for _ in 0..<baseCount {
            let si = pickSegmentIndex(prng.nextFloat01())
            let sSeg = RainSurfaceMath.clamp01(perSegmentStrength[si])
            if sSeg <= 0.000_001 { continue }

            // Strongly suppress low-strength segments (prevents dry charts from paying cost).
            let accept = pow(sSeg, 0.65)
            if prng.nextFloat01() > accept { continue }

            let p0 = surfacePoints[si]
            let p1 = surfacePoints[si + 1]
            let t = CGFloat(prng.nextFloat01())
            let px = p0.x + (p1.x - p0.x) * t
            let py = p0.y + (p1.y - p0.y) * t

            let n0 = normals[si]
            let n1 = normals[si + 1]
            let nxRaw = n0.dx + (n1.dx - n0.dx) * t
            let nyRaw = n0.dy + (n1.dy - n0.dy) * t
            let nrmLen = sqrt(nxRaw * nxRaw + nyRaw * nyRaw)
            let nn: CGVector = (nrmLen > 0.000_001)
                ? CGVector(dx: nxRaw / nrmLen, dy: nyRaw / nrmLen)
                : CGVector(dx: 0, dy: -1)
            let tan = CGVector(dx: -nn.dy, dy: nn.dx)

            let insidePick = (prng.nextFloat01() < insideFraction) && (insideWidth > 0.000_01)
            let u = prng.nextFloat01()
            let d01 = pow(u, insidePick ? powInside : (powOutside * 1.08))
            let dist = CGFloat(d01) * (insidePick ? insideWidth : outsideWidth)
            let signedDist = insidePick ? -dist : dist

            let jitter = CGFloat(prng.nextSignedFloat()) * CGFloat(tangentJitter) * bandPt * 0.55
            let cx = px + nn.dx * signedDist + tan.dx * jitter
            let cy = py + nn.dy * signedDist + tan.dy * jitter

            if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
            if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

            var rr = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())
            var alphaMul: Double = 1.0

            // Occasional macro grains add volume to the outside fuzz (only when not in tight budget).
            if !isTightBudget, !insidePick, prng.nextFloat01() < 0.055 {
                rr *= 2.10
                alphaMul *= 0.55
            }

            let denom = Double(insidePick ? insideWidth : outsideWidth)
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
            alpha *= (0.78 + 0.22 * density)
            alpha = max(0.0, min(1.0, alpha))

            let bin = min(bins - 1, max(0, Int(floor(alpha * Double(bins)))))
            let rect = CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)

            if insidePick {
                insideBins[bin].addEllipse(in: rect)
            } else {
                outsideBins[bin].addEllipse(in: rect)
            }
        }

        // Dense edge beads (hug the silhouette; cheap way to read ends/slopes).
        if surfacePoints.count >= 3, outsideWidth > 0.000_1 {
            var perPointS: [Double] = Array(repeating: 0.0, count: surfacePoints.count)
            if perSegmentStrength.count >= 1 {
                perPointS[0] = max(0.0, min(1.0, perSegmentStrength[0]))
                for i in 1..<(surfacePoints.count - 1) {
                    let a = max(0.0, min(1.0, perSegmentStrength[i - 1]))
                    let b = max(0.0, min(1.0, perSegmentStrength[min(perSegmentStrength.count - 1, i)]))
                    perPointS[i] = 0.5 * (a + b)
                }
                perPointS[surfacePoints.count - 1] = max(0.0, min(1.0, perSegmentStrength[perSegmentStrength.count - 1]))
            }

            // Point CDF.
            var ptCDF: [Double] = Array(repeating: 0.0, count: perPointS.count)
            var totalPt: Double = 0.0
            for i in 0..<perPointS.count {
                let s = max(0.0, min(1.0, perPointS[i]))
                if s <= 0.000_001 {
                    ptCDF[i] = totalPt
                    continue
                }
                let w = pow(s, 0.85)
                totalPt += w
                ptCDF[i] = totalPt
            }

            func pickPointIndex(_ u01: Double) -> Int {
                if totalPt <= 0.000_001 { return 0 }
                let target = u01 * totalPt
                var lo = 0
                var hi = ptCDF.count - 1
                while lo < hi {
                    let mid = (lo + hi) >> 1
                    if ptCDF[mid] >= target {
                        hi = mid
                    } else {
                        lo = mid + 1
                    }
                }
                return max(0, min(ptCDF.count - 1, lo))
            }

            let beadCap = isTightBudget ? 520 : 2400
            let beadBase = Int(
                (Double(surfacePoints.count) * (isTightBudget ? 2.6 : 5.6) * (0.35 + 0.65 * maxStrength) * (0.75 + 0.25 * density))
                    .rounded(.toNearestOrAwayFromZero)
            )
            let beadBudget = min(beadCap, max(0, beadBase))

            if beadBudget > 0 {
                for _ in 0..<beadBudget {
                    let i = pickPointIndex(prng.nextFloat01())
                    let s = max(0.0, min(1.0, perPointS[i]))
                    if s <= 0.000_001 { continue }

                    let accept = pow(s, 0.60)
                    if prng.nextFloat01() > accept { continue }

                    let p = surfacePoints[i]
                    let nn = normals[i]
                    let tan = CGVector(dx: -nn.dy, dy: nn.dx)

                    let u = prng.nextFloat01()
                    let d = outsideWidth * 0.52 * CGFloat(pow(u, 2.7))

                    let jitter = CGFloat(prng.nextSignedFloat()) * bandPt * CGFloat(tangentJitter) * 0.18
                    let cx = p.x + nn.dx * d + tan.dx * jitter
                    let cy = p.y + nn.dy * d + tan.dy * jitter

                    if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
                    if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

                    var rr = (r0 * 0.55) + (r1 * 0.70 - r0 * 0.55) * CGFloat(prng.nextFloat01())
                    var a = baseSpeckAlpha * (0.44 + 0.56 * s)

                    let edgeW: Double = {
                        if outsideWidth <= 0.000_001 { return 1.0 }
                        let t = max(0.0, min(1.0, 1.0 - Double(d / max(0.000_1, outsideWidth * 0.52))))
                        return pow(t, 1.55)
                    }()
                    a *= edgeW
                    a *= (0.82 + 0.18 * density)

                    if !isTightBudget, prng.nextFloat01() < 0.07 {
                        rr *= 1.85
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

                if !isTightBudget {
                    let microBlur = max(0.0, bandPt * 0.050)
                    if microBlur > 0.001 {
                        layer.addFilter(.blur(radius: microBlur))
                    }
                }

                for b in 0..<bins {
                    if outsideBins[b].isEmpty { continue }
                    let t = Double(b + 1) / Double(bins)
                    let a = max(0.0, min(1.0, t))
                    layer.fill(outsideBins[b], with: .color(boostedColor.opacity(a)))
                }
            }
        }

        if insideWidth > 0.000_01, insideBins.contains(where: { !$0.isEmpty }) {
            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .plusLighter

                if !isTightBudget {
                    let microBlur = max(0.0, bandPt * 0.045)
                    if microBlur > 0.001 {
                        layer.addFilter(.blur(radius: microBlur))
                    }
                }

                let insideOpacity = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
                for b in 0..<bins {
                    if insideBins[b].isEmpty { continue }
                    let t = Double(b + 1) / Double(bins)
                    let a = max(0.0, min(1.0, t)) * insideOpacity
                    layer.fill(insideBins[b], with: .color(boostedColor.opacity(a)))
                }
            }
        }
    }

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
        let offset = chartRect.height * cfg.glossVerticalOffsetFraction

        let a = max(0.0, min(1.0, cfg.glossMaxOpacity))
        if a <= 0.0001 { return }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter
            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            var shifted = surfacePath
            shifted = shifted.offsetBy(dx: 0, dy: offset)

            layer.stroke(
                shifted,
                with: .color(cfg.coreTopColor.opacity(a)),
                lineWidth: depth
            )
        }
    }

    static func drawRim(
        in context: inout GraphicsContext,
        surfacePath: Path,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let outerW = max(0.5, cfg.rimOuterWidthPixels / scale)
        let innerW = max(0.5, cfg.rimInnerWidthPixels / scale)

        if cfg.rimOuterOpacity > 0.0001 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                let blur = max(0.0, outerW * 0.32)
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

        if cfg.rimInnerOpacity > 0.0001 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.stroke(
                    surfacePath,
                    with: .color(cfg.rimColor.opacity(cfg.rimInnerOpacity)),
                    lineWidth: innerW
                )
            }
        }
    }

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

        let n = max(1, cfg.glintCount)
        let a0 = max(0.0, min(1.0, cfg.glintMaxOpacity))

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: max(0.0, sigma * 0.60)))

            for _ in 0..<n {
                let idx = max(0, min(surfacePoints.count - 1, Int(floor(prng.nextFloat01() * Double(surfacePoints.count)))))
                let p = surfacePoints[idx]

                let jitterX = CGFloat(prng.nextSignedFloat()) * sigma * 0.65
                let jitterY = CGFloat(prng.nextSignedFloat()) * sigma * 0.35

                let r = sigma * (0.80 + 0.55 * CGFloat(prng.nextFloat01()))
                let rect = CGRect(
                    x: (p.x + jitterX) - r,
                    y: (p.y + offsetY + jitterY) - r,
                    width: r * 2,
                    height: r * 2
                )

                var path = Path()
                path.addEllipse(in: rect)

                let a = a0 * (0.35 + 0.65 * prng.nextFloat01())
                layer.fill(path, with: .color(cfg.rimColor.opacity(a)))
            }
        }
    }
}
