//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Converts minute intensities -> surface geometry and draws using RainSurfaceDrawing.
//

import SwiftUI

struct RainForecastSurfaceRenderer {
    let intensities: [Double]
    let certainties: [Double?]
    let configuration: RainForecastSurfaceConfiguration

    init(
        intensities: [Double],
        certainties: [Double?] = [],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
    }

    func render(in context: inout GraphicsContext, rect: CGRect, displayScale: CGFloat) {
        var cfg = configuration
        cfg.sourceMinuteCount = intensities.count

        let ds = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0
        guard rect.width > 1.0, rect.height > 1.0 else { return }

        let baselineY = rect.minY + rect.height * CGFloat(clamp01(cfg.baselineFractionFromTop))
        let chartRect = rect

        // No data: just the baseline (if enabled).
        guard !intensities.isEmpty else {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                configuration: cfg,
                displayScale: ds
            )
            return
        }

        let (filledIntensities, missingMask) = fillMissingLinearHoldEnds(intensities)
        let referenceMax = robustReferenceMaxMMPerHour(
            values: filledIntensities,
            defaultMax: cfg.intensityReferenceMaxMMPerHour,
            percentile: cfg.robustMaxPercentile
        )

        let maxHeight = maxUsableHeight(chartRect: chartRect, baselineY: baselineY, cfg: cfg)
        let minuteHeights = makeMinuteHeights(
            intensities: filledIntensities,
            referenceMax: referenceMax,
            maxHeight: maxHeight,
            gamma: cfg.intensityGamma
        )
        let minuteCertainties = makeMinuteCertainties(
            sourceCount: intensities.count,
            certainties: certainties,
            missingMask: missingMask
        )

        let targetCount = denseSampleCount(
            chartRect: chartRect,
            displayScale: ds,
            sourceCount: minuteHeights.count,
            cfg: cfg
        )

        let denseHeights = resampleLinear(values: minuteHeights, targetCount: targetCount)
        let denseCertainties = resampleLinear(values: minuteCertainties, targetCount: targetCount)

        let geometry = RainSurfaceGeometry(
            chartRect: chartRect,
            baselineY: baselineY,
            heights: denseHeights,
            certainties: denseCertainties,
            displayScale: ds
        )

        RainSurfaceDrawing.drawSurface(in: &context, geometry: geometry, configuration: cfg)

