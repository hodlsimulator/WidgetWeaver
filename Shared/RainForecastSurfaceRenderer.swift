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

        var baselineY = plotRect.minY + plotRect.height * configuration.baselineYFraction
        baselineY = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        let availableAboveBaseline = max(0, baselineY - plotRect.minY)
        guard availableAboveBaseline > 0 else { return }

        // Height mapping MUST be plot-rect based.
        let fracCap = max(0.0, min(1.0, configuration.maxCoreHeightFractionOfPlotHeight))
        var maxCoreHeight = plotRect.height * fracCap
        maxCoreHeight = min(maxCoreHeight, availableAboveBaseline)

        if configuration.maxCoreHeightPoints > 0 {
            maxCoreHeight = min(maxCoreHeight, max(0.0, configuration.maxCoreHeightPoints))
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let minVisibleHeight = max(onePixel * 0.50, maxCoreHeight * configuration.minVisibleHeightFraction)

        let intensityCap = max(configuration.intensityCap, 0.000_001)
        let stepX = plotRect.width / CGFloat(n)

        // Raw per-sample values
        var rawWetMask = [Bool](repeating: false, count: n)
        var intensityNorm = [Double](repeating: 0.0, count: n)
        var certainty = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let rawI = max(0.0, intensities[i])
            certainty[i] = RainSurfaceMath.clamp01(certainties[i])

            guard rawI > configuration.wetThreshold else { continue }

            rawWetMask[i] = true
            let v = min(rawI / intensityCap, 1.0)
            intensityNorm[i] = pow(v, configuration.intensityEasingPower)
        }

        // Baseline behind everything (supports the surface, does not compete).
        RainSurfaceDrawing.drawBaseline(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )

        // If fully dry, stop here.
        if rawWetMask.allSatisfy({ !$0 }) { return }

        // Heights from shaped values (NO end-taper height squashing).
        var heights = [CGFloat](repeating: 0.0, count: n)
        for i in 0..<n {
            var h = CGFloat(RainSurfaceMath.clamp01(intensityNorm[i])) * maxCoreHeight
            if rawWetMask[i], h > 0 {
                h = max(h, minVisibleHeight)
            }
            heights[i] = min(maxCoreHeight, max(0.0, h))
        }

        // Mild smoothing for stability.
        if configuration.geometrySmoothingPasses > 0 {
            heights = RainSurfaceMath.smooth(heights, passes: configuration.geometrySmoothingPasses)
            for i in 0..<n { heights[i] = min(maxCoreHeight, max(0.0, heights[i])) }
        }

        // Segment drop settling: extend short geometric tails into neighbouring dry samples.
        let tailIn = max(0, configuration.geometryTailInSamples)
        let tailOut = max(0, configuration.geometryTailOutSamples)
        let tailPow = max(0.50, configuration.geometryTailPower)

        if tailIn > 0 || tailOut > 0 {
            let rawRanges = RainSurfaceGeometry.wetRanges(from: rawWetMask)

            for r in rawRanges {
                if r.isEmpty { continue }

                let start = r.lowerBound
                let end = max(start, r.upperBound - 1)

                let hStart = heights[start]
                let hEnd = heights[end]

                // Leading tail
                if tailIn > 0, hStart > onePixel {
                    for k in 1...tailIn {
                        let idx = start - k
                        if idx < 0 { break }
                        if rawWetMask[idx] { break }

                        let t = Double(k) / Double(tailIn + 1)
                        let f = pow(max(0.0, 1.0 - t), tailPow)
                        let hh = hStart * CGFloat(f)

                        if hh > heights[idx] {
                            heights[idx] = hh
                        }
                    }
                }

                // Trailing tail
                if tailOut > 0, hEnd > onePixel {
                    for k in 1...tailOut {
                        let idx = end + k
                        if idx >= n { break }
                        if rawWetMask[idx] { break }

                        let t = Double(k) / Double(tailOut + 1)
                        let f = pow(max(0.0, 1.0 - t), tailPow)
                        let hh = hEnd * CGFloat(f)

                        if hh > heights[idx] {
                            heights[idx] = hh
                        }
                    }
                }
            }
        }

        // Wet mask from geometry.
        let epsilon = max(onePixel * 0.18, maxCoreHeight * 0.0015)
        var wetMask = [Bool](repeating: false, count: n)
        for i in 0..<n { wetMask[i] = heights[i] > epsilon }

        let wetRanges = RainSurfaceGeometry.wetRanges(from: wetMask)
        if wetRanges.isEmpty { return }

        // End tapers are ALPHA ONLY.
        let firstWet = wetMask.firstIndex(where: { $0 }) ?? 0
        let lastWet = wetMask.lastIndex(where: { $0 }) ?? (n - 1)

        let fadeIn = max(0, configuration.wetRegionFadeInSamples)
        let fadeOut = max(0, configuration.wetRegionFadeOutSamples)

        var alphaTaper = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            if i < firstWet || i > lastWet { alphaTaper[i] = 0.0 }
            else { alphaTaper[i] = 1.0 }
        }

        if fadeIn > 0 {
            let end = min(lastWet, firstWet + fadeIn)
            if end >= firstWet {
                for i in firstWet...end {
                    let t = Double(i - firstWet) / Double(max(1, fadeIn))
                    alphaTaper[i] *= RainSurfaceMath.smoothstep01(t)
                }
            }
        }

        if fadeOut > 0 {
            let start = max(firstWet, lastWet - fadeOut)
            if lastWet >= start {
                for i in start...lastWet {
                    let t = Double(lastWet - i) / Double(max(1, fadeOut))
                    alphaTaper[i] *= RainSurfaceMath.smoothstep01(t)
                }
            }
        }

        // Build segments (paths from geometry only).
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

        // Smooth certainty slightly for steadier uncertainty signals.
        let certaintySmoothed = RainSurfaceMath.smooth(certainty, passes: 1)

        RainSurfaceDrawing.drawProbabilityMaskedSurface(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            stepX: stepX,
            segments: segments,
            heights: heights,
            intensityNorm: intensityNorm,
            certainty: certaintySmoothed,
            edgeFactors: alphaTaper,
            configuration: configuration,
            displayScale: displayScale
        )
    }
}
