//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Forecast surface renderer (WidgetKit-safe):
//  - One filled ribbon above a subtle baseline
//  - Internal streak texture (rain “grain”) clipped to the ribbon
//  - Top-edge fuzz/spray driven by uncertainty (1 - certainty)
//  - Deterministic pseudo-random jitter (stable across renders)
//

import Foundation
import SwiftUI

// MARK: - Configuration

struct RainForecastSurfaceConfiguration: Hashable {
    // Background (usually handled by the chart stage view; kept here for flexibility)
    var backgroundColor: Color = .clear
    var backgroundOpacity: Double = 0.0

    // Data mapping
    var intensityCap: Double = 1.0
    var wetThreshold: Double = 0.0
    var intensityEasingPower: Double = 0.75
    var minVisibleHeightFraction: CGFloat = 0.03

    // Geometry smoothing (visual only; keep small)
    var geometrySmoothingPasses: Int = 1

    // Layout
    var baselineYFraction: CGFloat = 0.82
    var edgeInsetFraction: CGFloat = 0.0

    // Baseline (felt, not seen)
    var baselineColor: Color = .white
    var baselineOpacity: Double = 0.09
    var baselineLineWidth: CGFloat = 1.0
    var baselineInsetPoints: CGFloat = 6.0
    var baselineSoftWidthMultiplier: CGFloat = 2.6
    var baselineSoftOpacityMultiplier: Double = 0.28

    // Core ribbon fill (matte)
    var fillBottomColor: Color = .blue
    var fillTopColor: Color = .blue
    var fillBottomOpacity: Double = 0.18
    var fillTopOpacity: Double = 0.92

    // Boundary modifiers (rendering only)
    var startEaseMinutes: Int = 6
    var endFadeMinutes: Int = 10
    var endFadeFloor: Double = 0.0

    // Diffusion controls (used as the “fuzz richness” dial)
    var diffusionLayers: Int = 24
    var diffusionFalloffPower: Double = 2.2

    // Uncertainty -> diffusion radius
    var diffusionMinRadiusPoints: CGFloat = 1.5
    var diffusionMaxRadiusPoints: CGFloat = 18.0
    var diffusionMinRadiusFractionOfHeight: CGFloat = 0.03
    var diffusionMaxRadiusFractionOfHeight: CGFloat = 0.34
    var diffusionRadiusUncertaintyPower: Double = 1.35

    // Uncertainty -> diffusion strength
    var diffusionStrengthMax: Double = 0.60
    var diffusionStrengthMinUncertainTerm: Double = 0.30
    var diffusionStrengthUncertaintyPower: Double = 1.15

    // Intensity gating (keeps drizzle calm but present)
    var diffusionDrizzleThreshold: Double = 0.10
    var diffusionLowIntensityGateMin: Double = 0.55

    // Light-rain restraint (summary intensity)
    var diffusionLightRainMeanThreshold: Double = 0.18
    var diffusionLightRainMaxRadiusScale: Double = 0.80
    var diffusionLightRainStrengthScale: Double = 0.85

    // Anti-banding controls
    var diffusionStopStride: Int = 2
    var diffusionJitterAmplitudePoints: Double = 0.35
    var diffusionEdgeSofteningWidth: Double = 0.08

    // Internal texture (vertical streaks inside the ribbon)
    var textureEnabled: Bool = true
    var textureMaxAlpha: Double = 0.22
    var textureMinAlpha: Double = 0.04
    var textureIntensityPower: Double = 0.70
    var textureUncertaintyAlphaBoost: Double = 0.35
    var textureStreaksMin: Int = 1
    var textureStreaksMax: Int = 3
    var textureLineWidthMultiplier: CGFloat = 0.70
    var textureBlurRadiusPoints: CGFloat = 0.6
    var textureTopInsetFractionOfHeight: CGFloat = 0.02

