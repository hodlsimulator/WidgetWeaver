//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Rendering helpers for the forecast surface.
//

import Foundation
import SwiftUI

enum RainSurfaceDrawing {
    // MARK: - Surface (fuzz + core + optional glints)

    static func drawSurface(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        certainties: [Double],
        corePath: Path,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard chartRect.width > 1, chartRect.height > 1 else { return }
        guard !heights.isEmpty else { return }

        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let maxHeight = max(heights.max() ?? 0, onePixel)

        // (2) Fuzz layer: speckled uncertainty outside core only, additive.
        if configuration.fuzzEnabled {
            drawFuzz(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                certainties: certainties,
                maxHeight: maxHeight,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // (3) Core layer: fully opaque fill with interior shading + inside-only gloss band.
        drawCore(
            in: &context,
            chartRect: chartRect,
            baselineY: baselineY,
            maxHeight: maxHeight,
            corePath: corePath,
            topEdgePath: topEdgePath,
            configuration: configuration,
            displayScale: displayScale
        )

        // (4) Optional tiny local glints near local maxima.
        if configuration.glintEnabled {
            drawGlints(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                maxHeight: maxHeight,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }
    }

    private static func drawFuzz(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        certainties: [Double],
        maxHeight: CGFloat,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        // fuzzWidth ≈ 10–20% of chart height, clamped to a sensible pixel range.
        let desiredPx = Double(chartRect.height * configuration.fuzzWidthFraction * scale)
        let clampedPx = RainSurfaceMath.clamp(desiredPx, min: configuration.fuzzWidthPixelsClamp.lowerBound, max: configuration.fuzzWidthPixelsClamp.upperBound)
        let fuzzWidth = CGFloat(clampedPx / scale)

        // Clip rect expanded so speckles near the edge are not hard-clipped.
        let clipRect = chartRect.insetBy(dx: -fuzzWidth * 0.55, dy: -fuzzWidth * 1.1)
        let outsideMask = RainSurfaceGeometry.makeOutsideMaskPath(clipRect: clipRect, corePath: corePath)
        let aboveBaselineRect = CGRect(x: clipRect.minX, y: clipRect.minY, width: clipRect.width, height: max(0, baselineY - clipRect.minY - onePixel))

        // Seed must be stable; renderer also mixes size, so only base seed is needed here.
        let seed = configuration.noiseSeed
        let sizeSaltW = UInt64(max(1, Int((chartRect.width * scale).rounded())))
        let sizeSaltH = UInt64(max(1, Int((chartRect.height * scale).rounded())))
        let sizeSalt = RainSurfacePRNG.combine(sizeSaltW, sizeSaltH)
        let baseSeed = RainSurfacePRNG.combine(seed, sizeSalt)

        let n = heights.count
        let certaintyCount = certainties.count

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            // Optional micro-blur (< 1 px) to soften aliasing only.
            let blurPx = configuration.fuzzMicroBlurPixels
            if blurPx > 0 {
                layer.addFilter(.blur(radius: CGFloat(blurPx / scale)))
            }

            // Fuzz exists only outside the core silhouette.
            layer.clip(to: outsideMask, style: FillStyle(eoFill: true))
            layer.clip(to: Path(aboveBaselineRect))

            let minWetHeight = onePixel * 0.35
            let maxAttempts = max(4, configuration.fuzzMaxAttemptsPerColumn)
            let radiusMinPx = configuration.fuzzSpeckleRadiusPixels.lowerBound
            let radiusMaxPx = configuration.fuzzSpeckleRadiusPixels.upperBound

            for i in 0..<n {
                let h = heights[i]
                if h <= minWetHeight { continue }

                let xCenter = chartRect.minX + (CGFloat(i) + 0.5) * stepX
                let topY = baselineY - h

                // Low-height emphasis: strongest near baseline, suppressed near peaks.
                let heightNorm = RainSurfaceMath.clamp01(h / maxHeight)
                let lowHeightEmphasis = pow(Double(1.0 - heightNorm), configuration.fuzzLowHeightPower)

                // Uncertainty term: dense near boundary when uncertain.
                let c: Double
                if certaintyCount == 0 {
                    c = 1.0
                } else if i < certaintyCount {
                    c = RainSurfaceMath.clamp01(certainties[i])
                } else {
                    c = RainSurfaceMath.clamp01(certainties[certaintyCount - 1])
                }

                let uncertaintyFloor = configuration.fuzzUncertaintyFloor
                let uncertainty = RainSurfaceMath.clamp01(uncertaintyFloor + (1.0 - uncertaintyFloor) * (1.0 - c))

                // Base column density (still deterministic; turned into speckles via thresholds).
                let base = configuration.fuzzBaseDensity
                let columnDensity = RainSurfaceMath.clamp01(base * uncertainty * (0.15 + 0.85 * lowHeightEmphasis))

                if columnDensity <= 0.0001 { continue }

                // Per-column PRNG stream (stable).
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(baseSeed, UInt64(i) &* 0xD6E8FEB86659FD93))

                // Attempts scaled by density, capped to keep grain consistent.
                let attempts = Int(ceil(Double(maxAttempts) * columnDensity))

                for _ in 0..<attempts {
                    // Distance from the core boundary outward (in points).
                    // Bias towards the boundary so density is highest at d = 0.
                    let u = prng.nextDouble01()
                    let d = fuzzWidth * CGFloat(pow(u, 2.25))

                    // density(d): highest at 0, eases to 0 at fuzzWidth.
                    let t = RainSurfaceMath.clamp01(d / max(fuzzWidth, onePixel))
                    let fade = 1.0 - RainSurfaceMath.smoothstep01(t)
                    let densityAtD = RainSurfaceMath.clamp01(columnDensity * Double(fade))

                    // Deterministic noise threshold -> speckle decision.
                    let n01 = prng.nextDouble01()
                    if n01 >= densityAtD { continue }

                    // Jitter keeps speckles granular (not a blur).
                    let jitterX = (CGFloat(prng.nextDouble01()) - 0.5) * (stepX * 0.85 + d * 0.35)
                    let jitterY = (CGFloat(prng.nextDouble01()) - 0.5) * (onePixel * 0.90)

                    let y = topY - d + jitterY
                    if y < chartRect.minY - fuzzWidth { continue }

                    let rPx = RainSurfaceMath.lerp(radiusMinPx, radiusMaxPx, prng.nextDouble01())
                    let r = CGFloat(rPx / scale)

                    // Alpha fades with distance; additive blend keeps blacks black outside speckles.
                    let a = configuration.fuzzMaxOpacity * densityAtD * (0.65 + 0.35 * prng.nextDouble01())

                    let rect = CGRect(x: xCenter + jitterX - r, y: y - r, width: r * 2, height: r * 2)
                    layer.fill(Path(ellipseIn: rect), with: .color(configuration.fuzzColor.opacity(a)))
                }
            }
        }
    }

    private static func drawCore(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        maxHeight: CGFloat,
        corePath: Path,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        // Fully opaque interior shading (no holes, no fuzz, no transparency).
        let topY = baselineY - maxHeight
        let gradient = Gradient(stops: [
            .init(color: configuration.coreBottomColor.opacity(1.0), location: 0.0),
            .init(color: configuration.coreMidColor.opacity(1.0), location: 0.55),
            .init(color: configuration.coreTopColor.opacity(1.0), location: 1.0)
        ])

        let shading = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: chartRect.midX, y: baselineY),
            endPoint: CGPoint(x: chartRect.midX, y: topY)
        )

