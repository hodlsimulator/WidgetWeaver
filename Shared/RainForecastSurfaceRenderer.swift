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

        let availableAboveBaseline = max(0, baselineY - plotRect.minY)
        guard availableAboveBaseline > 0 else { return }

        // Step 1: scale cap is defined against plot height (not the baseline height).
        let fracCap = max(0.0, min(1.0, configuration.maxCoreHeightFractionOfPlotHeight))
        var maxCoreHeight = plotRect.height * fracCap
        maxCoreHeight = min(maxCoreHeight, availableAboveBaseline)

        if configuration.maxCoreHeightPoints > 0 {
            maxCoreHeight = min(maxCoreHeight, max(0.0, configuration.maxCoreHeightPoints))
        }

        guard maxCoreHeight > 0.5 else {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                configuration: configuration,
                displayScale: displayScale
            )
            return
        }

        let minVisibleHeight = max(0, maxCoreHeight * configuration.minVisibleHeightFraction)

        let intensityCap = max(configuration.intensityCap, 0.000_001)
        let stepX = plotRect.width / CGFloat(n)
        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        // Raw arrays
        var rawWetMask = [Bool](repeating: false, count: n)
        var intensityNorm = [Double](repeating: 0, count: n)
        var certainty = [Double](repeating: 0, count: n)

        for i in 0..<n {
            let rawI = max(0.0, intensities[i])
            let c = RainSurfaceMath.clamp01(certainties[i])
            certainty[i] = c

            guard rawI > configuration.wetThreshold else { continue }
            rawWetMask[i] = true

            let v = min(rawI / intensityCap, 1.0)
            intensityNorm[i] = pow(v, configuration.intensityEasingPower)
        }

        // If no rain, baseline only.
        if rawWetMask.allSatisfy({ !$0 }) {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                configuration: configuration,
                displayScale: displayScale
            )
            return
        }

        // Build heights from shaped values.
        var heights = [CGFloat](repeating: 0, count: n)
        for i in 0..<n {
            var h = CGFloat(RainSurfaceMath.clamp01(intensityNorm[i])) * maxCoreHeight
            if rawWetMask[i], h > 0 {
                h = max(h, minVisibleHeight)
            }
            heights[i] = h
        }

        // Mild smoothing keeps the silhouette stable without inflating into a block.
        if configuration.geometrySmoothingPasses > 0 {
            heights = RainSurfaceMath.smooth(heights, passes: configuration.geometrySmoothingPasses)
            for i in 0..<n { heights[i] = min(maxCoreHeight, max(0.0, heights[i])) }
        }

        // Step 2: wet-region taper mask (applies to core, ridge, mist, glow).
        let firstWet = rawWetMask.firstIndex(where: { $0 }) ?? 0
        let lastWet = rawWetMask.lastIndex(where: { $0 }) ?? (n - 1)

        let fadeIn = max(0, configuration.wetRegionFadeInSamples)
        let fadeOut = max(0, configuration.wetRegionFadeOutSamples)

        var horizontalTaper = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            // Outside wet region is fully suppressed.
            if i < firstWet || i > lastWet {
                horizontalTaper[i] = 0.0
                heights[i] = 0.0
                continue
            }

            var s: Double = 1.0
            if fadeIn > 0 {
                let t = Double(i - firstWet) / Double(max(1, fadeIn))
                s *= RainSurfaceMath.smoothstep01(t)
            }

            var e: Double = 1.0
            if fadeOut > 0 {
                let t = Double(lastWet - i) / Double(max(1, fadeOut))
                e *= RainSurfaceMath.smoothstep01(t)
            }

            let f = RainSurfaceMath.clamp01(s * e)
            horizontalTaper[i] = f
            heights[i] *= CGFloat(f)
        }

        // Extra softening at each wet segment boundary (internal cliffs).
        let epsilon = max(onePixel * 0.18, maxCoreHeight * 0.0015)

        var wetMask = [Bool](repeating: false, count: n)
        for i in 0..<n { wetMask[i] = heights[i] > epsilon }

        if configuration.segmentEdgeTaperSamples > 0 {
            let ranges = RainSurfaceGeometry.wetRanges(from: wetMask)
            let kTaper = max(1, configuration.segmentEdgeTaperSamples)
            let p = max(0.25, configuration.segmentEdgeTaperPower)

            for r in ranges {
                let count = r.count
                if count <= 1 { continue }

                let kMax = min(kTaper, max(1, count / 2))
                if kMax <= 0 { continue }

                // Leading edge
                for o in 0..<kMax {
                    let idx = r.lowerBound + o
                    if idx < 0 || idx >= n { continue }
                    let u = Double(o + 1) / Double(kMax + 1)
                    let f = pow(RainSurfaceMath.smoothstep01(u), p)
                    heights[idx] *= CGFloat(f)
                }

                // Trailing edge
                for o in 0..<kMax {
                    let idx = (r.upperBound - 1) - o
                    if idx < 0 || idx >= n { continue }
                    let u = Double(o + 1) / Double(kMax + 1)
                    let f = pow(RainSurfaceMath.smoothstep01(u), p)
                    heights[idx] *= CGFloat(f)
                }
            }

            for i in 0..<n { wetMask[i] = heights[i] > epsilon }
        }

        let wetRanges = RainSurfaceGeometry.wetRanges(from: wetMask)
        if wetRanges.isEmpty {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                configuration: configuration,
                displayScale: displayScale
            )
            return
        }

        // Smooth certainty slightly for steadier mist/ridge behaviour.
        let certaintySmoothed = RainSurfaceMath.smooth(certainty, passes: 1)

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

        // 3 masks + 3 passes happen inside RainSurfaceDrawing.
        RainSurfaceDrawing.drawProbabilityMaskedSurface(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            stepX: stepX,
            segments: segments,
            heights: heights,
            intensityNorm: intensityNorm,
            certainty: certaintySmoothed,
            edgeFactors: horizontalTaper,
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
            edgeFactors: horizontalTaper,
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