    // Top fuzz/spray (uncertainty / chance)
    var fuzzEnabled: Bool = true
    var fuzzGlobalBlurRadiusPoints: CGFloat = 1.0
    var fuzzLineWidthMultiplier: CGFloat = 0.70
    var fuzzLengthMultiplier: CGFloat = 1.15
    var fuzzDotsEnabled: Bool = true
    var fuzzDotsPerSampleMax: Int = 3

    // Glow (optional; tight inward concentration, never a stroke)
    var glowEnabled: Bool = true
    var glowColor: Color = .blue
    var glowLayers: Int = 6
    var glowMaxAlpha: Double = 0.22
    var glowFalloffPower: Double = 1.75
    var glowCertaintyPower: Double = 1.6
    var glowMaxRadiusPoints: CGFloat = 3.8
    var glowMaxRadiusFractionOfHeight: CGFloat = 0.075
}

// MARK: - View

struct RainForecastSurfaceView: View {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration

    @Environment(\.displayScale) private var displayScale

    init(
        intensities: [Double],
        certainties: [Double],
        configuration: RainForecastSurfaceConfiguration
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
    }

    var body: some View {
        Canvas { context, size in
            let renderer = RainForecastSurfaceRenderer(
                intensities: intensities,
                certainties: certainties,
                configuration: configuration,
                displayScale: displayScale
            )
            renderer.render(in: &context, size: size)
        }
    }
}

// MARK: - Renderer

private struct RainForecastSurfaceRenderer {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration
    let displayScale: CGFloat

    private struct WetSegment {
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
        baselineY = Helpers.alignToPixelCenter(baselineY, displayScale: displayScale)

        let maxHeight = max(0, baselineY - rect.minY)
        let minVisibleHeight = max(0, maxHeight * configuration.minVisibleHeightFraction)

        let intensityCap = max(configuration.intensityCap, 0.000_001)
        let stepX = plotRect.width / CGFloat(n)

        let edgeFactors = Helpers.edgeFactors(
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
            let c = Helpers.clamp01(certainties[i])
            certainty[i] = c

            let isWet = rawI > configuration.wetThreshold
            wetMask[i] = isWet
            guard isWet else { continue }

            let frac = min(rawI / intensityCap, 1.0)
            let eased = pow(frac, configuration.intensityEasingPower)
            intensityNorm[i] = eased

            var h = CGFloat(eased) * maxHeight
            if h > 0 { h = max(h, minVisibleHeight) }
            heights[i] = h
        }

        if configuration.geometrySmoothingPasses > 0 {
            heights = Helpers.smooth(heights, passes: configuration.geometrySmoothingPasses)
            for i in 0..<n {
                if !wetMask[i] {
                    heights[i] = 0
                } else {
                    heights[i] = max(heights[i], minVisibleHeight)
                }
            }
        }

        let wetRanges = Helpers.wetRanges(from: wetMask)
        guard !wetRanges.isEmpty else {
            Helpers.drawBaseline(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                configuration: configuration
            )
            return
        }

        // Light-rain restraint (summary intensity)
        let meanIntensityNorm = intensityNorm.reduce(0.0, +) / Double(max(1, n))
        let isLightOverall = meanIntensityNorm < configuration.diffusionLightRainMeanThreshold
        let lightRainRadiusScale = isLightOverall ? configuration.diffusionLightRainMaxRadiusScale : 1.0
        let lightRainStrengthScale = isLightOverall ? configuration.diffusionLightRainStrengthScale : 1.0

        // Diffusion radius bounds (scaled with size)
        let minRadius = max(configuration.diffusionMinRadiusPoints, rect.height * configuration.diffusionMinRadiusFractionOfHeight)
        let maxRadiusUnscaled = min(configuration.diffusionMaxRadiusPoints, rect.height * configuration.diffusionMaxRadiusFractionOfHeight)
        let maxRadius = max(minRadius, maxRadiusUnscaled * CGFloat(lightRainRadiusScale))

        // Per-sample diffusion radius/strength and glow strength
        var diffusionRadius = [CGFloat](repeating: 0, count: n)
        var diffusionStrength = [Double](repeating: 0, count: n)
        var glowStrength = [Double](repeating: 0, count: n)

