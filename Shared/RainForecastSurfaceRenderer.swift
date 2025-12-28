//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI

struct RainForecastSurfaceRenderer {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration
    let displayScale: CGFloat

    func render(in context: inout GraphicsContext, size: CGSize) {
        let chartRect = CGRect(origin: .zero, size: size)

        // Always clear to black inside the plot.
        context.fill(Path(chartRect), with: .color(.black))

        guard chartRect.width > 2, chartRect.height > 2 else { return }

        guard !intensities.isEmpty else {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                chartRect: chartRect,
                baselineY: RainSurfaceMath.alignToPixelCenter(chartRect.midY, displayScale: displayScale),
                configuration: configuration,
                displayScale: displayScale
            )
            return
        }

        let nMinutes = intensities.count

        let safeCertainties: [Double] = {
            if certainties.count == nMinutes {
                return certainties.map { RainSurfaceMath.clamp01($0) }
            }
            if certainties.isEmpty {
                return Array(repeating: 1.0, count: nMinutes)
            }
            var c = certainties.map { RainSurfaceMath.clamp01($0) }
            if c.count < nMinutes {
                c.append(contentsOf: Array(repeating: c.last ?? 1.0, count: nMinutes - c.count))
            } else if c.count > nMinutes {
                c = Array(c.prefix(nMinutes))
            }
            return c
        }()

        // Baseline placement.
        var baselineY = chartRect.minY + chartRect.height * configuration.baselineFractionFromTop
        baselineY = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        // Geometry reinterpretation to match the “ratio knobs” you’re using:
        // - headroom is fraction of baseline distance-from-top
        // - typicalPeakFraction is a Y-position-from-top target
        let baselineDistanceFromTop = max(0.0, baselineY - chartRect.minY)
        let topHeadroom = baselineDistanceFromTop * configuration.topHeadroomFraction
        let maxHeight = max(0.0, baselineDistanceFromTop - topHeadroom)

        let typicalPeakY = chartRect.minY + chartRect.height * configuration.typicalPeakFraction
        let typicalHeight = max(0.0, baselineY - typicalPeakY)
        let heightScale = max(1.0, min(maxHeight, typicalHeight))

        // Robust max.
        let nonNeg = intensities.map { max(0.0, $0) }
        let robustMax = max(0.000_001, RainSurfaceMath.percentile(nonNeg, p: configuration.robustMaxPercentile))

        // Map intensity → height (in points).
        let gamma = max(0.10, min(2.50, configuration.intensityGamma))
        let minuteHeights: [CGFloat] = nonNeg.map { i in
            let r = i / robustMax
            let h = pow(max(0.0, r), gamma) * Double(heightScale)
            return CGFloat(min(Double(maxHeight), h))
        }

        // Dense resample count (cap by config).
        let targetDense = max(12, min(configuration.maxDenseSamples, Int(max(12.0, chartRect.width * displayScale))))
        var denseHeights = RainSurfaceMath.resampleMonotoneCubic(minuteHeights, targetCount: targetDense)
        var denseCertainties = RainSurfaceMath.resampleMonotoneCubic(safeCertainties, targetCount: targetDense)
        denseCertainties = denseCertainties.map { RainSurfaceMath.clamp01($0) }

        // Smooth the heights a bit.
        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 2, passes: 2)

        // Ease chart edges.
        RainSurfaceMath.applyEdgeEasing(to: &denseHeights, fraction: configuration.edgeEasingFraction, power: configuration.edgeEasingPower)

        // Ease wet-run boundaries (prevents hard “walls” at stop/start).
        let onePixel = 1.0 / max(1.0, displayScale)
        RainSurfaceMath.applyWetSegmentEasing(
            to: &denseHeights,
            threshold: onePixel * 0.10,
            fraction: max(configuration.edgeEasingFraction, 0.12),
            power: configuration.edgeEasingPower
        )

        // Snap tiny values to 0 so “dry” really becomes dry.
        for i in 0..<denseHeights.count {
            if denseHeights[i] < onePixel * 0.25 {
                denseHeights[i] = 0
            }
        }

        let geometry = RainSurfaceGeometry(
            chartRect: chartRect,
            baselineY: baselineY,
            heights: denseHeights,
            certainties: denseCertainties,
            displayScale: displayScale
        )

        RainSurfaceDrawing.drawSurface(
            in: &context,
            geometry: geometry,
            configuration: configuration,
            displayScale: displayScale
        )

        RainSurfaceDrawing.drawBaseline(
            in: &context,
            chartRect: chartRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )
    }
}
