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
        guard size.width > 1, size.height > 1 else { return }

        let chartRect = CGRect(origin: .zero, size: size)

        // Background
        context.fill(Path(chartRect), with: .color(.black))

        guard !intensities.isEmpty else { return }

        // ---- Geometry -------------------------------------------------------
        let baselineY = chartRect.minY + chartRect.height * configuration.baselineFractionFromTop
        let baselineDistanceFromTop = max(1.0, baselineY - chartRect.minY)
        let headroom = baselineDistanceFromTop * max(0.0, min(0.45, configuration.topHeadroomFraction))
        let maxHeight = max(1.0, baselineDistanceFromTop - headroom)

        let typicalPeakY = chartRect.minY + chartRect.height * configuration.typicalPeakFraction
        let typicalHeightRaw = baselineY - typicalPeakY
        let heightScale: CGFloat = {
            if typicalHeightRaw.isFinite, typicalHeightRaw > 1.0 {
                return max(1.0, min(maxHeight, typicalHeightRaw))
            }
            return maxHeight * 0.55
        }()

        // ---- Sampling -------------------------------------------------------
        let nMinutes = intensities.count
        let targetDense = max(12, min(configuration.maxDenseSamples, Int(max(12.0, chartRect.width * displayScale))))

        let safeIntensities = intensities.map { $0.isFinite ? max(0.0, $0) : 0.0 }
        let safeCertainties: [Double] = {
            if certainties.count == intensities.count {
                return certainties.map { $0.isFinite ? RainSurfaceMath.clamp01($0) : 1.0 }
            }
            return Array(repeating: 1.0, count: intensities.count)
        }()

        // Resample (monotone cubic keeps it smooth without overshoot).
        let denseIntensities = RainSurfaceMath.resampleMonotoneCubic(safeIntensities, targetCount: targetDense)
        var denseCertainties = RainSurfaceMath.resampleMonotoneCubic(safeCertainties, targetCount: targetDense)
        denseCertainties = denseCertainties.map { RainSurfaceMath.clamp01($0) }

        // ---- Robust intensity window (ignoring zeros / dry minutes) ---------
        let nonNeg = safeIntensities.map { max(0.0, $0) }
        let positive = nonNeg.filter { $0 > 0.0 }

        let hiP = RainSurfaceMath.clamp01(configuration.robustMaxPercentile)
        let loP = 0.20

        let hiI = RainSurfaceMath.percentile(positive, p: hiP)
        let loI = RainSurfaceMath.percentile(positive, p: loP)

        let fallbackMax = positive.max() ?? 0.0

        var low = max(0.0, min(loI.isFinite ? loI : 0.0, fallbackMax))
        var high = max(low, hiI.isFinite ? hiI : fallbackMax)

        // If the wet intensities are effectively flat (high ≈ low), the percentile window collapses.
        // In that case, (intensity - low) becomes ~0 for the entire wet run and the ribbon
        // collapses to the baseline. Fall back to a zero-based mapping so "steady rain" still
        // renders with height (and can receive deterministic relief noise below).
        if fallbackMax > 0.0 {
            let range = high - low
            let eps = max(0.000_001, fallbackMax * 0.0005) // 0.05% of max, or tiny absolute floor.
            if !range.isFinite || range <= eps {
                low = 0.0
                high = max(fallbackMax, 1.0) // Matches the chart's visual scaling floor.
            }
        }

        let lowFinal = low
        let denom = max(0.000_001, high - lowFinal)

        let gamma = max(0.10, min(2.50, configuration.intensityGamma))

        let minuteHeights: [CGFloat] = (0..<nMinutes).map { i in
            let intensity = nonNeg[i]
            guard intensity > 0 else { return 0 }

            var t = (intensity - lowFinal) / denom
            t = RainSurfaceMath.clamp01(t)
            t = pow(t, gamma)

            // Weight by certainty (chance). If certainty is low, height shrinks a bit.
            let c = safeCertainties[i]
            let certaintyWeight = CGFloat(0.35 + 0.65 * RainSurfaceMath.clamp01(c))

            let h = CGFloat(t) * heightScale * certaintyWeight
            if !h.isFinite { return 0 }
            return min(maxHeight, max(0, h))
        }

        // Resample heights to dense.
        var denseHeights = RainSurfaceMath.resampleMonotoneCubic(minuteHeights, targetCount: targetDense)
        denseHeights = denseHeights.map { $0.isFinite ? max(0, min(maxHeight, $0)) : 0 }

        // Gentle smoothing.
        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)

        // Edge easing.
        RainSurfaceMath.applyEdgeEasing(
            to: &denseHeights,
            fraction: configuration.edgeEasingFraction,
            power: configuration.edgeEasingPower
        )

        // Ease into/out of wet segments (prevents hard steps).
        let wetThreshold = max(0.5, (1.0 / max(1.0, displayScale)) * 0.8)
        RainSurfaceMath.applyWetSegmentEasing(
            to: &denseHeights,
            threshold: wetThreshold,
            fraction: 0.14,
            power: 1.7
        )

        // Pixel-snap tiny heights to 0 so dry looks clean.
        let onePixel = 1.0 / max(1.0, displayScale)
        for i in 0..<denseHeights.count {
            if denseHeights[i] < onePixel * 0.25 { denseHeights[i] = 0 }
        }

        // ---- If WeatherKit delivers an effectively flat hour (constant intensity/chance),
        // add deterministic "relief" so the ribbon is not a rectangle.
        // This is subtle: it is only applied when wet for a meaningful duration AND the range is small.
        let wetCount = denseHeights.filter { $0 > (onePixel * 0.60) }.count
        if wetCount >= 14 {
            let wetMin = denseHeights.filter { $0 > (onePixel * 0.60) }.min() ?? 0
            let wetMax = denseHeights.max() ?? 0
            let range = wetMax - wetMin

            let flatTrigger = max(onePixel * 3.0, heightScale * 0.08)
            if range < flatTrigger {
                // Deterministic seed per hour + location-ish.
                let seedBase: UInt64 = configuration.noiseSeed
                var prng = RainSurfacePRNG(seed: seedBase != 0 ? seedBase : 1234567)

                // Coarse noise, then smooth to get broad, organic bumps.
                var noise = (0..<denseHeights.count).map { _ in prng.nextSignedFloat() }
                noise = RainSurfaceMath.smooth(noise.map { CGFloat($0) }, windowRadius: 10, passes: 2).map { Double($0) }

                // Scale the relief to a modest fraction of the available height.
                let amp = min(maxHeight * 0.22, max(onePixel * 10.0, heightScale * 0.45))

                for i in 0..<denseHeights.count {
                    let c = denseCertainties[i]
                    let uncertainty = 0.45 + 0.55 * (1.0 - RainSurfaceMath.clamp01(c))

                    // Taper near edges so the ends stay calm.
                    let t = Double(i) / Double(max(1, denseHeights.count - 1))
                    let edgeW = RainSurfaceMath.smoothstep(0.0, 0.10, t) * RainSurfaceMath.smoothstep(1.0, 0.90, t)

                    let delta = CGFloat(noise[i]) * amp * CGFloat(edgeW) * CGFloat(uncertainty)
                    let h = denseHeights[i] + delta
                    denseHeights[i] = max(0.0, min(maxHeight, h))
                }

                // One more softening pass so it reads like forecast, not "noise".
                denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 2, passes: 1)
            }
        }

        // ---- Draw -----------------------------------------------------------
        let geom = RainSurfaceGeometry(
            chartRect: chartRect,
            baselineY: baselineY,
            heights: denseHeights,
            certainties: denseCertainties,
            displayScale: displayScale
        )

        RainSurfaceDrawing.drawSurface(
            in: &context,
            geometry: geom,
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