        // Baseline drawn last so it stays crisp.
        RainSurfaceDrawing.drawBaseline(
            in: &context,
            chartRect: chartRect,
            baselineY: baselineY,
            configuration: cfg,
            displayScale: ds
        )
    }

    // MARK: - Heights

    private func maxUsableHeight(chartRect: CGRect, baselineY: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let topY = chartRect.minY + chartRect.height * CGFloat(clamp01(cfg.topHeadroomFraction))
        let available = max(0.0, baselineY - topY)
        return available * CGFloat(clamp01(cfg.typicalPeakFraction))
    }

    private func makeMinuteHeights(
        intensities: [Double],
        referenceMax: Double,
        maxHeight: CGFloat,
        gamma: Double
    ) -> [CGFloat] {
        guard !intensities.isEmpty else { return [] }

        let ref = max(0.000_001, referenceMax)
        let g = max(0.10, gamma)

        return intensities.map { raw in
            let v = max(0.0, raw.isFinite ? raw : 0.0)
            let n = clamp01(v / ref)
            // Gamma in [~1.2] lifts lighter rain slightly while preserving peaks.
            let shaped = pow(n, 1.0 / g)
            return maxHeight * CGFloat(shaped)
        }
    }

    // MARK: - Certainty / chance (styling only)

    private func makeMinuteCertainties(
        sourceCount: Int,
        certainties: [Double?],
        missingMask: [Bool]
    ) -> [Double] {
        guard sourceCount > 0 else { return [] }

        var result: [Double] = Array(repeating: 1.0, count: sourceCount)

        for i in 0..<sourceCount {
            if i < certainties.count, let c = certainties[i], c.isFinite {
                result[i] = clamp01(c)
            } else {
                result[i] = 1.0
            }

            // Missing minutes are treated as "unknown": keep height continuity, but avoid
            // strong styling cues by leaning towards high certainty.
            if i < missingMask.count, missingMask[i] {
                result[i] = max(result[i], 0.85)
            }
        }
        return result
    }

    // MARK: - Sampling

    private func denseSampleCount(
        chartRect: CGRect,
        displayScale: CGFloat,
        sourceCount: Int,
        cfg: RainForecastSurfaceConfiguration
    ) -> Int {
        let wPx = Double(max(1.0, chartRect.width * displayScale))
        // Aim for smoothness without blowing widget budgets.
        let desired = max(sourceCount, Int(wPx * 1.9))
        return max(2, min(cfg.maxDenseSamples, desired))
    }

    private func resampleLinear(values: [CGFloat], targetCount: Int) -> [CGFloat] {
        guard targetCount > 0 else { return [] }
        guard values.count > 1 else { return Array(repeating: values.first ?? 0.0, count: targetCount) }
        if values.count == targetCount { return values }

        let n = values.count
        let denom = Double(max(1, targetCount - 1))
        let srcDenom = Double(max(1, n - 1))

        var out: [CGFloat] = []
        out.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let t = Double(i) / denom
            let srcPos = t * srcDenom
            let i0 = min(n - 2, max(0, Int(floor(srcPos))))
            let f = CGFloat(srcPos - Double(i0))
            let a = values[i0]
            let b = values[i0 + 1]
            out.append(a + (b - a) * f)
        }
        return out
    }

    private func resampleLinear(values: [Double], targetCount: Int) -> [Double] {
        guard targetCount > 0 else { return [] }
        guard values.count > 1 else { return Array(repeating: values.first ?? 0.0, count: targetCount) }
        if values.count == targetCount { return values }

        let n = values.count
        let denom = Double(max(1, targetCount - 1))
        let srcDenom = Double(max(1, n - 1))

        var out: [Double] = []
        out.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            let t = Double(i) / denom
            let srcPos = t * srcDenom
            let i0 = min(n - 2, max(0, Int(floor(srcPos))))
            let f = srcPos - Double(i0)
            let a = values[i0]
            let b = values[i0 + 1]
            out.append(a + (b - a) * f)
        }
        return out
    }

    // MARK: - Missing fill

    private func fillMissingLinearHoldEnds(_ values: [Double]) -> (filled: [Double], missingMask: [Bool]) {
        let n = values.count
        guard n > 0 else { return ([], []) }

        var filled = values
        var missing = values.map { !$0.isFinite }

        guard let firstKnown = values.firstIndex(where: { $0.isFinite }) else {
            return (Array(repeating: 0.0, count: n), Array(repeating: true, count: n))
        }

        // Hold start.
        for i in 0..<firstKnown {
            filled[i] = values[firstKnown]
            missing[i] = true
        }

        var lastKnown = firstKnown
        if !filled[lastKnown].isFinite { filled[lastKnown] = 0.0 }

        // Fill gaps.
        if lastKnown + 1 < n {
            for i in (lastKnown + 1)..<n {
                if values[i].isFinite {
                    let a = values[lastKnown]
                    let b = values[i]
                    let gap = i - lastKnown
                    if gap > 1 {
                        for j in 1..<gap {
                            let t = Double(j) / Double(gap)
                            filled[lastKnown + j] = a + (b - a) * t
                            missing[lastKnown + j] = true
                        }
                    }
                    filled[i] = values[i]
                    lastKnown = i
                }
            }
        }

        // Hold end.
        if lastKnown < n - 1 {
            for i in (lastKnown + 1)..<n {
                filled[i] = values[lastKnown]
                missing[i] = true
            }
        }

        // Sanitise.
        for i in 0..<n {
            if !filled[i].isFinite { filled[i] = 0.0 }
            if filled[i] < 0.0 { filled[i] = 0.0 }
        }
        return (filled, missing)
    }

    // MARK: - Robust scale

    private func robustReferenceMaxMMPerHour(values: [Double], defaultMax: Double, percentile: Double) -> Double {
        let finite = values.filter { $0.isFinite && $0 > 0.0 }
        guard !finite.isEmpty else { return max(0.000_001, defaultMax) }

        let p = clamp01(percentile)
        let sorted = finite.sorted()
        let idx = min(sorted.count - 1, max(0, Int(round(p * Double(sorted.count - 1)))))
        let v = sorted[idx]
        return max(0.000_001, max(defaultMax, v))
    }

    private func clamp01(_ x: Double) -> Double {
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }
}
