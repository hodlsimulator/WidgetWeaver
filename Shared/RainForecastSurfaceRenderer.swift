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

        // Intensity → height mapping.
        //
        // The previous implementation used a low/high percentile window and then *clamped to 1.0*.
        // In practice, many rainy hours end up with a large portion of samples at/above the chosen
        // high percentile, which collapses the surface into a flat “slab”.
        //
        // Fix: map against a single reference max and do NOT clamp the upper bound.
        // This keeps contrast in the high end (peaks can rise) while still supporting caller-provided
        // absolute scaling via intensityReferenceMaxMMPerHour.
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

        let minuteHeights: [CGFloat] = (0..<nMinutes).map { i in
            let intensity = nonNeg[i]
            guard intensity > 0 else { return 0 }

            var r = intensity * invReferenceMax
            if !r.isFinite { r = 0.0 }
            r = max(0.0, r)
            let t = pow(r, gamma)

            let c = (i < safeCertainties.count) ? RainSurfaceMath.clamp01(safeCertainties[i]) : 1.0
            let certaintyWeight = 0.35 + 0.65 * pow(c, 0.70)

            let h = CGFloat(t) * heightScale * CGFloat(certaintyWeight)
            return h.isFinite ? min(maxHeight, max(0, h)) : 0
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

                var isEffectivelyFlat = range < flatTrigger

                // If the ends taper (as they should), wetMin can be small even when the
                // middle is a perfectly flat plateau. Detect that case by measuring the
                // range in the "core" (near the max height).
                if !isEffectivelyFlat, wetMax > wetThreshold {
                    let coreCut = max(wetThreshold, wetMax * 0.75)
                    var coreMin: CGFloat = .greatestFiniteMagnitude
                    var coreMax: CGFloat = 0
                    var coreCount = 0

                    for h in denseHeights where h > coreCut {
                        coreCount += 1
                        coreMin = min(coreMin, h)
                        coreMax = max(coreMax, h)
                    }

                    if coreCount >= 14 {
                        let coreRange = coreMax - coreMin
                        if coreRange < flatTrigger {
                            isEffectivelyFlat = true
                        }
                    }
                }

                if isEffectivelyFlat {
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