        let drizzleT = max(0.000_001, configuration.diffusionDrizzleThreshold)

        for i in 0..<n {
            guard wetMask[i] else { continue }

            let certainty01 = certainty[i]
            let uncertainty01 = 1.0 - certainty01

            let uRadiusT = pow(uncertainty01, configuration.diffusionRadiusUncertaintyPower)
            diffusionRadius[i] = CGFloat(Helpers.lerp(Double(minRadius), Double(maxRadius), uRadiusT))

            let uStrengthT = pow(uncertainty01, configuration.diffusionStrengthUncertaintyPower)
            let uncertainTerm = Helpers.lerp(configuration.diffusionStrengthMinUncertainTerm, 1.0, uStrengthT)

            var strength = configuration.diffusionStrengthMax * uncertainTerm

            let iNorm = intensityNorm[i]
            if iNorm < drizzleT {
                let t = iNorm / drizzleT
                let gate = Helpers.lerp(configuration.diffusionLowIntensityGateMin, 1.0, t)
                strength *= gate
            }

            strength *= edgeFactors[i]
            strength *= lightRainStrengthScale
            diffusionStrength[i] = max(0.0, strength)

            glowStrength[i] = pow(certainty01, configuration.glowCertaintyPower) * edgeFactors[i]
        }

        // Build segments once (paths reused by fill + texture + glow)
        let segments: [WetSegment] = wetRanges.map { range in
            let surfacePoints = Helpers.surfacePoints(
                for: range,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights
            )

            var surfacePath = Path()
            Helpers.addSmoothQuadSegments(&surfacePath, points: surfacePoints, moveToFirst: true)
            surfacePath.closeSubpath()

            let topEdgePoints = Helpers.topEdgePoints(
                for: range,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights
            )

            var topEdgePath = Path()
            Helpers.addSmoothQuadSegments(&topEdgePath, points: topEdgePoints, moveToFirst: true)

            return WetSegment(range: range, surfacePath: surfacePath, topEdgePath: topEdgePath)
        }

        // Base ribbon fill (matte)
        drawFill(
            in: &context,
            rect: rect,
            baselineY: baselineY,
            segments: segments
        )

        // Internal streak texture clipped to ribbon
        if configuration.textureEnabled {
            drawTexture(
                in: &context,
                rect: rect,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                segments: segments,
                heights: heights,
                intensityNorm: intensityNorm,
                certainty: certainty,
                diffusionStrength: diffusionStrength,
                diffusionRadius: diffusionRadius,
                edgeFactors: edgeFactors
            )
        }

        // Top fuzz/spray above the edge (uncertainty-driven)
        if configuration.fuzzEnabled {
            drawFuzz(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                segments: segments,
                heights: heights,
                certainty: certainty,
                intensityNorm: intensityNorm,
                diffusionStrength: diffusionStrength,
                diffusionRadius: diffusionRadius
            )
        }

        // Glow on the top edge (tight)
        if configuration.glowEnabled {
            drawGlow(
                in: &context,
                rect: rect,
                segments: segments,
                glowStrength: glowStrength
            )
        }

        // Baseline on top
        Helpers.drawBaseline(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            configuration: configuration
        )
    }

    private func drawFill(
        in context: inout GraphicsContext,
        rect: CGRect,
        baselineY: CGFloat,
        segments: [WetSegment]
    ) {
        let bottom = configuration.fillBottomColor.opacity(configuration.fillBottomOpacity)
        let top = configuration.fillTopColor.opacity(configuration.fillTopOpacity)

        let grad = Gradient(stops: [
            .init(color: bottom, location: 0.0),
            .init(color: top, location: 1.0)
        ])

        let shading = GraphicsContext.Shading.linearGradient(
            grad,
            startPoint: CGPoint(x: rect.midX, y: baselineY),
            endPoint: CGPoint(x: rect.midX, y: rect.minY)
        )

        for seg in segments {
            context.fill(seg.surfacePath, with: shading)
        }
    }

