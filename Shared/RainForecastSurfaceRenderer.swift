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

        let fallbackMax = positive.max() ?? 0.0

        var low = max(0.0, min(loI.isFinite ? loI : 0.0, fallbackMax))
        var high = max(low, hiI.isFinite ? hiI : fallbackMax)
        var denom = max(0.000_001, high - low)

        // Flat-band fix:
        // If the wet intensities are effectively constant, percentile scaling collapses (high ≈ low)
        // and (intensity - low) becomes ~0 for all wet minutes -> zero height -> flat band.
        if fallbackMax > 0.0 {
            let range = high - low
            let eps = max(0.000_001, fallbackMax * 0.0005)
            if !range.isFinite || range <= eps {
                low = 0.0
                high = max(fallbackMax, 0.000_001)
                denom = max(0.000_001, high - low)
            }
        }

        let gamma = max(0.10, min(2.50, configuration.intensityGamma))

        let minuteHeights: [CGFloat] = (0..<nMinutes).map { i in
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

        // If WeatherKit delivers an effectively “plateaued” hour (very low variance once the ends are eased),
        // add deterministic relief so the ribbon doesn't read as a flat slab.
        do {
            let wetThreshold = onePixel * 0.60

            var wetMax: CGFloat = 0
            var wetCount = 0
            for h in denseHeights where h > wetThreshold {
                wetCount += 1
                wetMax = max(wetMax, h)
            }

            // Measure flatness on the *core* of the ribbon.
            // Using wetMin/wetMax across the whole segment fails because the edge easing produces
            // large range even when the interior is perfectly flat.
            if wetCount >= 14, wetMax > wetThreshold {
                let coreCut = max(wetThreshold, wetMax * 0.70)

                var coreMin: CGFloat = .greatestFiniteMagnitude
                var coreMax: CGFloat = 0
                var coreCount = 0

                for h in denseHeights where h >= coreCut {
                    coreCount += 1
                    coreMin = min(coreMin, h)
                    coreMax = max(coreMax, h)
                }

                let coreRatio = (wetCount > 0) ? (Double(coreCount) / Double(wetCount)) : 0.0
                let coreRange = coreMax - coreMin

                let flatTrigger = max(
                    onePixel * 2.5,
                    max(wetMax * 0.06, heightScale * 0.06)
                )

                if coreCount >= 16, coreRatio >= 0.45, coreRange < flatTrigger {
                    var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(configuration.noiseSeed, 0xA1D3_CE55_9B27_4F1D))

                    var noise: [CGFloat] = []
                    noise.reserveCapacity(denseHeights.count)
                    for _ in 0..<denseHeights.count {
                        noise.append(CGFloat(prng.nextSignedFloat()))
                    }

                    // Low-frequency curve (keep enough energy so it reads at widget scale).
                    let r = max(4, min(12, denseHeights.count / 24))
                    noise = RainSurfaceMath.smooth(noise, windowRadius: r, passes: 1)

                    let amp = min(
                        maxHeight * 0.26,
                        max(onePixel * 14.0, max(wetMax * 0.32, heightScale * 0.50))
                    )

                    let n = denseHeights.count
                    for i in 0..<n {
                        let h = denseHeights[i]
                        if h <= wetThreshold { continue }

                        let t = (n <= 1) ? 0.0 : Double(i) / Double(n - 1)
                        let edgeL = RainSurfaceMath.smoothstep(0.0, 0.20, t)
                        let edgeR = RainSurfaceMath.smoothstep(0.0, 0.20, 1.0 - t)
                        let edgeW = CGFloat(edgeL * edgeR)

                        // Focus the relief on the interior plateau (avoid making the tapered ends wobbly).
                        let plateauW: CGFloat = {
                            if wetMax <= coreCut { return 0 }
                            let w = RainSurfaceMath.smoothstep(Double(coreCut), Double(wetMax), Double(h))
                            return CGFloat(max(0.0, min(1.0, w)))
                        }()

                        if plateauW <= 0.0001 { continue }

                        let c = (i < denseCertainties.count) ? RainSurfaceMath.clamp01(denseCertainties[i]) : 1.0
                        let uncertainty = CGFloat(0.45 + 0.55 * (1.0 - c))

                        let delta = noise[i] * amp * edgeW * plateauW * uncertainty
                        var out = h + delta
                        if !out.isFinite { out = h }
                        denseHeights[i] = min(maxHeight, max(0.0, out))
                    }

                    denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)
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
