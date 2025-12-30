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
        guard chartRect.width > 1, chartRect.height > 1 else { return }

        let displayScale = max(1.0, geometry.displayScale)
        let onePx = 1.0 / displayScale

        let bandWidthPt = computeBandWidthPt(chartRect: chartRect, displayScale: displayScale, cfg: cfg)
        let surfacePoints = buildSurfacePoints(geometry: geometry)
        guard surfacePoints.count >= 2 else { return }

        let normals = computeNormals(surfacePoints: surfacePoints)
        let perPointStrength = computeFuzzStrengthPerPoint(
            geometry: geometry,
            surfacePoints: surfacePoints,
            normals: normals,
            bandWidthPt: bandWidthPt,
            displayScale: displayScale,
            cfg: cfg
        )
        let perSegmentStrength = computePerSegmentStrength(perPointStrength: perPointStrength)
        let maxStrength = perPointStrength.max() ?? 0

        let corePath = buildCorePath(geometry: geometry, smoothingWindowRadius: 1, smoothingPasses: 1)

        // Draw core fill in its own layer so destinationOut operations only affect the core.
        context.drawLayer { layer in
            let shading = coreShading(chartRect: chartRect, baselineY: geometry.baselineY, cfg: cfg)
            layer.fill(corePath, with: shading)

            // Always soften the edge slightly so fuzz can “own” the silhouette when needed.
            drawCoreEdgeFade(
                in: &layer,
                surfacePoints: surfacePoints,
                perSegmentStrength: perSegmentStrength,
                bandWidthPt: bandWidthPt,
                displayScale: displayScale,
                cfg: cfg
            )

            // Dissolution near rim (only when fuzz is enabled + allowed).
            if cfg.fuzzEnabled, cfg.canEnableFuzz {
                let tight = isTightBudget(chartRect: chartRect, displayScale: displayScale, cfg: cfg)

                if cfg.fuzzErodeEnabled {
                    drawCoreErosion(
                        in: &layer,
                        surfacePoints: surfacePoints,
                        normals: normals,
                        perSegmentStrength: perSegmentStrength,
                        bandWidthPt: bandWidthPt,
                        displayScale: displayScale,
                        cfg: cfg,
                        isTightBudget: tight
                    )
                }

                drawCoreDissolvePerforation(
                    in: &layer,
                    corePath: corePath,
                    surfacePoints: surfacePoints,
                    normals: normals,
                    perPointStrength: perPointStrength,
                    bandWidthPt: bandWidthPt,
                    displayScale: displayScale,
                    cfg: cfg,
                    isTightBudget: tight
                )
            }
        }

        // Fuzz (particulates) drawn above the core.
        if cfg.fuzzEnabled, cfg.canEnableFuzz {
            let tight = isTightBudget(chartRect: chartRect, displayScale: displayScale, cfg: cfg)

            drawFuzzSpeckles(
                in: &context,
                chartRect: chartRect,
                baselineY: geometry.baselineY,
                surfacePoints: surfacePoints,
                normals: normals,
                perPointStrength: perPointStrength,
                bandWidthPt: bandWidthPt,
                displayScale: displayScale,
                cfg: cfg,
                isTightBudget: tight
            )

            if cfg.fuzzHazeStrength > 0.0001, maxStrength > 0.02, !tight {
                drawFuzzHaze(
                    in: &context,
                    surfacePoints: surfacePoints,
                    normals: normals,
                    perSegmentStrength: perSegmentStrength,
                    bandWidthPt: bandWidthPt,
                    displayScale: displayScale,
                    cfg: cfg
                )
            }
        }

        // Rim + optional glints (very subtle; most “edge energy” comes from speckles).
        if cfg.rimEnabled, maxStrength > 0.02 {
            drawRim(
                in: &context,
                surfacePoints: surfacePoints,
                maxStrength: maxStrength,
                displayScale: displayScale,
                cfg: cfg
            )
        }

        if cfg.glintEnabled, maxStrength > 0.12 {
            drawGlints(
                in: &context,
                chartRect: chartRect,
                baselineY: geometry.baselineY,
                surfacePoints: surfacePoints,
                normals: normals,
                perPointStrength: perPointStrength,
                bandWidthPt: bandWidthPt,
                displayScale: displayScale,
                cfg: cfg
            )
        }

        // Baseline (drawn last so it’s crisp).
        drawBaseline(
            in: &context,
            chartRect: chartRect,
            baselineY: geometry.baselineY,
            displayScale: displayScale,
            cfg: cfg
        )

        _ = onePx
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        displayScale: CGFloat,
        cfg: RainForecastSurfaceConfiguration
    ) {
        guard cfg.baselineEnabled else { return }
        guard chartRect.width > 1 else { return }

        let y = alignToPixelCenter(baselineY + CGFloat(cfg.baselineOffsetPixels) / displayScale, displayScale: displayScale)
        let lineWidth = max(0.5 / displayScale, CGFloat(cfg.baselineWidthPixels) / displayScale)

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: y))
        p.addLine(to: CGPoint(x: chartRect.maxX, y: y))

        let fade = max(0.0, min(0.49, cfg.baselineEndFadeFraction))
        let c0 = cfg.baselineColor.opacity(0.0)
        let c1 = cfg.baselineColor.opacity(cfg.baselineLineOpacity)

        let gradient = Gradient(stops: [
            .init(color: c0, location: 0.0),
            .init(color: c1, location: CGFloat(fade)),
            .init(color: c1, location: CGFloat(1.0 - fade)),
            .init(color: c0, location: 1.0)
        ])

        let shading = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: chartRect.minX, y: y),
            endPoint: CGPoint(x: chartRect.maxX, y: y)
        )

        context.stroke(p, with: shading, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    // MARK: - Internal helpers

    static func computeBandWidthPt(chartRect: CGRect, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let basePt = max(0.0, chartRect.height * cfg.fuzzWidthFraction)
        let basePx = Double(basePt * displayScale)
        let lo = cfg.fuzzWidthPixelsClamp.lowerBound
        let hi = cfg.fuzzWidthPixelsClamp.upperBound
        let clampedPx = clamp(basePx, lo, hi)
        let pt = CGFloat(clampedPx / Double(displayScale))
        return max(1.0 / displayScale, pt)
    }

    static func coreShading(chartRect: CGRect, baselineY: CGFloat, cfg: RainForecastSurfaceConfiguration) -> GraphicsContext.Shading {
        let mix = RainSurfaceMath.clamp01(cfg.coreTopMix)
        let topStart = CGFloat(max(0.0, min(1.0, 1.0 - mix)))

        let gradient = Gradient(stops: [
            .init(color: cfg.coreBodyColor, location: 0.0),
            .init(color: cfg.coreBodyColor, location: topStart),
            .init(color: cfg.coreTopColor, location: 1.0)
        ])

        return GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: chartRect.midX, y: baselineY),
            endPoint: CGPoint(x: chartRect.midX, y: chartRect.minY)
        )
    }

    static func isTightBudget(chartRect: CGRect, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) -> Bool {
        let wPx = Double(chartRect.width * displayScale)
        let hPx = Double(chartRect.height * displayScale)
        let px = wPx * hPx

        if px > 150_000 { return true }
        if cfg.fuzzSpeckleBudget > 7000 { return true }
        return false
    }

    static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(x, lo), hi)
    }

    static func alignToPixelCenter(_ v: CGFloat, displayScale: CGFloat) -> CGFloat {
        let s = max(1.0, displayScale)
        return (floor(v * s) + 0.5) / s
    }
}