    private func drawTexture(
        in context: inout GraphicsContext,
        rect: CGRect,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        segments: [WetSegment],
        heights: [CGFloat],
        intensityNorm: [Double],
        certainty: [Double],
        diffusionStrength: [Double],
        diffusionRadius: [CGFloat],
        edgeFactors: [Double]
    ) {
        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let baseLineWidth = max(0.5, onePixel * configuration.textureLineWidthMultiplier)

        let topInset = max(0, rect.height * configuration.textureTopInsetFractionOfHeight)
        let colour = configuration.fillTopColor

        let savedBlendMode = context.blendMode

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            if configuration.textureBlurRadiusPoints > 0 {
                layer.addFilter(.blur(radius: configuration.textureBlurRadiusPoints))
            }

            for seg in segments {
                layer.drawLayer { clipped in
                    clipped.clip(to: seg.surfacePath)

                    for i in seg.range {
                        let h = heights[i]
                        guard h > 0 else { continue }

                        let centreX = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                        let topY = baselineY - h

                        let iW = pow(intensityNorm[i], configuration.textureIntensityPower)
                        let u = 1.0 - certainty[i]
                        let uBoost = 1.0 + configuration.textureUncertaintyAlphaBoost * pow(u, 0.85)

                        let alphaBase = Helpers.lerp(configuration.textureMinAlpha, configuration.textureMaxAlpha, iW) * uBoost * edgeFactors[i]
                        if alphaBase <= 0.000_01 { continue }

                        let streakCount = max(
                            configuration.textureStreaksMin,
                            min(
                                configuration.textureStreaksMax,
                                Int(round(Helpers.lerp(Double(configuration.textureStreaksMin), Double(configuration.textureStreaksMax), iW)))
                            )
                        )

                        for k in 0..<streakCount {
                            let r0 = Helpers.hash01(i, k, seed: 0xA11CE)
                            let r1 = Helpers.hash01(i, k, seed: 0xBEE5)
                            let r2 = Helpers.hash01(i, k, seed: 0xC0FFEE)

                            let xJitter = (CGFloat(r0) * 2.0 - 1.0) * 0.45 * stepX
                            let x = centreX + xJitter

                            let endFrac = CGFloat(0.35 + 0.65 * r1)
                            var y1 = baselineY - h * endFrac
                            y1 = max(y1, topY + topInset)

                            let alpha = Helpers.clamp01(alphaBase * (0.65 + 0.35 * r2))
                            if alpha <= 0.000_01 { continue }

                            let w = baseLineWidth * (0.80 + 0.50 * CGFloat(r2))

                            var p = Path()
                            p.move(to: CGPoint(x: x, y: baselineY))
                            p.addLine(to: CGPoint(x: x, y: y1))

                            clipped.stroke(
                                p,
                                with: .color(colour.opacity(alpha)),
                                style: StrokeStyle(lineWidth: w, lineCap: .round)
                            )
                        }

                        // Small “mist” specks near the top, tied to uncertainty and radius
                        let localStrength01 = Helpers.clamp01(diffusionStrength[i] / max(0.000_001, configuration.diffusionStrengthMax))
                        if localStrength01 > 0.08 {
                            let dots = min(2, max(0, Int(round(2.0 * localStrength01))))
                            if dots > 0 {
                                for d in 0..<dots {
                                    let rr0 = Helpers.hash01(i, d, seed: 0xD0D0)
                                    let rr1 = Helpers.hash01(i, d, seed: 0xDADA)

                                    let xJ = (CGFloat(rr0) * 2.0 - 1.0) * 0.42 * stepX
                                    let x = centreX + xJ

                                    let r = max(0.6, onePixel * (0.8 + 1.2 * CGFloat(rr1)))
                                    let y = topY + topInset + CGFloat(0.10 + 0.55 * rr1) * min(h, max(1.0, diffusionRadius[i]))

                                    var dot = Path()
                                    dot.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))

                                    let a = Helpers.clamp01(alphaBase * 0.55 * (0.45 + 0.55 * rr0))
                                    clipped.fill(dot, with: .color(colour.opacity(a)))
                                }
                            }
                        }
                    }
                }
            }
        }

        context.blendMode = savedBlendMode
    }

    private func drawFuzz(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        segments: [WetSegment],
        heights: [CGFloat],
        certainty: [Double],
        intensityNorm: [Double],
        diffusionStrength: [Double],
        diffusionRadius: [CGFloat]
    ) {
        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let colour = configuration.fillTopColor

        let savedBlendMode = context.blendMode

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            if configuration.fuzzGlobalBlurRadiusPoints > 0 {
                layer.addFilter(.blur(radius: configuration.fuzzGlobalBlurRadiusPoints))
            }

            let richnessMax = max(4, configuration.diffusionLayers)
            let perSampleMax = max(2, min(10, Int(round(Double(richnessMax) / 3.8))))

            for seg in segments {
                for i in seg.range {
                    let h = heights[i]
                    guard h > 0 else { continue }

                    let centreX = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                    let topY = baselineY - h

                    let u = 1.0 - certainty[i]
                    let iW = pow(intensityNorm[i], 0.65)

                    let strength = diffusionStrength[i]
                    let s01 = Helpers.clamp01(strength / max(0.000_001, configuration.diffusionStrengthMax))
                    if s01 <= 0.02 { continue }

                    let radius = diffusionRadius[i]
                    let lengthBase = radius * configuration.fuzzLengthMultiplier

                    let uExtra = pow(u, 1.05)
                    let iGate = Helpers.lerp(0.50, 1.0, iW)

                    let lineCount = max(
                        1,
                        min(
                            perSampleMax,
                            Int(round(Helpers.lerp(1.0, Double(perSampleMax), 0.55 * s01 + 0.45 * uExtra)))
                        )
                    )

                    let lineWidthBase = max(0.5, onePixel * configuration.fuzzLineWidthMultiplier)

                    for k in 0..<lineCount {
                        let r0 = Helpers.hash01(i, k, seed: 0xF00D)
                        let r1 = Helpers.hash01(i, k, seed: 0xFACE)
                        let r2 = Helpers.hash01(i, k, seed: 0xBADA)
                        let r3 = Helpers.hash01(i, k, seed: 0xC001)

                        let xJitter = (CGFloat(r0) * 2.0 - 1.0) * 0.48 * stepX
                        let x = centreX + xJitter

                        let len = lengthBase * CGFloat(0.35 + 0.75 * r1) * CGFloat(iGate)
                        let y0 = topY - onePixel * CGFloat(0.10 + 0.25 * r2)
                        let y1 = topY - len

                        let alpha = Helpers.clamp01(strength * (0.22 + 0.48 * r3) * iGate)
                        if alpha <= 0.000_01 { continue }

                        let w = lineWidthBase * (0.75 + 0.55 * CGFloat(r2))

                        var p = Path()
                        p.move(to: CGPoint(x: x, y: y0))
                        p.addLine(to: CGPoint(x: x, y: y1))

                        layer.stroke(
                            p,
                            with: .color(colour.opacity(alpha)),
                            style: StrokeStyle(lineWidth: w, lineCap: .round)
                        )
                    }

                    if configuration.fuzzDotsEnabled {
                        let dotCount = max(0, min(configuration.fuzzDotsPerSampleMax, Int(round(Double(lineCount) * 0.55))))
                        if dotCount > 0 {
                            for d in 0..<dotCount {
                                let rr0 = Helpers.hash01(i, d, seed: 0xDADA)
                                let rr1 = Helpers.hash01(i, d, seed: 0xDEAD)
                                let rr2 = Helpers.hash01(i, d, seed: 0xFEED)

                                let xJitter = (CGFloat(rr0) * 2.0 - 1.0) * 0.46 * stepX
                                let x = centreX + xJitter

                                let len = lengthBase * CGFloat(0.30 + 0.85 * rr1) * CGFloat(iGate)
                                let y = topY - len * CGFloat(0.20 + 0.80 * rr2)

                                let r = max(0.7, onePixel * (0.9 + 1.6 * CGFloat(rr2)))
                                var dot = Path()
                                dot.addEllipse(in: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))

                                let a = Helpers.clamp01(strength * 0.55 * (0.25 + 0.65 * rr0) * iGate)
                                layer.fill(dot, with: .color(colour.opacity(a)))
                            }
                        }
                    }
                }
            }
        }

        context.blendMode = savedBlendMode
    }

    private func drawGlow(
        in context: inout GraphicsContext,
        rect: CGRect,
        segments: [WetSegment],
        glowStrength: [Double]
    ) {
        let glowLayers = max(2, configuration.glowLayers)
        let maxRadius = min(configuration.glowMaxRadiusPoints, rect.height * configuration.glowMaxRadiusFractionOfHeight)

        let meanGlowStrength: Double = {
            var sum = 0.0
            var count = 0.0
            for g in glowStrength where g > 0 {
                sum += g
                count += 1.0
            }
            guard count > 0 else { return 0.0 }
            return sum / count
        }()

        if meanGlowStrength <= 0.000_01 || maxRadius <= 0.000_01 {
            return
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let strokeStyle = StrokeStyle(lineWidth: max(0.5, onePixel), lineCap: .round, lineJoin: .round)

        let savedBlendMode = context.blendMode
        context.blendMode = .plusLighter

        for k in 0..<glowLayers {
            let t = (glowLayers == 1) ? 0.0 : Double(k) / Double(glowLayers - 1)
            let falloff = pow(1.0 - t, max(1.0, configuration.glowFalloffPower))
            let alpha = configuration.glowMaxAlpha * falloff * meanGlowStrength
            if alpha <= 0.000_01 { continue }

            let radius = maxRadius * CGFloat(1.0 - t)

            context.drawLayer { layer in
                if radius > 0.001 {
                    layer.addFilter(.blur(radius: radius))
                }
                for seg in segments {
                    layer.stroke(seg.topEdgePath, with: .color(configuration.glowColor.opacity(alpha)), style: strokeStyle)
                }
            }
        }

        context.blendMode = savedBlendMode
    }
}

