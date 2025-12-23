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

        if configuration.baselineSoftOpacityMultiplier > 0, configuration.baselineSoftWidthMultiplier > 1 {
            let softWidth = max(configuration.baselineLineWidth, configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier)
            let softOpacity = max(0.0, min(1.0, configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier))
            let softStyle = StrokeStyle(lineWidth: max(onePixel, softWidth), lineCap: .round)
            context.stroke(base, with: .color(configuration.baselineColor.opacity(softOpacity)), style: softStyle)
        }

        let stroke = StrokeStyle(lineWidth: max(onePixel, configuration.baselineLineWidth), lineCap: .round)
        context.stroke(base, with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)), style: stroke)
    }

    static func drawFill(
        in context: inout GraphicsContext,
        rect: CGRect,
        baselineY: CGFloat,
        segments: [RainForecastSurfaceRenderer.WetSegment],
        configuration: RainForecastSurfaceConfiguration
    ) {
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

    // MARK: - Internal grain

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
        guard configuration.textureMaxAlpha > 0.000_01 else { return }

        let minDots = max(0, configuration.textureStreaksMin)
        let maxDots = max(minDots, configuration.textureStreaksMax)
        guard maxDots > 0 else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let dotBaseSize = max(onePixel, onePixel * configuration.textureLineWidthMultiplier)

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

                        let alpha = RainSurfaceMath.lerp(configuration.textureMinAlpha, configuration.textureMaxAlpha, iW) * uBoost * edgeFactors[i]
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

                        var rng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0x71F1, saltB: dotCount))
                        let xSpread = Double(stepX) * 0.80

                        for _ in 0..<dotCount {
                            let rx = (rng.nextDouble01() - 0.5) * xSpread
                            let y = RainSurfaceMath.lerp(Double(yMin), Double(yMax), rng.nextDouble01())

                            let sizeJitter = RainSurfaceMath.lerp(0.65, 1.45, rng.nextDouble01())
                            let r = dotBaseSize * CGFloat(sizeJitter)

                            let circle = Path(
                                ellipseIn: CGRect(
                                    x: Double(centreX) + rx - Double(r),
                                    y: y - Double(r),
                                    width: Double(r * 2),
                                    height: Double(r * 2)
                                )
                            )
                            clipped.fill(circle, with: .color(configuration.fillTopColor.opacity(alpha)))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Uncertainty mist

    static func drawUncertaintyMist(
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
        let ridgeEnabled = configuration.fuzzRidgeEnabled
        let particlesEnabled = configuration.fuzzDotsEnabled && configuration.fuzzDotsPerSampleMax > 0
        guard ridgeEnabled || particlesEnabled else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let particleBaseSize = max(onePixel, onePixel * configuration.fuzzLineWidthMultiplier)

        let maxHeight = max(1.0, baselineY - plotRect.minY)
        let minRadius = max(configuration.diffusionMinRadiusPoints, maxHeight * configuration.diffusionMinRadiusFractionOfHeight)
        let maxRadius = max(configuration.diffusionMaxRadiusPoints, maxHeight * configuration.diffusionMaxRadiusFractionOfHeight)

        let stride = max(1, configuration.diffusionStopStride)

        // Light-rain restraint
        let meanIntensity: Double = {
            var s = 0.0
            var c = 0.0
            for v in intensityNorm where v > 0 {
                s += v
                c += 1.0
            }
            return c > 0 ? (s / c) : 0.0
        }()

        let lightRainScaleRadius = (meanIntensity < configuration.diffusionLightRainMeanThreshold) ? configuration.diffusionLightRainMaxRadiusScale : 1.0
        let lightRainScaleStrength = (meanIntensity < configuration.diffusionLightRainMeanThreshold) ? configuration.diffusionLightRainStrengthScale : 1.0

        // Per-sample particle cap is derived from both the explicit per-sample max and the overall “layers” dial.
        let richness = max(4, configuration.diffusionLayers)
        let derivedPerSampleMax = max(configuration.fuzzDotsPerSampleMax, min(18, Int(round(Double(richness) / 2.6))))
        let perSampleMax = max(2, derivedPerSampleMax)

        let savedBlendMode = context.blendMode
        context.blendMode = .plusLighter

        context.drawLayer { layer in
            if configuration.fuzzGlobalBlurRadiusPoints > 0 {
                layer.addFilter(.blur(radius: configuration.fuzzGlobalBlurRadiusPoints))
            }

            for seg in segments {
                layer.drawLayer { clipped in
                    if configuration.fuzzOutsideOnly {
                        let outsideMask = RainSurfaceGeometry.makeOutsideMaskPath(
                            plotRect: plotRect,
                            surfacePath: seg.surfacePath,
                            padding: maxRadius * 2.2
                        )
                        clipped.clip(to: outsideMask, style: FillStyle(eoFill: true))
                    }

                    for i in seg.range {
                        if (i % stride) != 0 { continue }

                        let h = heights[i]
                        guard h > 0 else { continue }

                        let iW = pow(intensityNorm[i], 0.65)
                        let edge = edgeFactors[i]
                        guard edge > 0.000_01 else { continue }

                        let u = 1.0 - RainSurfaceMath.clamp01(certainty[i])
                        guard u > 0.000_01 else { continue }

                        let uPowR = pow(u, configuration.diffusionRadiusUncertaintyPower)
                        let uPowS = pow(u, configuration.diffusionStrengthUncertaintyPower)

                        // Diffusion radius grows with uncertainty, bounded by view scale.
                        var radius = CGFloat(RainSurfaceMath.lerp(Double(minRadius), Double(maxRadius), uPowR))
                        radius *= configuration.fuzzLengthMultiplier
                        radius *= CGFloat(lightRainScaleRadius)

                        // Drizzle gating keeps low intensity calm.
                        let drizzleGate: Double
                        if iW <= 0.000_01 {
                            drizzleGate = configuration.diffusionLowIntensityGateMin
                        } else if iW < configuration.diffusionDrizzleThreshold {
                            let t = iW / max(0.000_001, configuration.diffusionDrizzleThreshold)
                            drizzleGate = RainSurfaceMath.lerp(configuration.diffusionLowIntensityGateMin, 1.0, t)
                        } else {
                            drizzleGate = 1.0
                        }

                        // Strength is driven by uncertainty and then intensity-gated.
                        let base = max(0.0, configuration.diffusionStrengthMinUncertainTerm)
                        let strengthAtU1 = max(0.0, configuration.diffusionStrengthMax)
                        var strength = (base * u) + (uPowS * max(0.0, strengthAtU1 - base))
                        strength *= drizzleGate
                        strength *= lightRainScaleStrength
                        strength *= edge

                        let strengthMax = max(0.000_001, configuration.diffusionStrengthMax)
                        let s01 = RainSurfaceMath.clamp01(strength / strengthMax)
                        if s01 <= 0.015 { continue }

                        let centreX = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                        let topY = baselineY - h

                        // Ridge haze: a continuous glow-like band at the surface.
                        if ridgeEnabled {
                            let centreY = CGFloat(Double(topY) - Double(radius) * 0.12)

                            let coreRadius = max(onePixel, radius * CGFloat(max(0.05, configuration.fuzzRidgeCoreRadiusMultiplier)))
                            let featherRadius = max(coreRadius, radius * CGFloat(max(0.10, configuration.fuzzRidgeFeatherRadiusMultiplier)))

                            let coreAlpha = strength * max(0.0, configuration.fuzzRidgeCoreAlphaMultiplier)
                            let featherAlpha = strength * max(0.0, configuration.fuzzRidgeFeatherAlphaMultiplier)

                            if coreAlpha > 0.000_01 {
                                let g = Gradient(stops: [
                                    .init(color: configuration.fillTopColor.opacity(coreAlpha), location: 0.0),
                                    .init(color: configuration.fillTopColor.opacity(0.0), location: 1.0)
                                ])
                                let shading = GraphicsContext.Shading.radialGradient(
                                    g,
                                    center: CGPoint(x: centreX, y: centreY),
                                    startRadius: 0,
                                    endRadius: coreRadius
                                )

                                var p = Path()
                                p.addEllipse(in: CGRect(x: centreX - coreRadius, y: centreY - coreRadius, width: coreRadius * 2, height: coreRadius * 2))
                                clipped.fill(p, with: shading)
                            }

                            if featherAlpha > 0.000_01 {
                                let g = Gradient(stops: [
                                    .init(color: configuration.fillTopColor.opacity(featherAlpha), location: 0.0),
                                    .init(color: configuration.fillTopColor.opacity(0.0), location: 1.0)
                                ])
                                let shading = GraphicsContext.Shading.radialGradient(
                                    g,
                                    center: CGPoint(x: centreX, y: centreY),
                                    startRadius: 0,
                                    endRadius: featherRadius
                                )

                                var p = Path()
                                p.addEllipse(in: CGRect(x: centreX - featherRadius, y: centreY - featherRadius, width: featherRadius * 2, height: featherRadius * 2))
                                clipped.fill(p, with: shading)
                            }
                        }

                        guard particlesEnabled else { continue }

                        // Particle count rises with uncertainty/strength.
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
                        let xSpread = Double(stepX) * 0.95
                        let jitterAmp = configuration.diffusionJitterAmplitudePoints

                        for _ in 0..<count {
                            let rx = (rng.nextDouble01() - 0.5) * xSpread
                            let ryBase = pow(rng.nextDouble01(), 0.55) * Double(radius)
                            let ry = -ryBase + (rng.nextDouble01() - 0.5) * Double(radius) * 0.18

                            let jx = (rng.nextDouble01() - 0.5) * jitterAmp
                            let jy = (rng.nextDouble01() - 0.5) * jitterAmp

                            let x = Double(centreX) + rx + jx
                            let y = Double(topY) + ry + jy

                            // Falloff: closer to the edge is denser.
                            let dn = RainSurfaceMath.clamp01(abs(ryBase) / max(0.000_001, Double(radius)))
                            let fall = pow(1.0 - dn, configuration.diffusionFalloffPower)

                            let alpha = strength * configuration.fuzzParticleAlphaMultiplier * fall
                            if alpha <= 0.000_01 { continue }

                            let sizeJitter = RainSurfaceMath.lerp(0.70, 1.90, rng.nextDouble01())
                            let r = particleBaseSize * CGFloat(sizeJitter)

                            let circle = Path(
                                ellipseIn: CGRect(
                                    x: x - Double(r),
                                    y: y - Double(r),
                                    width: Double(r * 2),
                                    height: Double(r * 2)
                                )
                            )
                            clipped.fill(circle, with: .color(configuration.fillTopColor.opacity(alpha)))
                        }
                    }
                }
            }
        }

        context.blendMode = savedBlendMode
    }

    // MARK: - Glow

    static func drawGlow(
        in context: inout GraphicsContext,
        maxHeight: CGFloat,
        segments: [RainForecastSurfaceRenderer.WetSegment],
        intensityNorm: [Double],
        certainty: [Double],
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let maxRadius = max(
            configuration.glowMaxRadiusPoints,
            maxHeight * configuration.glowMaxRadiusFractionOfHeight
        )
        guard maxRadius > 0.000_01 else { return }

        let meanGlowStrength: Double = {
            var sum = 0.0
            var count = 0.0
            for i in 0..<min(intensityNorm.count, certainty.count) {
                let iW = pow(RainSurfaceMath.clamp01(intensityNorm[i]), 0.85)
                let cW = pow(RainSurfaceMath.clamp01(certainty[i]), configuration.glowCertaintyPower)
                let g = iW * cW
                if g > 0.000_01 {
                    sum += g
                    count += 1.0
                }
            }
            return count > 0 ? (sum / count) : 0.0
        }()

        guard meanGlowStrength > 0.000_01 else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        let savedBlendMode = context.blendMode
        context.blendMode = .plusLighter

        // Core ridge highlight (tight, no blur)
        do {
            let alpha = min(1.0, configuration.glowMaxAlpha * 0.55) * meanGlowStrength
            let style = StrokeStyle(lineWidth: max(0.5, onePixel * 1.15), lineCap: .round, lineJoin: .round)
            if alpha > 0.000_01 {
                for seg in segments {
                    context.stroke(seg.topEdgePath, with: .color(configuration.glowColor.opacity(alpha)), style: style)
                }
            }
        }

        // Bloom layers
        let layers = max(1, configuration.glowLayers)
        for k in 0..<layers {
            let t = (layers <= 1) ? 1.0 : Double(k) / Double(layers - 1)
            let radius = Double(maxRadius) * pow(t, 1.05)
            let fall = pow(1.0 - t, configuration.glowFalloffPower)

            let alpha = configuration.glowMaxAlpha * meanGlowStrength * fall
            if alpha <= 0.000_01 { continue }

            let lineWidth = max(onePixel, CGFloat(radius) * 0.85)

            context.drawLayer { layer in
                if radius > 0.001 {
                    layer.addFilter(.blur(radius: radius))
                }
                let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                for seg in segments {
                    layer.stroke(seg.topEdgePath, with: .color(configuration.glowColor.opacity(alpha)), style: style)
                }
            }
        }

        context.blendMode = savedBlendMode
    }
}