        context.fill(corePath, with: shading)

        // Inside-only gloss band: soft brightening just beneath the top curve (clipped inside).
        if configuration.glossEnabled {
            let depthPx = RainSurfaceMath.clamp(
                configuration.glossDepthPixels.mid,
                min: configuration.glossDepthPixels.lowerBound,
                max: configuration.glossDepthPixels.upperBound
            )
            let depth = CGFloat(depthPx / scale)

            let blur = CGFloat(configuration.glossSoftBlurPixels / scale)
            let opacity = configuration.glossMaxOpacity

            context.drawLayer { layer in
                layer.clip(to: corePath)

                // Screen-like blend for a glossy skin that does not read as a hard rim.
                layer.blendMode = .screen
                if blur > 0 { layer.addFilter(.blur(radius: blur)) }

                let stroke = StrokeStyle(lineWidth: max(onePixel, depth * 2), lineCap: .round, lineJoin: .round)
                layer.stroke(
                    topEdgePath,
                    with: .color(configuration.coreTopColor.opacity(opacity)),
                    style: stroke
                )
            }
        }
    }

    private static func drawGlints(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        maxHeight: CGFloat,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let minFrac = RainSurfaceMath.clamp(configuration.glintMinHeightFraction, min: 0.35, max: 0.85)
        let minH = maxHeight * CGFloat(minFrac)

        let peakIndices = localMaximaIndices(
            heights: heights,
            minHeight: minH,
            maxCount: max(0, configuration.glintMaxCount),
            minSeparationPoints: max(onePixel * 10, chartRect.width * 0.06),
            stepX: stepX
        )

        guard !peakIndices.isEmpty else { return }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter

            let blur = CGFloat(configuration.glintBlurPixels / scale)
            if blur > 0 { layer.addFilter(.blur(radius: blur)) }

            for idx in peakIndices {
                let h = heights[idx]
                let x = chartRect.minX + (CGFloat(idx) + 0.5) * stepX
                let y = baselineY - h

                // Tiny, localised glint near the apex only.
                let r = max(onePixel * 1.25, onePixel * 1.75)
                let rect = CGRect(x: x - r, y: y - r * 0.65, width: r * 2, height: r * 1.6)
                layer.fill(
                    Path(ellipseIn: rect),
                    with: .color(configuration.glintColor.opacity(configuration.glintMaxOpacity))
                )
            }
        }
    }

    private static func localMaximaIndices(
        heights: [CGFloat],
        minHeight: CGFloat,
        maxCount: Int,
        minSeparationPoints: CGFloat,
        stepX: CGFloat
    ) -> [Int] {
        guard heights.count >= 3, maxCount > 0 else { return [] }

        var peaks: [(idx: Int, h: CGFloat)] = []
        peaks.reserveCapacity(8)

        for i in 1..<(heights.count - 1) {
            let a = heights[i - 1]
            let b = heights[i]
            let c = heights[i + 1]
            if b >= minHeight && b > a && b >= c {
                peaks.append((i, b))
            }
        }

        guard !peaks.isEmpty else { return [] }

        peaks.sort { $0.h > $1.h }

        var chosen: [Int] = []
        chosen.reserveCapacity(min(maxCount, peaks.count))

        for p in peaks {
            if chosen.count >= maxCount { break }
            let xP = CGFloat(p.idx) * stepX
            let tooClose = chosen.contains { j in
                abs(CGFloat(j) * stepX - xP) < minSeparationPoints
            }
            if !tooClose {
                chosen.append(p.idx)
            }
        }

        return chosen
    }

    // MARK: - Baseline

    /// Thin luminous baseline with vertical glow and end fade. Drawn last.
    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard chartRect.width > 1 else { return }

        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let x0 = chartRect.minX
        let x1 = chartRect.maxX
        let fadeFrac = RainSurfaceMath.clamp(configuration.baselineEndFadeFraction, min: 0.03, max: 0.04)
        let fadeW = max(onePixel, chartRect.width * fadeFrac)

        // End fade as a horizontal alpha gradient.
        let alpha = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.0), location: 0.0),
                .init(color: .white.opacity(1.0), location: min(1.0, Double(fadeW / chartRect.width))),
                .init(color: .white.opacity(1.0), location: max(0.0, 1.0 - Double(fadeW / chartRect.width))),
                .init(color: .white.opacity(0.0), location: 1.0)
            ]),
            startPoint: CGPoint(x: x0, y: baselineY),
            endPoint: CGPoint(x: x1, y: baselineY)
        )

        // 1 px line + glow strokes. Additive so it reads through the core without lifting blacks globally.
        var line = Path()
        line.move(to: CGPoint(x: x0, y: baselineY))
        line.addLine(to: CGPoint(x: x1, y: baselineY))

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            let base = configuration.baselineLineOpacity

            // Tail to ~5–6 px (radius) via a wide, faint stroke.
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.14)),
                style: StrokeStyle(lineWidth: onePixel * 11, lineCap: .round)
            )

            // Mid glow within a few pixels.
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.26)),
                style: StrokeStyle(lineWidth: onePixel * 6, lineCap: .round)
            )

            // Inner glow close to the line.
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.38)),
                style: StrokeStyle(lineWidth: onePixel * 3, lineCap: .round)
            )

            // Core 1 px line.
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base)),
                style: StrokeStyle(lineWidth: onePixel, lineCap: .butt)
            )

            // Apply end fade to the whole baseline/glow stack.
            layer.blendMode = .destinationIn
            var fadeRect = Path()
            fadeRect.addRect(chartRect)
            layer.fill(fadeRect, with: alpha)
        }
    }
}

private extension ClosedRange where Bound == Double {
    var mid: Double { (lowerBound + upperBound) * 0.5 }
}