// MARK: - Helpers

private enum Helpers {
    static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }

    static func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        max(lo, min(hi, v))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let tt = max(0.0, min(1.0, t))
        return a + (b - a) * tt
    }

    static func smoothstep01(_ u: Double) -> Double {
        let x = max(0.0, min(1.0, u))
        return x * x * (3.0 - 2.0 * x)
    }

    static func alignToPixelCenter(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        guard displayScale > 0 else { return value }
        return (floor(value * displayScale) + 0.5) / displayScale
    }

    static func edgeFactors(
        sampleCount: Int,
        startEaseMinutes: Int,
        endFadeMinutes: Int,
        endFadeFloor: Double
    ) -> [Double] {
        guard sampleCount > 0 else { return [] }
        if sampleCount == 1 { return [1.0] }

        let startN = max(0, startEaseMinutes)
        let endN = max(0, endFadeMinutes)
        let floorClamped = clamp01(endFadeFloor)

        var out: [Double] = []
        out.reserveCapacity(sampleCount)

        for i in 0..<sampleCount {
            let startEase: Double
            if startN <= 1 {
                startEase = 1.0
            } else if i >= startN {
                startEase = 1.0
            } else {
                let u = Double(i) / Double(max(1, startN - 1))
                startEase = smoothstep01(u)
            }

            let endFade: Double
            if endN <= 0 {
                endFade = 1.0
            } else {
                let startIndex = max(0, sampleCount - endN)
                if i < startIndex {
                    endFade = 1.0
                } else if endN == 1 {
                    endFade = floorClamped
                } else {
                    let u = Double(i - startIndex) / Double(max(1, endN - 1))
                    let s = smoothstep01(u)
                    endFade = max(1.0 - s, floorClamped)
                }
            }

            out.append(startEase * endFade)
        }

        return out
    }

    static func wetRanges(from mask: [Bool]) -> [Range<Int>] {
        guard !mask.isEmpty else { return [] }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(4)

        var start: Int? = nil

        for i in 0..<mask.count {
            if mask[i] {
                if start == nil { start = i }
            } else if let s = start {
                ranges.append(s..<i)
                start = nil
            }
        }

        if let s = start {
            ranges.append(s..<mask.count)
        }

        return ranges
    }

    static func surfacePoints(
        for range: Range<Int>,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> [CGPoint] {
        let startEdgeX = plotRect.minX + CGFloat(range.lowerBound) * stepX
        let endEdgeX = plotRect.minX + CGFloat(range.upperBound) * stepX

        var points: [CGPoint] = []
        points.reserveCapacity(range.count + 2)

        points.append(CGPoint(x: startEdgeX, y: baselineY))

        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            points.append(CGPoint(x: x, y: y))
        }

        points.append(CGPoint(x: endEdgeX, y: baselineY))
        return points
    }

    static func topEdgePoints(
        for range: Range<Int>,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> [CGPoint] {
        guard let first = range.first else { return [] }
        let last = max(first, range.upperBound - 1)

        let startEdgeX = plotRect.minX + CGFloat(range.lowerBound) * stepX
        let endEdgeX = plotRect.minX + CGFloat(range.upperBound) * stepX

        var points: [CGPoint] = []
        points.reserveCapacity(range.count + 2)

        points.append(CGPoint(x: startEdgeX, y: baselineY - heights[first]))

        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            points.append(CGPoint(x: x, y: y))
        }

        points.append(CGPoint(x: endEdgeX, y: baselineY - heights[last]))
        return points
    }

    static func addSmoothQuadSegments(_ path: inout Path, points: [CGPoint], moveToFirst: Bool) {
        guard points.count >= 2 else { return }

        if moveToFirst {
            path.move(to: points[0])
        }

        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        for i in 1..<(points.count - 1) {
            let current = points[i]
            let next = points[i + 1]
            let mid = CGPoint(x: (current.x + next.x) * 0.5, y: (current.y + next.y) * 0.5)
            path.addQuadCurve(to: mid, control: current)
        }

        path.addQuadCurve(to: points[points.count - 1], control: points[points.count - 2])
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration
    ) {
        let inset = max(0, configuration.baselineInsetPoints)
        let x0 = plotRect.minX + inset
        let x1 = plotRect.maxX - inset
        guard x1 > x0 else { return }

        var base = Path()
        base.move(to: CGPoint(x: x0, y: baselineY))
        base.addLine(to: CGPoint(x: x1, y: baselineY))

        if configuration.baselineSoftOpacityMultiplier > 0, configuration.baselineSoftWidthMultiplier > 1 {
            let softWidth = max(configuration.baselineLineWidth, configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier)
            let softOpacity = max(0.0, min(1.0, configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier))
            let softStyle = StrokeStyle(lineWidth: softWidth, lineCap: .round)

            context.stroke(
                base,
                with: .color(configuration.baselineColor.opacity(softOpacity)),
                style: softStyle
            )
        }

        let stroke = StrokeStyle(lineWidth: configuration.baselineLineWidth, lineCap: .round)
        context.stroke(
            base,
            with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)),
            style: stroke
        )
    }

    static func smooth(_ values: [CGFloat], passes: Int) -> [CGFloat] {
        guard values.count >= 3, passes > 0 else { return values }

        var out = values
        var tmp = values

        for _ in 0..<passes {
            tmp = out
            for i in 1..<(values.count - 1) {
                out[i] = (tmp[i - 1] + tmp[i] + tmp[i + 1]) / 3.0
            }
            out[0] = tmp[0]
            out[values.count - 1] = tmp[values.count - 1]
        }

        return out
    }

    // Deterministic pseudo-random in [0, 1]
    static func hash01(_ a: Int, _ b: Int, seed: UInt64) -> Double {
        var x = UInt64(bitPattern: Int64(a &* 0x1F123BB5 ^ b &* 0x6A09E667))
        x &+= seed
        x &+= 0x9E3779B97F4A7C15

        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x = x ^ (x >> 31)

        return Double(x) / Double(UInt64.max)
    }
}
