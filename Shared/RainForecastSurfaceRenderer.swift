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

        // Preserve unknown buckets as NaN.
        let rawIntensities: [Double] = intensities.map { v in
            guard v.isFinite else { return Double.nan }
            return max(0.0, v)
        }

        // Rendering continuity only: fill unknowns by interpolation/hold, but fade them out via certainty.
        let filledIntensities = RainSurfaceMath.fillMissingLinearHoldEnds(rawIntensities)
        let minuteCertainties = makeMinuteCertainties(rawIntensities: rawIntensities, inputCertainties: certainties)

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

        let positiveKnown = rawIntensities.filter { $0.isFinite && $0 > 0.0 }
        let referenceMaxMMPerHour: Double = {
            let ref = configuration.intensityReferenceMaxMMPerHour
            if ref.isFinite, ref > 0.0 { return max(1.0, ref) }

            let p = RainSurfaceMath.clamp01(configuration.robustMaxPercentile)
            if !positiveKnown.isEmpty {
                let robust = RainSurfaceMath.percentile(positiveKnown, p: p)
                if robust.isFinite, robust > 0.0 { return max(1.0, robust) }
            }

            let fallback = positiveKnown.max() ?? 0.0
            return max(1.0, fallback)
        }()

        let invReferenceMax = 1.0 / max(0.000_001, referenceMaxMMPerHour)
        let gamma = max(0.10, min(2.50, configuration.intensityGamma))
        let onePixel = 1.0 / max(1.0, displayScale)

        @inline(__always)
        func softCeil(_ h: CGFloat, ceiling: CGFloat) -> CGFloat {
            guard h.isFinite, ceiling.isFinite, ceiling > 0 else { return 0.0 }
            if h <= ceiling { return max(0.0, h) }

            // Soft-knee near the top avoids hard clipping artefacts when intensity exceeds the reference max.
            let kneeStartFraction: CGFloat = 0.92
            let kneeStart = ceiling * kneeStartFraction
            if h <= kneeStart { return h }

            let available = ceiling - kneeStart
            if available <= max(onePixel, 0.000_5) { return ceiling }

            let x = (h - kneeStart) / available
            let y = kneeStart + available * CGFloat(tanh(Double(x)))
            return min(ceiling, max(0.0, y.isFinite ? y : ceiling))
        }

        let asinh1 = RainSurfaceMath.asinh(1.0)

        // Height is driven by intensity only (unknowns filled for continuity).
        let minuteHeights: [CGFloat] = filledIntensities.map { intensity in
            guard intensity.isFinite, intensity > 0.0 else { return 0.0 }

            var r = intensity * invReferenceMax
            if !r.isFinite { r = 0.0 }
            r = max(0.0, r)

            let t: Double
            if r <= 1.0 {
                t = pow(r, gamma)
            } else {
                let compressed = (asinh1 > 0.0) ? (RainSurfaceMath.asinh(r) / asinh1) : r
                t = pow(max(0.0, compressed), gamma)
            }

            var h = CGFloat(t) * heightScale
            if !h.isFinite { h = 0.0 }
            h = max(0.0, h)
            return softCeil(h, ceiling: maxHeight)
        }

        let targetDense = max(
            12,
            min(configuration.maxDenseSamples, Int(max(12.0, chartRect.width * max(1.0, displayScale))))
        )

        var denseHeights = RainSurfaceMath.resampleMonotoneCubicCenters(minuteHeights, targetCount: targetDense)
        var denseCertainties = RainSurfaceMath.resampleMonotoneCubicCenters(minuteCertainties, targetCount: targetDense)
            .map { RainSurfaceMath.clamp01($0) }

        // Small smoothing keeps fades continuous and reduces seam artefacts.
        denseCertainties = RainSurfaceMath.smooth(denseCertainties, windowRadius: 2, passes: 1)
            .map { RainSurfaceMath.clamp01($0) }

        // Minimal smoothing; keeps the curve faithful to minute data while avoiding pixel jitter.
        denseHeights = RainSurfaceMath.smooth(denseHeights, windowRadius: 1, passes: 1)

        // Optional easing (caller-controlled via configuration.edgeEasingFraction).
        RainSurfaceMath.applyEdgeEasing(
            to: &denseHeights,
            fraction: configuration.edgeEasingFraction,
            power: configuration.edgeEasingPower
        )

        // Always apply a tiny local easing at wet boundaries to avoid guillotine-looking drops.
        let minBoundaryFraction = CGFloat(2.0) / CGFloat(max(1, nMinutes))
        RainSurfaceMath.applyWetSegmentEasing(
            to: &denseHeights,
            threshold: onePixel * 0.10,
            fraction: max(configuration.edgeEasingFraction, minBoundaryFraction),
            power: configuration.edgeEasingPower
        )

        // Snap sub-pixel heights to zero to avoid a faint “baseline band”.
        if onePixel.isFinite {
            let snap = onePixel * 0.10
            for i in 0..<denseHeights.count {
                if denseHeights[i] < snap { denseHeights[i] = 0.0 }
            }
        }

        let geometry = RainSurfaceGeometry(
            chartRect: chartRect,
            baselineY: baselineY,
            heights: denseHeights,
            certainties: denseCertainties,
            displayScale: displayScale
        )

        let maskStopsCap: Int = (configuration.maxDenseSamples <= 280) ? 220 : 360
        let needsMask: Bool = denseCertainties.contains { maskAlpha(from: $0) < 0.999 }

        context.drawLayer { layer in
            var layerCtx = layer
            RainSurfaceDrawing.drawSurface(
                in: &layerCtx,
                geometry: geometry,
                configuration: configuration,
                displayScale: displayScale
            )

            if needsMask {
                layerCtx.blendMode = .destinationIn
                let grad = makeMaskGradient(denseCertainties: denseCertainties, maxStops: maskStopsCap)

                var rectPath = Path()
                rectPath.addRect(chartRect)

                layerCtx.fill(
                    rectPath,
                    with: .linearGradient(
                        grad,
                        startPoint: CGPoint(x: chartRect.minX, y: chartRect.midY),
                        endPoint: CGPoint(x: chartRect.maxX, y: chartRect.midY)
                    )
                )
            }
        }

        RainSurfaceDrawing.drawBaseline(
            in: &context,
            chartRect: chartRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )
    }

    private func makeMinuteCertainties(rawIntensities: [Double], inputCertainties: [Double]) -> [Double] {
        let n = rawIntensities.count
        let aligned: [Double] = {
            if inputCertainties.count == n { return inputCertainties }
            if inputCertainties.isEmpty { return Array(repeating: Double.nan, count: n) }
            var c = inputCertainties
            if c.count < n {
                c.append(contentsOf: Array(repeating: c.last ?? Double.nan, count: n - c.count))
            } else if c.count > n {
                c = Array(c.prefix(n))
            }
            return c
        }()

        var out: [Double] = []
        out.reserveCapacity(n)

        for i in 0..<n {
            let intensityKnown = rawIntensities[i].isFinite
            if !intensityKnown {
                out.append(0.0)
                continue
            }

            let c = aligned[i]
            if c.isFinite {
                out.append(RainSurfaceMath.clamp01(c))
            } else {
                out.append(1.0)
            }
        }

        return out
    }

    private func makeMaskGradient(denseCertainties: [Double], maxStops: Int) -> Gradient {
        let n = denseCertainties.count
        guard n > 1 else {
            let a = maskAlpha(from: denseCertainties.first ?? 1.0)
            return Gradient(stops: [
                .init(color: Color.white.opacity(a), location: 0.0),
                .init(color: Color.white.opacity(a), location: 1.0)
            ])
        }

        let stopCount = max(6, min(maxStops, n))
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(stopCount)

        if stopCount == n {
            for i in 0..<n {
                let loc = Double(i) / Double(n - 1)
                let a = maskAlpha(from: denseCertainties[i])
                stops.append(.init(color: Color.white.opacity(a), location: loc))
            }
        } else {
            let step = Double(n - 1) / Double(stopCount - 1)
            for j in 0..<stopCount {
                let idx = max(0, min(n - 1, Int(round(Double(j) * step))))
                let loc = Double(idx) / Double(n - 1)
                let a = maskAlpha(from: denseCertainties[idx])
                stops.append(.init(color: Color.white.opacity(a), location: loc))
            }
        }

        return Gradient(stops: stops)
    }

    private func maskAlpha(from certainty: Double) -> Double {
        let c = RainSurfaceMath.clamp01(certainty)
        if c <= 0.000_5 { return 0.0 }

        // Lift mid certainties to avoid crushed interiors; preserves 0 for missing/unknown.
        let exponent: Double = 0.55
        return RainSurfaceMath.clamp01(pow(c, exponent))
    }
}
