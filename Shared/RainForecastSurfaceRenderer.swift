//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Procedural nowcast rain surface renderer:
//  - pure black background
//  - opaque core (solid fill; no vertical gradient)
//  - crisp rim + inside-only gloss
//  - granular speckled fuzz outside core only
//  - baseline anchored inside the chart (leaves empty space beneath)
//

import Foundation
import SwiftUI

struct RainForecastSurfaceRenderer {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration
    let displayScale: CGFloat

    func render(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        guard rect.width >= 2, rect.height >= 2 else { return }

        // (1) Background: pure black, no gradients/vignette/grain.
        var bg = Path()
        bg.addRect(rect)
        context.fill(bg, with: .color(.black))

        let chartRect = rect
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        // Baseline placed inside the chart, matching the mock composition.
        let baselineFrac = RainSurfaceMath.clamp(configuration.baselineFractionFromTop, min: 0.45, max: 0.75)
        let baselineRaw = chartRect.minY + chartRect.height * baselineFrac

        // Optional inset to avoid clipping if baseline gets very close to an edge.
        let inset = CGFloat(configuration.baselineAntiClipInsetPixels / scale)

        let baselineY = RainSurfaceMath.alignToPixelCenter(
            RainSurfaceMath.clamp(baselineRaw, min: chartRect.minY + inset, max: chartRect.maxY - inset),
            displayScale: scale
        )

        // Normalise inputs.
        let nI = intensities.count
        if nI == 0 {
            // (5) Baseline only.
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                configuration: configuration,
                displayScale: displayScale
            )
            return
        }

        let safeCertainties: [Double] = {
            if certainties.isEmpty {
                return Array(repeating: 1.0, count: nI)
            }
            if certainties.count == nI {
                return certainties.map { RainSurfaceMath.clamp01($0) }
            }
            if certainties.count > nI {
                return Array(certainties.prefix(nI)).map { RainSurfaceMath.clamp01($0) }
            }
            // Pad with last value.
            let last = RainSurfaceMath.clamp01(certainties.last ?? 1.0)
            return certainties.map { RainSurfaceMath.clamp01($0) } + Array(repeating: last, count: nI - certainties.count)
        }()

        let clampedIntensities = intensities.map { max(0.0, $0) }

        // Robust scaling max: percentile of non-zero values.
        let nonZero = clampedIntensities.filter { $0 > 0.0 }
        if nonZero.isEmpty {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                configuration: configuration,
                displayScale: displayScale
            )
            return
        }

        let p = RainSurfaceMath.clamp(configuration.robustMaxPercentile, min: 0.90, max: 0.95)
        let robustMax = max(1e-9, RainSurfaceMath.percentile(nonZero, p: p))

        // Height budget:
        // - baseline is inside the rect (space exists below)
        // - top headroom caps absolute maximum height
        // - typical peaks map to a fixed fraction of chart height (matches mock)
        let headroomFrac = RainSurfaceMath.clamp(configuration.topHeadroomFraction, min: 0.20, max: 0.50)
        let typicalFrac = RainSurfaceMath.clamp(configuration.typicalPeakFraction, min: 0.12, max: 0.30)

        let availableAboveBaseline = max(onePixel, baselineY - chartRect.minY)
        let headroom = chartRect.height * headroomFrac
        let maxHeight = max(onePixel, min(availableAboveBaseline - onePixel, availableAboveBaseline - headroom))
        let targetPeakHeight = min(maxHeight, chartRect.height * typicalFrac)

        let gamma = RainSurfaceMath.clamp(configuration.intensityGamma, min: 0.20, max: 0.95)
        let ratio = max(1.0, Double(maxHeight / max(onePixel, targetPeakHeight)))
        let vMax = pow(ratio, 1.0 / gamma)

        // Map minute intensities to heights (no minimum clamp; near-zero approaches baseline).
        let minuteHeights: [CGFloat] = clampedIntensities.map { intensity in
            if intensity <= 0.0 { return 0.0 }
            let v = intensity / robustMax
            let u = min(v, vMax) / vMax
            let shaped = pow(max(0.0, u), gamma)
            return CGFloat(shaped) * maxHeight
        }

        // Dense sampling: per-pixel (or sub-pixel) across chart width, capped.
        let pxW = max(1, Int(ceil(chartRect.width * scale)))
        let denseCount = max(32, min(configuration.maxDenseSamples, pxW))

        var denseHeights = RainSurfaceMath.resampleMonotoneCubicCenters(minuteHeights, targetCount: denseCount)
        denseHeights = RainSurfaceMath.smooth(denseHeights, passes: 2)
        denseHeights = denseHeights.map { h in
            let hh = RainSurfaceMath.clamp(h, min: 0.0, max: maxHeight)
            // Allow true zeros; drop tiny numerical fuzz without creating a flat strip.
            return (hh < onePixel * 0.10) ? 0.0 : hh
        }

        var denseCertainties = RainSurfaceMath.resampleMonotoneCubicCenters(safeCertainties, targetCount: denseCount)
        denseCertainties = RainSurfaceMath.smooth(denseCertainties, passes: 1)
        denseCertainties = denseCertainties.map { RainSurfaceMath.clamp01($0) }

        // Path construction at per-column centres.
        let stepX = chartRect.width / CGFloat(max(1, denseCount))
        let corePath = RainSurfaceGeometry.makeCorePath(
            chartRect: chartRect,
            baselineY: baselineY,
            stepX: stepX,
            heights: denseHeights
        )
        let topEdgePath = RainSurfaceGeometry.makeTopEdgePath(
            chartRect: chartRect,
            baselineY: baselineY,
            stepX: stepX,
            heights: denseHeights
        )

        // (2)(3)(4) Fuzz + Core + Rim + Glints
        RainSurfaceDrawing.drawSurface(
            in: &context,
            chartRect: chartRect,
            baselineY: baselineY,
            stepX: stepX,
            heights: denseHeights,
            certainties: denseCertainties,
            corePath: corePath,
            topEdgePath: topEdgePath,
            configuration: configuration,
            displayScale: displayScale
        )

        // (5) Baseline drawn last (top-most), end-faded, additive.
        RainSurfaceDrawing.drawBaseline(
            in: &context,
            chartRect: chartRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )
    }
}
