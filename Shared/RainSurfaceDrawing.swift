//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Drawing entry point for the nowcast surface chart (Canvas/GraphicsContext).
//

import SwiftUI

enum RainSurfaceDrawing {

    static func drawSurface(
        in context: inout GraphicsContext,
        geometry: RainSurfaceGeometry,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        let chartRect = geometry.chartRect

        if chartRect.width <= 0 || chartRect.height <= 0 {
            return
        }

        let displayScale = context.environment.displayScale
        let onePx = 1.0 / max(1.0, displayScale)

        // Build surface points and normals.
        let surfacePoints = buildSurfacePoints(geometry: geometry)
        if surfacePoints.count <= 2 { return }
        let normals = computeNormals(surfacePoints: surfacePoints)

        // Core fill path.
        let corePath = geometry.filledPath

        // Certainty/chance is styling-only (never height).
        let fuzzAllowed = cfg.fuzzEnabled && cfg.canEnableFuzz
        let perPointStrength = computeFuzzStrengthPerPoint(
            geometry: geometry,
            surfacePoints: surfacePoints,
            normals: normals,
            cfg: cfg,
            bandWidthPt: bandWidthPt(chartRect: chartRect),
            displayScale: displayScale
        )
        let perSegmentStrength = computeFuzzStrengthPerSegment(perPointStrength: perPointStrength)

        let maxStrength = perPointStrength.max() ?? 0.0

        let isTightBudget = cfg.tightBudgetPreferred

        // Core fill (solid body) – can be heavily dissolved by fuzz passes in low-certainty areas.
        if cfg.coreFillEnabled {
            drawCoreFill(
                in: &context,
                corePath: corePath,
                surfacePoints: surfacePoints,
                normals: normals,
                cfg: cfg,
                maxStrength: maxStrength,
                displayScale: displayScale
            )
        }

        // Fuzz-related passes (dissolve + particulate edge).
        if fuzzAllowed, maxStrength > 0.01 {
            let bw = bandWidthPt(chartRect: chartRect)

            // Keep haze effectively off; this renderer is “black background, no halo”.
            drawFuzzHaze(
                in: &context,
                corePath: corePath,
                chartRect: chartRect,
                cfg: cfg,
                bandWidthPt: bw,
                displayScale: displayScale,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )

            // Edge fade (strong destinationOut along rim, clipped to core).
            drawCoreEdgeFade(
                in: &context,
                corePath: corePath,
                surfacePoints: surfacePoints,
                perSegmentStrength: perSegmentStrength,
                cfg: cfg,
                bandWidthPt: bw,
                displayScale: displayScale,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )

            // Jittered rim erosion (destinationOut; clipped to core).
            drawCoreErosion(
                in: &context,
                corePath: corePath,
                surfacePoints: surfacePoints,
                normals: normals,
                perSegmentStrength: perSegmentStrength,
                cfg: cfg,
                bandWidthPt: bw,
                displayScale: displayScale,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )

            // Perforation (tiny holes inside rim band; clipped to core).
            drawCoreDissolvePerforation(
                in: &context,
                corePath: corePath,
                surfacePoints: surfacePoints,
                normals: normals,
                perPointStrength: perPointStrength,
                cfg: cfg,
                bandWidthPt: bw,
                displayScale: displayScale,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )

            // Speckles (outside dust, edge beads, inside weld).
            drawFuzzSpeckles(
                in: &context,
                corePath: corePath,
                chartRect: chartRect,
                surfacePoints: surfacePoints,
                normals: normals,
                perPointStrength: perPointStrength,
                perSegmentStrength: perSegmentStrength,
                cfg: cfg,
                bandWidthPt: bw,
                displayScale: displayScale,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )
        }

        // Rim / glints (suppressed when fuzz is enabled/available).
        drawRim(
            in: &context,
            surfacePoints: surfacePoints,
            maxStrength: maxStrength,
            displayScale: displayScale,
            cfg: cfg
        )

        drawGlints(
            in: &context,
            chartRect: chartRect,
            baselineY: geometry.baselineY,
            surfacePoints: surfacePoints,
            normals: normals,
            perPointStrength: perPointStrength,
            bandWidthPt: bandWidthPt(chartRect: chartRect),
            displayScale: displayScale,
            cfg: cfg
        )

        // Baseline (drawn last so it’s crisp).
        var baselineCfg = cfg
        if fuzzAllowed, maxStrength > 0.02 {
            let t = min(1.0, max(0.0, Double(maxStrength)))
            // As the particulate edge ramps up, the baseline should recede so it does not read like a chart axis.
            baselineCfg.baselineLineOpacity *= (0.22 + 0.58 * (1.0 - t))
            baselineCfg.baselineWidthPixels = min(baselineCfg.baselineWidthPixels, 0.90)
        }
        drawBaseline(
            in: &context,
            chartRect: chartRect,
            baselineY: geometry.baselineY,
            configuration: baselineCfg,
            displayScale: displayScale
        )
    }

