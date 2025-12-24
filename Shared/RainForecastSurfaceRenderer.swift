//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Forecast surface rendering core (WidgetKit-safe).
//

import Foundation
import SwiftUI

struct RainForecastSurfaceRenderer {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration
    let displayScale: CGFloat

    struct WetSegment {
        let range: Swift.Range<Int>
        let surfacePath: Path
        let topEdgePath: Path
    }

    func render(in context: inout GraphicsContext, size: CGSize) {
        let n = min(intensities.count, certainties.count)
        guard n > 0 else { return }

        let rect = CGRect(origin: .zero, size: size)

        if configuration.backgroundOpacity > 0 {
            var bg = Path()
            bg.addRect(rect)
            context.fill(bg, with: .color(configuration.backgroundColor.opacity(configuration.backgroundOpacity)))
        }

        let insetX = max(0, rect.width * configuration.edgeInsetFraction)
        let plotRect = rect.insetBy(dx: insetX, dy: 0)
        guard plotRect.width > 0, plotRect.height > 0 else { return }

        var baselineY = rect.minY + rect.height * configuration.baselineYFraction
        baselineY = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        let availableHeight = max(0, baselineY - rect.minY)
        guard availableHeight > 0 else { return }

        let heightScale = max(0.0, min(1.0, configuration.surfaceHeightScale))
        let maxHeight = max(0.0, availableHeight * heightScale)

        let minVisibleHeight = max(0, maxHeight * configuration.minVisibleHeightFraction)

        let capBase = max(configuration.intensityCap, 0.000_001)
        let capHeadroom = max(0.0, configuration.intensityCapHeadroomFraction)
        let intensityCap = capBase * (1.0 + capHeadroom)

        let stepX = plotRect.width / CGFloat(n)
        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        // Rendering-only horizon fade
        let edgeFactors = RainSurfaceMath.edgeFactors(
            sampleCount: n,
            startEaseMinutes: configuration.startEaseMinutes,
            endFadeMinutes: configuration.endFadeMinutes,
            endFadeFloor: configuration.endFadeFloor
        )

        // Raw arrays (before taper/smoothing)
        var rawWetMask = [Bool](repeating: false, count: n)
        var rawIntensityNorm = [Double](repeating: 0, count: n)
        var certainty = [Double](repeating: 0, count: n)

        for i in 0..<n {
            let rawI = max(0.0, intensities[i])
            certainty[i] = RainSurfaceMath.clamp01(certainties[i])

            guard rawI > configuration.wetThreshold else { continue }

            rawWetMask[i] = true
            let frac = min(rawI / intensityCap, 1.0)
            let eased = pow(frac, configuration.intensityEasingPower)
            rawIntensityNorm[i] = eased
        }

        // Segment-aware taper into neighbouring dry minutes so rain falls to baseline gracefully.
        let rawRanges = RainSurfaceGeometry.wetRanges(from: rawWetMask)
        var taperedIntensityNorm = rawIntensityNorm
        var taperedCertainty = certainty

        let startTaper = max(0, min(14, max(configuration.startEaseMinutes + 4, 10)))
        let endTaper = max(0, min(18, max(configuration.endFadeMinutes + 6, 14)))

        if startTaper > 0 || endTaper > 0 {
            for r in rawRanges {
                if r.isEmpty { continue }

                let startIdx = r.lowerBound
                let endIdx = max(startIdx, r.upperBound - 1)

                // Leading taper (into earlier dry minutes)
                if startTaper > 0 {
                    let anchorI = taperedIntensityNorm[startIdx]
                    let anchorC = taperedCertainty[startIdx]
                    if anchorI > 0 {
                        for k in 1...startTaper {
                            let idx = startIdx - k
                            if idx < 0 { break }
                            let t = Double(k) / Double(startTaper + 1) // 0..1
                            let f = pow(max(0.0, 1.0 - t), 2.15)
                            taperedIntensityNorm[idx] = max(taperedIntensityNorm[idx], anchorI * f)
                            taperedCertainty[idx] = max(taperedCertainty[idx], anchorC * f)
                        }
                    }
                }

                // Trailing taper (into later dry minutes)
                if endTaper > 0 {
                    let anchorI = taperedIntensityNorm[endIdx]
                    let anchorC = taperedCertainty[endIdx]
                    if anchorI > 0 {
                        for k in 1...endTaper {
                            let idx = endIdx + k
                            if idx >= n { break }
                            let t = Double(k) / Double(endTaper + 1)
                            let f = pow(max(0.0, 1.0 - t), 2.20)
                            taperedIntensityNorm[idx] = max(taperedIntensityNorm[idx], anchorI * f)
                            taperedCertainty[idx] = max(taperedCertainty[idx], anchorC * f)
                        }
                    }
                }
            }
        }

        // Mild smoothing after taper to avoid kinks.
        let intensitySmoothPasses = max(1, configuration.geometrySmoothingPasses + 1)
        let certaintySmoothPasses = 1
        let intensityNorm = RainSurfaceMath.smooth(taperedIntensityNorm, passes: intensitySmoothPasses)
        let certaintySmoothed = RainSurfaceMath.smooth(taperedCertainty, passes: certaintySmoothPasses)

        // Build heights (minVisibleHeight applies only to original wet points)
        var heights = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            var h = CGFloat(RainSurfaceMath.clamp01(intensityNorm[i])) * maxHeight
            if rawWetMask[i], h > 0 {
                h = max(h, minVisibleHeight)
            }
            heights[i] = h
        }

