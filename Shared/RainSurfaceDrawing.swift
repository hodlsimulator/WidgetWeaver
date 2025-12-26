//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Rendering helpers for the forecast surface.
//

import SwiftUI

enum RainSurfaceDrawing {

    // MARK: - Baseline (drawn last; additive)

    static func drawBaseline(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let inset = max(0, configuration.baselineInsetPoints)
        let x0 = plotRect.minX + inset
        let x1 = plotRect.maxX - inset
        guard x1 > x0 else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let y = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        var line = Path()
        line.move(to: CGPoint(x: x0, y: y))
        line.addLine(to: CGPoint(x: x1, y: y))

        let base = RainSurfaceMath.clamp01(configuration.baselineOpacity)
        if base <= 0 { return }

        let fadeFrac: CGFloat = 0.035
        let fadeW = max(onePixel, plotRect.width * fadeFrac)
        let f = Double(RainSurfaceMath.clamp(fadeW / max(plotRect.width, onePixel), min: 0.0, max: 0.25))

        func fadeShading(opacity: Double) -> GraphicsContext.Shading {
            let c0 = configuration.baselineColor.opacity(0)
            let c1 = configuration.baselineColor.opacity(RainSurfaceMath.clamp01(opacity))

            let stops = [
                Gradient.Stop(color: c0, location: 0.0),
                Gradient.Stop(color: c1, location: f),
                Gradient.Stop(color: c1, location: 1.0 - f),
                Gradient.Stop(color: c0, location: 1.0)
            ]

            return .linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(x: x0, y: y),
                endPoint: CGPoint(x: x1, y: y)
            )
        }

        let soft = RainSurfaceMath.clamp01(configuration.baselineSoftOpacityMultiplier)
        let glowBase = RainSurfaceMath.clamp01(base * max(0.60, soft * 2.0))

        let outerAlpha = glowBase * 0.18
        let midAlpha = glowBase * 0.28
        let innerAlpha = glowBase * 0.40
        let coreAlpha = base

        let outerW = onePixel * 11.0 // faint tail out to ~5–6px
        let midW = onePixel * 6.0
        let innerW = onePixel * 3.0 // strongest within ~2px
        let coreW = max(onePixel, configuration.baselineLineWidth)

        let savedBlend = context.blendMode
        context.blendMode = .plusLighter

        context.stroke(line, with: fadeShading(opacity: outerAlpha), style: StrokeStyle(lineWidth: outerW, lineCap: .butt))
        context.stroke(line, with: fadeShading(opacity: midAlpha), style: StrokeStyle(lineWidth: midW, lineCap: .butt))
        context.stroke(line, with: fadeShading(opacity: innerAlpha), style: StrokeStyle(lineWidth: innerW, lineCap: .butt))
        context.stroke(line, with: fadeShading(opacity: coreAlpha), style: StrokeStyle(lineWidth: coreW, lineCap: .butt))

