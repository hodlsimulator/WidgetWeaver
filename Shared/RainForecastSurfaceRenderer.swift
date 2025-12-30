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
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration
    let displayScale: CGFloat

    func render(in context: inout GraphicsContext, size: CGSize) {
        guard size.width.isFinite, size.height.isFinite, size.width > 0.5, size.height > 0.5 else { return }

        let cfg = configuration
        let scale = max(1.0, displayScale)

        let chartRect = CGRect(origin: .zero, size: size)

        let baselineY0 = chartRect.minY + chartRect.height * CGFloat(cfg.baselineFractionFromTop)
        let baselineY = RainSurfaceMath.alignToPixelCenter(baselineY0, displayScale: scale)

        guard !intensities.isEmpty else {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                configuration: cfg,
                displayScale: scale
            )
            return
        }

        let nMinutes = intensities.count
        let rawIntensity: [Double] = intensities.map { v in
            if v.isFinite { return max(0.0, v) }
            return Double.nan
        }

        let filled = fillMissingLinearHoldEnds(rawIntensity)
        let minuteHeights = makeMinuteHeights(
            filledIntensity: filled.filled,
            chartRect: chartRect,
            baselineY: baselineY,
            cfg: cfg,
            displayScale: scale
        )

        let minuteCertainties = makeMinuteCertainties(
            rawIntensity: rawIntensity,
            inputCertainties: certainties,
            minuteCount: nMinutes
        )

        // Determine the last wet minute using height semantics (intensity-only) and known (non-missing) minutes.
        let onePx = 1.0 / max(1.0, scale)
        let wetEps = CGFloat(onePx * 0.5)
        var lastWetMinuteIndex: Int? = nil
        if nMinutes >= 1 {
            for i in 0..<nMinutes {
                if rawIntensity[i].isFinite, minuteHeights[i] > wetEps {
                    lastWetMinuteIndex = i
                }
            }
        }

        let tailMinutes = max(2, min(6, cfg.fuzzTailMinutes))
        let minuteDx = (nMinutes <= 1) ? chartRect.width : (chartRect.width / CGFloat(nMinutes - 1))
        let tailStartX: CGFloat?
        let tailEndX: CGFloat?
        if let lastWetMinuteIndex, nMinutes >= 2, tailMinutes > 0 {
            let sx = chartRect.minX + CGFloat(lastWetMinuteIndex) * minuteDx
            let ex = min(chartRect.maxX, sx + CGFloat(tailMinutes) * minuteDx)
            if ex > sx + onePx {
                tailStartX = sx
                tailEndX = ex
            } else {
                tailStartX = nil
                tailEndX = nil
            }
        } else {
            tailStartX = nil
            tailEndX = nil
        }

        // Dense resample (budgeted).
        let denseCount = denseSampleCount(
            minuteCount: nMinutes,
            widthPx: chartRect.width * scale,
            maxDenseSamples: cfg.maxDenseSamples
        )

        let denseHeights = resampleMonotoneCubicCenters(minuteHeights, targetCount: denseCount)
        let denseCertainties = smoothDouble(
            resampleLinearCenters(minuteCertainties, targetCount: denseCount),
            radius: 2
        )

        let easedHeights = applyEdgeEasing(
            smoothCGFloat(denseHeights, radius: 2),
            fraction: cfg.edgeEasingFraction,
            power: cfg.edgeEasingPower
        ).map { h in
            (h < wetEps) ? 0.0 : h
        }

        let geometry = RainSurfaceGeometry(
            chartRect: chartRect,
            baselineY: baselineY,
            heights: easedHeights,
            certainties: denseCertainties,
            displayScale: scale,
            sourceMinuteCount: nMinutes,
            tailStartX: tailStartX,
            tailEndX: tailEndX
        )

        RainSurfaceDrawing.drawSurface(in: &context, geometry: geometry, configuration: cfg)
        RainSurfaceDrawing.drawBaseline(in: &context, chartRect: chartRect, baselineY: baselineY, configuration: cfg, displayScale: scale)
    }
}

// MARK: - Internals
private extension RainForecastSurfaceRenderer {
    struct FilledSeries {
        let filled: [Double]
        let wasMissing: [Bool]
    }

