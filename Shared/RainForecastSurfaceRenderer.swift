//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Forecast surface rendering core (WidgetKit-safe).
//

import Foundation
import SwiftUI

struct RainForecastSurfaceRenderer {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration
    let displayScale: CGFloat
    let baselineLabelSafeBottom: CGFloat

    init(
        intensities: [Double],
        certainties: [Double],
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat,
        baselineLabelSafeBottom: CGFloat = 0
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
        self.displayScale = displayScale
        self.baselineLabelSafeBottom = baselineLabelSafeBottom
    }

    func render(in context: inout GraphicsContext, size: CGSize) {
        let rect = CGRect(origin: .zero, size: size)
        guard rect.width > 1, rect.height > 1 else { return }

        // 1) Background: pure black (no haze, no gradient).
        context.fill(Path(rect), with: .color(.black))

        // Spec: work inside the exact rect being drawn into.
        let plotRect = rect

        // Spec fixed geometry.
        let baselineY = RainSurfaceMath.alignToPixelCenter(
            plotRect.minY + 0.596 * plotRect.height,
            displayScale: displayScale
        )
        let maxCoreHeightBudget = plotRect.height * 0.195
        let onePixel = RainSurfaceMath.onePixel(displayScale: displayScale)

        let n = min(intensities.count, certainties.count)
        if n <= 0 {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                configuration: configuration,
                displayScale: displayScale
            )
            return
        }

        // Map input data to a low mound height budget.
        let cap = max(configuration.intensityCap, 0.000_000_1)
        let certaintyPower = max(0.0, configuration.coreCertaintyPower)

        var intensity01 = [CGFloat](repeating: 0, count: n)
        var certainty01 = [CGFloat](repeating: 0, count: n)
        var coreHeights = [CGFloat](repeating: 0, count: n)

        for i in 0..<n {
            let intensity = intensities[i]
            let certainty = certainties[i]

            let wet = (intensity > configuration.wetThreshold) && (certainty > 0)

            let i01 = RainSurfaceMath.clamp01(intensity / cap)
            let eased = pow(i01, configuration.intensityEasingPower)

            let c01 = RainSurfaceMath.clamp01(CGFloat(certainty))

            intensity01[i] = CGFloat(eased)
            certainty01[i] = c01

            let coreFactor = pow(Double(c01), certaintyPower)
            var h = CGFloat(eased * coreFactor) * maxCoreHeightBudget

            if wet && h > 0 {
                let minVisible = max(onePixel, maxCoreHeightBudget * configuration.minVisibleHeightFractionOfMax)
                if h < minVisible { h = minVisible }
            } else {
                h = 0
            }

            coreHeights[i] = RainSurfaceMath.clamp(h, min: 0, max: maxCoreHeightBudget)
        }

        // Smooth before path construction.
        coreHeights = RainSurfaceMath.smooth(coreHeights, passes: max(1, configuration.geometrySmoothingPasses))
        coreHeights = coreHeights.map { RainSurfaceMath.clamp($0, min: 0, max: maxCoreHeightBudget) }

        // Resample beyond 60 points (per-pixel sampling across width).
        let pixelWidth = max(1, Int(ceil(plotRect.width * max(displayScale, 1.0))))
        let denseCount = min(max(pixelWidth + 1, max(121, n * 4)), 2049)

        var denseHeights = RainSurfaceMath.resampleMonotoneCubic(coreHeights, targetCount: denseCount)
        denseHeights = RainSurfaceMath.smooth(denseHeights, passes: 1).map { RainSurfaceMath.clamp($0, min: 0, max: maxCoreHeightBudget) }

        var denseIntensity = RainSurfaceMath.resampleMonotoneCubic(intensity01, targetCount: denseCount).map { RainSurfaceMath.clamp01($0) }
        denseIntensity = RainSurfaceMath.smooth(denseIntensity, passes: 1)

        var denseCertainty = RainSurfaceMath.resampleMonotoneCubic(certainty01, targetCount: denseCount).map { RainSurfaceMath.clamp01($0) }
        denseCertainty = RainSurfaceMath.smooth(denseCertainty, passes: 1)

        let denseAlphas = [CGFloat](repeating: 1.0, count: denseCount)

        // Build smoothed segments.
        let wetThreshold = onePixel * 0.35
        let segments = RainSurfaceGeometry.buildSegments(
            plotRect: plotRect,
            baselineY: baselineY,
            heights: denseHeights,
            threshold: wetThreshold
        )

        if !segments.isEmpty {
            // 2–4) Fuzz, core, glints.
            RainSurfaceDrawing.drawProbabilityMaskedSurface(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                baselineLabelSafeBottom: baselineLabelSafeBottom,
                heights: denseHeights,
                alphas: denseAlphas,
                intensities: denseIntensity,
                certainties: denseCertainty,
                segments: segments,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // 5) Baseline (final layer).
        RainSurfaceDrawing.drawBaseline(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )
    }
}
