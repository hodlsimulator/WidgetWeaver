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

        if configuration.baselineSoftOpacityMultiplier > 0,
           configuration.baselineSoftWidthMultiplier > 1
        {
            let softWidth = max(
                configuration.baselineLineWidth,
                configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier
            )
            let softOpacity = max(
                0.0,
                min(1.0, configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier)
            )

            let softStyle = StrokeStyle(
                lineWidth: max(onePixel, softWidth),
                lineCap: .round
            )

            context.stroke(
                base,
                with: .color(configuration.baselineColor.opacity(softOpacity)),
                style: softStyle
            )
        }

        let stroke = StrokeStyle(
            lineWidth: max(onePixel, configuration.baselineLineWidth),
            lineCap: .round
        )

        context.stroke(
            base,
            with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)),
            style: stroke
        )
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
            .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0)
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

    // MARK: - Internal texture (optional)
    //
    // The default configuration disables this. When enabled, it renders as soft dots (not streaks).
    //
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
        guard configuration.textureEnabled else { return }
        guard configuration.textureMaxAlpha > 0.000_01 else { return }

        let minDots = max(0, configuration.textureStreaksMin)
        let maxDots = max(minDots, configuration.textureStreaksMax)
        guard maxDots > 0 else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let baseSize = max(onePixel, onePixel * configuration.textureLineWidthMultiplier)

        context.drawLayer { layer in
            if configuration.textureBlurRadiusPoints > 0 {
                layer.addFilter(.blur(radius: configuration.textureBlurRadiusPoints))
            }

            for seg in segments {
                layer.drawLayer { clipped in
                    clipped.clip(to: seg.surfacePath)

                    for i in seg.range {
                        let h = heights[i]
                        guard h > 0 else { continue }

                        let iW = pow(intensityNorm[i], configuration.textureIntensityPower)
                        let u = 1.0 - RainSurfaceMath.clamp01(certainty[i])
                        let uBoost = 1.0 + configuration.textureUncertaintyAlphaBoost * pow(u, 0.85)

                        let alpha = RainSurfaceMath.lerp(
                            configuration.textureMinAlpha,
                            configuration.textureMaxAlpha,
                            iW
                        ) * uBoost * edgeFactors[i]

                        guard alpha > 0.000_01 else { continue }

                        let centreX = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                        let topY = baselineY - h

                        let insetTop = max(0, h * configuration.textureTopInsetFractionOfHeight)
                        let yMin = topY + insetTop
                        let yMax = baselineY - insetTop
                        guard yMax > yMin else { continue }

                        let dotCount = max(
                            minDots,
                            min(maxDots, Int(round(RainSurfaceMath.lerp(Double(minDots), Double(maxDots), iW))))
                        )
                        guard dotCount > 0 else { continue }

                        var rng = RainSurfacePRNG(
                            seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0x71F1, saltB: dotCount)
                        )

                        let xSpread = Double(stepX) * 0.85
                        for _ in 0..<dotCount {
                            let rx = (rng.nextDouble01() - 0.5) * xSpread
                            let ry = rng.nextDouble01()
                            let y = RainSurfaceMath.lerp(Double(yMin), Double(yMax), ry)

                            let r = baseSize * CGFloat(0.8 + 1.6 * rng.nextDouble01())
                            let cx = centreX + CGFloat(rx)

                            let g = Gradient(stops: [
                                .init(color: configuration.fillTopColor.opacity(alpha), location: 0.0),
                                .init(color: configuration.fillTopColor.opacity(0.0), location: 1.0)
                            ])

                            let shading = GraphicsContext.Shading.radialGradient(
                                g,
                                center: CGPoint(x: cx, y: CGFloat(y)),
                                startRadius: 0,
                                endRadius: r
                            )

                            var p = Path()
                            p.addEllipse(in: CGRect(x: cx - r, y: CGFloat(y) - r, width: 2 * r, height: 2 * r))
                            clipped.fill(p, with: shading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Uncertainty mist + inner glow
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
        guard !segments.isEmpty else { return }

        let fuzzEnabled = configuration.fuzzEnabled && (configuration.fuzzRidgeEnabled || configuration.fuzzDotsEnabled)
        let glowEnabled = configuration.glowEnabled && configuration.glowMaxAlpha > 0.000_01

        guard fuzzEnabled || glowEnabled else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        let maxHeight = max(1.0, baselineY - plotRect.minY)

        let minRadiusBase = max(configuration.diffusionMinRadiusPoints, maxHeight * configuration.diffusionMinRadiusFractionOfHeight)
        let maxRadiusBase = max(configuration.diffusionMaxRadiusPoints, maxHeight * configuration.diffusionMaxRadiusFractionOfHeight)

        let stride = max(1, configuration.diffusionStopStride)

        let meanIntensity: Double = {
            var s = 0.0
            var c = 0.0
            for v in intensityNorm where v > 0 {
                s += v
                c += 1.0
            }
            return c > 0 ? (s / c) : 0.0
        }()

        let lightRainScaleRadius = (meanIntensity < configuration.diffusionLightRainMeanThreshold)
        ? configuration.diffusionLightRainMaxRadiusScale
        : 1.0

        let lightRainScaleStrength = (meanIntensity < configuration.diffusionLightRainMeanThreshold)
        ? configuration.diffusionLightRainStrengthScale
        : 1.0

        // ---------------------------------------------------------------------
        // Uncertainty mist: band-limited, speckled haze near the top edge.
        // ---------------------------------------------------------------------
        if fuzzEnabled {
            let particleBaseSize = max(onePixel, onePixel * configuration.fuzzLineWidthMultiplier)

            let richness = max(4, configuration.diffusionLayers)
            let derivedPerSampleMax = max(configuration.fuzzDotsPerSampleMax, min(18, Int(round(Double(richness) / 2.6))))
            let perSampleMax = max(1, derivedPerSampleMax)

            let savedBlend = context.blendMode
            context.blendMode = .plusLighter

            context.drawLayer { layer in
                if configuration.fuzzGlobalBlurRadiusPoints > 0 {
                    layer.addFilter(.blur(radius: configuration.fuzzGlobalBlurRadiusPoints))
                }

                for seg in segments {
                    // Segment-local max uncertainty -> segment-local band width (keeps certain segments crisp).
                    var segMaxU = 0.0
                    for i in seg.range {
                        let u = 1.0 - RainSurfaceMath.clamp01(certainty[i])
                        if u > segMaxU { segMaxU = u }
                    }

                    let uPowForBand = pow(segMaxU, configuration.diffusionRadiusUncertaintyPower)
                    var segRadius = CGFloat(RainSurfaceMath.lerp(Double(minRadiusBase), Double(maxRadiusBase), uPowForBand))
                    segRadius *= configuration.fuzzLengthMultiplier
                    segRadius *= CGFloat(lightRainScaleRadius)

                    // Clamp keeps the halo from getting “puffy” relative to bin width.
                    segRadius = min(segRadius, max(6.0, stepX * 3.25))

                    let bandWidth = max(onePixel, segRadius * 2.4)

                    let bandPath = seg.topEdgePath.strokedPath(
                        StrokeStyle(lineWidth: bandWidth, lineCap: .round, lineJoin: .round)
                    )

                    layer.drawLayer { clipped in
                        clipped.clip(to: bandPath)

                        if configuration.fuzzOutsideOnly {
                            let outsideMask = RainSurfaceGeometry.makeOutsideMaskPath(
                                plotRect: plotRect,
                                surfacePath: seg.surfacePath,
                                padding: bandWidth * 0.55
                            )
                            clipped.clip(to: outsideMask, style: FillStyle(eoFill: true))
                        }

                        for i in seg.range {
                            if (i % stride) != 0 { continue }

                            let h = heights[i]
                            guard h > 0 else { continue }

                            let edge = edgeFactors[i]
                            guard edge > 0.000_01 else { continue }

                            let c = RainSurfaceMath.clamp01(certainty[i])
                            let u = 1.0 - c
                            if u <= 0.035 { continue }

                            let iW = pow(intensityNorm[i], 0.65)

                            let uPowR = pow(u, configuration.diffusionRadiusUncertaintyPower)
                            let uPowS = pow(u, configuration.diffusionStrengthUncertaintyPower)

                            var radius = CGFloat(RainSurfaceMath.lerp(Double(minRadiusBase), Double(maxRadiusBase), uPowR))
                            radius *= configuration.fuzzLengthMultiplier
                            radius *= CGFloat(lightRainScaleRadius)
                            radius = min(radius, max(6.0, stepX * 3.25))

                            let drizzleGate: Double
                            if iW <= 0.000_01 {
                                drizzleGate = configuration.diffusionLowIntensityGateMin
                            } else if iW < configuration.diffusionDrizzleThreshold {
                                let t = iW / max(0.000_001, configuration.diffusionDrizzleThreshold)
                                drizzleGate = RainSurfaceMath.lerp(configuration.diffusionLowIntensityGateMin, 1.0, t)
                            } else {
                                drizzleGate = 1.0
                            }

                            let base = max(0.0, configuration.diffusionStrengthMinUncertainTerm)
                            let strengthAtU1 = max(0.0, configuration.diffusionStrengthMax)

                            var strength = (base * u) + (uPowS * max(0.0, strengthAtU1 - base))
                            strength *= drizzleGate
                            strength *= lightRainScaleStrength
                            strength *= edge

                            let strengthMax = max(0.000_001, configuration.diffusionStrengthMax)
                            let s01 = RainSurfaceMath.clamp01(strength / strengthMax)

                            if s01 <= 0.020 { continue }

                            // Softening near segment edges reduces “hard cut” fuzz boundaries.
                            let edgeSoft = segmentEdgeSofteningFactor(
                                index: i,
                                range: seg.range,
                                widthFraction: configuration.diffusionEdgeSofteningWidth
                            )

                            let centreX = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                            let topY = baselineY - h

                            // Continuous ridge haze: a couple of soft “splats” per sample.
                            if configuration.fuzzRidgeEnabled {
                                let centreY = topY - radius * 0.22

                                let coreRadius = max(onePixel, radius * CGFloat(max(0.05, configuration.fuzzRidgeCoreRadiusMultiplier)))
                                let featherRadius = max(coreRadius, radius * CGFloat(max(0.10, configuration.fuzzRidgeFeatherRadiusMultiplier)))

                                let coreAlpha = strength * max(0.0, configuration.fuzzRidgeCoreAlphaMultiplier) * edgeSoft
                                let featherAlpha = strength * max(0.0, configuration.fuzzRidgeFeatherAlphaMultiplier) * edgeSoft

                                if coreAlpha > 0.000_01 {
                                    drawRadialSplat(
                                        in: &clipped,
                                        center: CGPoint(x: centreX, y: centreY),
                                        radius: coreRadius,
                                        color: configuration.fillTopColor,
                                        alpha: coreAlpha
                                    )
                                }

                                if featherAlpha > 0.000_01 {
                                    drawRadialSplat(
                                        in: &clipped,
                                        center: CGPoint(x: centreX, y: centreY),
                                        radius: featherRadius,
                                        color: configuration.fillTopColor,
                                        alpha: featherAlpha
                                    )
                                }
                            }

                            guard configuration.fuzzDotsEnabled else { continue }

                            let count = max(
                                1,
                                min(
                                    perSampleMax,
                                    Int(
                                        round(
                                            RainSurfaceMath.lerp(
                                                1.0,
                                                Double(perSampleMax),
                                                0.55 * s01 + 0.45 * pow(u, 1.05)
                                            )
                                        )
                                    )
                                )
                            )

                            var rng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xA13F, saltB: count))

                            let xSpread = Double(stepX) * 1.05
                            let jitterAmp = configuration.diffusionJitterAmplitudePoints

                            for _ in 0..<count {
                                let rx = (rng.nextDouble01() - 0.5) * xSpread
                                let ry = rng.nextDouble01()

                                // Falloff keeps particles concentrated near the ridge.
                                let fall = pow(1.0 - ry, max(0.25, configuration.diffusionFalloffPower))

                                let y = Double(topY) - (Double(radius) * (0.15 + 0.95 * ry)) + (rng.nextDouble01() - 0.5) * jitterAmp
                                let r = max(
                                    particleBaseSize,
                                    particleBaseSize * CGFloat(0.70 + 1.85 * rng.nextDouble01()) + radius * 0.10
                                )

                                let a = strength
                                * max(0.0, configuration.fuzzParticleAlphaMultiplier)
                                * (0.35 + 0.65 * rng.nextDouble01())
                                * fall
                                * edgeSoft

                                if a <= 0.000_01 { continue }

                                let cx = centreX + CGFloat(rx)

                                drawRadialSplat(
                                    in: &clipped,
                                    center: CGPoint(x: cx, y: CGFloat(y)),
                                    radius: r,
                                    color: configuration.fillTopColor,
                                    alpha: a
                                )
                            }
                        }
                    }
                }
            }

            context.blendMode = savedBlend
        }

        // ---------------------------------------------------------------------
        // Inner glow: clipped to the surface fill (no protrusion above the ribbon).
        // ---------------------------------------------------------------------
        if glowEnabled {
            let meanGlowStrength: Double = {
                var sum = 0.0
                var count = 0.0
                for i in 0..<min(intensityNorm.count, certainty.count) {
                    let iW = intensityNorm[i]
                    if iW <= 0.000_01 { continue }
                    let c = RainSurfaceMath.clamp01(certainty[i])
                    let g = pow(iW, 0.85) * pow(c, configuration.glowCertaintyPower) * edgeFactors[i]
                    if g > 0.000_01 {
                        sum += g
                        count += 1.0
                    }
                }
                return count > 0 ? (sum / count) : 0.0
            }()

            guard meanGlowStrength > 0.000_01 else { return }

            let maxGlowRadius = max(configuration.glowMaxRadiusPoints, maxHeight * configuration.glowMaxRadiusFractionOfHeight)
            let layers = max(1, configuration.glowLayers)

            let savedBlend = context.blendMode
            context.blendMode = .plusLighter

            context.drawLayer { layer in
                for seg in segments {
                    layer.drawLayer { inner in
                        // Clipping to the filled ribbon makes the glow inward-only.
                        inner.clip(to: seg.surfacePath)

                        for k in 0..<layers {
                            let t = layers == 1 ? 0.0 : Double(k) / Double(layers - 1)
                            let fall = pow(1.0 - t, max(0.2, configuration.glowFalloffPower))

                            let alpha = min(1.0, configuration.glowMaxAlpha * fall) * meanGlowStrength
                            if alpha <= 0.000_01 { continue }

                            let radius = CGFloat(t) * maxGlowRadius
                            let lineWidth = max(onePixel, onePixel * 1.2 + radius * 2.15)

                            let style = StrokeStyle(
                                lineWidth: lineWidth,
                                lineCap: .round,
                                lineJoin: .round
                            )

                            inner.stroke(
                                seg.topEdgePath,
                                with: .color(configuration.glowColor.opacity(alpha)),
                                style: style
                            )
                        }
                    }
                }
            }

            context.blendMode = savedBlend
        }
    }

    // MARK: - Helpers

    private static func drawRadialSplat(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        color: Color,
        alpha: Double
    ) {
        let r = max(0.0, radius)
        guard r > 0.000_5 else { return }

        let g = Gradient(stops: [
            .init(color: color.opacity(alpha), location: 0.0),
            .init(color: color.opacity(0.0), location: 1.0)
        ])

        let shading = GraphicsContext.Shading.radialGradient(
            g,
            center: center,
            startRadius: 0,
            endRadius: r
        )

        var p = Path()
        p.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        context.fill(p, with: shading)
    }

    private static func segmentEdgeSofteningFactor(
        index: Int,
        range: Range<Int>,
        widthFraction: Double
    ) -> Double {
        let w = RainSurfaceMath.clamp01(widthFraction)
        guard w > 0.000_01 else { return 1.0 }

        let count = max(1, range.count)
        if count <= 2 { return 1.0 }

        let pos = Double(index - range.lowerBound) / Double(count - 1) // 0...1
        let left = RainSurfaceMath.smoothstep01(min(1.0, pos / w))
        let right = RainSurfaceMath.smoothstep01(min(1.0, (1.0 - pos) / w))
        return min(left, right)
    }
}