    func fillMissingLinearHoldEnds(_ raw: [Double]) -> FilledSeries {
        let n = raw.count
        guard n > 0 else { return FilledSeries(filled: [], wasMissing: []) }

        let wasMissing = raw.map { !$0.isFinite }

        guard let firstKnown = raw.firstIndex(where: { $0.isFinite }) else {
            return FilledSeries(filled: Array(repeating: 0.0, count: n), wasMissing: wasMissing)
        }

        var out = raw

        // Leading hold.
        let firstVal = raw[firstKnown]
        if firstKnown > 0 {
            for i in 0..<firstKnown { out[i] = firstVal }
        }

        // Interior linear fill.
        var prevKnown = firstKnown
        var i = firstKnown + 1
        while i < n {
            if raw[i].isFinite {
                let nextKnown = i
                let a = raw[prevKnown]
                let b = raw[nextKnown]
                let gap = nextKnown - prevKnown
                if gap >= 2 {
                    for k in 1..<(gap) {
                        let t = Double(k) / Double(gap)
                        out[prevKnown + k] = a + (b - a) * t
                    }
                }
                prevKnown = nextKnown
            }
            i += 1
        }

        // Trailing hold.
        let lastKnown = prevKnown
        let lastVal = raw[lastKnown]
        if lastKnown < n - 1 {
            for j in (lastKnown + 1)..<n { out[j] = lastVal }
        }

        // Ensure finite.
        out = out.map { v in
            if v.isFinite { return max(0.0, v) }
            return 0.0
        }

        return FilledSeries(filled: out, wasMissing: wasMissing)
    }

    func makeMinuteCertainties(rawIntensity: [Double], inputCertainties: [Double], minuteCount: Int) -> [Double] {
        var out: [Double] = Array(repeating: 0.0, count: minuteCount)

        for i in 0..<minuteCount {
            // Missing intensity buckets fade via styling.
            if i < rawIntensity.count, !rawIntensity[i].isFinite {
                out[i] = 0.0
                continue
            }

            if i < inputCertainties.count, inputCertainties[i].isFinite {
                out[i] = RainSurfaceMath.clamp01(inputCertainties[i])
            } else {
                out[i] = 1.0
            }
        }
        return out
    }

    func robustReferenceMax(intensities: [Double], cfg: RainForecastSurfaceConfiguration) -> Double {
        let fallback = max(1.0, cfg.intensityReferenceMaxMMPerHour.isFinite ? cfg.intensityReferenceMaxMMPerHour : 1.0)
        let positive = intensities.filter { $0.isFinite && $0 > 0.0 }
        guard !positive.isEmpty else { return fallback }

        let p = RainSurfaceMath.percentile(positive, p: RainSurfaceMath.clamp01(cfg.robustMaxPercentile))
        if p.isFinite, p > 0.0 { return max(1.0, p) }
        return fallback
    }

