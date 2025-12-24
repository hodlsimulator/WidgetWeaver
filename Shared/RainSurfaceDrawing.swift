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

    // MARK: - Baseline

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

        var base = Path()
        base.move(to: CGPoint(x: x0, y: baselineY))
        base.addLine(to: CGPoint(x: x1, y: baselineY))

        let savedBlend = context.blendMode
        context.blendMode = .screen

        if configuration.baselineSoftOpacityMultiplier > 0, configuration.baselineSoftWidthMultiplier > 1 {
            let softWidth = max(
                configuration.baselineLineWidth,
                configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier
            )
            let softOpacity = max(0.0, min(1.0, configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier))
            let softStyle = StrokeStyle(lineWidth: max(onePixel, softWidth), lineCap: .round)
            context.stroke(base, with: .color(configuration.baselineColor.opacity(softOpacity)), style: softStyle)
        }

        let stroke = StrokeStyle(lineWidth: max(onePixel, configuration.baselineLineWidth), lineCap: .round)
        context.stroke(base, with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)), style: stroke)

        context.blendMode = savedBlend
    }

    // MARK: - Probability-masked surface (this is the main change)

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
        let maxHeight = max(1.0, baselineY - plotRect.minY)

        // Sigma controls how thick the diffuse boundary region is.
        // It must be strong enough to replace the silhouette in low-chance regions.

        let minSigmaPoints = max(onePixel, CGFloat(max(0.0, configuration.diffusionMinRadiusPoints)))
        let hardMaxSigmaPoints = max(minSigmaPoints, CGFloat(max(0.0, configuration.diffusionMaxRadiusPoints)))

        let fracMax = max(0.05, CGFloat(configuration.diffusionMaxRadiusFractionOfHeight))
        let maxFromHeight = max(minSigmaPoints, (maxHeight * fracMax))
        let maxSigmaPoints = min(hardMaxSigmaPoints, maxFromHeight)

        let radiusPower = max(0.01, configuration.diffusionRadiusUncertaintyPower)
        let strengthMax = max(0.0, configuration.diffusionStrengthMax)

        let jitterAmp = CGFloat(max(0.0, configuration.diffusionJitterAmplitudePoints)) / max(1.0, displayScale)

        // Heavier than before; this directly controls the silhouette now.
        let insideBands = max(8, min(20, configuration.diffusionLayers / 3))
        let outsideBands = max(6, min(16, configuration.diffusionLayers / 4))

        // Dots provide the “diffuse / fuzzy” grain.
        let dotsOn = configuration.fuzzDotsEnabled && configuration.fuzzDotsPerSampleMax > 0
        let maxDots = max(0, configuration.fuzzDotsPerSampleMax)

        // Mask blur should be small: the softness is mostly from sigma + bands.
        // This keeps the fuzz from turning into a giant haze patch.
        let dotBlur = max(0.0, CGFloat(configuration.fuzzGlobalBlurRadiusPoints))

        // Precompute per-sample parameters.
        var sigma = [CGFloat](repeating: 0, count: n)
        var coreAlpha = [Double](repeating: 0, count: n)
        var fuzzAlpha = [Double](repeating: 0, count: n)
        var coreHeights = [CGFloat](repeating: 0, count: n)

        // Smooth certainty a little to avoid “striped” fuzz banding.
        let certaintySmoothed = RainSurfaceMath.smooth(Array(certainty.prefix(n)), passes: 2)

        for i in 0..<n {
            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certaintySmoothed[i])
            let u = RainSurfaceMath.clamp01(1.0 - c)
            let edge = RainSurfaceMath.clamp01(edgeFactors[i])

            // Sigma grows strongly as certainty drops.
            var s = minSigmaPoints + (maxSigmaPoints - minSigmaPoints) * CGFloat(pow(u, radiusPower))

            // Prevent tiny rain amounts from producing a huge cloud.
            // Cap sigma relative to the actual column height.
            let h = heights[i]
            let sigmaCap = max(onePixel, min(maxSigmaPoints, (h * (0.55 + 0.90 * CGFloat(u))) + (8.0 / max(1.0, displayScale))))
            s = min(s, sigmaCap)

            // Deterministic micro-jitter (adds texture without streaks).
            if jitterAmp > 0.000_01, s > 0.000_01 {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xA11CE5E, saltB: 0xBADC0DE))
                let jr = randTriangle(&prng)
                s += CGFloat(jr) * jitterAmp
            }

            s = max(onePixel, s)
            sigma[i] = s

            // Core opacity: mostly certainty-driven (low chance => less solid).
            // Keep a floor so low chance still has visible structure.
            let core = RainSurfaceMath.clamp01((0.28 + 0.72 * pow(c, 0.85)) * (0.55 + 0.45 * pow(inorm, 0.55)) * edge)
            coreAlpha[i] = core

            // Fuzz strength: uncertainty-driven, but intensity helps.
            // This controls the diffuse bands and grain that define the silhouette.
            let fuzz = RainSurfaceMath.clamp01(
                strengthMax
                * (0.10 + 0.90 * pow(u, 0.80))
                * (0.40 + 0.60 * pow(inorm, 0.70))
                * edge
                * max(0.0, configuration.fuzzParticleAlphaMultiplier > 0 ? configuration.fuzzParticleAlphaMultiplier : 1.0)
            )
            fuzzAlpha[i] = fuzz

            // Core height ends below the mean top so the “inside fade” replaces the edge.
            let cut = s * 0.95
            coreHeights[i] = max(0.0, h - cut)
        }

        // Vertical fill gradient used for the final colour.
        let fillGradient = Gradient(stops: [
            .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
            .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0),
        ])

        // Using plotRect width so stops align across all segments.
        let width = max(1.0, plotRect.width)

        for seg in segments {
            let r = seg.range
            guard !r.isEmpty else { continue }

            let startEdgeX = plotRect.minX + CGFloat(r.lowerBound) * stepX
            let endEdgeX = plotRect.minX + CGFloat(r.upperBound) * stepX

            // Clip HARD to segment bounds and never below baseline.
            // This removes the “fuzz leaking to sides / below baseline” problem.
            let clipRect = CGRect(
                x: startEdgeX,
                y: plotRect.minY,
                width: max(0, endEdgeX - startEdgeX),
                height: max(0, baselineY - plotRect.minY)
            )
            if clipRect.width <= 0 || clipRect.height <= 0 { continue }

            // Core path (solid interior).
            let corePath = RainSurfaceGeometry.makeSurfacePath(
                for: r,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: coreHeights
            )

            // Prebuild the top edge “points” for bands (include edges).
            let first = r.lowerBound
            let last = max(first, r.upperBound - 1)

            var topPoints: [CGPoint] = []
            var pointSigma: [CGFloat] = []
            var pointCoreA: [Double] = []
            var pointFuzzA: [Double] = []

            topPoints.reserveCapacity(r.count + 2)
            pointSigma.reserveCapacity(r.count + 2)
            pointCoreA.reserveCapacity(r.count + 2)
            pointFuzzA.reserveCapacity(r.count + 2)

            func appendPoint(x: CGFloat, idx: Int) {
                let yTop = baselineY - heights[idx]
                topPoints.append(CGPoint(x: x, y: yTop))
                pointSigma.append(sigma[idx])
                pointCoreA.append(coreAlpha[idx])
                pointFuzzA.append(fuzzAlpha[idx])
            }

            appendPoint(x: startEdgeX, idx: first)

            for i in r {
                let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                appendPoint(x: x, idx: i)
            }

            appendPoint(x: endEdgeX, idx: last)

            // Core alpha shading (horizontal, per-minute).
            let coreStops = makeHorizontalStops(
                plotRect: plotRect,
                width: width,
                points: topPoints,
                alphas: pointCoreA,
                stride: 1
            )

            let coreShading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: coreStops),
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
            )

            // Draw one segment into a layer:
            // 1) draw mask (core + inside fade + outside fade + grain)
            // 2) draw fill gradient with .sourceIn (so the mask defines the silhouette)
            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))

                // --- MASK STAGE (destination alpha = probability field) ---

                // Core
                layer.fill(corePath, with: coreShading)

                // Inside fade (soften INTO the surface; removes the smooth edge)
                if insideBands > 0 {
                    drawFadeBands(
                        in: &layer,
                        plotRect: plotRect,
                        baselineY: baselineY,
                        topPoints: topPoints,
                        sigmaByPoint: pointSigma,
                        alphaByPoint: pointCoreA,
                        direction: .inside,
                        bandCount: insideBands,
                        baseStrength: 1.0,
                        falloffPower: 1.25,
                        width: width
                    )
                }

                // Outside fade (soften ABOVE the surface; heavier when chance is lower)
                if outsideBands > 0 {
                    drawFadeBands(
                        in: &layer,
                        plotRect: plotRect,
                        baselineY: baselineY,
                        topPoints: topPoints,
                        sigmaByPoint: pointSigma,
                        alphaByPoint: pointFuzzA,
                        direction: .outside,
                        bandCount: outsideBands,
                        baseStrength: 0.82,
                        falloffPower: 1.65,
                        width: width
                    )
                }

                // Grain/diffuse dots (the “fuzz” texture)
                if dotsOn, maxDots > 0 {
                    layer.drawLayer { dotsLayer in
                        if dotBlur > 0.000_01 {
                            dotsLayer.addFilter(.blur(radius: dotBlur))
                        }

                        drawDiffuseDots(
                            in: &dotsLayer,
                            plotRect: plotRect,
                            baselineY: baselineY,
                            stepX: stepX,
                            range: r,
                            heights: heights,
                            sigma: sigma,
                            coreAlpha: coreAlpha,
                            fuzzAlpha: fuzzAlpha,
                            intensityNorm: intensityNorm,
                            maxDotsPerSample: maxDots,
                            onePixel: onePixel
                        )
                    }
                }

                // --- COLOUR STAGE (apply fill through the mask) ---
                let saved = layer.blendMode
                layer.blendMode = .sourceIn

                let fillShading = GraphicsContext.Shading.linearGradient(
                    fillGradient,
                    startPoint: CGPoint(x: plotRect.midX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.midX, y: plotRect.minY)
                )

                layer.fill(Path(clipRect), with: fillShading)
                layer.blendMode = saved
            }
        }
    }

    // MARK: - Glow (optional, certainty-weighted so it does not reintroduce a hard edge)

    static func drawGlowIfEnabled(
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
        let glowOn = configuration.glowEnabled
            && configuration.glowLayers > 1
            && configuration.glowMaxAlpha > 0.000_01
        guard glowOn else { return }

        let n = min(heights.count, min(intensityNorm.count, min(certainty.count, edgeFactors.count)))
        guard n > 0 else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let maxHeight = max(1.0, baselineY - plotRect.minY)
        let heightPx = Double(maxHeight * displayScale)

        let glowMaxRadiusPx = max(0.0, Double(configuration.glowMaxRadiusPoints))
        let glowMaxScaledPx = RainSurfaceMath.clamp(
            heightPx * Double(configuration.glowMaxRadiusFractionOfHeight),
            min: 1.0,
            max: glowMaxRadiusPx
        )
        let glowRadius = CGFloat(glowMaxScaledPx) / displayScale
        if glowRadius <= 0.5 * onePixel { return }

        let certaintySmoothed = RainSurfaceMath.smooth(Array(certainty.prefix(n)), passes: 2)
        let glowCertaintyPower = max(0.01, configuration.glowCertaintyPower)

        var glowAlpha = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let c = RainSurfaceMath.clamp01(certaintySmoothed[i])
            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            var a = configuration.glowMaxAlpha * pow(c, glowCertaintyPower) * pow(inorm, 0.85)
            a *= edgeFactors[i]
            glowAlpha[i] = RainSurfaceMath.clamp01(a)
        }

        let savedBlend = context.blendMode
        context.blendMode = .screen

        for seg in segments {
            drawStackedGlow(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                range: seg.range,
                heights: heights,
                glowRadius: glowRadius,
                alphaBySample: glowAlpha,
                layers: max(2, configuration.glowLayers),
                falloffPower: max(0.01, configuration.glowFalloffPower),
                color: configuration.glowColor,
                edgeSofteningWidth: configuration.diffusionEdgeSofteningWidth,
                onePixel: onePixel,
                stopStride: max(1, configuration.diffusionStopStride)
            )
        }

        context.blendMode = savedBlend
    }

    // MARK: - Fade bands

    private enum FadeDirection { case inside, outside }

    private static func drawFadeBands(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        topPoints: [CGPoint],
        sigmaByPoint: [CGFloat],
        alphaByPoint: [Double],
        direction: FadeDirection,
        bandCount: Int,
        baseStrength: Double,
        falloffPower: Double,
        width: CGFloat
    ) {
        guard bandCount > 0 else { return }
        guard topPoints.count >= 2, topPoints.count == sigmaByPoint.count, topPoints.count == alphaByPoint.count else { return }

        let denom = Double(bandCount)

        for k in 0..<bandCount {
            let t0 = Double(k) / denom
            let t1 = Double(k + 1) / denom
            let tMid = 0.5 * (t0 + t1)

            let w: Double
            switch direction {
            case .inside:
                // Alpha increases downward into the fill.
                w = pow(max(0.0, tMid), falloffPower)
            case .outside:
                // Alpha decreases upward away from the fill.
                w = pow(max(0.0, 1.0 - tMid), falloffPower)
            }

            if w <= 0.000_01 { continue }

            var outer: [CGPoint] = topPoints
            var inner: [CGPoint] = topPoints

            for i in 0..<topPoints.count {
                let s = sigmaByPoint[i] * 0.95

                switch direction {
                case .inside:
                    // Inside bands live below the top edge.
                    inner[i].y = min(baselineY, topPoints[i].y + s * CGFloat(t0))
                    outer[i].y = min(baselineY, topPoints[i].y + s * CGFloat(t1))
                case .outside:
                    // Outside bands live above the top edge.
                    inner[i].y = topPoints[i].y - s * 0.85 * CGFloat(t0)
                    outer[i].y = topPoints[i].y - s * 0.85 * CGFloat(t1)
                }
            }

            var band = Path()
            addSmoothBandPath(&band, outer: outer, inner: inner)

            // Per-x alpha for this band.
            var stops: [Gradient.Stop] = []
            stops.reserveCapacity(topPoints.count)

            for i in 0..<topPoints.count {
                let locRaw = (topPoints[i].x - plotRect.minX) / max(1.0, width)
                let loc = max(0.0, min(1.0, locRaw))
                let a = RainSurfaceMath.clamp01(alphaByPoint[i] * baseStrength * w)
                stops.append(.init(color: Color.white.opacity(a), location: loc))
            }

            if stops.count >= 2 {
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: stops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )
                context.fill(band, with: shading)
            }
        }
    }

    // MARK: - Diffuse dots (mask grain)

    private static func drawDiffuseDots(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        sigma: [CGFloat],
        coreAlpha: [Double],
        fuzzAlpha: [Double],
        intensityNorm: [Double],
        maxDotsPerSample: Int,
        onePixel: CGFloat
    ) {
        guard maxDotsPerSample > 0 else { return }

        for i in range {
            let h = heights[i]
            if h <= 0.000_01 { continue }

            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            if inorm <= 0.000_01 { continue }

            let s = max(onePixel, sigma[i])
            let topY = baselineY - h

            let ca = coreAlpha[i]
            let fa = fuzzAlpha[i]
            if (ca <= 0.000_5) && (fa <= 0.000_5) { continue }

            // Density is driven by fuzzAlpha (which is uncertainty-heavy).
            let density = RainSurfaceMath.clamp01(0.18 + 0.82 * fa)
            let desired = Double(maxDotsPerSample) * density
            let dotCount = max(1, Int(desired.rounded(.toNearestOrAwayFromZero)))

            for j in 0..<dotCount {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xFEEDBEEF, saltB: (j &* 167) &+ 29))

                let rx = prng.nextDouble01()
                let x = plotRect.minX + (CGFloat(i) + CGFloat(rx)) * stepX

                // Mix inside + outside dots.
                // Outside dominates as uncertainty increases (already in fa).
                let chooser = prng.nextDouble01()
                let outsideWeight = RainSurfaceMath.clamp01(0.40 + 0.60 * fa)

                let y: CGFloat
                if chooser < outsideWeight {
                    // Outside: above the top edge (soft boundary extension).
                    let t = prng.nextDouble01()
                    let up = CGFloat(pow(t, 1.35)) * (s * 0.85)
                    y = max(plotRect.minY, topY - up)
                } else {
                    // Inside: just under the top edge (breaks any remaining smoothness).
                    let t = prng.nextDouble01()
                    let down = CGFloat(pow(t, 1.15)) * (s * 0.95)
                    y = min(baselineY, topY + down)
                }

                let rr = prng.nextDouble01()
                let r = max(onePixel * 0.75, onePixel * (0.95 + 2.60 * rr) * (0.65 + 0.85 * CGFloat(fa)))

                // Alpha fades with distance away from the ridge.
                let dy = abs(y - topY)
                let tFade = RainSurfaceMath.clamp01(Double(dy / max(onePixel, s)))
                let ridgeFade = pow(1.0 - tFade, 1.20)

                let ra = prng.nextDouble01()
                let a = RainSurfaceMath.clamp01((0.08 + 0.22 * ra) * (0.25 + 0.75 * fa) * ridgeFade)

                if a <= 0.000_5 { continue }

                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(a)))
            }
        }
    }

    // MARK: - Glow (stacked, screen blended)

    private static func drawStackedGlow(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        glowRadius: CGFloat,
        alphaBySample: [Double],
        layers: Int,
        falloffPower: Double,
        color: Color,
        edgeSofteningWidth: Double,
        onePixel: CGFloat,
        stopStride: Int
    ) {
        guard let first = range.first else { return }
        let last = max(first, range.upperBound - 1)

        let startEdgeX = plotRect.minX + CGFloat(range.lowerBound) * stepX
        let endEdgeX = plotRect.minX + CGFloat(range.upperBound) * stepX

        var points: [CGPoint] = []
        var baseAlpha: [Double] = []

        points.reserveCapacity(range.count + 2)
        baseAlpha.reserveCapacity(range.count + 2)

        let leftSoft = segmentEdgeSofteningFactor(index: first, range: range, widthFraction: edgeSofteningWidth)
        points.append(CGPoint(x: startEdgeX, y: baselineY - heights[first]))
        baseAlpha.append(alphaBySample[first] * leftSoft)

        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            let soft = segmentEdgeSofteningFactor(index: i, range: range, widthFraction: edgeSofteningWidth)
            points.append(CGPoint(x: x, y: y))
            baseAlpha.append(alphaBySample[i] * soft)
        }

        let rightSoft = segmentEdgeSofteningFactor(index: last, range: range, widthFraction: edgeSofteningWidth)
        points.append(CGPoint(x: endEdgeX, y: baselineY - heights[last]))
        baseAlpha.append(alphaBySample[last] * rightSoft)

        let peakAlpha = baseAlpha.max() ?? 0.0
        guard peakAlpha > 0.000_5, glowRadius > (0.5 * onePixel) else { return }

        baseAlpha = RainSurfaceMath.smooth(baseAlpha, passes: 2)

        let width = max(0.000_01, plotRect.width)
        let denom = Double(max(1, layers - 1))
        let stride = max(1, stopStride)

        for k in 0..<(layers - 1) {
            let t0 = Double(k) / denom
            let t1 = Double(k + 1) / denom
            let tMid = 0.5 * (t0 + t1)

            let w = pow(max(0.0, 1.0 - tMid), falloffPower)
            if w <= 0.000_01 { continue }

            let outer = insetPointsDownConstant(points: points, radius: glowRadius, baselineY: baselineY, fraction: CGFloat(t0))
            let inner = insetPointsDownConstant(points: points, radius: glowRadius, baselineY: baselineY, fraction: CGFloat(t1))

            var band = Path()
            addSmoothBandPath(&band, outer: outer, inner: inner)

            var stops: [Gradient.Stop] = []
            stops.reserveCapacity((points.count / stride) + 2)

            var j = 0
            while j < points.count {
                let locRaw = (points[j].x - plotRect.minX) / width
                let loc = max(0.0, min(1.0, locRaw))
                let a = RainSurfaceMath.clamp01(baseAlpha[j] * w)
                stops.append(.init(color: color.opacity(a), location: loc))
                j += stride
            }

            if stops.count >= 2 {
                let g = Gradient(stops: stops)
                let shading = GraphicsContext.Shading.linearGradient(
                    g,
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )
                context.fill(band, with: shading)
            }
        }
    }

    // MARK: - Helpers

    private static func makeHorizontalStops(
        plotRect: CGRect,
        width: CGFloat,
        points: [CGPoint],
        alphas: [Double],
        stride: Int
    ) -> [Gradient.Stop] {
        let s = max(1, stride)

        var stops: [Gradient.Stop] = []
        stops.reserveCapacity((points.count / s) + 2)

        var i = 0
        while i < points.count {
            let locRaw = (points[i].x - plotRect.minX) / max(1.0, width)
            let loc = max(0.0, min(1.0, locRaw))
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: Color.white.opacity(a), location: loc))
            i += s
        }

        if stops.count == 1 {
            let c = stops[0].color
            stops.append(.init(color: c, location: min(1.0, stops[0].location + 0.0001)))
        }

        return stops
    }

    private static func insetPointsDownConstant(points: [CGPoint], radius: CGFloat, baselineY: CGFloat, fraction: CGFloat) -> [CGPoint] {
        let f = max(0, min(1, fraction))
        let dy = max(0, radius) * f

        var out = points
        for i in 0..<out.count {
            out[i].y = min(baselineY, out[i].y + dy)
        }
        return out
    }

    private static func addSmoothBandPath(_ path: inout Path, outer: [CGPoint], inner: [CGPoint]) {
        guard outer.count >= 2, inner.count == outer.count else { return }

        RainSurfaceGeometry.addSmoothQuadSegments(&path, points: outer, moveToFirst: true)

        if let innerLast = inner.last {
            path.addLine(to: innerLast)
        }

        let innerRev = Array(inner.reversed())
        RainSurfaceGeometry.addSmoothQuadSegments(&path, points: innerRev, moveToFirst: false)

        if let outerFirst = outer.first {
            path.addLine(to: outerFirst)
        }

        path.closeSubpath()
    }

    private static func segmentEdgeSofteningFactor(index: Int, range: Range<Int>, widthFraction: Double) -> Double {
        let w = RainSurfaceMath.clamp01(widthFraction)
        guard w > 0.000_01 else { return 1.0 }

        let count = max(1, range.count)
        if count <= 2 { return 1.0 }

        let pos = Double(index - range.lowerBound) / Double(count - 1)
        let left = RainSurfaceMath.smoothstep01(min(1.0, pos / w))
        let right = RainSurfaceMath.smoothstep01(min(1.0, (1.0 - pos) / w))
        return min(left, right)
    }

    private static func randTriangle(_ prng: inout RainSurfacePRNG) -> Double {
        (prng.nextDouble01() + prng.nextDouble01()) - 1.0
    }
}
    