    // MARK: - Baseline

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard cfg.baselineEnabled else { return }
        let opacity = max(0.0, min(1.0, cfg.baselineLineOpacity))
        if opacity <= 0.0001 { return }

        let onePx = 1.0 / max(1.0, displayScale)
        let width = max(onePx, CGFloat(cfg.baselineWidthPixels) / displayScale)
        let fadeFrac = max(0.0, min(0.45, cfg.baselineEndFadeFraction))
        let fadeW = chartRect.width * CGFloat(fadeFrac)

        // Baseline path with optional end fades (still no “halo”; keep it crisp).
        var p = Path()
        let y = alignToPixelCenter(y: baselineY, displayScale: displayScale)

        let x0 = chartRect.minX
        let x1 = chartRect.maxX

        if fadeW <= onePx * 1.5 {
            p.move(to: CGPoint(x: x0, y: y))
            p.addLine(to: CGPoint(x: x1, y: y))
            context.stroke(p, with: .color(cfg.baselineColor.opacity(opacity)), style: StrokeStyle(lineWidth: width))
            return
        }

        // Draw as 3 segments with fading ends.
        let midX0 = x0 + fadeW
        let midX1 = x1 - fadeW

        if midX1 > midX0 {
            var pMid = Path()
            pMid.move(to: CGPoint(x: midX0, y: y))
            pMid.addLine(to: CGPoint(x: midX1, y: y))
            context.stroke(pMid, with: .color(cfg.baselineColor.opacity(opacity)), style: StrokeStyle(lineWidth: width))
        }

        // Left fade
        var pLeft = Path()
        pLeft.move(to: CGPoint(x: x0, y: y))
        pLeft.addLine(to: CGPoint(x: midX0, y: y))
        context.stroke(pLeft, with: .color(cfg.baselineColor.opacity(opacity * 0.55)), style: StrokeStyle(lineWidth: width))

        // Right fade
        var pRight = Path()
        pRight.move(to: CGPoint(x: midX1, y: y))
        pRight.addLine(to: CGPoint(x: x1, y: y))
        context.stroke(pRight, with: .color(cfg.baselineColor.opacity(opacity * 0.55)), style: StrokeStyle(lineWidth: width))
    }

    // MARK: - Band width

    static func bandWidthPt(chartRect: CGRect) -> CGFloat {
        // Narrow band for rim effects, scaled with chart height.
        // Keep within small bounds to stay widget-safe.
        let h = chartRect.height
        return max(2.0, min(14.0, h * 0.12))
    }

    // MARK: - Pixel alignment

    static func alignToPixelCenter(y: CGFloat, displayScale: CGFloat) -> CGFloat {
        let onePx = 1.0 / max(1.0, displayScale)
        return floor(y / onePx) * onePx + onePx * 0.5
    }
}