    func makeMinuteHeights(
        filledIntensity: [Double],
        chartRect: CGRect,
        baselineY: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) -> [CGFloat] {
        let n = filledIntensity.count
        guard n > 0 else { return [] }

        let scale = max(1.0, displayScale)
        let onePx = 1.0 / scale

        let baselineDist = max(onePx, baselineY - chartRect.minY)
        let headroom = max(0.0, baselineDist * CGFloat(max(0.0, cfg.topHeadroomFraction)))
        let maxHeight = max(onePx, baselineDist - headroom)

        let typicalPeakY = chartRect.minY + chartRect.height * CGFloat(cfg.typicalPeakFraction)
        let typicalPeakHeight = max(onePx, baselineY - typicalPeakY)
        let targetPeakHeight = min(maxHeight, typicalPeakHeight)

        let refMax = robustReferenceMax(intensities: filledIntensity, cfg: cfg)
        let gamma = max(0.08, cfg.intensityGamma)

        func softSaturate(_ hRaw: CGFloat, cap: CGFloat) -> CGFloat {
            let c = max(onePx, cap)
            let x = max(0.0, hRaw)
            // Smooth saturation; linear near 0, asymptotic near cap.
            return c * (1.0 - exp(-x / c))
        }

        var heights: [CGFloat] = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            let v = filledIntensity[i]
            if !v.isFinite || v <= 0.0 {
                heights[i] = 0.0
                continue
            }

            let norm = max(0.0, v / max(0.000_001, refMax))
            let shaped = pow(norm, gamma)

            let hRaw = CGFloat(shaped) * targetPeakHeight
            heights[i] = softSaturate(hRaw, cap: maxHeight)
        }
        return heights
    }

    func denseSampleCount(minuteCount: Int, widthPx: CGFloat, maxDenseSamples: Int) -> Int {
        let w = Int(max(12.0, widthPx.rounded(.toNearestOrAwayFromZero)))
        let cap = max(12, maxDenseSamples)
        let base = max(12, max(minuteCount, w))
        return max(12, min(cap, base))
    }

    func resampleLinearCenters(_ values: [Double], targetCount: Int) -> [Double] {
        let n = values.count
        guard targetCount > 0 else { return [] }
        guard n >= 2 else { return Array(repeating: (n == 1 ? values[0] : 0.0), count: targetCount) }
        guard targetCount >= 2 else { return [values[0]] }

        let maxX = Double(n - 1)
        var out: [Double] = Array(repeating: 0.0, count: targetCount)
        for j in 0..<targetCount {
            let x = (Double(j) / Double(targetCount - 1)) * maxX
            let i = Int(floor(x))
            let t = x - Double(i)
            if i >= n - 1 {
                out[j] = values[n - 1]
            } else {
                let a = values[i]
                let b = values[i + 1]
                out[j] = a + (b - a) * t
            }
        }
        return out
    }

    func resampleMonotoneCubicCenters(_ values: [CGFloat], targetCount: Int) -> [CGFloat] {
        let n = values.count
        guard targetCount > 0 else { return [] }
        guard n >= 2 else { return Array(repeating: (n == 1 ? values[0] : 0.0), count: targetCount) }
        guard targetCount >= 2 else { return [values[0]] }

        // Uniform x spacing (dx = 1).
        var d: [CGFloat] = Array(repeating: 0.0, count: n - 1)
        for i in 0..<(n - 1) { d[i] = values[i + 1] - values[i] }

        var m: [CGFloat] = Array(repeating: 0.0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        if n >= 3 {
            for i in 1..<(n - 1) {
                let a = d[i - 1]
                let b = d[i]
                if a == 0.0 || b == 0.0 || (a > 0 && b < 0) || (a < 0 && b > 0) {
                    m[i] = 0.0
                } else {
                    // Harmonic mean.
                    m[i] = (2.0 * a * b) / (a + b)
                }
            }
        }

        func hermite(_ y0: CGFloat, _ y1: CGFloat, _ m0: CGFloat, _ m1: CGFloat, _ t: CGFloat) -> CGFloat {
            let t2 = t * t
            let t3 = t2 * t
            let h00 = 2.0 * t3 - 3.0 * t2 + 1.0
            let h10 = t3 - 2.0 * t2 + t
            let h01 = -2.0 * t3 + 3.0 * t2
            let h11 = t3 - t2
            return h00 * y0 + h10 * m0 + h01 * y1 + h11 * m1
        }

        let maxX = CGFloat(n - 1)
        var out: [CGFloat] = Array(repeating: 0.0, count: targetCount)
        for j in 0..<targetCount {
            let x = (CGFloat(j) / CGFloat(targetCount - 1)) * maxX
            let i = Int(floor(Double(x)))
            let t = x - CGFloat(i)
            if i >= n - 1 {
                out[j] = values[n - 1]
            } else {
                out[j] = hermite(values[i], values[i + 1], m[i], m[i + 1], t)
            }
        }

        // Clamp to non-negative.
        return out.map { $0.isFinite ? max(0.0, $0) : 0.0 }
    }

    func smoothCGFloat(_ values: [CGFloat], radius: Int) -> [CGFloat] {
        let n = values.count
        guard n > 0, radius > 0 else { return values }
        let r = min(12, radius)

        var prefix: [CGFloat] = Array(repeating: 0.0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + values[i] }

        func sum(_ a: Int, _ b: Int) -> CGFloat { prefix[b] - prefix[a] }

        var out: [CGFloat] = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            let lo = max(0, i - r)
            let hi = min(n, i + r + 1)
            let c = CGFloat(hi - lo)
            out[i] = sum(lo, hi) / max(1.0, c)
        }
        return out
    }

    func smoothDouble(_ values: [Double], radius: Int) -> [Double] {
        let n = values.count
        guard n > 0, radius > 0 else { return values }
        let r = min(12, radius)

        var prefix: [Double] = Array(repeating: 0.0, count: n + 1)
        for i in 0..<n { prefix[i + 1] = prefix[i] + values[i] }

        func sum(_ a: Int, _ b: Int) -> Double { prefix[b] - prefix[a] }

        var out: [Double] = Array(repeating: 0.0, count: n)
        for i in 0..<n {
            let lo = max(0, i - r)
            let hi = min(n, i + r + 1)
            let c = Double(hi - lo)
            out[i] = sum(lo, hi) / max(1.0, c)
        }
        return out.map { $0.isFinite ? RainSurfaceMath.clamp01($0) : 0.0 }
    }

    func applyEdgeEasing(_ values: [CGFloat], fraction: Double, power: Double) -> [CGFloat] {
        let n = values.count
        guard n >= 2 else { return values }
        let f = max(0.0, min(0.45, fraction))
        guard f > 0.000_1 else { return values }

        let p = max(0.10, power)

        var out = values
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            let left = RainSurfaceMath.clamp01(t / max(0.000_001, f))
            let right = RainSurfaceMath.clamp01((1.0 - t) / max(0.000_001, f))

            let wL = pow(RainSurfaceMath.smoothstep01(left), p)
            let wR = pow(RainSurfaceMath.smoothstep01(right), p)

            let w = min(1.0, wL * wR)
            out[i] = out[i] * CGFloat(w)
        }
        return out
    }
}
