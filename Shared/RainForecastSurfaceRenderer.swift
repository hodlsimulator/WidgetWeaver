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

        let edgeFactors = RainSurfaceMath.edgeFactors(
            sampleCount: n,
            startEaseMinutes: configuration.startEaseMinutes,
            endFadeMinutes: configuration.endFadeMinutes,
            endFadeFloor: configuration.endFadeFloor
        )

        var wetMask = [Bool](repeating: false, count: n)
        var heights = [CGFloat](repeating: 0, count: n)
        var intensityNorm = [Double](repeating: 0, count: n)
        var certainty = [Double](repeating: 0, count: n)

        for i in 0..<n {
            let rawI = max(0.0, intensities[i])
            let c = RainSurfaceMath.clamp01(certainties[i])
            certainty[i] = c

            let isWet = rawI > configuration.wetThreshold
            wetMask[i] = isWet
            guard isWet else { continue }

            let frac = min(rawI / intensityCap, 1.0)
            let eased = pow(frac, configuration.intensityEasingPower)
            let edge = edgeFactors[i]

            intensityNorm[i] = eased * edge

            var h = CGFloat(eased) * maxHeight
            if h > 0 { h = max(h, minVisibleHeight) }
            h *= CGFloat(edge)

            heights[i] = h
        }

        if configuration.geometrySmoothingPasses > 0 {
            heights = RainSurfaceMath.smooth(heights, passes: configuration.geometrySmoothingPasses)
        }

        for i in 0..<n {
            if heights[i] <= 0.000_01 {
                wetMask[i] = false
                intensityNorm[i] = 0.0
            }
        }

        let ranges = RainSurfaceGeometry.wetRanges(from: wetMask)
        guard !ranges.isEmpty else {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                configuration: configuration,
                displayScale: displayScale
            )
            return
        }

        let segments: [WetSegment] = ranges.map { range in
            let surfacePath = RainSurfaceGeometry.makeSurfacePath(
                for: range,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights
            )
            let topEdgePath = RainSurfaceGeometry.makeTopEdgePath(
                for: range,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights
            )
            return WetSegment(range: range, surfacePath: surfacePath, topEdgePath: topEdgePath)
        }

        RainSurfaceDrawing.drawBaseline(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )

        RainSurfaceDrawing.drawFill(
            in: &context,
            rect: rect,
            baselineY: baselineY,
            segments: segments,
            configuration: configuration
        )

        if configuration.textureEnabled {
            RainSurfaceDrawing.drawInternalGrainIfEnabled(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                segments: segments,
                heights: heights,
                intensityNorm: intensityNorm,
                certainty: certainty,
                edgeFactors: edgeFactors,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        if configuration.fuzzEnabled {
            RainSurfaceDrawing.drawUncertaintyMist(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                segments: segments,
                heights: heights,
                intensityNorm: intensityNorm,
                certainty: certainty,
                edgeFactors: edgeFactors,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        if configuration.glowEnabled {
            RainSurfaceDrawing.drawGlow(
                in: &context,
                maxHeight: maxHeight,
                segments: segments,
                intensityNorm: intensityNorm,
                certainty: certainty,
                configuration: configuration,
                displayScale: displayScale
            )
        }
    }
}
