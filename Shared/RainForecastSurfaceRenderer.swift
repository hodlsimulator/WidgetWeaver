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

    let configuration: RainForecastSurfaceConfiguration

    init(configuration: RainForecastSurfaceConfiguration) {
        self.configuration = configuration
    }

    func render(
        in context: inout GraphicsContext,
        rect: CGRect,
        rawMinuteIntensities: [Double?],
        rawMinuteCertainties: [Double?]
    ) {
        let cfg = configuration

        // Fill missing intensities WITHOUT collapsing the visual height to baseline.
        // Styling will handle uncertainty; height remains intensity-driven.
        let filled = fillMissingLinearHoldEnds(rawMinuteIntensities)
        let minuteIntensities = filled.values
        let minuteCertainties = makeMinuteCertainties(
            rawIntensity: rawMinuteIntensities,
            rawCertainty: rawMinuteCertainties,
            filledIntensity: minuteIntensities
        )

        // Determine where the “wet window” actually begins/ends based on raw intensities.
        // This is used only for styling tails; it must never alter the height series.
        let sourceMinutes = max(1, minuteIntensities.count)
        let (tailStartX, tailEndX) = computeWetTailBoundsX(
            rect: rect,
            rawMinuteIntensities: rawMinuteIntensities,
            sourceMinutes: sourceMinutes,
            cfg: cfg
        )

        // Geometry build
        let geom = makeGeometry(
            rect: rect,
            minuteIntensities: minuteIntensities,
            minuteCertainties: minuteCertainties,
            tailStartX: tailStartX,
            tailEndX: tailEndX,
            cfg: cfg
        )

        // Draw
        RainSurfaceDrawing.drawSurface(
            in: &context,
            geometry: geom,
            configuration: cfg
        )
    }

    // MARK: - Certainty handling

    private func makeMinuteCertainties(
        rawIntensity: [Double?],
        rawCertainty: [Double?],
        filledIntensity: [Double]
    ) -> [Double] {
        let n = max(rawIntensity.count, filledIntensity.count, rawCertainty.count)
        if n == 0 { return [] }

        var out: [Double] = Array(repeating: 1.0, count: n)

        for i in 0..<n {
            let ri: Double? = (i < rawIntensity.count) ? rawIntensity[i] : nil
            let rc: Double? = (i < rawCertainty.count) ? rawCertainty[i] : nil

            if ri == nil {
                // Missing intensity: treat as UNKNOWN for styling.
                // (Height is already filled from neighbours.)
                out[i] = 0.0
            } else if let c = rc {
                out[i] = max(0.0, min(1.0, c))
            } else {
                // No certainty provided: assume fully certain.
                out[i] = 1.0
            }
        }

        return out
    }

    // MARK: - Wet tail bounds (styling only)

    private func computeWetTailBoundsX(
        rect: CGRect,
        rawMinuteIntensities: [Double?],
        sourceMinutes: Int,
        cfg: RainForecastSurfaceConfiguration
    ) -> (CGFloat?, CGFloat?) {
        guard sourceMinutes > 1 else { return (nil, nil) }

        let wetEps = max(0.000_001, cfg.wetEpsilon)
        let minutes = rawMinuteIntensities.count
        if minutes == 0 { return (nil, nil) }

        var firstWetMinuteIndex: Int? = nil
        var lastWetMinuteIndex: Int? = nil

        for i in 0..<minutes {
            if let v = rawMinuteIntensities[i], v > wetEps {
                firstWetMinuteIndex = i
                break
            }
        }
        for i in stride(from: minutes - 1, through: 0, by: -1) {
            if let v = rawMinuteIntensities[i], v > wetEps {
                lastWetMinuteIndex = i
                break
            }
        }

        guard let firstWet = firstWetMinuteIndex, let lastWet = lastWetMinuteIndex, lastWet >= firstWet else {
            return (nil, nil)
        }

        let x0 = rect.minX
        let x1 = rect.maxX
        let t0 = CGFloat(firstWet) / CGFloat(max(1, sourceMinutes - 1))
        let t1 = CGFloat(lastWet) / CGFloat(max(1, sourceMinutes - 1))

        let sx = x0 + (x1 - x0) * t0
        let ex = x0 + (x1 - x0) * t1

        return (sx, ex)
    }

    // MARK: - Geometry build

    private func makeGeometry(
        rect: CGRect,
        minuteIntensities: [Double],
        minuteCertainties: [Double],
        tailStartX: CGFloat?,
        tailEndX: CGFloat?,
        cfg: RainForecastSurfaceConfiguration
    ) -> RainSurfaceGeometry {
        let n = max(minuteIntensities.count, minuteCertainties.count)
        if n == 0 {
            return RainSurfaceGeometry(
                chartRect: rect,
                baselineY: rect.maxY,
                yValues: [],
                certainties: [],
                tailStartX: tailStartX,
                tailEndX: tailEndX
            )
        }

        // Heights are derived only from intensity.
        // Certainty/chance never alters the height series.
        let heights = makeHeights(
            minuteIntensities: minuteIntensities,
            rect: rect,
            cfg: cfg
        )

        // Certainties are clamped and interpolated to match geometry sampling.
        let certainties = makeCertainties(
            minuteCertainties: minuteCertainties,
            count: heights.count
        )

        return RainSurfaceGeometry(
            chartRect: rect,
            baselineY: rect.maxY,
            yValues: heights,
            certainties: certainties,
            tailStartX: tailStartX,
            tailEndX: tailEndX
        )
    }

    private func makeHeights(
        minuteIntensities: [Double],
        rect: CGRect,
        cfg: RainForecastSurfaceConfiguration
    ) -> [CGFloat] {
        let minutes = minuteIntensities.count
        guard minutes > 0 else { return [] }

        let sampleCount = max(2, cfg.sampleCount)
        let baselineY = rect.maxY
        let maxH = max(0.0, rect.height)

        // Map intensity (0..1-ish) to height fraction.
        // Keep this purely intensity-driven.
        let intensityGain = max(0.0, cfg.intensityGain)
        let intensityGamma = max(0.01, cfg.intensityGamma)

        var raw: [CGFloat] = Array(repeating: 0.0, count: sampleCount)

        for i in 0..<sampleCount {
            let t = (sampleCount <= 1) ? 0.0 : Double(i) / Double(sampleCount - 1)
            let srcX = t * Double(max(1, minutes - 1))

            let i0 = Int(floor(srcX))
            let i1 = min(minutes - 1, i0 + 1)
            let f = srcX - Double(i0)

            let v0 = (i0 < minutes) ? minuteIntensities[i0] : 0.0
            let v1 = (i1 < minutes) ? minuteIntensities[i1] : v0

            let v = v0 * (1.0 - f) + v1 * f

            let vn = max(0.0, v) * intensityGain
            let shaped = pow(min(1.0, vn), intensityGamma)

            raw[i] = CGFloat(shaped) * CGFloat(maxH)
        }

        // Smoothing (still height-only; do not use certainty here).
        if cfg.smoothingPasses > 0, cfg.smoothingWindowRadius > 0 {
            let smoothed = RainSurfaceMath.smooth(
                raw,
                windowRadius: cfg.smoothingWindowRadius,
                passes: cfg.smoothingPasses
            )
            raw = smoothed
        }

        // Apply wet epsilon to avoid micro speck noise turning into “wet”.
        let wetEpsPx = max(0.000_001, CGFloat(cfg.wetEpsilon) * rect.height)
        for i in 0..<raw.count {
            if raw[i] < wetEpsPx { raw[i] = 0 }
        }

        // Convert height to yValue (absolute Y).
        // baselineY - height.
        return raw.map { baselineY - $0 }
    }

    private func makeCertainties(
        minuteCertainties: [Double],
        count: Int
    ) -> [Double] {
        let minutes = minuteCertainties.count
        if minutes == 0 || count == 0 { return Array(repeating: 1.0, count: count) }
        if minutes == 1 { return Array(repeating: max(0.0, min(1.0, minuteCertainties[0])), count: count) }

        var out: [Double] = Array(repeating: 1.0, count: count)

        for i in 0..<count {
            let t = (count <= 1) ? 0.0 : Double(i) / Double(count - 1)
            let srcX = t * Double(minutes - 1)

            let i0 = Int(floor(srcX))
            let i1 = min(minutes - 1, i0 + 1)
            let f = srcX - Double(i0)

            let c0 = max(0.0, min(1.0, minuteCertainties[i0]))
            let c1 = max(0.0, min(1.0, minuteCertainties[i1]))

            out[i] = c0 * (1.0 - f) + c1 * f
        }

        return out
    }

    // MARK: - Missing fill

    private func fillMissingLinearHoldEnds(_ input: [Double?]) -> (values: [Double], wasMissing: [Bool]) {
        let n = input.count
        if n == 0 { return ([], []) }

        var out: [Double] = Array(repeating: 0.0, count: n)
        var miss: [Bool] = Array(repeating: false, count: n)

        // Identify runs of missing.
        var lastKnownIndex: Int? = nil
        var lastKnownValue: Double = 0.0

        for i in 0..<n {
            if let v = input[i] {
                out[i] = v
                lastKnownIndex = i
                lastKnownValue = v
            } else {
                miss[i] = true
            }
        }

        // Fill leading missing with first known (hold).
        if let firstKnown = input.firstIndex(where: { $0 != nil }) {
            let v = input[firstKnown] ?? 0.0
            for i in 0..<firstKnown {
                out[i] = v
            }
        }

        // Fill trailing missing with last known (hold).
        if let lastKnown = input.lastIndex(where: { $0 != nil }) {
            let v = input[lastKnown] ?? 0.0
            if lastKnown + 1 < n {
                for i in (lastKnown + 1)..<n {
                    out[i] = v
                }
            }
        }

        // Fill interior gaps linearly between known neighbours.
        var i = 0
        while i < n {
            if input[i] != nil {
                i += 1
                continue
            }

            // Start of a missing run.
            let start = i
            while i < n && input[i] == nil { i += 1 }
            let end = i - 1

            // Neighbour bounds
            let leftIndex = start - 1
            let rightIndex = i

            if leftIndex >= 0, rightIndex < n, let lv = input[leftIndex], let rv = input[rightIndex] {
                let runLen = rightIndex - leftIndex
                if runLen > 0 {
                    for k in start...end {
                        let t = Double(k - leftIndex) / Double(runLen)
                        out[k] = lv * (1.0 - t) + rv * t
                    }
                }
            } else if leftIndex >= 0, let lv = input[leftIndex] {
                for k in start...end { out[k] = lv }
            } else if rightIndex < n, let rv = input[rightIndex] {
                for k in start...end { out[k] = rv }
            } else {
                // All missing; leave at 0.
                for k in start...end { out[k] = 0.0 }
            }
        }

        _ = lastKnownIndex
        _ = lastKnownValue
        return (out, miss)
    }
}