        context.blendMode = savedBlend
    }

    // MARK: - Surface (spec order)
    //
    // 1) fuzz envelope (outside-core speckle)
    // 2) solid core (opaque)
    // 3) inside-only gloss band
    // 4) optional localised glint

    static func drawProbabilityMaskedSurface(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        segments: [RainForecastSurfaceRenderer.WetSegment],
        heights: [CGFloat],
        intensityNorm: [Double],
        certainty: [Double],
        edgeFactors: [Double],
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard !segments.isEmpty else { return }

        let n = min(heights.count, min(intensityNorm.count, min(certainty.count, edgeFactors.count)))
        guard n > 0 else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let plotH = max(onePixel, plotRect.height)

        let globalMaxHeight = max(onePixel, heights.max() ?? onePixel)

        // Fuzz width in pixels, scaled by render size.
        let fuzzPx = RainSurfaceMath.clamp(plotRect.height * 0.22 * max(displayScale, 1.0), min: 40.0, max: 120.0)
        let fuzzW = max(onePixel, fuzzPx / max(displayScale, 1.0))

        // Padding so speckles are not clipped.
        let padX = min(max(onePixel, fuzzW * 0.35), 44.0)
        let padY = min(max(onePixel, fuzzW * 0.55), 52.0)
        let clipRect = plotRect.insetBy(dx: -padX, dy: -padY)

        // Union mask for all wet segments.
        var coreMaskPath = Path()
        for seg in segments { coreMaskPath.addPath(seg.surfacePath) }

        // Outside-of-core mask (even-odd fill).
        var outsideMaskPath = Path()
        outsideMaskPath.addRect(clipRect)
        outsideMaskPath.addPath(coreMaskPath)

        // Keep texture above the baseline so the baseline stays crisp.
        var aboveBaselineMask = Path()
        aboveBaselineMask.addRect(
            CGRect(
                x: clipRect.minX,
                y: clipRect.minY,
                width: clipRect.width,
                height: max(onePixel, (baselineY - (onePixel * 1.5)) - clipRect.minY)
            )
        )

        // Deterministic salting derived from plot size + forecast intensity field.
        let peakI = intensityNorm.max() ?? 0.0
        let sumI = intensityNorm.reduce(0.0, +)
        let pxW = Int((plotRect.width * max(1.0, displayScale)).rounded())
        let pxH = Int((plotRect.height * max(1.0, displayScale)).rounded())
        let saltA = 0xA11C_AFE ^ pxW ^ (pxH &* 33) ^ Int((peakI * 10_000.0).rounded())
        let saltB = 0x0B0B_1E ^ (n &* 97) ^ Int((sumI * 1_000.0).rounded())

        // PASS 1 — Fuzz envelope (outside-core speckle, density fade)
        if configuration.shellEnabled,
           configuration.shellMaxOpacity > 0.000_01,
           configuration.shellNoiseAmount > 0.000_01 {

            let baseDensity = RainSurfaceMath.clamp01(configuration.shellNoiseAmount)
            let alphaCap = RainSurfaceMath.clamp01(configuration.shellMaxOpacity)

            let rawMicroBlur = plotH * max(0.0, configuration.shellBlurFractionOfPlotHeight)
            let microBlur = min(onePixel * 0.95, max(0.0, rawMicroBlur))

            let edgeFadeWidth = max(onePixel, plotRect.width * 0.045)

            func edgeFade(_ x: CGFloat) -> Double {
                let d = min(x - plotRect.minX, plotRect.maxX - x)
                let t = RainSurfaceMath.clamp01(Double(d / max(onePixel, edgeFadeWidth)))
                return RainSurfaceMath.smoothstep01(t)
            }

            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))
                if microBlur > onePixel * 0.60 {
                    layer.addFilter(.blur(radius: microBlur))
                }

                layer.blendMode = .plusLighter

                for seg in segments {
                    for i in seg.range {
                        if i < 0 || i >= n { continue }

                        let h = heights[i]
                        if h <= onePixel * 0.25 { continue }

                        let v = RainSurfaceMath.clamp01(intensityNorm[i])
                        let c = RainSurfaceMath.clamp01(certainty[i])
                        let unc = RainSurfaceMath.clamp01(1.0 - c)
                        let taper = RainSurfaceMath.clamp01(edgeFactors[i])

                        let height01 = RainSurfaceMath.clamp01(Double(h / globalMaxHeight))
                        let lowHeight = pow(max(0.0, 1.0 - height01), 1.6)

                        // Stronger when uncertain, stronger near baseline, suppressed near peak.
                        var strength = baseDensity
                        strength *= (0.25 + 0.75 * unc)
                        strength *= (0.55 + 0.45 * pow(max(0.0, v), 0.55))
                        strength *= (0.12 + 0.88 * lowHeight)
                        strength *= taper

                        if strength <= 0.000_8 { continue }

                        let cx = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                        let ex = edgeFade(cx)
                        if ex <= 0.0 { continue }

                        let columnStrength = RainSurfaceMath.clamp01(strength * ex)
                        if columnStrength <= 0.000_8 { continue }

                        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: saltA, saltB: saltB))

                        let attempts = max(2, Int(18.0 * columnStrength + 0.5))
                        let topY = baselineY - h

                        for _ in 0..<attempts {
                            let uDist = prng.random01()
                            let d = fuzzW * CGFloat(pow(uDist, 2.2))

                            let d01 = Double(d / max(fuzzW, onePixel))
                            let distFactor = pow(max(0.0, 1.0 - d01), 1.35)

                            let p = columnStrength * distFactor
                            if prng.random01() > p { continue }

                            let jx = (CGFloat(prng.random01() - 0.5)) * (stepX * 5.6 + d * 0.85)
                            let x = cx + jx
                            if x < clipRect.minX || x > clipRect.maxX { continue }

                            let y = topY - d + (CGFloat(prng.random01() - 0.5)) * onePixel
                            if y < clipRect.minY || y > baselineY - onePixel * 1.0 { continue }

                            let rPx = 0.45 + 0.70 * CGFloat(prng.random01())
                            let r = rPx / max(displayScale, 1.0)

                            let a = RainSurfaceMath.clamp01(alphaCap * (0.28 + 0.72 * distFactor) * columnStrength)
                            if a <= 0.000_9 { continue }

                            let speck = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                            layer.fill(speck, with: .color(configuration.shellColor.opacity(a)))
                        }
                    }
                }

                // Keep only outside-of-core + above baseline.
                layer.blendMode = .destinationIn
                layer.fill(outsideMaskPath, with: .color(.white), style: FillStyle(eoFill: true))
                layer.fill(aboveBaselineMask, with: .color(.white))
            }
        }

        // PASS 2 — Solid core (opaque; interior shading only)
        for seg in segments {
            let r = seg.range
            if r.isEmpty { continue }

            var peakIndex = r.lowerBound
            var peakHeight: CGFloat = 0.0
            for i in r {
                let h = heights[safe: i] ?? 0.0
                if h > peakHeight {
                    peakHeight = h
                    peakIndex = i
                }
            }

            let segMaxHeight = max(onePixel, peakHeight)
            let peakV01 = RainSurfaceMath.clamp01(Double(segMaxHeight / globalMaxHeight))

            let fillTopY = baselineY - segMaxHeight

            let fillGradient = Gradient(stops: [
                .init(color: configuration.fillBottomColor.opacity(1.0), location: 0.0),
                .init(color: configuration.fillMidColor.opacity(1.0), location: 0.60),
                .init(color: configuration.fillTopColor.opacity(1.0), location: 1.0)
            ])

            let fillShading = GraphicsContext.Shading.linearGradient(
                fillGradient,
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.minX, y: fillTopY)
            )

            context.fill(seg.surfacePath, with: fillShading)

            // Subtle directional shading between sides.
            let sideStops = [
                Gradient.Stop(color: Color.black.opacity(0.12), location: 0.0),
                Gradient.Stop(color: Color.black.opacity(0.00), location: 1.0)
            ]
            let sideShading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: sideStops),
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
            )

            context.drawLayer { layer in
                layer.clip(to: seg.surfacePath)
                layer.fill(Path(plotRect), with: sideShading)
            }

            // PASS 3 — Inside-only gloss band (8–14px beneath the top curve)
            if configuration.crestLiftEnabled, configuration.crestLiftMaxOpacity > 0.000_01 {
                let depthPx = RainSurfaceMath.clamp(plotH * 0.04 * max(displayScale, 1.0), min: 8.0, max: 14.0)
                let depth = max(onePixel, depthPx / max(displayScale, 1.0))

                let insetY = onePixel * 2.0
                let glossEdge = seg.topEdgePath.applying(CGAffineTransform(translationX: 0, y: insetY))
                let glossBand = glossEdge.strokedPath(
                    StrokeStyle(lineWidth: depth * 2.0, lineCap: .round, lineJoin: .round)
                )

                let glossOpacity = RainSurfaceMath.clamp01(configuration.crestLiftMaxOpacity * (0.75 + 0.25 * peakV01))

                context.drawLayer { layer in
                    layer.clip(to: seg.surfacePath)
                    layer.addFilter(.blur(radius: onePixel * 0.85))
                    layer.blendMode = .screen
                    layer.fill(glossBand, with: .color(configuration.fillTopColor.opacity(glossOpacity)))
                }
            }

            // PASS 4 — Optional localised glint (tiny; near peak only)
            if configuration.glintEnabled, configuration.glintMaxOpacity > 0.000_01 {
                if peakV01 >= configuration.glintMinPeakHeightFractionOfSegmentMax {
                    let span = max(1, configuration.glintSpanSamples)
                    let start = max(r.lowerBound, peakIndex - span)
                    let end = min(r.upperBound - 1, peakIndex + span)

                    if start <= end {
                        var glintAlphaLocal = [Double](repeating: 0.0, count: n)
                        for i in start...end {
                            let dx = abs(i - peakIndex)
                            let t = 1.0 - Double(dx) / Double(max(1, span))
                            let w = RainSurfaceMath.smoothstep01(t)
                            glintAlphaLocal[i] = RainSurfaceMath.clamp01(configuration.glintMaxOpacity * w)
                        }

                        // Convert to a simple peak blob rather than a ridge-running highlight.
                        let x = plotRect.minX + (CGFloat(peakIndex) + 0.5) * stepX
                        let y = (baselineY - segMaxHeight) + onePixel * 1.6

                        let rPx: CGFloat = 1.2 + 0.6 * CGFloat(RainSurfaceMath.clamp01(peakV01))
                        let rr = rPx / max(displayScale, 1.0)

                        let a = RainSurfaceMath.clamp01(configuration.glintMaxOpacity * 0.22)
                        if a > 0.000_9 {
                            let p = Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: 2 * rr, height: 2 * rr))
                            context.drawLayer { layer in
                                layer.clip(to: seg.surfacePath)
                                layer.blendMode = .plusLighter
                                layer.addFilter(.blur(radius: max(onePixel, configuration.glintBlurRadiusPoints)))
                                layer.fill(p, with: .color(configuration.glintColor.opacity(a)))
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Safe indexing

private extension Array {
    subscript(safe index: Int) -> Element? {
        if index < 0 { return nil }
        if index >= count { return nil }
        return self[index]
    }
}
