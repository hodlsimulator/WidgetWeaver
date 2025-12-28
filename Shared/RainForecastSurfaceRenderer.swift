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
        // Flat-band cause:
        // Normalising to a tight percentile window and clamping at 1.0 makes
        // many wet minutes saturate at the same height, collapsing into a slab.
        //
        // Fix:
        // Map against a single reference max, and do not clamp the upper bound.
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
            guard h.isFinite else { return 0 }
            return min(maxHeight, max(0, h))
        }

        let targetDense = max(
            12,
            min(configuration.maxDenseSamples, Int(max(12.0, chartRect.width * max(1.0, displayScale))))
        )

        var denseHeights = RainSurfaceMath.resampleMonotoneCubic(minuteHeights, targetCount: targetDense)
        var denseCertainties = RainSurfaceMath.resampleMonotoneCubic(safeCertainties, targetCount: targetDense).map {
            RainSurfaceMath.clamp01($0)
        }

        // Keep smoothing light; heavy smoothing reads as a slab.
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

        // Plateau relief:
        // If the wet region is effectively flat, add subtle deterministic low-frequency modulation.
        // This preserves wet/dry boundaries while avoiding the “single band” look.
        applyPlateauReliefIfNeeded(
            denseHeights: &denseHeights,
            denseCertainties: &denseCertainties,
            maxHeight: maxHeight,
            heightScale: heightScale,
            displayScale: displayScale,
            noiseSeed: configuration.noiseSeed
        )

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

    private func applyPlateauReliefIfNeeded(
        denseHeights: inout [CGFloat],
        denseCertainties: inout [Double],
        maxHeight: CGFloat,
        heightScale: CGFloat,
        displayScale: CGFloat,
        noiseSeed: UInt64
    ) {
        guard denseHeights.count >= 20 else { return }
        guard maxHeight.isFinite, maxHeight > 1 else { return }
        guard heightScale.isFinite, heightScale > 1 else { return }

        let onePixel = 1.0 / max(1.0, displayScale)
        let wetThreshold = max(onePixel * 0.25, heightScale * 0.010)

        var wetCount = 0
        var wetMin: CGFloat = .greatestFiniteMagnitude
        var wetMax: CGFloat = 0

        for h in denseHeights where h > wetThreshold {
            wetCount += 1
            wetMin = min(wetMin, h)
            wetMax = max(wetMax, h)
        }

        guard wetCount >= 14, wetMax > wetThreshold else { return }

        // Detect a plateau by looking at the “core” near the maximum.
        let flatTrigger = max(onePixel * 2.4, wetMax * 0.040)

        let coreCut = max(wetThreshold, wetMax * 0.78)
        var coreMin: CGFloat = .greatestFiniteMagnitude
        var coreMax: CGFloat = 0
        var coreCount = 0

        for h in denseHeights where h > coreCut {
            coreCount += 1
            coreMin = min(coreMin, h)
            coreMax = max(coreMax, h)
        }

        guard coreCount >= 14 else { return }
        let coreRange = coreMax - coreMin
        guard coreRange < flatTrigger else { return }

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(noiseSeed, 0xA1D3_CE55_9B27_4F1D))
        let tau = Double.pi * 2.0

        let phase1 = prng.nextFloat01() * tau
        let phase2 = prng.nextFloat01() * tau
        let phase3 = prng.nextFloat01() * tau

        // Cycles across the chart width (low-frequency “natural” variation).
        let f1 = 1.35 + prng.nextFloat01() * 0.55
        let f2 = 2.60 + prng.nextFloat01() * 0.75
        let f3 = 6.20 + prng.nextFloat01() * 1.10

        // Amplitude is intentionally small; enough to break a dead-flat slab.
        var amp = max(onePixel * 1.25, min(wetMax * 0.060, heightScale * 0.035))
        amp = min(amp, maxHeight * 0.070)

        if !amp.isFinite || amp <= 0 { return }

        let n = denseHeights.count
        let denom = Double(max(1, n - 1))

        for i in 0..<n {
            let base = denseHeights[i]
            guard base > wetThreshold else { continue }

            let x = Double(i) / denom

            let n1 = sin((x * f1) * tau + phase1)
            let n2 = sin((x * f2) * tau + phase2)
            let n3 = sin((x * f3) * tau + phase3)

            let noise = (0.55 * n1 + 0.30 * n2 + 0.15 * n3)

            // Envelope reduces modulation near the wet threshold.
            let above = base - wetThreshold
            let envDen = max(onePixel * 2.0, amp * 2.2)
            let env = Double(RainSurfaceMath.clamp01(above / envDen))

            let delta = CGFloat(noise) * amp * CGFloat(env)

            var h = base + delta
            if !h.isFinite { h = base }

            h = max(0, min(maxHeight, h))

            // Keep wet samples wet to avoid introducing gaps.
            h = max(wetThreshold, h)

            denseHeights[i] = h
        }

        // Light re-smooth to remove sharp wiggles.
        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)
    }
}
