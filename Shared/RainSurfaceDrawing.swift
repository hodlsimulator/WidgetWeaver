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

        // Baseline stays visible even when the filled ribbon is bright.
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

    // MARK: - Fill

    static func drawFill(
        in context: inout GraphicsContext,
        rect: CGRect,
        baselineY: CGFloat,
        segments: [RainForecastSurfaceRenderer.WetSegment],
        configuration: RainForecastSurfaceConfiguration
    ) {
        guard !segments.isEmpty else { return }

        let gradient = Gradient(stops: [
            .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
            .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0),
        ])

        let shading = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: rect.midX, y: baselineY),
            endPoint: CGPoint(x: rect.midX, y: rect.minY)
        )

        for seg in segments {
            context.fill(seg.surfacePath, with: shading)
        }
    }

    // MARK: - Internal texture (intentionally disabled)

    static func drawInternalGrainIfEnabled(
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
        // Intentionally empty.
        _ = context
        _ = plotRect
        _ = baselineY
        _ = stepX
        _ = segments
        _ = heights
        _ = intensityNorm
        _ = certainty
        _ = edgeFactors
        _ = configuration
        _ = displayScale
    }

    // MARK: - Diffusion (destinationOut) + Mist (screen) + Glow (screen)

    static func drawFuzzAndGlowIfEnabled(
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
        let diffusionOn = configuration.fuzzEnabled
            && configuration.diffusionLayers > 1
            && configuration.diffusionStrengthMax > 0.000_01

        let glowOn = configuration.glowEnabled
            && configuration.glowLayers > 1
            && configuration.glowMaxAlpha > 0.000_01

        // “Mist” haze above the surface edge (this is what the mock shows heavily).
        let mistOn = configuration.fuzzParticleAlphaMultiplier > 0.000_01

        guard diffusionOn || glowOn || mistOn else { return }
        guard !segments.isEmpty else { return }

        let n = min(heights.count, min(intensityNorm.count, min(certainty.count, edgeFactors.count)))
        guard n > 0 else { return }

        let maxHeight = max(1.0, baselineY - plotRect.minY)
        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        // Radii are configured in pixel-like units; conversion happens here.
        let heightPx = Double(maxHeight * displayScale)

        let minRadiusPx = max(0.0, Double(configuration.diffusionMinRadiusPoints))
        let maxRadiusClampPx = max(minRadiusPx, Double(configuration.diffusionMaxRadiusPoints))
        let maxRadiusScaledPx = RainSurfaceMath.clamp(
            heightPx * Double(configuration.diffusionMaxRadiusFractionOfHeight),
            min: 10.0,
            max: maxRadiusClampPx
        )

        let minRadius = CGFloat(minRadiusPx) / displayScale
        let maxRadius = CGFloat(maxRadiusScaledPx) / displayScale

        let glowMaxRadiusPx = max(0.0, Double(configuration.glowMaxRadiusPoints))
        let glowMaxScaledPx = RainSurfaceMath.clamp(
            heightPx * Double(configuration.glowMaxRadiusFractionOfHeight),
            min: 1.0,
            max: glowMaxRadiusPx
        )
        let glowRadius = CGFloat(glowMaxScaledPx) / displayScale

        var diffusionRadiusBySample = [CGFloat](repeating: 0, count: n)
        var diffusionAlphaBySample = [Double](repeating: 0, count: n)
        var glowAlphaBySample = [Double](repeating: 0, count: n)

        // Mist arrays (screen blended)
        var mistRadiusBySample = [CGFloat](repeating: 0, count: n)
        var mistAlphaBySample = [Double](repeating: 0, count: n)

        let drizzleThreshold = max(0.000_001, configuration.diffusionDrizzleThreshold)
        let gateMin = RainSurfaceMath.clamp01(configuration.diffusionLowIntensityGateMin)

        let strengthMax = max(0.0, configuration.diffusionStrengthMax)
        let strengthMinFactor = RainSurfaceMath.clamp01(configuration.diffusionStrengthMinUncertainTerm)
        let strengthPower = max(0.01, configuration.diffusionStrengthUncertaintyPower)
        let radiusPower = max(0.01, configuration.diffusionRadiusUncertaintyPower)

        // Heavy rain boost (adds energy without any streak texture).
        let heavyStart = 0.45
        let heavyEnd = 0.85
        let heavyRadiusBoostMax = 0.35
        let heavyStrengthBoostMax = 0.25

        // Certainty smoothing avoids banding/striping in the diffusion mask.
        let certaintySmoothed = RainSurfaceMath.smooth(Array(certainty.prefix(n)), passes: 3)

        // Deterministic jitter (in points) – contributes to fuzz texture without lines.
        let jitterAmpPoints = max(0.0, configuration.diffusionJitterAmplitudePoints)
        let jitterAmp = CGFloat(jitterAmpPoints) / max(1.0, displayScale)

        let glowCertaintyPower = max(0.01, configuration.glowCertaintyPower)

        for i in 0..<n {
            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certaintySmoothed[i])
            let u = RainSurfaceMath.clamp01(1.0 - c)

            // Light rain scaling keeps fuzz tighter for drizzle/light rain.
            var localMaxRadius = maxRadius
            var localStrengthMax = strengthMax
            if inorm < configuration.diffusionLightRainMeanThreshold {
                localMaxRadius = max(onePixel, localMaxRadius * CGFloat(configuration.diffusionLightRainMaxRadiusScale))
                localStrengthMax = localStrengthMax * configuration.diffusionLightRainStrengthScale
            }

            // Uncertainty → radius/strength
            let rT = pow(u, radiusPower)
            var radius = minRadius + (localMaxRadius - minRadius) * CGFloat(rT)

            let sT = pow(u, strengthPower)
            let strengthFactor = strengthMinFactor + (1.0 - strengthMinFactor) * sT
            var strength = localStrengthMax * strengthFactor

            // Low-intensity gating (prevents over-fuzz at near-zero precipitation).
            let gate: Double
            if inorm <= drizzleThreshold {
                gate = gateMin
            } else {
                let t = RainSurfaceMath.clamp01((inorm - drizzleThreshold) / max(0.000_001, 1.0 - drizzleThreshold))
                gate = RainSurfaceMath.lerp(gateMin, 1.0, RainSurfaceMath.smoothstep01(t))
            }
            strength *= gate

            // Edge fade (start/end easing).
            strength *= edgeFactors[i]

            // Heavy rain boost.
            let heavyT = RainSurfaceMath.clamp01((inorm - heavyStart) / max(0.000_001, heavyEnd - heavyStart))
            let heavyW = RainSurfaceMath.smoothstep01(heavyT)
            radius *= (1.0 + CGFloat(heavyRadiusBoostMax * heavyW))
            strength *= (1.0 + heavyStrengthBoostMax * heavyW)

            // Deterministic micro-jitter (no streaks).
            if jitterAmp > 0.000_01, strength > 0.000_01 {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0x4A17B156, saltB: 0x00C0FFEE))
                let jr = randTriangle(&prng)  // -1...1, biased towards 0
                let ja = randSigned(&prng)    // -1...1

                let fuzziness = RainSurfaceMath.clamp01(strengthFactor)
                let amp = Double(jitterAmp) * (0.35 + 0.65 * fuzziness)

                radius += CGFloat(jr) * CGFloat(amp)
                strength *= (1.0 + 0.20 * fuzziness * ja)
            }

            radius = max(onePixel, radius)
            strength = RainSurfaceMath.clamp01(strength)

            diffusionRadiusBySample[i] = radius
            diffusionAlphaBySample[i] = strength

            if glowOn {
                var g = configuration.glowMaxAlpha * pow(c, glowCertaintyPower) * inorm
                g *= edgeFactors[i]
                glowAlphaBySample[i] = RainSurfaceMath.clamp01(g)
            } else {
                glowAlphaBySample[i] = 0.0
            }

            // Mist: strong contributor to the mock’s look.
            // Drives primarily from intensity, then uncertainty; includes a small base for “smooth” cases.
            let mistBase = 0.14
            let mistU = 0.86
            var m = (mistBase + mistU * u) * pow(max(0.0, inorm), 0.62)
            m *= edgeFactors[i]
            m *= max(0.0, configuration.fuzzParticleAlphaMultiplier)
            mistAlphaBySample[i] = RainSurfaceMath.clamp01(m)

            // Mist radius: larger than diffusion radius so haze rises into the black.
            mistRadiusBySample[i] = max(onePixel, radius * 1.9)
        }

        // ---- 1) DIFFUSION: erode the fill edge (destinationOut) ----
        if diffusionOn {
            let savedBlend = context.blendMode
            context.blendMode = .destinationOut

            let diffusionBlur = max(0, configuration.fuzzGlobalBlurRadiusPoints)
            let dotsOn = configuration.fuzzDotsEnabled && configuration.fuzzDotsPerSampleMax > 0

            for seg in segments {
                context.drawLayer { diffLayer in
                    if diffusionBlur > 0.000_01 {
                        diffLayer.addFilter(.blur(radius: diffusionBlur))
                    }

                    drawStackedDiffusion(
                        in: &diffLayer,
                        plotRect: plotRect,
                        baselineY: baselineY,
                        stepX: stepX,
                        range: seg.range,
                        heights: heights,
                        radiusBySample: diffusionRadiusBySample,
                        alphaBySample: diffusionAlphaBySample,
                        layers: max(2, configuration.diffusionLayers),
                        falloffPower: max(0.01, configuration.diffusionFalloffPower),
                        color: .black,
                        edgeSofteningWidth: configuration.diffusionEdgeSofteningWidth,
                        onePixel: onePixel,
                        stopStride: max(1, configuration.diffusionStopStride)
                    )

                    if dotsOn {
                        drawErosionSprayDots(
                            in: &diffLayer,
                            plotRect: plotRect,
                            baselineY: baselineY,
                            stepX: stepX,
                            range: seg.range,
                            heights: heights,
                            intensityNorm: intensityNorm,
                            radiusBySample: diffusionRadiusBySample,
                            alphaBySample: diffusionAlphaBySample,
                            maxDotsPerSample: max(1, configuration.fuzzDotsPerSampleMax),
                            onePixel: onePixel
                        )
                    }
                }
            }

            context.blendMode = savedBlend
        }

        // ---- 2) MIST: haze above the edge (screen) ----
        if mistOn {
            let savedBlend = context.blendMode
            context.blendMode = .screen

            // Two-pass mist: a soft layer + a grain layer (no streaks).
            let softBlur = max(3.0, Double(configuration.fuzzGlobalBlurRadiusPoints) * 4.6)
            let grainBlur = max(0.0, Double(configuration.fuzzGlobalBlurRadiusPoints) * 1.35)

            for seg in segments {
                let meanAlpha = mean(mistAlphaBySample, in: seg.range)
                let meanRadius = mean(mistRadiusBySample, in: seg.range)

                if meanAlpha > 0.000_5, meanRadius > onePixel {
                    // Soft continuous haze along the ridge.
                    context.drawLayer { hazeLayer in
                        hazeLayer.addFilter(.blur(radius: CGFloat(softBlur)))

                        let lw = max(onePixel, meanRadius * 2.35)
                        let style = StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round)

                        hazeLayer.stroke(
                            seg.topEdgePath,
                            with: .color(configuration.fillTopColor.opacity(min(1.0, meanAlpha * 0.70))),
                            style: style
                        )
                    }
                }

                // Grainy haze dots (adds the “diffuse/fuzzy” texture the mock shows).
                context.drawLayer { grainLayer in
                    if grainBlur > 0.000_01 {
                        grainLayer.addFilter(.blur(radius: CGFloat(grainBlur)))
                    }

                    drawMistSprayDots(
                        in: &grainLayer,
                        plotRect: plotRect,
                        baselineY: baselineY,
                        stepX: stepX,
                        range: seg.range,
                        heights: heights,
                        intensityNorm: intensityNorm,
                        radiusBySample: mistRadiusBySample,
                        alphaBySample: mistAlphaBySample,
                        color: configuration.fillTopColor,
                        maxDotsPerSample: max(2, configuration.fuzzDotsPerSampleMax + 3),
                        onePixel: onePixel
                    )
                }
            }

            context.blendMode = savedBlend
        }

        // ---- 3) GLOW: subtle (screen) ----
        if glowOn, glowRadius > 0.000_01 {
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
                    alphaBySample: glowAlphaBySample,
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
    }

    // MARK: - Diffusion implementation (stacked contours, smooth per-sample alpha)

    private static func drawStackedDiffusion(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        radiusBySample: [CGFloat],
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
        var radii: [CGFloat] = []
        var baseAlpha: [Double] = []

        points.reserveCapacity(range.count + 2)
        radii.reserveCapacity(range.count + 2)
        baseAlpha.reserveCapacity(range.count + 2)

        let leftSoft = segmentEdgeSofteningFactor(index: first, range: range, widthFraction: edgeSofteningWidth)
        points.append(CGPoint(x: startEdgeX, y: baselineY - heights[first]))
        radii.append(radiusBySample[first])
        baseAlpha.append(alphaBySample[first] * leftSoft)

        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            let soft = segmentEdgeSofteningFactor(index: i, range: range, widthFraction: edgeSofteningWidth)
            points.append(CGPoint(x: x, y: y))
            radii.append(radiusBySample[i])
            baseAlpha.append(alphaBySample[i] * soft)
        }

        let rightSoft = segmentEdgeSofteningFactor(index: last, range: range, widthFraction: edgeSofteningWidth)
        points.append(CGPoint(x: endEdgeX, y: baselineY - heights[last]))
        radii.append(radiusBySample[last])
        baseAlpha.append(alphaBySample[last] * rightSoft)

        let peakAlpha = baseAlpha.max() ?? 0.0
        let peakRadius = radii.max() ?? 0.0
        guard peakAlpha > 0.000_5, peakRadius > (0.5 * onePixel) else { return }

        // Smoothing prevents banding; keep mild so the edge still reads “textured” once mist is applied.
        radii = RainSurfaceMath.smooth(radii, passes: 1)
        baseAlpha = RainSurfaceMath.smooth(baseAlpha, passes: 3)

        let width = max(0.000_01, plotRect.width)
        let denom = Double(max(1, layers - 1))
        let stride = max(1, stopStride)

        for k in 0..<(layers - 1) {
            let t0 = Double(k) / denom
            let t1 = Double(k + 1) / denom
            let tMid = 0.5 * (t0 + t1)

            let w = pow(max(0.0, 1.0 - tMid), falloffPower)
            if w <= 0.000_01 { continue }

            let outer = insetPointsDown(points: points, radii: radii, baselineY: baselineY, fraction: CGFloat(t0))
            let inner = insetPointsDown(points: points, radii: radii, baselineY: baselineY, fraction: CGFloat(t1))

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

    // MARK: - Mist dots (screen)

    private static func drawMistSprayDots(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        intensityNorm: [Double],
        radiusBySample: [CGFloat],
        alphaBySample: [Double],
        color: Color,
        maxDotsPerSample: Int,
        onePixel: CGFloat
    ) {
        guard maxDotsPerSample > 0 else { return }

        for i in range {
            let h = heights[i]
            if h <= 0.000_01 { continue }

            let a0 = alphaBySample[i]
            if a0 <= 0.000_5 { continue }

            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            if inorm <= 0.000_01 { continue }

            let rBand = max(onePixel, radiusBySample[i])

            // Density: intensity dominates, uncertainty has already been baked into alphaBySample.
            let density = RainSurfaceMath.clamp01(0.30 + 0.70 * pow(inorm, 0.70))
            let desired = Double(maxDotsPerSample) * density
            let dotCount = max(1, Int(desired.rounded(.toNearestOrAwayFromZero)))

            let topY = baselineY - h

            for j in 0..<dotCount {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xC011D00D, saltB: (j &* 131) &+ 17))

                let rx = prng.nextDouble01()
                let x = plotRect.minX + (CGFloat(i) + CGFloat(rx)) * stepX

                // Mostly above the ridge, with a small portion slightly inside to avoid a crisp boundary.
                let ry = prng.nextDouble01()
                let insideBias = 0.18
                let y: CGFloat
                if ry < insideBias {
                    let t = CGFloat(ry / max(0.000_001, insideBias))
                    y = topY + t * (rBand * 0.18)
                } else {
                    let t = (ry - insideBias) / max(0.000_001, (1.0 - insideBias))
                    y = topY - CGFloat(pow(t, 1.55)) * rBand
                }

                let rr = prng.nextDouble01()
                let dotR = max(onePixel * 0.70, onePixel * (0.90 + 2.60 * rr))

                let ra = prng.nextDouble01()
                let dotA = RainSurfaceMath.clamp01(a0 * (0.20 + 0.80 * ra))

                if dotA <= 0.000_5 { continue }

                let rect = CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(dotA)))
            }
        }
    }

    // MARK: - Erosion dots (destinationOut)

    private static func drawErosionSprayDots(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        intensityNorm: [Double],
        radiusBySample: [CGFloat],
        alphaBySample: [Double],
        maxDotsPerSample: Int,
        onePixel: CGFloat
    ) {
        guard maxDotsPerSample > 0 else { return }

        for i in range {
            let h = heights[i]
            if h <= 0.000_01 { continue }

            let a0 = alphaBySample[i]
            if a0 <= 0.000_5 { continue }

            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            if inorm <= 0.000_01 { continue }

            let rBand = max(onePixel, radiusBySample[i] * 0.85)

            // Erosion dots are fewer than mist dots; they exist to break the edge, not destroy the fill.
            let density = RainSurfaceMath.clamp01(0.18 + 0.82 * pow(inorm, 0.85))
            let desired = Double(maxDotsPerSample) * 0.62 * density
            let dotCount = Int(desired.rounded(.toNearestOrAwayFromZero))
            if dotCount <= 0 { continue }

            let topY = baselineY - h

            for j in 0..<dotCount {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xD07D07D0, saltB: (j &* 197) &+ 41))

                let rx = prng.nextDouble01()
                let x = plotRect.minX + (CGFloat(i) + CGFloat(rx)) * stepX

                // Bias inside the fill so destinationOut actually erodes the edge.
                let ry = prng.nextDouble01()
                let y = topY + CGFloat(pow(ry, 1.20)) * rBand

                let rr = prng.nextDouble01()
                let dotR = max(onePixel * 0.65, onePixel * (0.85 + 2.10 * rr))

                let ra = prng.nextDouble01()
                let dotA = RainSurfaceMath.clamp01(a0 * (0.10 + 0.32 * ra))

                if dotA <= 0.000_5 { continue }

                let rect = CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.black.opacity(dotA)))
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

        baseAlpha = RainSurfaceMath.smooth(baseAlpha, passes: 3)

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

    // MARK: - Band geometry helpers

    private static func insetPointsDown(points: [CGPoint], radii: [CGFloat], baselineY: CGFloat, fraction: CGFloat) -> [CGPoint] {
        guard points.count == radii.count else { return points }
        let f = max(0, min(1, fraction))

        var out = points
        for i in 0..<out.count {
            let dy = max(0, radii[i]) * f
            out[i].y = min(baselineY, out[i].y + dy)
        }
        return out
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

        let pos = Double(index - range.lowerBound) / Double(count - 1) // 0...1
        let left = RainSurfaceMath.smoothstep01(min(1.0, pos / w))
        let right = RainSurfaceMath.smoothstep01(min(1.0, (1.0 - pos) / w))
        return min(left, right)
    }

    // MARK: - Averages

    private static func mean(_ values: [Double], in range: Range<Int>) -> Double {
        guard !values.isEmpty, range.lowerBound < range.upperBound else { return 0.0 }
        let lo = max(0, range.lowerBound)
        let hi = min(values.count, range.upperBound)
        if hi <= lo { return 0.0 }

        var sum = 0.0
        for i in lo..<hi { sum += values[i] }
        return sum / Double(hi - lo)
    }

    private static func mean(_ values: [CGFloat], in range: Range<Int>) -> CGFloat {
        guard !values.isEmpty, range.lowerBound < range.upperBound else { return 0.0 }
        let lo = max(0, range.lowerBound)
        let hi = min(values.count, range.upperBound)
        if hi <= lo { return 0.0 }

        var sum: CGFloat = 0
        for i in lo..<hi { sum += values[i] }
        return sum / CGFloat(hi - lo)
    }

    // MARK: - PRNG helpers

    private static func randSigned(_ prng: inout RainSurfacePRNG) -> Double {
        (prng.nextDouble01() * 2.0) - 1.0
    }

    private static func randTriangle(_ prng: inout RainSurfacePRNG) -> Double {
        (prng.nextDouble01() + prng.nextDouble01()) - 1.0
    }
}
