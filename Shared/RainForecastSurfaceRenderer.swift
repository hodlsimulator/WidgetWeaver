//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Converts minute intensities -> surface geometry and draws using RainSurfaceDrawing.
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

        var baselineY = chartRect.minY + chartRect.height * configuration.baselineFractionFromTop
        baselineY = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        let baselineDistanceFromTop = max(0.0, baselineY - chartRect.minY)
        let topHeadroom = baselineDistanceFromTop * configuration.topHeadroomFraction
        let maxHeight = max(0.0, baselineDistanceFromTop - topHeadroom)

        let typicalPeakY = chartRect.minY + chartRect.height * configuration.typicalPeakFraction
        let typicalHeightRaw = baselineY - typicalPeakY

        let heightScale: CGFloat = {
            if typicalHeightRaw.isFinite, typicalHeightRaw > 1.0 {
                return max(1.0, min(maxHeight, typicalHeightRaw))
            }
            return max(1.0, maxHeight * 0.55)
        }()

        let nonNeg: [Double] = intensities.map { v in
            guard v.isFinite else { return 0.0 }
            return v > 0.0 ? v : 0.0
        }

        let positive = nonNeg.filter { $0 > 0.0 }

        let referenceMaxMMPerHour: Double = {
            let ref = configuration.intensityReferenceMaxMMPerHour
            if ref.isFinite, ref > 0 { return ref }

            let p = RainSurfaceMath.clamp01(configuration.robustMaxPercentile)
            if !positive.isEmpty {
                let robust = RainSurfaceMath.percentile(positive, p: p)
                if robust.isFinite, robust > 0 { return robust }
            }

            let fallback = positive.max() ?? 0.0
            return max(0.000_001, fallback)
        }()

        let invReferenceMax = 1.0 / max(0.000_001, referenceMaxMMPerHour)
        let gamma = max(0.10, min(2.50, configuration.intensityGamma))

        let onePixel = 1.0 / max(1.0, displayScale)

        @inline(__always)
        func softCeil(_ h: CGFloat, ceiling: CGFloat) -> CGFloat {
            guard h.isFinite, ceiling.isFinite, ceiling > 0 else { return 0.0 }
            if h <= ceiling { return max(0.0, h) }

            // Soft-knee near the top avoids hard clipping artefacts when intensity exceeds the reference max.
            let kneeStartFraction: CGFloat = 0.92
            let kneeStart = ceiling * kneeStartFraction
            if h <= kneeStart { return h }

            let available = ceiling - kneeStart
            if available <= max(onePixel, 0.000_5) { return ceiling }

            let x = (h - kneeStart) / available
            let y = kneeStart + available * CGFloat(tanh(Double(x)))
            return min(ceiling, max(0.0, y.isFinite ? y : ceiling))
        }

        // Height is driven by intensity only.
        // Certainty is carried separately and is used by fuzz/edge styling, not the core height.
        let minuteHeights: [CGFloat] = nonNeg.map { intensity in
            guard intensity > 0 else { return 0.0 }

            var r = intensity * invReferenceMax
            if !r.isFinite { r = 0.0 }
            r = max(0.0, r)

            let t = pow(r, gamma)
            var h = CGFloat(t) * heightScale
            if !h.isFinite { h = 0.0 }
            h = max(0.0, h)

            return softCeil(h, ceiling: maxHeight)
        }

        let targetDense = max(
            12,
            min(configuration.maxDenseSamples, Int(max(12.0, chartRect.width * max(1.0, displayScale))))
        )

        var denseHeights = RainSurfaceMath.resampleMonotoneCubicCenters(minuteHeights, targetCount: targetDense)

        var denseCertainties = RainSurfaceMath.resampleMonotoneCubic(safeCertainties, targetCount: targetDense)
            .map { RainSurfaceMath.clamp01($0) }

        // Minimal smoothing; keeps the curve faithful to minute data while avoiding pixel jitter.
        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)

        // Optional easing (caller-controlled via configuration.edgeEasingFraction).
        RainSurfaceMath.applyEdgeEasing(
            to: &denseHeights,
            fraction: configuration.edgeEasingFraction,
            power: configuration.edgeEasingPower
        )

        RainSurfaceMath.applyWetSegmentEasing(
            to: &denseHeights,
            threshold: onePixel * 0.10,
            fraction: configuration.edgeEasingFraction,
            power: configuration.edgeEasingPower
        )

        // Snap sub-pixel heights to zero to avoid a faint “baseline band”.
        if onePixel.isFinite {
            let snap = onePixel * 0.10
            for i in 0..<denseHeights.count {
                if denseHeights[i] < snap {
                    denseHeights[i] = 0.0
                }
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
