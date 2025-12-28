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
        let typicalHeight = max(0.0, baselineY - typicalPeakY)
        let heightScale = max(1.0, min(maxHeight, typicalHeight))

        let nonNeg: [Double] = intensities.map { v in
            if !v.isFinite { return 0.0 }
            return (v > 0.0) ? v : 0.0
        }

        // Ignore zeros when estimating the robust max (dry minutes collapse percentiles).
        let positive = nonNeg.filter { $0 > 0.0 }
        let robustSource = positive.isEmpty ? nonNeg : positive
        let robustMax = max(0.000_001, RainSurfaceMath.percentile(robustSource, p: configuration.robustMaxPercentile))

        let gamma = max(0.10, min(2.50, configuration.intensityGamma))
        let minuteHeights: [CGFloat] = nonNeg.map { i in
            let r = i / robustMax
            let h = pow(max(0.0, r), gamma) * Double(heightScale)
            let hh = CGFloat(min(Double(maxHeight), h))
            return hh.isFinite ? hh : 0
        }

        let targetDense = max(12, min(configuration.maxDenseSamples, Int(max(12.0, chartRect.width * displayScale))))
        var denseHeights = RainSurfaceMath.resampleMonotoneCubic(minuteHeights, targetCount: targetDense)
        var denseCertainties = RainSurfaceMath.resampleMonotoneCubic(safeCertainties, targetCount: targetDense)
        denseCertainties = denseCertainties.map { RainSurfaceMath.clamp01($0) }

        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 2, passes: 2)

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

        for i in 0..<denseHeights.count {
            if !denseHeights[i].isFinite { denseHeights[i] = 0 }
            if denseHeights[i] < onePixel * 0.25 { denseHeights[i] = 0 }
        }

        // If WeatherKit delivers a near-constant minute intensity for the whole hour,
        // the surface becomes a flat bar. Add a tiny deterministic undulation ONLY when
        // the surface is effectively flat, so real variation remains untouched.
        do {
            let wetThreshold = onePixel * 0.60
            let wetHeights = denseHeights.filter { $0 > wetThreshold }

            if wetHeights.count >= 16 {
                let minH = wetHeights.min() ?? 0
                let maxH = wetHeights.max() ?? 0
                let range = max(0.0, maxH - minH)

                let flatRangeThreshold = max(onePixel * 2.0, heightScale * 0.06)

                if range < flatRangeThreshold {
                    let salt: UInt64 = 0x8E3B_1C7A_D4F2_6B19
                    var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(configuration.noiseSeed, salt))

                    var noise: [CGFloat] = []
                    noise.reserveCapacity(denseHeights.count)
                    for _ in 0..<denseHeights.count {
                        noise.append(CGFloat(prng.nextSignedFloat()))
                    }

                    noise = RainSurfaceMath.smooth(noise, windowRadius: 7, passes: 2)

                    let amp = min(
                        maxHeight * 0.18,
                        max(onePixel * 4.0, heightScale * 0.28)
                    )

                    for i in 0..<denseHeights.count {
                        let h = denseHeights[i]
                        if h <= wetThreshold { continue }

                        let t = (denseHeights.count <= 1) ? 0.0 : (Double(i) / Double(denseHeights.count - 1))
                        let edgeL = RainSurfaceMath.smoothstep(0.0, 0.20, t)
                        let edgeR = RainSurfaceMath.smoothstep(0.0, 0.20, 1.0 - t)
                        let edgeW = CGFloat(edgeL * edgeR)

                        let c = (i < denseCertainties.count) ? RainSurfaceMath.clamp01(denseCertainties[i]) : 1.0
                        let uncertainty = CGFloat(0.45 + 0.55 * (1.0 - c))

                        let jitter = noise[i] * amp * edgeW * uncertainty

                        var out = h + jitter
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
