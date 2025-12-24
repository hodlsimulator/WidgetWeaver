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

        // Baseline stays visible even under the filled ribbon.
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

    // MARK: - Internal texture (disabled by design)

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
        // No grain, particles, dots, streaks, or noise textures are rendered as an interior fill layer.
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

    // MARK: - Layer 3 (Diffusion) + Layer 4 (Glow)

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
        let diffusionEnabled = configuration.fuzzEnabled
        let glowEnabled = configuration.glowEnabled

        let diffusionOn = diffusionEnabled && configuration.diffusionLayers > 1 && configuration.diffusionStrengthMax > 0.000_01
        let glowOn = glowEnabled && configuration.glowLayers > 1 && configuration.glowMaxAlpha > 0.000_01

        guard diffusionOn || glowOn else { return }
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
        var uncertaintyBySample = [Double](repeating: 0, count: n)

        let drizzleThreshold = max(0.000_001, configuration.diffusionDrizzleThreshold)
        let gateMin = RainSurfaceMath.clamp01(configuration.diffusionLowIntensityGateMin)

        let strengthMax = max(0.0, configuration.diffusionStrengthMax)
        let strengthMinFactor = RainSurfaceMath.clamp01(configuration.diffusionStrengthMinUncertainTerm)
        let strengthPower = max(0.01, configuration.diffusionStrengthUncertaintyPower)
        let radiusPower = max(0.01, configuration.diffusionRadiusUncertaintyPower)

        // Heavy rain boost: adds surface energy without any line/streak texture.
        let heavyStart = 0.45
        let heavyEnd = 0.85
        let heavyRadiusBoostMax = 0.25
        let heavyStrengthBoostMax = 0.20

        // Certainty is smoothed for rendering to avoid banding artifacts in the diffusion mask.
        let certaintySmoothed = RainSurfaceMath.smooth(Array(certainty.prefix(n)), passes: 3)

        // Optional jitter in pixel-like units, converted into points.
        let jitterAmpPx = max(0.0, configuration.diffusionJitterAmplitudePoints)
        let jitterAmp = CGFloat(jitterAmpPx) / max(1.0, displayScale)

        let glowCertaintyPower = max(0.01, configuration.glowCertaintyPower)

        for i in 0..<n {
            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certaintySmoothed[i])
            let u = RainSurfaceMath.clamp01(1.0 - c)
            uncertaintyBySample[i] = u

            // Light-rain scaling (keeps fuzz tighter for drizzle/light rain).
            var localMaxRadius = maxRadius
            var localStrengthMax = strengthMax
            if inorm < configuration.diffusionLightRainMeanThreshold {
                localMaxRadius = max(onePixel, localMaxRadius * CGFloat(configuration.diffusionLightRainMaxRadiusScale))
                localStrengthMax = localStrengthMax * configuration.diffusionLightRainStrengthScale
            }

            // Uncertainty-to-radius/strength mapping.
            let rT = pow(u, radiusPower)
            var radius = minRadius + (localMaxRadius - minRadius) * CGFloat(rT)

            let sT = pow(u, strengthPower)
            let strengthFactor = strengthMinFactor + (1.0 - strengthMinFactor) * sT
            var strength = localStrengthMax * strengthFactor

            // Low-intensity gating (prevents over-fuzz for near-zero precipitation).
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

            // Deterministic jitter: adds micro-structure without streaks.
            if jitterAmp > 0.000_01, strength > 0.000_01 {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0x4A17B156, saltB: 0x00C0FFEE))
                let nR = randTriangle(&prng)     // -1...1, biased towards 0
                let nA = randSigned(&prng)       // -1...1

                // Jitter scales with fuzz strength (more certainty => smaller jitter).
                let fuzziness = RainSurfaceMath.clamp01(strengthFactor)
                let amp = Double(jitterAmp) * fuzziness

                radius += CGFloat(nR) * CGFloat(amp)
                strength *= (1.0 + 0.22 * fuzziness * nA)
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
        }

        let dotsOn = configuration.fuzzDotsEnabled && configuration.fuzzDotsPerSampleMax > 0

        let radiusSmoothPasses = (jitterAmpPx > 0.000_01 || dotsOn) ? 1 : 2
        let alphaSmoothPasses = (jitterAmpPx > 0.000_01 || dotsOn) ? 2 : 4

        context.drawLayer { inner in
            if diffusionOn {
                let savedBlend = inner.blendMode
                inner.blendMode = .destinationOut

                let diffusionBlur = max(0, configuration.fuzzGlobalBlurRadiusPoints)

                for seg in segments {
                    if diffusionBlur > 0.000_01 {
                        inner.drawLayer { diffLayer in
                            diffLayer.addFilter(.blur(radius: diffusionBlur))

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
                                stopStride: max(1, configuration.diffusionStopStride),
                                radiusSmoothPasses: radiusSmoothPasses,
                                alphaSmoothPasses: alphaSmoothPasses
                            )

                            if dotsOn {
                                drawDiffusionSprayDots(
                                    in: &diffLayer,
                                    plotRect: plotRect,
                                    baselineY: baselineY,
                                    stepX: stepX,
                                    range: seg.range,
                                    heights: heights,
                                    intensityNorm: intensityNorm,
                                    uncertainty: uncertaintyBySample,
                                    radiusBySample: diffusionRadiusBySample,
                                    alphaBySample: diffusionAlphaBySample,
                                    maxDotsPerSample: max(0, configuration.fuzzDotsPerSampleMax),
                                    onePixel: onePixel
                                )
                            }
                        }
                    } else {
                        drawStackedDiffusion(
                            in: &inner,
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
                            stopStride: max(1, configuration.diffusionStopStride),
                            radiusSmoothPasses: radiusSmoothPasses,
                            alphaSmoothPasses: alphaSmoothPasses
                        )

                        if dotsOn {
                            drawDiffusionSprayDots(
                                in: &inner,
                                plotRect: plotRect,
                                baselineY: baselineY,
                                stepX: stepX,
                                range: seg.range,
                                heights: heights,
                                intensityNorm: intensityNorm,
                                uncertainty: uncertaintyBySample,
                                radiusBySample: diffusionRadiusBySample,
                                alphaBySample: diffusionAlphaBySample,
                                maxDotsPerSample: max(0, configuration.fuzzDotsPerSampleMax),
                                onePixel: onePixel
                            )
                        }
                    }
                }

                inner.blendMode = savedBlend
            }

            if glowOn, glowRadius > 0.000_01 {
                let savedBlend = inner.blendMode
                inner.blendMode = .screen

                for seg in segments {
                    drawStackedGlow(
                        in: &inner,
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

                inner.blendMode = savedBlend
            }
        }
    }

    // MARK: - Diffusion implementation (multi-contour stacked-alpha)

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
        stopStride: Int,
        radiusSmoothPasses: Int,
        alphaSmoothPasses: Int
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

        radii = RainSurfaceMath.smooth(radii, passes: max(0, radiusSmoothPasses))
        baseAlpha = RainSurfaceMath.smooth(baseAlpha, passes: max(0, alphaSmoothPasses))

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

    // MARK: - Diffusion micro-structure (dot "spray", blurred as part of the diffusion layer)

    private static func drawDiffusionSprayDots(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        intensityNorm: [Double],
        uncertainty: [Double],
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

            let u = RainSurfaceMath.clamp01(uncertainty[i])

            // Dot density is driven mainly by uncertainty, with intensity providing a smaller boost.
            let density = RainSurfaceMath.clamp01((u * 0.85) + (inorm * 0.25))
            let desired = Double(maxDotsPerSample) * pow(density, 0.85)

            let dotCount = Int(desired.rounded(.toNearestOrAwayFromZero))
            if dotCount <= 0 { continue }

            let topY = baselineY - h
            let band = max(onePixel, radiusBySample[i] * 0.85)

            for j in 0..<dotCount {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xD07D07D0, saltB: (j &* 131) &+ 17))

                let rx = prng.nextDouble01()
                let x = plotRect.minX + (CGFloat(i) + CGFloat(rx)) * stepX

                // Bias Y closer to the top edge, but still inside the fill (destinationOut needs overlap).
                let ry = prng.nextDouble01()
                let y = topY + CGFloat(ry * ry) * band

                // Small circles; blur expands them into a fuzzy edge (no streaks).
                let rr = prng.nextDouble01()
                let r = max(onePixel * 0.60, onePixel * (0.75 + 2.10 * rr) * (0.70 + 0.60 * CGFloat(u)))

                let ra = prng.nextDouble01()
                let dotAlpha = RainSurfaceMath.clamp01(a0 * (0.22 + 0.38 * u) * (0.45 + 0.55 * ra))

                if dotAlpha <= 0.000_5 { continue }

                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                let p = Path(ellipseIn: rect)
                context.fill(p, with: .color(Color.black.opacity(dotAlpha)))
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

    // MARK: - PRNG helpers

    private static func randSigned(_ prng: inout RainSurfacePRNG) -> Double {
        (prng.nextDouble01() * 2.0) - 1.0
    }

    private static func randTriangle(_ prng: inout RainSurfacePRNG) -> Double {
        // Sum of uniforms yields a triangular distribution (more values near 0).
        (prng.nextDouble01() + prng.nextDouble01()) - 1.0
    }
}
