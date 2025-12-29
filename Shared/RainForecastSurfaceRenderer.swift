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

            let kneeStartFraction: CGFloat = 0.92
            let kneeStart = ceiling * kneeStartFraction
            if h <= kneeStart { return h }

            let available = ceiling - kneeStart
            if available <= max(onePixel, 0.000_5) { return ceiling }

            let x = (h - kneeStart) / available
            let y = kneeStart + available * CGFloat(tanh(Double(x)))
            return min(ceiling, max(0.0, y.isFinite ? y : ceiling))
        }

        let minuteHeights: [CGFloat] = nonNeg.enumerated().map { i, intensity in
            if intensity <= 0.0 { return 0.0 }

            var r = intensity * invReferenceMax
            if !r.isFinite { r = 0.0 }
            r = max(0.0, r)

            let t = pow(r, gamma)

            let c = (i < safeCertainties.count) ? RainSurfaceMath.clamp01(safeCertainties[i]) : 1.0
            let certaintyWeight = 0.35 + 0.65 * pow(c, 0.70)

            var h = CGFloat(t) * heightScale * CGFloat(certaintyWeight)
            if !h.isFinite { h = 0.0 }
            h = max(0.0, h)

            return softCeil(h, ceiling: maxHeight)
        }

        let targetDense = max(
            12,
            min(configuration.maxDenseSamples, Int(max(12.0, chartRect.width * max(1.0, displayScale))))
        )

        // Heights: centre-sampled monotone cubic restores the earlier “rounded ramp” silhouette,
        // especially in widget extension budgets.
        var denseHeights = RainSurfaceMath.resampleMonotoneCubicCenters(minuteHeights, targetCount: targetDense)

        // Certainties: keep the standard resample to preserve the current fuzz behaviour.
        let denseCertainties = RainSurfaceMath.resampleMonotoneCubic(safeCertainties, targetCount: targetDense)
            .map { RainSurfaceMath.clamp01($0) }

        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 2, passes: 2)

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

        applyPlateauReliefIfNeeded(
            denseHeights: &denseHeights,
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
        var wetMax: CGFloat = 0
        for h in denseHeights where h > wetThreshold {
            wetCount += 1
            wetMax = max(wetMax, h)
        }
        guard wetCount >= 14, wetMax > wetThreshold else { return }

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

        let f1 = 1.35 + prng.nextFloat01() * 0.55
        let f2 = 2.60 + prng.nextFloat01() * 0.75
        let f3 = 6.20 + prng.nextFloat01() * 1.10

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

            let above = base - wetThreshold
            let envDen = max(onePixel * 2.0, amp * 2.2)
            let env = Double(RainSurfaceMath.clamp01(above / envDen))

            let delta = CGFloat(noise) * amp * CGFloat(env)
            var h = base + delta
            if !h.isFinite { h = base }

            h = max(0.0, min(maxHeight, h))
            h = max(wetThreshold, h)
            denseHeights[i] = h
        }

        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)
    }
}
