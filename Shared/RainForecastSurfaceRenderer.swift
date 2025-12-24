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
        let range: Range<Int>
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

        let maxHeight = max(0, baselineY - rect.minY)
        guard maxHeight > 0 else { return }

        let minVisibleHeight = max(0, maxHeight * configuration.minVisibleHeightFraction)
        let intensityCap = max(configuration.intensityCap, 0.000_001)

        let stepX = plotRect.width / CGFloat(n)
        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        // Rendering-only edge fade (start/end of horizon).
        let edgeFactors = RainSurfaceMath.edgeFactors(
            sampleCount: n,
            startEaseMinutes: configuration.startEaseMinutes,
            endFadeMinutes: configuration.endFadeMinutes,
            endFadeFloor: configuration.endFadeFloor
        )

        // Raw arrays (before taper / smoothing).
        var rawWetMask = [Bool](repeating: false, count: n)
        var rawIntensityNorm = [Double](repeating: 0, count: n)
        var certainty = [Double](repeating: 0, count: n)

        for i in 0..<n {
            let c = RainSurfaceMath.clamp01(certainties[i])
            certainty[i] = c

            let rawI = max(0.0, intensities[i])
            guard rawI > configuration.wetThreshold else { continue }

            rawWetMask[i] = true

            let frac = min(rawI / intensityCap, 1.0)
            let eased = pow(frac, configuration.intensityEasingPower)
            rawIntensityNorm[i] = eased
        }

        // Segment-aware taper so rain falls to baseline gracefully instead of a vertical cliff.
        let rawRanges = RainSurfaceGeometry.wetRanges(from: rawWetMask)

        var taperedIntensityNorm = rawIntensityNorm
        var taperedCertainty = certainty

        // Longer tails than before (prevents the ugly hard stop).
        let startTaper = max(0, min(14, max(configuration.startEaseMinutes + 4, 10)))
        let endTaper = max(0, min(18, max(configuration.endFadeMinutes + 6, 14)))

        if startTaper > 0 || endTaper > 0 {
            for r in rawRanges {
                if r.isEmpty { continue }

                let startIdx = r.lowerBound
                let endIdx = max(startIdx, r.upperBound - 1)

                // Leading taper (into earlier dry minutes).
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

                // Trailing taper (into later dry minutes).
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

        // Mild smoothing after taper to avoid any kinks.
        let intensitySmoothPasses = max(1, configuration.geometrySmoothingPasses + 1)
        let certaintySmoothPasses = 1

        let intensityNorm = RainSurfaceMath.smooth(taperedIntensityNorm, passes: intensitySmoothPasses)
        let certaintySmoothed = RainSurfaceMath.smooth(taperedCertainty, passes: certaintySmoothPasses)

        // Build heights from smoothed intensity.
        // minVisibleHeight applies only to original wet points so taper tails can reach baseline.
        var heights = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])

            var h = CGFloat(inorm) * maxHeight

            // Horizon start/end easing affects geometry as well.
            h *= CGFloat(RainSurfaceMath.clamp01(edgeFactors[i]))

            if rawWetMask[i], h > 0 {
                h = max(h, minVisibleHeight)
            }

            heights[i] = h
        }

        // Determine wet mask from geometry (includes taper).
        let epsilon = max(onePixel * 0.20, maxHeight * 0.0012)

        var wetMask = [Bool](repeating: false, count: n)
        for i in 0..<n {
            wetMask[i] = heights[i] > epsilon
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
