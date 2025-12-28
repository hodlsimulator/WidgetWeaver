//
// RainForecastSurfaceRenderer.swift
// WidgetWeaver
//
// Created by . . on 12/23/25.
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

        // The template expects a dark chart region; this keeps blend modes predictable.
        context.fill(Path(chartRect), with: .color(.black))

        guard chartRect.width > 2, chartRect.height > 2 else { return }

        guard !intensities.isEmpty else {
            let y = RainSurfaceMath.alignToPixelCenter(chartRect.midY, displayScale: displayScale)
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                chartRect: chartRect,
                baselineY: y,
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

        // MARK: - Geometry setup

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

        // MARK: - Intensity → height

        let nonNeg: [Double] = intensities.map { v in
            guard v.isFinite else { return 0.0 }
            return (v > 0.0) ? v : 0.0
        }
        let positive = nonNeg.filter { $0 > 0.0 }

        let referenceMaxMMPerHour: Double = {
            let ref = configuration.intensityReferenceMaxMMPerHour
            if ref.isFinite, ref > 0.0 { return ref }

            let p = RainSurfaceMath.clamp01(configuration.robustMaxPercentile)
            if !positive.isEmpty {
                let robust = RainSurfaceMath.percentile(positive, p: p)
                if robust.isFinite, robust > 0.0 { return robust }
            }

            let fallback = positive.max() ?? 0.0
            return max(0.000_001, fallback)
        }()

        let invReferenceMax = 1.0 / max(0.000_001, referenceMaxMMPerHour)
        let gamma = max(0.10, min(2.50, configuration.intensityGamma))

        let minuteHeights: [CGFloat] = (0..<nMinutes).map { i in
            let intensity = nonNeg[i]
            if intensity <= 0.0 { return 0.0 }

            var r = intensity * invReferenceMax
            if !r.isFinite { r = 0.0 }
            r = max(0.0, r)

            let t = pow(r, gamma)

            let c = (i < safeCertainties.count) ? RainSurfaceMath.clamp01(safeCertainties[i]) : 1.0
            let certaintyWeight = 0.35 + 0.65 * pow(c, 0.70)

            let h = CGFloat(t) * heightScale * CGFloat(certaintyWeight)
            guard h.isFinite else { return 0.0 }
            return min(maxHeight, max(0.0, h))
        }

        // Dense sampling scales with pixels, capped for widgets.
        let scale = max(1.0, displayScale)
        let denseFromPixels = Int(max(12.0, Double(chartRect.width * scale)))
        let targetDense = max(12, min(configuration.maxDenseSamples, denseFromPixels))

        var denseHeights = RainSurfaceMath.resampleMonotoneCubic(minuteHeights, targetCount: targetDense)
        var denseCertainties = RainSurfaceMath.resampleMonotoneCubic(safeCertainties, targetCount: targetDense)
        denseCertainties = denseCertainties.map { RainSurfaceMath.clamp01($0) }

        // Keep smoothing light; heavy smoothing makes low-variation hours read as a slab.
        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)

        RainSurfaceMath.applyEdgeEasing(
            to: &denseHeights,
            fraction: configuration.edgeEasingFraction,
            power: configuration.edgeEasingPower
        )

        let onePixel = 1.0 / max(1.0, scale)

        RainSurfaceMath.applyWetSegmentEasing(
            to: &denseHeights,
            threshold: onePixel * 0.10,
            fraction: max(configuration.edgeEasingFraction, 0.12),
            power: configuration.edgeEasingPower
        )

        // If the “core” of the wet region is effectively flat, add deterministic relief so it
        // reads like a surface instead of a dead-straight band.
        denseHeights = applyFlatPlateauReliefIfNeeded(
            heights: denseHeights,
            certainties: denseCertainties,
            maxHeight: maxHeight,
            heightScale: heightScale,
            onePixel: onePixel
        )

        // MARK: - Draw

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

    // MARK: - Plateau relief

    private func applyFlatPlateauReliefIfNeeded(
        heights: [CGFloat],
        certainties: [Double],
        maxHeight: CGFloat,
        heightScale: CGFloat,
        onePixel: CGFloat
    ) -> [CGFloat] {
        guard heights.count >= 24 else { return heights }

        let wetThreshold = onePixel * 0.12

        var wetCount = 0
        var wetMin: CGFloat = .greatestFiniteMagnitude
        var wetMax: CGFloat = 0.0

        for h in heights where h > wetThreshold {
            wetCount += 1
            wetMin = min(wetMin, h)
            wetMax = max(wetMax, h)
        }

        guard wetCount >= 14, wetMax > wetThreshold else { return heights }

        let flatTrigger = max(onePixel * 3.0, heightScale * 0.08)

        var isEffectivelyFlat = (wetMax - wetMin) < flatTrigger

        // Ends often taper (by design), which can hide a dead-flat middle if only wetMin/wetMax is checked.
        // Detect a flat “core” by looking near the top of the wet envelope.
        if !isEffectivelyFlat {
            let coreCut = max(wetThreshold, wetMax * 0.75)

            var coreMin: CGFloat = .greatestFiniteMagnitude
            var coreMax: CGFloat = 0.0
            var coreCount = 0

            for h in heights where h > coreCut {
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

        guard isEffectivelyFlat else { return heights }

        // Deterministic amplitude: strong enough to break the slab, small enough to stay “physical”.
        let amp = min(maxHeight * 0.16, max(onePixel * 4.0, wetMax * 0.10))

        let meanCertainty: Double = {
            guard !certainties.isEmpty else { return 1.0 }
            let s = certainties.reduce(0.0, +)
            return RainSurfaceMath.clamp01(s / Double(certainties.count))
        }()
        let certaintyMul = 0.70 + 0.30 * (1.0 - meanCertainty)   // [0.70, 1.0]
        let finalAmp = amp * CGFloat(certaintyMul)

        var prng = RainSurfacePRNG(
            seed: RainSurfacePRNG.combine(configuration.noiseSeed, 0xA1D3_CE55_9B27_4F1D)
        )

        // Smooth value-noise along X (two bands, mixed).
        let n = heights.count

        let cells1 = max(8, min(64, n / 10))
        let step1 = Double(max(1, n - 1)) / Double(cells1)
        var ctrl1: [CGFloat] = []
        ctrl1.reserveCapacity(cells1 + 2)
        for _ in 0..<(cells1 + 2) {
            ctrl1.append(CGFloat(prng.nextSignedFloat()))
        }

        let cells2 = max(8, min(96, n / 6))
        let step2 = Double(max(1, n - 1)) / Double(cells2)
        var ctrl2: [CGFloat] = []
        ctrl2.reserveCapacity(cells2 + 2)
        for _ in 0..<(cells2 + 2) {
            ctrl2.append(CGFloat(prng.nextSignedFloat()))
        }

        @inline(__always)
        func valueNoise(_ i: Int, ctrl: [CGFloat], step: Double) -> CGFloat {
            let x = Double(i) / step
            let k = max(0, min(ctrl.count - 2, Int(floor(x))))
            let t = x - Double(k)
            let s = RainSurfaceMath.smoothstep01(t)
            return RainSurfaceMath.lerp(ctrl[k], ctrl[k + 1], CGFloat(s))
        }

        var out = heights

        for i in 0..<n {
            let h = heights[i]
            guard h > wetThreshold else { continue }

            let n1 = valueNoise(i, ctrl: ctrl1, step: step1)
            let n2 = valueNoise(i, ctrl: ctrl2, step: step2)
            let noise = (0.70 * n1) + (0.30 * n2)   // ~[-1, 1]

            // Weight noise by height so tapering ends stay clean.
            let wn = RainSurfaceMath.clamp01((h - wetThreshold) / max(onePixel, wetMax - wetThreshold))
            let w = 0.30 + 0.70 * pow(Double(wn), 0.85)

            var nh = h + finalAmp * CGFloat(w) * noise
            if !nh.isFinite { nh = h }
            nh = min(maxHeight, max(0.0, nh))
            out[i] = nh
        }

        return out
    }
}
