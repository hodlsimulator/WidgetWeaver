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
        let n0 = min(intensities.count, certainties.count)

        let rect = CGRect(origin: .zero, size: size)
        guard rect.width > 1, rect.height > 1 else { return }

        // Spec: background is always true black.
        var bg = Path()
        bg.addRect(rect)
        context.fill(bg, with: .color(.black))

        guard n0 > 0 else {
            // Baseline still anchors the chart.
            let plotRect = rect
            let baselineY = RainSurfaceMath.alignToPixelCenter(plotRect.minY + plotRect.height * 0.596, displayScale: displayScale)
            RainSurfaceDrawing.drawBaseline(in: &context, plotRect: plotRect, baselineY: baselineY, configuration: configuration, displayScale: displayScale)
            return
        }

        let insetX = max(0, rect.width * configuration.edgeInsetFraction)
        let plotRect = rect.insetBy(dx: insetX, dy: 0)
        guard plotRect.width > 0, plotRect.height > 0 else { return }

        // Spec: fixed baseline ratio.
        var baselineY = plotRect.minY + plotRect.height * 0.596
        baselineY = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        let availableAboveBaseline = max(0, baselineY - plotRect.minY)
        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        // Spec: fixed height budget (≈19–20% of rect height above baseline).
        var maxCoreHeight = plotRect.height * 0.195
        maxCoreHeight = min(maxCoreHeight, availableAboveBaseline)
        if configuration.maxCoreHeightPoints > 0 {
            maxCoreHeight = min(maxCoreHeight, max(0.0, configuration.maxCoreHeightPoints))
        }
        maxCoreHeight = max(onePixel, maxCoreHeight)

        let minVisibleHeight = max(onePixel * 0.60, maxCoreHeight * configuration.minVisibleHeightFraction)

        // Raw per-sample values (coarse)
        let intensityCap = max(configuration.intensityCap, 0.000_001)

        var rawWetMask = [Bool](repeating: false, count: n0)
        var intensityNorm = [Double](repeating: 0.0, count: n0)
        var certainty = [Double](repeating: 0.0, count: n0)

        for i in 0..<n0 {
            let rawI = max(0.0, intensities[i])
            let c = RainSurfaceMath.clamp01(certainties[i])
            certainty[i] = c

            guard rawI > configuration.wetThreshold else { continue }
            guard c > 0 else { continue }

            rawWetMask[i] = true
            let v = min(rawI / intensityCap, 1.0)
            intensityNorm[i] = pow(v, configuration.intensityEasingPower)
        }

        // If fully dry, draw baseline only.
        if rawWetMask.allSatisfy({ !$0 }) {
            RainSurfaceDrawing.drawBaseline(in: &context, plotRect: plotRect, baselineY: baselineY, configuration: configuration, displayScale: displayScale)
            return
        }

        // Heights from shaped values (no end-taper height squashing).
        var heights = [CGFloat](repeating: 0.0, count: n0)
        for i in 0..<n0 {
            var h = CGFloat(RainSurfaceMath.clamp01(intensityNorm[i])) * maxCoreHeight
            if rawWetMask[i], h > 0 {
                h = max(h, minVisibleHeight)
            }
            heights[i] = min(maxCoreHeight, max(0.0, h))
        }

        // Mild smoothing.
        if configuration.geometrySmoothingPasses > 0 {
            heights = RainSurfaceMath.smooth(heights, passes: configuration.geometrySmoothingPasses)
            for i in 0..<n0 { heights[i] = min(maxCoreHeight, max(0.0, heights[i])) }
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

                if tailIn > 0, hStart > onePixel {
                    for k in 1...tailIn {
                        let idx = start - k
                        if idx < 0 { break }
                        if rawWetMask[idx] { break }

                        let t = Double(k) / Double(tailIn + 1)
                        let f = pow(max(0.0, 1.0 - t), tailPow)
                        let hh = hStart * CGFloat(f)
                        if hh > heights[idx] { heights[idx] = hh }
                    }
                }

                if tailOut > 0, hEnd > onePixel {
                    for k in 1...tailOut {
                        let idx = end + k
                        if idx >= n0 { break }
                        if rawWetMask[idx] { break }

                        let t = Double(k) / Double(tailOut + 1)
                        let f = pow(max(0.0, 1.0 - t), tailPow)
                        let hh = hEnd * CGFloat(f)
                        if hh > heights[idx] { heights[idx] = hh }
                    }
                }
            }
        }

        // Resample beyond minute steps (dense, widget-safe cap).
        let pxW = max(1, Int(ceil(plotRect.width * max(1.0, displayScale))))
        let denseCount = min(1025, max(121, (pxW / 2) + 1))

        var denseHeights = RainSurfaceMath.resampleMonotoneCubic(heights, targetCount: denseCount)
        denseHeights = RainSurfaceMath.smooth(denseHeights, passes: 1).map { min(maxCoreHeight, max(0.0, $0)) }

        var denseIntensity = RainSurfaceMath.resampleMonotoneCubic(intensityNorm, targetCount: denseCount)
        denseIntensity = denseIntensity.map { RainSurfaceMath.clamp01($0) }
        denseIntensity = RainSurfaceMath.smooth(denseIntensity, passes: 1)

        let certaintySmoothed = RainSurfaceMath.smooth(certainty, passes: 1)
        var denseCertainty = RainSurfaceMath.resampleMonotoneCubic(certaintySmoothed, targetCount: denseCount)
        denseCertainty = denseCertainty.map { RainSurfaceMath.clamp01($0) }
        denseCertainty = RainSurfaceMath.smooth(denseCertainty, passes: 1)

        // Wet mask from geometry.
        let epsilon = max(onePixel * 0.18, maxCoreHeight * 0.0015)
        var wetMask = [Bool](repeating: false, count: denseCount)
        for i in 0..<denseCount { wetMask[i] = denseHeights[i] > epsilon }

        if wetMask.allSatisfy({ !$0 }) {
            RainSurfaceDrawing.drawBaseline(in: &context, plotRect: plotRect, baselineY: baselineY, configuration: configuration, displayScale: displayScale)
            return
        }

        let wetRanges = RainSurfaceGeometry.wetRanges(from: wetMask)
        if wetRanges.isEmpty {
            RainSurfaceDrawing.drawBaseline(in: &context, plotRect: plotRect, baselineY: baselineY, configuration: configuration, displayScale: displayScale)
            return
        }

        // End tapers are ALPHA ONLY.
        let firstWet = wetMask.firstIndex(where: { $0 }) ?? 0
        let lastWet = wetMask.lastIndex(where: { $0 }) ?? (denseCount - 1)

        let fadeIn = max(0, configuration.wetRegionFadeInSamples)
        let fadeOut = max(0, configuration.wetRegionFadeOutSamples)

        var alphaTaper = [Double](repeating: 0.0, count: denseCount)
        for i in 0..<denseCount {
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

        let stepX = plotRect.width / CGFloat(denseCount)

        // Build segments (paths from geometry only).
        var segments: [WetSegment] = []
        segments.reserveCapacity(wetRanges.count)

        for r in wetRanges {
            let surface = RainSurfaceGeometry.makeSurfacePath(
                for: r,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: denseHeights
            )
            let top = RainSurfaceGeometry.makeTopEdgePath(
                for: r,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: denseHeights
            )
            segments.append(.init(range: r, surfacePath: surface, topEdgePath: top))
        }

        RainSurfaceDrawing.drawProbabilityMaskedSurface(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            stepX: stepX,
            segments: segments,
            heights: denseHeights,
            intensityNorm: denseIntensity,
            certainty: denseCertainty,
            edgeFactors: alphaTaper,
            configuration: configuration,
            displayScale: displayScale
        )

        // Spec: baseline is drawn last so it reads through the surface.
        RainSurfaceDrawing.drawBaseline(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )
    }
}
