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

        // (2) Fuzz layer: speckled uncertainty outside core only; additive.
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

        // (3) Core layer: opaque fill + inside-only gloss band.
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

    // MARK: - Fuzz (granular, outside-only, concentrated near baseline)

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

        // fuzzWidth ≈ 10–20% of chart height, clamped.
        let desiredPx = Double(chartRect.height * configuration.fuzzWidthFraction * scale)
        let clampedPx = RainSurfaceMath.clamp(
            desiredPx,
            min: configuration.fuzzWidthPixelsClamp.lowerBound,
            max: configuration.fuzzWidthPixelsClamp.upperBound
        )
        let fuzzWidth = CGFloat(clampedPx / scale)
        if fuzzWidth <= onePixel { return }

        // Deterministic seed mixed with size for stability across widget families/sizes.
        let seed = configuration.noiseSeed
        let sizeSaltW = UInt64(max(1, Int((chartRect.width * scale).rounded())))
        let sizeSaltH = UInt64(max(1, Int((chartRect.height * scale).rounded())))
        let sizeSalt = RainSurfacePRNG.combine(sizeSaltW, sizeSaltH)
        let baseSeed = RainSurfacePRNG.combine(seed, sizeSalt)

        let n = heights.count
        let certaintyCount = certainties.count

        // Column stride cap (keeps work bounded even if dense sampling grows).
        let maxCols = max(1, configuration.fuzzMaxColumns)
        let colStride = max(1, Int(ceil(Double(n) / Double(maxCols))))
        let processedCols = (n + colStride - 1) / colStride

        // Global hard budget on speckle attempts.
        let maxAttemptsPerCol = max(4, configuration.fuzzMaxAttemptsPerColumn)
        let budget = max(500, configuration.fuzzSpeckleBudget)
        let attemptScale = min(1.0, Double(budget) / Double(max(1, processedCols * maxAttemptsPerCol)))

        // Batched fills: 3 distance buckets. No blur.
        var pNear = Path()
        var pMid = Path()
        var pFar = Path()
        var hasAny = false

        let radiusMinPx = configuration.fuzzSpeckleRadiusPixels.lowerBound
        let radiusMaxPx = configuration.fuzzSpeckleRadiusPixels.upperBound

        let minWetHeight = onePixel * 0.35

        // Extra bias so fuzz lives on lower slopes rather than the crest.
        let lowHeightPower = max(1.0, configuration.fuzzLowHeightPower)

        for ii in stride(from: 0, to: n, by: colStride) {
            let h = heights[ii]
            if h <= minWetHeight { continue }

            // Curve point on the top surface.
            let x = chartRect.minX + (CGFloat(ii) + 0.5) * stepX
            let y = baselineY - h

            // Neighbour indices for slope/normal.
            let iPrev = max(0, ii - 1)
            let iNext = min(n - 1, ii + 1)

            let xPrev = chartRect.minX + (CGFloat(iPrev) + 0.5) * stepX
            let xNext = chartRect.minX + (CGFloat(iNext) + 0.5) * stepX
            let yPrev = baselineY - heights[iPrev]
            let yNext = baselineY - heights[iNext]

            let dx = max(onePixel, xNext - xPrev)
            let dy = yNext - yPrev

            // Tangent and outward normal (core is below; outward points “up” from the curve).
            let tLen = sqrt(dx * dx + dy * dy)
            let tx = dx / max(onePixel, tLen)
            let ty = dy / max(onePixel, tLen)

            // Normal = (dy, -dx) normalised, which has negative y (upwards).
            var nx = dy
            var ny = -dx
            let nLen = sqrt(nx * nx + ny * ny)
            if nLen > onePixel {
                nx /= nLen
                ny /= nLen
            } else {
                nx = 0
                ny = -1
            }

            // Height-based suppression: strongest near baseline / lower slopes.
            let heightNorm = RainSurfaceMath.clamp01(h / maxHeight)
            let lowHeightEmphasis = pow(Double(1.0 - heightNorm), lowHeightPower)

            // Uncertainty term (higher fuzz when certainty is low).
            let c: Double
            if certaintyCount == 0 {
                c = 1.0
            } else if ii < certaintyCount {
                c = RainSurfaceMath.clamp01(certainties[ii])
            } else {
                c = RainSurfaceMath.clamp01(certainties[certaintyCount - 1])
            }
            let uncertaintyFloor = configuration.fuzzUncertaintyFloor
            let uncertainty = RainSurfaceMath.clamp01(uncertaintyFloor + (1.0 - uncertaintyFloor) * (1.0 - c))

            // Slope bias: favour the sides (steeper areas) over flat crests.
            let slopeAbs = Double(abs(dy) / max(dx, onePixel))
            let slopeFactor = RainSurfaceMath.clamp01(slopeAbs * 0.85) // tuned for visual emphasis
            let slopeBias = 0.35 + 0.65 * slopeFactor

            let base = configuration.fuzzBaseDensity
            let columnDensity = RainSurfaceMath.clamp01(base * uncertainty * (0.12 + 0.88 * lowHeightEmphasis) * slopeBias)
            if columnDensity <= 0.0001 { continue }

            var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(baseSeed, UInt64(ii) &* 0xD6E8FEB86659FD93))

            let rawAttempts = Double(maxAttemptsPerCol) * columnDensity * attemptScale
            let attempts = max(1, Int(ceil(rawAttempts)))

            for _ in 0..<attempts {
                // Bias distance strongly toward the boundary (dense near edge).
                let u = prng.nextDouble01()
                let d = fuzzWidth * CGFloat(pow(u, 2.35))

                let t = RainSurfaceMath.clamp01(d / max(fuzzWidth, onePixel))
                let fade = 1.0 - RainSurfaceMath.smoothstep01(t)
                let densityAtD = RainSurfaceMath.clamp01(columnDensity * Double(fade))

                // Deterministic thresholding into speckles.
                if prng.nextDouble01() >= densityAtD { continue }

                // Jitter mostly along tangent (keeps fuzz “spray” granular rather than banded).
                let jt = (CGFloat(prng.nextDouble01()) - 0.5) * (stepX * (0.85 + 0.35 * t))
                let jn = (CGFloat(prng.nextDouble01()) - 0.5) * (onePixel * 0.9)

                let px = x + tx * jt + nx * (d + jn)
                let py = y + ty * jt + ny * (d + jn)

                // Never place fuzz below the baseline.
                if py >= baselineY - onePixel { continue }

                let rPx = RainSurfaceMath.lerp(radiusMinPx, radiusMaxPx, prng.nextDouble01())
                let r = CGFloat(rPx / scale)

                let rect = CGRect(x: px - r, y: py - r, width: r * 2, height: r * 2)

                if t < 0.33 {
                    pNear.addEllipse(in: rect)
                } else if t < 0.66 {
                    pMid.addEllipse(in: rect)
                } else {
                    pFar.addEllipse(in: rect)
                }

                hasAny = true
            }
        }

        if !hasAny { return }

        // Draw speckles additively, then erase anything inside the core (outside-only guarantee),
        // and erase anything below the baseline.
        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            let maxA = configuration.fuzzMaxOpacity
            if !pFar.isEmpty { layer.fill(pFar, with: .color(configuration.fuzzColor.opacity(maxA * 0.42))) }
            if !pMid.isEmpty { layer.fill(pMid, with: .color(configuration.fuzzColor.opacity(maxA * 0.70))) }
            if !pNear.isEmpty { layer.fill(pNear, with: .color(configuration.fuzzColor.opacity(maxA * 1.00))) }

            // Erase fuzz inside core.
            layer.blendMode = .destinationOut
            layer.fill(corePath, with: .color(.white))

            // Erase fuzz below baseline.
            let belowRectH = chartRect.maxY - baselineY + fuzzWidth * 2
            if belowRectH > onePixel {
                var below = Path()
                below.addRect(CGRect(x: chartRect.minX - fuzzWidth, y: baselineY, width: chartRect.width + fuzzWidth * 2, height: belowRectH))
                layer.fill(below, with: .color(.white))
            }
        }
    }

    // MARK: - Core (opaque volume + inside-only gloss)

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

        // Fully opaque interior shading.
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

        // Inside-only gloss band:
        // draw a softened band slightly below the top curve (not on the edge) and mask to the core.
        if configuration.glossEnabled {
            let depthPx = RainSurfaceMath.clamp(
                configuration.glossDepthPixels.mid,
                min: configuration.glossDepthPixels.lowerBound,
                max: configuration.glossDepthPixels.upperBound
            )
            let depth = CGFloat(depthPx / scale)
            let opacity = configuration.glossMaxOpacity

            let shiftY = max(onePixel, depth * 0.40)
            let bandPath = topEdgePath.applying(CGAffineTransform(translationX: 0, y: shiftY))
            let bandPath2 = topEdgePath.applying(CGAffineTransform(translationX: 0, y: shiftY + max(onePixel, depth * 0.35)))

            context.drawLayer { layer in
                layer.blendMode = .screen

                // Soft inner skin (wider, fainter).
                layer.stroke(
                    bandPath2,
                    with: .color(configuration.coreTopColor.opacity(opacity * 0.55)),
                    style: StrokeStyle(
                        lineWidth: max(onePixel, depth * 2.2),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                // Brighter band (narrower).
                layer.stroke(
                    bandPath,
                    with: .color(configuration.coreTopColor.opacity(opacity)),
                    style: StrokeStyle(
                        lineWidth: max(onePixel, depth * 1.35),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                // Mask to core so nothing appears outside the silhouette.
                layer.blendMode = .destinationIn
                layer.fill(corePath, with: .color(.white))
            }
        }
    }

    // MARK: - Glints (tiny, local maxima only)

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

        let minFrac = RainSurfaceMath.clamp(configuration.glintMinHeightFraction, min: 0.35, max: 0.90)
        let minH = maxHeight * CGFloat(minFrac)

        let peakIndices = localMaximaIndices(
            heights: heights,
            minHeight: minH,
            maxCount: max(0, configuration.glintMaxCount),
            minSeparationPoints: max(onePixel * 10, chartRect.width * 0.08),
            stepX: stepX
        )

        guard !peakIndices.isEmpty else { return }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            for idx in peakIndices {
                let h = heights[idx]
                let x = chartRect.minX + (CGFloat(idx) + 0.5) * stepX
                let y = baselineY - h

                // Tiny, localised “apex glint” (no long ridge).
                let w0 = max(onePixel * 9.0, onePixel * 11.0)
                let h0 = max(onePixel * 1.4, onePixel * 1.8)
                let rect0 = CGRect(x: x - w0 * 0.5, y: y - h0 * 0.6, width: w0, height: h0)
                layer.fill(
                    Path(roundedRect: rect0, cornerRadius: h0 * 0.5),
                    with: .color(configuration.glintColor.opacity(configuration.glintMaxOpacity * 0.55))
                )

                let w1 = max(onePixel * 5.0, onePixel * 6.5)
                let h1 = max(onePixel * 1.0, onePixel * 1.3)
                let rect1 = CGRect(x: x - w1 * 0.5, y: y - h1 * 0.6, width: w1, height: h1)
                layer.fill(
                    Path(roundedRect: rect1, cornerRadius: h1 * 0.5),
                    with: .color(configuration.glintColor.opacity(configuration.glintMaxOpacity))
                )
            }

            // Mask to core.
            layer.blendMode = .destinationIn
            layer.fill(corePath, with: .color(.white))
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

    // MARK: - Baseline (drawn last)

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

        var line = Path()
        line.move(to: CGPoint(x: x0, y: baselineY))
        line.addLine(to: CGPoint(x: x1, y: baselineY))

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            let base = configuration.baselineLineOpacity

            // Tail to ~5–6 px.
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.14)),
                style: StrokeStyle(lineWidth: onePixel * 11, lineCap: .round)
            )

            // Mid glow.
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.26)),
                style: StrokeStyle(lineWidth: onePixel * 6, lineCap: .round)
            )

            // Inner glow.
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

            // Apply end fade to the whole baseline stack.
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
