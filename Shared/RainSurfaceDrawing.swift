//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import SwiftUI

enum RainSurfaceDrawing {

    static func drawSurface(
        in context: inout GraphicsContext,
        geometry: RainSurfaceGeometry,
        cfg: RainForecastSurfaceConfiguration
    ) {
        let chartRect = geometry.chartRect
        let baselineY = geometry.baselineY
        let displayScale = max(1.0, geometry.displayScale)

        if cfg.fillBackgroundBlack {
            context.fill(Path(chartRect), with: .color(.black))
        }

        // Build core shape.
        let corePath = buildCorePath(
            chartRect: chartRect,
            baselineY: baselineY,
            xPositions: geometry.xPositions,
            heights: geometry.heights,
            topSmoothing: cfg.topSmoothing
        )

        let coreFillColor = cfg.coreBodyColor
        let coreFillOpacity = min(1.0, max(0.0, cfg.coreOpacity))

        // Fill core body.
        context.fill(corePath, with: .color(coreFillColor.opacity(coreFillOpacity)))

        // Surface sampling for fuzz/rim.
        let surfacePoints = buildSurfacePoints(
            chartRect: chartRect,
            baselineY: baselineY,
            xPositions: geometry.xPositions,
            heights: geometry.heights,
            topSmoothing: cfg.topSmoothing
        )
        if surfacePoints.count < 3 { return }

        let normals = computeNormals(for: surfacePoints)

        // Band width (points + pixels) for fuzz sizing.
        let bandWidthPt = max(1.0, chartRect.height * CGFloat(cfg.fuzzWidthFraction))
        let bandWidthPx = bandWidthPt * displayScale
        let scale = Double(displayScale)
        let bandPt = CGFloat(Double(bandWidthPx) / scale)

        let isTightBudget = isTightBudgetMode(cfg: cfg)

        // Strength mapping per sample point (0..1).
        let perPointStrength = computeFuzzStrengthPerPoint(
            geometry: geometry,
            cfg: cfg,
            bandWidthPt: bandPt
        )
        if perPointStrength.allSatisfy({ $0 <= 0.000_01 }) {
            // Still allow baseline grain and rim if configured, but skip heavy work.
        }

        let perSeg = computePerSegmentStrength(perPoint: perPointStrength)
        let maxStrength = perPointStrength.max() ?? 0.0

        // Inset the surface (let fuzz own the boundary when strong).
        let insetSurfacePoints = insetTopPoints(
            surfacePoints: surfacePoints,
            normals: normals,
            perPointStrength: perPointStrength,
            cfg: cfg,
            bandWidthPt: bandPt
        )
        let insetCorePath = buildCorePath(
            chartRect: chartRect,
            baselineY: baselineY,
            xPositions: insetSurfacePoints.map { $0.x },
            heights: insetSurfacePoints.map { baselineY - $0.y },
            topSmoothing: 0
        )

        // Top lift (keeps mid-tones readable).
        if cfg.coreTopLiftEnabled {
            drawCoreTopLift(
                in: &context,
                corePath: insetCorePath,
                chartRect: chartRect,
                baselineY: baselineY,
                cfg: cfg
            )
        }

        // Core edge fade (reduce the clean vector rim).
        if !isTightBudget, cfg.coreFadeFraction > 0.000_1 {
            drawCoreEdgeFade(
                in: &context,
                corePath: insetCorePath,
                surfacePoints: insetSurfacePoints,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt
            )
        }

        let fuzzAllowed = cfg.fuzzSpeckStrength > 0.000_1 && cfg.fuzzMaxOpacity > 0.000_1

        // Haze (optional).
        if fuzzAllowed, !isTightBudget, cfg.fuzzHazeStrength > 0.000_1 {
            drawFuzzHaze(
                in: &context,
                chartRect: chartRect,
                corePath: insetCorePath,
                surfacePoints: insetSurfacePoints,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )
        }

        // Erode core (optional; blurred destinationOut).
        if fuzzAllowed, !isTightBudget, cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.000_1 {
            drawCoreErosion(
                in: &context,
                corePath: insetCorePath,
                surfacePoints: insetSurfacePoints,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt,
                maxStrength: maxStrength
            )
        }

        // Dissolve the smooth core into particulate near the rim (cheap; keeps fuzz from floating).
        if fuzzAllowed {
            drawCoreDissolvePerforation(
                in: &context,
                corePath: insetCorePath,
                surfacePoints: insetSurfacePoints,
                normals: normals,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt,
                displayScale: scale,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )
        }

        // Speckles (primary particulate fuzz).
        if fuzzAllowed {
            drawFuzzSpeckles(
                in: &context,
                chartRect: chartRect,
                baselineY: geometry.baselineY,
                corePath: insetCorePath,
                surfacePoints: insetSurfacePoints,
                normals: normals,
                perPointStrength: perPointStrength,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt,
                displayScale: displayScale,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )
        }

        // Baseline grain (subtle) to avoid a “flat slab”.
        if cfg.baselineGrainEnabled {
            drawBaselineGrain(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                corePath: insetCorePath,
                cfg: cfg,
                displayScale: displayScale
            )
        }

        // Rim (thin luminous edge; beads + micro strokes, no halo).
        if cfg.rimEnabled {
            drawRim(
                in: &context,
                chartRect: chartRect,
                corePath: insetCorePath,
                surfacePoints: insetSurfacePoints,
                normals: normals,
                perPointStrength: perPointStrength,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )
        }
    }

