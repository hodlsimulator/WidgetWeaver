//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Drawing entry point for the nowcast surface chart (Canvas/GraphicsContext).
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum RainSurfaceDrawing {

    static func drawSurface(
        in context: inout GraphicsContext,
        geometry: RainSurfaceGeometry,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        let bandWidthPt = computeBandWidthPt(
            chartRect: geometry.chartRect,
            displayScale: geometry.displayScale,
            cfg: cfg
        )

        let surfacePoints = buildSurfacePoints(geometry: geometry)
        guard surfacePoints.count >= 2 else { return }

        let normals = computeNormals(surfacePoints: surfacePoints)

        let perPointStrength = computeFuzzStrengthPerPoint(
            geometry: geometry,
            surfacePoints: surfacePoints,
            normals: normals,
            bandWidthPt: bandWidthPt,
            displayScale: geometry.displayScale,
            cfg: cfg
        )

        let perSegmentStrength = computePerSegmentStrength(perPointStrength: perPointStrength)
        let maxStrength = perPointStrength.max() ?? 0.0

        // Core path (kept smooth-ish; dissolution owns the edge later).
        let corePath = buildCorePath(
            geometry: geometry,
            smoothingWindowRadius: 1,
            smoothingPasses: 1
        )

        let gradientTopY = geometry.chartRect.minY
        let gradientBottomY = geometry.baselineY

        // Core fill is drawn in its own layer, then destinationOut operations erode it *within the same layer*.
        context.drawLayer { layer in
            // Baseline fade (clipped safely using a nested layer so the clip doesn't leak).
            if cfg.coreFadeFraction > 0.0001 {
                let ds = max(1.0, geometry.displayScale)
                let fadeH = geometry.chartRect.height * CGFloat(clamp01(cfg.coreFadeFraction))
                let fadeTop = max(geometry.chartRect.minY, geometry.baselineY - fadeH)

                let fadeRect = CGRect(
                    x: geometry.chartRect.minX,
                    y: fadeTop,
                    width: geometry.chartRect.width,
                    height: geometry.baselineY - fadeTop
                )

                layer.drawLayer { inner in
                    inner.clip(to: corePath)
                    inner.fill(
                        Path(fadeRect),
                        with: .linearGradient(
                            Gradient(colors: [
                                cfg.coreBodyColor,
                                cfg.coreBodyColor.opacity(0.0)
                            ]),
                            startPoint: CGPoint(x: fadeRect.midX, y: fadeRect.minY),
                            endPoint: CGPoint(x: fadeRect.midX, y: fadeRect.maxY)
                        )
                    )
                }
            }

            // Core shading (subtle vertical blend).
            let topMix = CGFloat(clamp01(cfg.coreTopMix))
            let body = cfg.coreBodyColor
            let top = cfg.coreTopColor
            let mid = Color.blend(a: top, b: body, t: Double(1.0 - topMix))

            layer.fill(
                corePath,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: top, location: 0.0),
                        .init(color: mid, location: 0.30),
                        .init(color: body, location: 1.0)
                    ]),
                    startPoint: CGPoint(x: geometry.chartRect.midX, y: gradientTopY),
                    endPoint: CGPoint(x: geometry.chartRect.midX, y: gradientBottomY)
                )
            )

            // Edge dissolution and perforation (destinationOut) must happen on the SAME layer as the core fill.
            if cfg.fuzzEnabled, cfg.canEnableFuzz, maxStrength > 0.001 {
                drawCoreEdgeFade(
                    in: &layer,
                    surfacePoints: surfacePoints,
                    perSegmentStrength: perSegmentStrength,
                    bandWidthPt: bandWidthPt,
                    displayScale: geometry.displayScale,
                    cfg: cfg
                )

                if cfg.fuzzErodeEnabled {
                    drawCoreErosion(
                        in: &layer,
                        corePath: corePath,
                        surfacePoints: surfacePoints,
                        normals: normals,
                        perPointStrength: perPointStrength,
                        bandWidthPt: bandWidthPt,
                        displayScale: geometry.displayScale,
                        cfg: cfg
                    )
                }

                drawCoreDissolvePerforation(
                    in: &layer,
                    corePath: corePath,
                    surfacePoints: surfacePoints,
                    normals: normals,
                    perPointStrength: perPointStrength,
                    bandWidthPt: bandWidthPt,
                    displayScale: geometry.displayScale,
                    cfg: cfg
                )
            }
        }

        // Fuzz (outside dust + beads + inside weld) drawn on the main context (above the core layer).
        if cfg.fuzzEnabled, cfg.canEnableFuzz, maxStrength > 0.001 {
            drawFuzzSpeckles(
                in: &context,
                corePath: corePath,
                surfacePoints: surfacePoints,
                normals: normals,
                perPointStrength: perPointStrength,
                bandWidthPt: bandWidthPt,
                displayScale: geometry.displayScale,
                cfg: cfg
            )

            // Haze stays effectively disabled (implementation is a no-op) to prevent halo/fog.
            if cfg.fuzzHazeStrength > 0.0001,
               !isTightBudget(chartRect: geometry.chartRect, displayScale: geometry.displayScale, cfg: cfg) {
                drawFuzzHaze(
                    in: &context,
                    corePath: corePath,
                    surfacePoints: surfacePoints,
                    normals: normals,
                    perPointStrength: perPointStrength,
                    bandWidthPt: bandWidthPt,
                    displayScale: geometry.displayScale,
                    cfg: cfg
                )
            }
        }

        // Rim/glints are suppressed whenever fuzz meaningfully owns the edge.
        drawRim(
            in: &context,
            surfacePoints: surfacePoints,
            perSegmentStrength: perSegmentStrength,
            bandWidthPt: bandWidthPt,
            displayScale: geometry.displayScale,
            cfg: cfg,
            maxStrength: maxStrength
        )

        drawGlints(
            in: &context,
            geometry: geometry,
            surfacePoints: surfacePoints,
            perPointStrength: perPointStrength,
            bandWidthPt: bandWidthPt,
            displayScale: geometry.displayScale,
            cfg: cfg,
            maxStrength: maxStrength
        )
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard cfg.baselineEnabled else { return }
        guard cfg.baselineLineOpacity > 0.0001 else { return }

        let ds = max(1.0, displayScale)
        let onePx = 1.0 / ds

        let lineY = baselineY + CGFloat(cfg.baselineOffsetPixels) / ds
        let width = max(1.0, CGFloat(cfg.baselineWidthPixels) / ds)

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: alignToPixelCenter(lineY, onePx: onePx)))
        p.addLine(to: CGPoint(x: chartRect.maxX, y: alignToPixelCenter(lineY, onePx: onePx)))

        let fade = CGFloat(clamp01(cfg.baselineEndFadeFraction))
        if fade > 0.0001 {
            let w = max(1.0, chartRect.width)
            let leftFadeW = chartRect.width * fade
            let rightFadeW = chartRect.width * fade

            let g = Gradient(stops: [
                .init(color: cfg.baselineColor.opacity(0.0), location: 0.0),
                .init(color: cfg.baselineColor.opacity(cfg.baselineLineOpacity),
                      location: Double(clamp01(Double(leftFadeW / w)))),
                .init(color: cfg.baselineColor.opacity(cfg.baselineLineOpacity),
                      location: Double(clamp01(Double(1.0 - rightFadeW / w)))),
                .init(color: cfg.baselineColor.opacity(0.0), location: 1.0)
            ])

            context.stroke(
                p,
                with: .linearGradient(
                    g,
                    startPoint: CGPoint(x: chartRect.minX, y: lineY),
                    endPoint: CGPoint(x: chartRect.maxX, y: lineY)
                ),
                lineWidth: width
            )
        } else {
            context.stroke(
                p,
                with: .color(cfg.baselineColor.opacity(cfg.baselineLineOpacity)),
                lineWidth: width
            )
        }
    }

    // MARK: - Layout helpers

    static func computeBandWidthPt(chartRect: CGRect, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let wPx = Double(max(1.0, chartRect.width * displayScale))
        let fraction = max(0.001, cfg.fuzzWidthFraction)

        let unclampedPx = wPx * fraction
        let clampedPx = min(max(unclampedPx, cfg.fuzzWidthPixelsClamp.lowerBound), cfg.fuzzWidthPixelsClamp.upperBound)

        return CGFloat(clampedPx) / max(1.0, displayScale)
    }

    static func isTightBudget(chartRect: CGRect, displayScale: CGFloat, cfg: RainForecastSurfaceConfiguration) -> Bool {
        let wPx = Double(max(1.0, chartRect.width * displayScale))
        let hPx = Double(max(1.0, chartRect.height * displayScale))
        let px = wPx * hPx

        if px > 220_000.0 { return true }
        if cfg.fuzzSpeckleBudget > 8_500 { return true }
        return false
    }

    static func alignToPixelCenter(_ v: CGFloat, onePx: CGFloat) -> CGFloat {
        guard onePx > 0 else { return v }
        return (v / onePx).rounded() * onePx + onePx * 0.5
    }

    static func clamp01(_ x: Double) -> Double {
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }
}

private extension Color {

    static func blend(a: Color, b: Color, t: Double) -> Color {
        let tt = max(0.0, min(1.0, t))

        #if canImport(UIKit)
        let ua = UIColor(a)
        let ub = UIColor(b)

        var ra: CGFloat = 0.0, ga: CGFloat = 0.0, ba: CGFloat = 0.0, aa: CGFloat = 0.0
        var rb: CGFloat = 0.0, gb: CGFloat = 0.0, bb: CGFloat = 0.0, ab: CGFloat = 0.0

        _ = ua.getRed(&ra, green: &ga, blue: &ba, alpha: &aa)
        _ = ub.getRed(&rb, green: &gb, blue: &bb, alpha: &ab)

        let tCg = CGFloat(tt)
        let r = ra + (rb - ra) * tCg
        let g = ga + (gb - ga) * tCg
        let bC = ba + (bb - ba) * tCg
        let aC = aa + (ab - aa) * tCg

        return Color(red: Double(r), green: Double(g), blue: Double(bC), opacity: Double(aC))
        #else
        return tt < 0.5 ? a : b
        #endif
    }
}
