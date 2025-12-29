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

struct RainSurfaceDrawing {
    static func drawSurface(
        in context: inout GraphicsContext,
        geometry: RainSurfaceGeometry,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        let chartRect = geometry.chartRect
        guard chartRect.width > 0.5, chartRect.height > 0.5, geometry.sampleCount >= 2 else { return }

        let scale = max(1.0, geometry.displayScale)

        let bandWidthPx = fuzzBandWidthPixels(chartRect: chartRect, cfg: cfg, displayScale: scale)
        let bandPt = bandWidthPx / scale

        let perPointStrength = computeFuzzStrengthPerPoint(
            geometry: geometry,
            cfg: cfg,
            bandWidthPx: bandWidthPx
        )
        let maxStrength = perPointStrength.max() ?? 0.0

        let surfacePoints: [CGPoint] = (0..<geometry.sampleCount).map { geometry.surfacePointAt($0) }
        let normals = computeOutwardNormals(points: surfacePoints)
        let perSeg = computePerSegmentStrength(perPoint: perPointStrength)

        let isTightBudget = isTightBudgetMode(cfg)

        let fuzzAllowed: Bool = cfg.fuzzEnabled
            && cfg.canEnableFuzz
            && (cfg.fuzzMaxOpacity > 0.000_1)
            && (cfg.fuzzSpeckStrength > 0.000_1)
            && (maxStrength > 0.01)
            && (bandWidthPx > 0.5)

        // Slight inset so fuzz owns the boundary (cheap, no raster).
        let insetPt = CGFloat(max(0.0, cfg.fuzzErodeRimInsetPixels)) / scale
        var insetTopPoints = surfacePoints

        if fuzzAllowed,
           insetPt > 0.000_1,
           normals.count == insetTopPoints.count,
           perPointStrength.count == insetTopPoints.count
        {
            let edgePow = max(0.10, cfg.fuzzErodeEdgePower)
            let insetMul = isTightBudget ? 0.70 : 1.0

            for i in 0..<insetTopPoints.count {
                let s = RainSurfaceMath.clamp01(perPointStrength[i])
                if s <= 0.000_5 { continue }

                let w = pow(s, edgePow) * insetMul
                let n = normals[i]

                let dx: CGFloat = n.dx * insetPt * CGFloat(w)
                let dy: CGFloat = n.dy * insetPt * CGFloat(w)

                insetTopPoints[i] = CGPoint(
                    x: insetTopPoints[i].x - dx,
                    y: insetTopPoints[i].y - dy
                )
            }
        }

        let corePath = geometry.filledPath(usingInsetTopPoints: insetTopPoints)
        if corePath.isEmpty { return }

        let surfacePath = geometry.surfacePolylinePath()

        // ---- Core fill -------------------------------------------------------------------------
        context.fill(corePath, with: .color(cfg.coreBodyColor))

        // Top lift + inside weld (subtle; avoids floating fuzz).
        drawCoreTopLift(
            in: &context,
            corePath: corePath,
            surfacePath: surfacePath,
            chartRect: chartRect,
            baselineY: geometry.baselineY,
            cfg: cfg,
            bandWidthPt: bandPt,
            displayScale: scale,
            maxStrength: maxStrength,
            fuzzAllowed: fuzzAllowed,
            isTightBudget: isTightBudget
        )

        // Extra fade-out at the top edge inside the core (filtered layer); skip in tight budgets.
        if !isTightBudget {
            drawCoreEdgeFade(
                in: &context,
                corePath: corePath,
                surfacePath: surfacePath,
                cfg: cfg,
                bandWidthPt: bandPt,
                displayScale: scale,
                maxStrength: maxStrength
            )
        }

        // ---- Fuzz -----------------------------------------------------------------------------
        // Haze + erosion removed first under budget pressure.
        if fuzzAllowed, !isTightBudget, cfg.fuzzHazeStrength > 0.000_1 {
            drawFuzzHaze(
                in: &context,
                chartRect: chartRect,
                corePath: corePath,
                surfacePoints: surfacePoints,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt,
                displayScale: scale,
                maxStrength: maxStrength
            )
        }

        if fuzzAllowed, !isTightBudget, cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.000_1 {
            drawCoreErosion(
                in: &context,
                corePath: corePath,
                surfacePoints: surfacePoints,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt,
                displayScale: scale,
                maxStrength: maxStrength
            )
        }

        // Speckles (primary dense particulate band).
        if fuzzAllowed, cfg.fuzzSpeckleBudget > 0, cfg.fuzzSpeckStrength > 0.000_1 {
            drawFuzzSpeckles(
                in: &context,
                chartRect: chartRect,
                corePath: corePath,
                surfacePoints: surfacePoints,
                normals: normals,
                perPointStrength: perPointStrength,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt,
                displayScale: scale,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
            )
        }

        // Under-grain near baseline (cheap; clipped to core).
        drawBaselineGrain(
            in: &context,
            chartRect: chartRect,
            corePath: corePath,
            baselineY: geometry.baselineY,
            cfg: cfg,
            displayScale: scale,
            maxStrength: maxStrength,
            isTightBudget: isTightBudget
        )

        // Optional gloss + glints.
        if cfg.glossEnabled, cfg.glossMaxOpacity > 0.000_1 {
            drawGloss(
                in: &context,
                corePath: corePath,
                surfacePath: surfacePath,
                chartRect: chartRect,
                cfg: cfg,
                displayScale: scale
            )
        }

        if cfg.glintEnabled, cfg.glintMaxOpacity > 0.000_1, cfg.glintCount > 0 {
            drawGlints(in: &context, surfacePoints: surfacePoints, cfg: cfg, displayScale: scale)
        }

        // Rim: luminous boundary band + micro-grain (avoid “stroke line” look).
        if cfg.rimEnabled, maxStrength > 0.01 {
            drawRim(
                in: &context,
                chartRect: chartRect,
                corePath: corePath,
                surfacePoints: surfacePoints,
                normals: normals,
                perPointStrength: perPointStrength,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPt: bandPt,
                displayScale: scale,
                maxStrength: maxStrength,
                isTightBudget: isTightBudget
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
        let y = RainSurfaceMath.alignToPixelCenter(baselineY + (cfg.baselineOffsetPixels / scale), displayScale: displayScale)
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