        // Determine wet mask from geometry (includes taper)
        let epsilon = max(onePixel * 0.20, maxHeight * 0.0012)
        var wetMask = [Bool](repeating: false, count: n)
        for i in 0..<n {
            wetMask[i] = heights[i] > epsilon
        }

        // New: taper inside each wet segment so there are no hard cliffs at segment boundaries.
        if configuration.segmentEdgeTaperSamples > 0 {
            let rangesBefore = RainSurfaceGeometry.wetRanges(from: wetMask)
            let taperCount = max(0, configuration.segmentEdgeTaperSamples)
            let taperPower = max(0.25, configuration.segmentEdgeTaperPower)

            if taperCount > 0 {
                for r in rangesBefore {
                    let count = r.count
                    if count <= 1 { continue }

                    let kMax = min(taperCount, max(1, count / 2))
                    if kMax <= 0 { continue }

                    // Leading
                    for o in 0..<kMax {
                        let idx = r.lowerBound + o
                        if idx < 0 || idx >= n { continue }
                        let u = Double(o + 1) / Double(kMax + 1) // 0..1
                        let s = pow(RainSurfaceMath.smoothstep01(u), taperPower)
                        heights[idx] *= CGFloat(s)
                    }

                    // Trailing
                    for o in 0..<kMax {
                        let idx = (r.upperBound - 1) - o
                        if idx < 0 || idx >= n { continue }
                        let u = Double(o + 1) / Double(kMax + 1)
                        let s = pow(RainSurfaceMath.smoothstep01(u), taperPower)
                        heights[idx] *= CGFloat(s)
                    }
                }
            }

            // Recompute wetMask after taper
            for i in 0..<n {
                wetMask[i] = heights[i] > epsilon
            }
        }

        let wetRanges = RainSurfaceGeometry.wetRanges(from: wetMask)

        var segments: [WetSegment] = []
        segments.reserveCapacity(wetRanges.count)

        for r in wetRanges {
            let surface = RainSurfaceGeometry.makeSurfacePath(
                for: r,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights
            )
            let top = RainSurfaceGeometry.makeTopEdgePath(
                for: r,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights
            )
            segments.append(.init(range: r, surfacePath: surface, topEdgePath: top))
        }

        RainSurfaceDrawing.drawProbabilityMaskedSurface(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            stepX: stepX,
            segments: segments,
            heights: heights,
            intensityNorm: intensityNorm,
            certainty: certaintySmoothed,
            edgeFactors: edgeFactors,
            configuration: configuration,
            displayScale: displayScale
        )

        RainSurfaceDrawing.drawGlowIfEnabled(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            stepX: stepX,
            segments: segments,
            heights: heights,
            intensityNorm: intensityNorm,
            certainty: certaintySmoothed,
            edgeFactors: edgeFactors,
            configuration: configuration,
            displayScale: displayScale
        )

        RainSurfaceDrawing.drawBaseline(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )
    }
}
