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

        // The surface plot is drawn on a black backing inside the Nowcast card.
        context.fill(Path(chartRect), with: .color(.black))

        guard chartRect.width > 2, chartRect.height > 2 else { return }

        // Empty = just the baseline.
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
        let safeCertainties = normalisedCertainties(targetCount: nMinutes)

        // Baseline placement.
        var baselineY = chartRect.minY + chartRect.height * configuration.baselineFractionFromTop
        baselineY = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        let baselineDistanceFromTop = max(0.0, baselineY - chartRect.minY)
        let topHeadroom = baselineDistanceFromTop * configuration.topHeadroomFraction
        let maxHeight = max(0.0, baselineDistanceFromTop - topHeadroom)

        // Height scaling target (geometric).
        let typicalPeakY = chartRect.minY + chartRect.height * configuration.typicalPeakFraction
        let typicalHeightRaw = baselineY - typicalPeakY
        let heightScale: CGFloat = {
            if typicalHeightRaw.isFinite, typicalHeightRaw > 1.0 {
                return max(1.0, min(maxHeight, typicalHeightRaw))
            }
            return max(1.0, maxHeight * 0.55)
        }()

        // Sanitise intensities.
        let nonNeg: [Double] = intensities.map { v in
            guard v.isFinite else { return 0.0 }
            return max(0.0, v)
        }
        let positive = nonNeg.filter { $0 > 0.0 }

        // Intensity mapping:
        // - If intensityReferenceMaxMMPerHour > 0, map as intensity / referenceMax.
        // - Else, fall back to robust percentile scaling on wet minutes.
        let referenceMax = configuration.intensityReferenceMaxMMPerHour
        let usesReferenceMax = referenceMax.isFinite && referenceMax > 0.0

        var low: Double = 0.0
        var denom: Double = 1.0

        if usesReferenceMax {
            low = 0.0
            denom = max(0.000_001, referenceMax)
        } else {
            let hiP = RainSurfaceMath.clamp01(configuration.robustMaxPercentile)
            let loP = 0.20

            let hiI: Double = {
                guard !positive.isEmpty else { return 0.0 }
                return RainSurfaceMath.percentile(positive, p: hiP)
            }()

            let loI: Double = {
                guard !positive.isEmpty else { return 0.0 }
                return RainSurfaceMath.percentile(positive, p: loP)
            }()

            let fallbackMax = positive.max() ?? 0.0
            low = max(0.0, min(loI.isFinite ? loI : 0.0, fallbackMax))
            let high = max(low, hiI.isFinite ? hiI : fallbackMax)

            // Default denom.
            denom = max(0.000_001, high - low)

            // Guard: collapse when percentiles converge (steady rain / little variance).
            if fallbackMax > 0.0 {
                let range = high - low
                let eps = max(0.000_001, fallbackMax * 0.0005)
                if !range.isFinite || range <= eps {
                    low = 0.0
                    let high2 = max(fallbackMax, 0.000_001)
                    denom = max(0.000_001, high2 - low)
                }
            }
        }

        let gamma = max(0.10, min(2.50, configuration.intensityGamma))

        let minuteHeights: [CGFloat] = (0..<nMinutes).map { i in
            let intensity = nonNeg[i]
            if intensity <= 0.0 { return 0.0 }

            var t: Double
            if usesReferenceMax {
                t = intensity / denom
            } else {
                t = (intensity - low) / denom
            }

            if !t.isFinite { t = 0.0 }
            t = max(0.0, min(1.0, t))
            t = pow(t, gamma)

            let c = (i < safeCertainties.count) ? RainSurfaceMath.clamp01(safeCertainties[i]) : 1.0
            let certaintyWeight = 0.35 + 0.65 * pow(c, 0.70)

            let h = CGFloat(t) * heightScale * CGFloat(certaintyWeight)
            guard h.isFinite else { return 0.0 }
            return min(maxHeight, max(0.0, h))
        }

        // Dense resample for smooth rendering.
        let targetDense = max(
            12,
            min(configuration.maxDenseSamples, Int(max(12.0, chartRect.width * displayScale)))
        )

        var denseHeights = RainSurfaceMath.resampleMonotoneCubic(minuteHeights, targetCount: targetDense)

        var denseCertainties = RainSurfaceMath.resampleMonotoneCubic(safeCertainties, targetCount: targetDense)
        denseCertainties = denseCertainties.map { RainSurfaceMath.clamp01($0) }

        // Keep smoothing light.
        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)

        RainSurfaceMath.applyEdgeEasing(
            to: &denseHeights,
            fraction: configuration.edgeEasingFraction,
            power: configuration.edgeEasingPower
        )

        let onePixel = 1.0 / max(1.0, displayScale)

        RainSurfaceMath.applyWetSegmentEasing(
            to: &denseHeights,
            threshold: onePixel * 0.10,
            fraction: max(configuration.edgeEasingFraction, 0.12),
            power: configuration.edgeEasingPower
        )

        // If the wet region is almost perfectly flat, introduce a tiny deterministic relief.
        // This only runs when the wet range is very small, so it does not override real variation.
        let wetThreshold = max(onePixel * 0.60, heightScale * 0.015)

        var wetCount = 0
        var wetMin: CGFloat = .greatestFiniteMagnitude
        var wetMax: CGFloat = 0.0

        for h in denseHeights where h > wetThreshold {
            wetCount += 1
            wetMin = min(wetMin, h)
            wetMax = max(wetMax, h)
        }

        if wetCount >= 14 {
            let range = wetMax - wetMin
            let flatTrigger = max(onePixel * 3.0, heightScale * 0.08)

            if range < flatTrigger {
                var prng = RainSurfacePRNG(
                    seed: RainSurfacePRNG.combine(configuration.noiseSeed, 0xA1D3_CE55_9B27_4F1D)
                )

                var noise: [CGFloat] = []
                noise.reserveCapacity(denseHeights.count)
                for _ in 0..<denseHeights.count {
                    noise.append(CGFloat(prng.nextSignedFloat()))
                }

                noise = RainSurfaceMath.smooth(noise, windowRadius: 6, passes: 2)

                let ampBase = max(onePixel * 2.0, heightScale * 0.06)
                let amp = min(heightScale * 0.26, max(ampBase, wetMax * 0.32))

                // Bias relief to the interior and to low-certainty zones.
                let n = denseHeights.count
                for i in 0..<n {
                    let h = denseHeights[i]
                    if h <= wetThreshold { continue }

                    let t = (n <= 1) ? 0.0 : CGFloat(i) / CGFloat(n - 1)
                    let edge = min(t, 1.0 - t)
                    let edgeW = CGFloat(RainSurfaceMath.smoothstep(0.0, 0.18, Double(edge)))

                    let c = (i < denseCertainties.count) ? CGFloat(denseCertainties[i]) : 1.0
                    let uncertainty = 1.0 - max(0.0, min(1.0, c))
                    let uncertW = 0.30 + 0.70 * pow(uncertainty, 0.85)

                    let delta = noise[i] * amp * edgeW * uncertW
                    let hh = max(0.0, min(maxHeight, h + delta))
                    denseHeights[i] = hh.isFinite ? hh : h
                }

                denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)
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

    private func normalisedCertainties(targetCount: Int) -> [Double] {
        if certainties.count == targetCount {
            return certainties.map { RainSurfaceMath.clamp01($0) }
        }

        if certainties.isEmpty {
            return Array(repeating: 1.0, count: targetCount)
        }

        var c = certainties.map { RainSurfaceMath.clamp01($0) }

        if c.count < targetCount {
            c.append(contentsOf: Array(repeating: c.last ?? 1.0, count: targetCount - c.count))
        } else if c.count > targetCount {
            c = Array(c.prefix(targetCount))
        }

        return c
    }
}