    static func isTightBudgetMode(cfg: RainForecastSurfaceConfiguration) -> Bool {
        // Treat widget extension as tight: fewer samples and reduced extras.
        // Note: This is only a coarse knob; budgets are clamped per-layer.
        if cfg.maxDenseSamples <= 280 { return true }
        if cfg.fuzzSpeckleBudget <= 900 { return true }
        return false
    }

    // MARK: - Baseline grain

    static func drawBaselineGrain(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        corePath: Path,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)

        let grains = max(0, min(900, cfg.baselineGrainBudget))
        if grains <= 0 { return }

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xBADA55))

        let r0 = max(0.18, min(2.4, cfg.baselineGrainRadiusPixels.lowerBound)) / scale
        let r1 = max(r0, min(3.0, cfg.baselineGrainRadiusPixels.upperBound)) / scale

        let x0 = chartRect.minX
        let x1 = chartRect.maxX
        let y0 = baselineY - max(0.0, cfg.baselineGrainYOffsetPixels.lowerBound) / scale
        let y1 = baselineY + max(0.0, cfg.baselineGrainYOffsetPixels.upperBound) / scale

        let bins = 3
        var paths: [Path] = Array(repeating: Path(), count: bins)

        for _ in 0..<grains {
            let x = CGFloat(prng.nextFloat01()) * (x1 - x0) + x0
            let y = CGFloat(prng.nextFloat01()) * (y1 - y0) + y0
            let rrT = CGFloat(pow(prng.nextFloat01(), 2.6))
            let r = r0 + (r1 - r0) * rrT
            let a = 0.35 + 0.65 * prng.nextFloat01()
            let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))
            paths[bin].addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
        }

        if paths.allSatisfy({ $0.isEmpty }) { return }

        let alpha = max(0.0, min(1.0, cfg.baselineGrainOpacity))
        if alpha <= 0.000_1 { return }

        context.drawLayer { layer in
            let bleed: CGFloat = 8.0
            var outside = Path()
            outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
            outside.addPath(corePath)
            layer.clip(to: outside, style: FillStyle(eoFill: true))

            layer.blendMode = .plusLighter

            for b in 0..<bins {
                if paths[b].isEmpty { continue }
                let a = (Double(b + 1) / Double(bins)) * alpha
                layer.fill(paths[b], with: .color(cfg.baselineGrainColor.opacity(a)))
            }
        }
    }
}
