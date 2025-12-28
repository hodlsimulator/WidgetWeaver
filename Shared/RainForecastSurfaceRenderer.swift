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
        let onePixel = 1.0 / max(1.0, displayScale)

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
        let fallbackMax = positive.max() ?? 0.0

        // ---------------------------------------------------------------------
        // Height mapping
        //
        // There are two modes:
        // 1) Reference scaling: use a known "visual max" (mm/h) provided by the caller.
        //    This keeps chart height tied to real intensity (drizzle stays small).
        // 2) Robust window scaling: use percentiles of the wet minutes.
        //
        // Flat chart failure mode:
        // If all wet intensities are identical, the percentile window collapses (low == high)
        // and (intensity - low) becomes 0 for every wet minute. That yields a baseline-only
        // surface and only the fuzz layer is visible as a flat band.
        // ---------------------------------------------------------------------

        var low: Double = 0.0
        var high: Double = 0.0

        let refMax0 = configuration.intensityReferenceMaxMMPerHour
        let refMax = (refMax0.isFinite && refMax0 > 0.0) ? refMax0 : 0.0

        if refMax > 0.0 {
            low = 0.0
            high = refMax
        } else {
            // Robust window ignoring zeros (dry minutes).
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

            low = max(0.0, min(loI.isFinite ? loI : 0.0, fallbackMax))
            high = max(low, hiI.isFinite ? hiI : fallbackMax)

            // If the window collapses, fall back to a zero-based mapping.
            if fallbackMax > 0.0 {
                let range = high - low
                let eps = max(0.000_000_001, fallbackMax * 0.0005) // 0.05% of max, with a tiny floor.
                if !range.isFinite || range <= eps {
                    low = 0.0
                    high = max(fallbackMax, 0.000_001)
                }
            }
        }

        let denom = max(0.000_001, high - low)
        let gamma = max(0.10, min(2.50, configuration.intensityGamma))

        var minuteHeights: [CGFloat] = (0..<nMinutes).map { i in
            let intensity = nonNeg[i]
            guard intensity > 0 else { return 0 }

            var t = (intensity - low) / denom
            if !t.isFinite { t = 0.0 }
            t = max(0.0, min(1.0, t))
            t = pow(t, gamma)

            let c = (i < safeCertainties.count) ? RainSurfaceMath.clamp01(safeCertainties[i]) : 1.0
            let certaintyWeight = 0.35 + 0.65 * pow(c, 0.70)

            let h = CGFloat(t) * heightScale * CGFloat(certaintyWeight)
            return h.isFinite ? min(maxHeight, max(0, h)) : 0
        }

        // If intensity is entirely missing/zeroed but chance is present, synthesise a subtle
        // height from chance so the surface does not collapse to a straight baseline.
        if positive.isEmpty && !certainties.isEmpty {
            let cMax = safeCertainties.max() ?? 0.0
            if cMax > 0.10 {
                let chanceScale = heightScale * 0.30
                minuteHeights = (0..<nMinutes).map { i in
                    let c = RainSurfaceMath.clamp01(safeCertainties[i])
                    let t = pow(c, 1.35)
                    let h = CGFloat(t) * chanceScale
                    if !h.isFinite { return 0 }
                    return min(maxHeight, max(0, h))
                }
            }
        }

        let targetDense = max(12, min(configuration.maxDenseSamples, Int(max(12.0, chartRect.width * displayScale))))
        var denseHeights = RainSurfaceMath.resampleMonotoneCubic(minuteHeights, targetCount: targetDense)
        var denseCertainties = RainSurfaceMath.resampleMonotoneCubic(safeCertainties, targetCount: targetDense)
        denseCertainties = denseCertainties.map { RainSurfaceMath.clamp01($0) }

        // Keep this light; heavy smoothing makes low-variation hours read as a slab.
        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)

        RainSurfaceMath.applyEdgeEasing(
            to: &denseHeights,
            fraction: configuration.edgeEasingFraction,
            power: configuration.edgeEasingPower
        )

        RainSurfaceMath.applyWetSegmentEasing(
            to: &denseHeights,
            threshold: onePixel * 0.10,
            fraction: max(configuration.edgeEasingFraction, 0.12),
            power: configuration.edgeEasingPower
        )

        for i in 0..<denseHeights.count {
            if !denseHeights[i].isFinite { denseHeights[i] = 0 }
            if denseHeights[i] < onePixel * 0.25 { denseHeights[i] = 0 }
            denseHeights[i] = min(maxHeight, max(0, denseHeights[i]))
        }

        // If WeatherKit delivers an effectively flat hour (constant intensity/chance),
        // add deterministic “relief” so the ribbon is not a rectangle.
        do {
            let wetThreshold = onePixel * 0.60
            var wetMin: CGFloat = .greatestFiniteMagnitude
            var wetMax: CGFloat = 0
            var wetCount = 0

            for h in denseHeights where h > wetThreshold {
                wetCount += 1
                wetMin = min(wetMin, h)
                wetMax = max(wetMax, h)
            }

            if wetCount >= 14 {
                let range = wetMax - wetMin
                let flatTrigger = max(onePixel * 3.0, heightScale * 0.08)

                if range < flatTrigger {
                    var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(configuration.noiseSeed, 0xA1D3_CE55_9B27_4F1D))

                    var noise: [CGFloat] = []
                    noise.reserveCapacity(denseHeights.count)
                    for _ in 0..<denseHeights.count {
                        noise.append(CGFloat(prng.nextSignedFloat()))
                    }

                    // Low-frequency curve.
                    noise = RainSurfaceMath.smooth(noise, windowRadius: 10, passes: 2)

                    let amp = min(
                        maxHeight * 0.22,
                        max(onePixel * 10.0, heightScale * 0.45)
                    )

                    let n = denseHeights.count
                    for i in 0..<n {
                        let h = denseHeights[i]
                        if h <= wetThreshold { continue }

                        let t = (n <= 1) ? 0.0 : Double(i) / Double(n - 1)
                        let edgeL = RainSurfaceMath.smoothstep(0.0, 0.20, t)
                        let edgeR = RainSurfaceMath.smoothstep(0.0, 0.20, 1.0 - t)
                        let edgeW = CGFloat(edgeL * edgeR)

                        let c = (i < denseCertainties.count) ? RainSurfaceMath.clamp01(denseCertainties[i]) : 1.0
                        let uncertainty = CGFloat(0.45 + 0.55 * (1.0 - c))

                        let delta = noise[i] * amp * edgeW * uncertainty
                        var out = h + delta
                        if !out.isFinite { out = h }
                        denseHeights[i] = min(maxHeight, max(0.0, out))
                    }

                    denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 2, passes: 1)
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
