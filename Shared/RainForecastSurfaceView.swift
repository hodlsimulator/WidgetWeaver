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

//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Forecast surface renderer (WidgetKit-safe).
//  Goals:
//  - One filled ribbon above a subtle baseline
//  - Uncertainty is expressed as a fuzzy “mist” around the top edge
//  - Certainty stays smooth/crisp (minimal fuzz)
//  - Optional tight glow (no hard outline)
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

    // Internal texture (kept for compatibility; can be disabled by callers)
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

    // Top fuzz / uncertainty mist
    var fuzzEnabled: Bool = true
    var fuzzGlobalBlurRadiusPoints: CGFloat = 1.0
    var fuzzLineWidthMultiplier: CGFloat = 0.70
    var fuzzLengthMultiplier: CGFloat = 1.15
    var fuzzDotsEnabled: Bool = true
    var fuzzDotsPerSampleMax: Int = 3

    // Glow (optional; tight inward concentration, never a hard outline)
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
        baselineY = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        let maxHeight = max(0, baselineY - rect.minY)
        guard maxHeight > 0 else { return }

        let minVisibleHeight = max(0, maxHeight * configuration.minVisibleHeightFraction)
        let intensityCap = max(configuration.intensityCap, 0.000_001)
        let stepX = plotRect.width / CGFloat(n)

        let edgeFactors = RainSurfaceMath.edgeFactors(
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
            let c = RainSurfaceMath.clamp01(certainties[i])
            certainty[i] = c

            let isWet = rawI > configuration.wetThreshold
            wetMask[i] = isWet
            guard isWet else { continue }

            let frac = min(rawI / intensityCap, 1.0)
            let eased = pow(frac, configuration.intensityEasingPower)
            let edge = edgeFactors[i]

            intensityNorm[i] = eased * edge

            var h = CGFloat(eased) * maxHeight
            if h > 0 { h = max(h, minVisibleHeight) }
            h *= CGFloat(edge)

            heights[i] = h
        }

        if configuration.geometrySmoothingPasses > 0 {
            heights = RainSurfaceMath.smooth(heights, passes: configuration.geometrySmoothingPasses)
        }

        for i in 0..<n {
            if heights[i] <= 0.000_01 {
                wetMask[i] = false
                intensityNorm[i] = 0.0
            }
        }

        let ranges = RainSurfaceGeometry.wetRanges(from: wetMask)
        guard !ranges.isEmpty else {
            RainSurfaceDrawing.drawBaseline(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                configuration: configuration,
                displayScale: displayScale
            )
            return
        }

        let segments: [WetSegment] = ranges.map { range in
            let surfacePath = RainSurfaceGeometry.makeSurfacePath(
                for: range,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights
            )
            let topEdgePath = RainSurfaceGeometry.makeTopEdgePath(
                for: range,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights
            )
            return WetSegment(range: range, surfacePath: surfacePath, topEdgePath: topEdgePath)
        }

        RainSurfaceDrawing.drawBaseline(
            in: &context,
            plotRect: plotRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )

        RainSurfaceDrawing.drawFill(
            in: &context,
            rect: rect,
            baselineY: baselineY,
            segments: segments,
            configuration: configuration
        )

        // Texture path kept for compatibility, but callers can disable.
        // The nowcast-style “fuzziness” is handled by the uncertainty mist, not streaks.
        if configuration.textureEnabled {
            RainSurfaceDrawing.drawLegacyTextureIfEnabled(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                segments: segments,
                heights: heights,
                intensityNorm: intensityNorm,
                certainty: certainty,
                edgeFactors: edgeFactors,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        if configuration.fuzzEnabled {
            RainSurfaceDrawing.drawUncertaintyMist(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                segments: segments,
                heights: heights,
                intensityNorm: intensityNorm,
                certainty: certainty,
                edgeFactors: edgeFactors,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        if configuration.glowEnabled {
            RainSurfaceDrawing.drawGlow(
                in: &context,
                maxHeight: maxHeight,
                segments: segments,
                intensityNorm: intensityNorm,
                certainty: certainty,
                configuration: configuration,
                displayScale: displayScale
            )
        }
    }
}

// MARK: - Geometry

private enum RainSurfaceGeometry {
    static func wetRanges(from mask: [Bool]) -> [Range<Int>] {
        guard !mask.isEmpty else { return [] }

        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(6)

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

    static func makeSurfacePath(
        for range: Range<Int>,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> Path {
        let startEdgeX = plotRect.minX + CGFloat(range.lowerBound) * stepX
        let endEdgeX = plotRect.minX + CGFloat(range.upperBound) * stepX

        var topPoints: [CGPoint] = []
        topPoints.reserveCapacity(range.count + 2)
        topPoints.append(CGPoint(x: startEdgeX, y: baselineY))

        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            topPoints.append(CGPoint(x: x, y: y))
        }

        topPoints.append(CGPoint(x: endEdgeX, y: baselineY))

        var path = Path()
        RainSurfaceGeometry.addSmoothQuadSegments(&path, points: topPoints, moveToFirst: true)
        path.closeSubpath()
        return path
    }

    static func makeTopEdgePath(
        for range: Range<Int>,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> Path {
        guard let first = range.first else { return Path() }

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

        var path = Path()
        RainSurfaceGeometry.addSmoothQuadSegments(&path, points: points, moveToFirst: true)
        return path
    }

    static func addSmoothQuadSegments(_ path: inout Path, points: [CGPoint], moveToFirst: Bool) {
        guard points.count >= 2 else { return }

        if moveToFirst { path.move(to: points[0]) }

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
}

// MARK: - Drawing

private enum RainSurfaceDrawing {
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

    // Kept as a compatibility hook.
    // Current target look does not rely on this texture layer.
    static func drawLegacyTextureIfEnabled(
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
        // If streaks are undesired, set textureEnabled = false in the caller configuration.
        // A minimal, low-cost grain can be expressed via the uncertainty mist instead.
        guard configuration.textureMaxAlpha > 0.000_01 else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let lineWidth = max(onePixel, onePixel * configuration.textureLineWidthMultiplier)

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

                        let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                        let topY = baselineY - h

                        let iW = pow(intensityNorm[i], configuration.textureIntensityPower)
                        let u = 1.0 - certainty[i]
                        let uBoost = 1.0 + configuration.textureUncertaintyAlphaBoost * pow(u, 0.85)

                        let alpha = RainSurfaceMath.lerp(configuration.textureMinAlpha, configuration.textureMaxAlpha, iW) * uBoost * edgeFactors[i]
                        guard alpha > 0.000_01 else { continue }

                        // Draw a very subtle internal vertical “grain” column.
                        // This is intentionally restrained; the preferred uncertainty look is handled by the mist.
                        var p = Path()
                        let insetTop = max(0, h * configuration.textureTopInsetFractionOfHeight)
                        p.move(to: CGPoint(x: x, y: baselineY - insetTop))
                        p.addLine(to: CGPoint(x: x, y: topY + insetTop))

                        layer.stroke(p, with: .color(configuration.fillTopColor.opacity(alpha)), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    }
                }
            }
        }
    }

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
        guard configuration.fuzzDotsEnabled else { return }

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
        let derivedPerSampleMax = max(configuration.fuzzDotsPerSampleMax, min(12, Int(round(Double(richness) / 3.0))))
        let perSampleMax = max(2, derivedPerSampleMax)

        let savedBlendMode = context.blendMode
        context.blendMode = .plusLighter

        context.drawLayer { layer in
            if configuration.fuzzGlobalBlurRadiusPoints > 0 {
                layer.addFilter(.blur(radius: configuration.fuzzGlobalBlurRadiusPoints))
            }

            for seg in segments {
                for i in seg.range {
                    if (i % stride) != 0 { continue }

                    let h = heights[i]
                    guard h > 0 else { continue }

                    let iW = pow(intensityNorm[i], 0.65)
                    let edge = edgeFactors[i]
                    guard edge > 0.000_01 else { continue }

                    let u = 1.0 - RainSurfaceMath.clamp01(certainty[i])
                    let uPowR = pow(u, configuration.diffusionRadiusUncertaintyPower)
                    let uPowS = pow(u, configuration.diffusionStrengthUncertaintyPower)

                    // Diffusion radius grows with uncertainty, bounded by view scale.
                    var radius = RainSurfaceMath.lerp(Double(minRadius), Double(maxRadius), uPowR)
                    radius *= configuration.fuzzLengthMultiplier
                    radius *= lightRainScaleRadius

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

                    // Diffusion strength grows with uncertainty and is lightly intensity-gated.
                    var strength = configuration.diffusionStrengthMinUncertainTerm
                        + uPowS * max(0.0, configuration.diffusionStrengthMax - configuration.diffusionStrengthMinUncertainTerm)
                    strength *= drizzleGate
                    strength *= lightRainScaleStrength
                    strength *= edge

                    let s01 = RainSurfaceMath.clamp01(strength / max(0.000_001, configuration.diffusionStrengthMax))
                    if s01 <= 0.02 { continue }

                    let centreX = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                    let topY = baselineY - h

                    // Particle count rises with uncertainty/strength.
                    let count = max(1, min(perSampleMax, Int(round(RainSurfaceMath.lerp(1.0, Double(perSampleMax), 0.55 * s01 + 0.45 * pow(u, 1.05))))))

                    var rng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xA13F, saltB: count))
                    let xSpread = Double(stepX) * 0.95
                    let jitterAmp = configuration.diffusionJitterAmplitudePoints

                    for pIndex in 0..<count {
                        let rx = (rng.nextDouble01() - 0.5) * xSpread
                        let ryBase = pow(rng.nextDouble01(), 0.55) * radius
                        let ry = -ryBase + (rng.nextDouble01() - 0.5) * radius * 0.18

                        let jx = (rng.nextDouble01() - 0.5) * jitterAmp
                        let jy = (rng.nextDouble01() - 0.5) * jitterAmp

                        let x = Double(centreX) + rx + jx
                        let y = Double(topY) + ry + jy

                        // Falloff: closer to the edge is denser.
                        let dn = RainSurfaceMath.clamp01(abs(ryBase) / max(0.000_001, radius))
                        let fall = pow(1.0 - dn, configuration.diffusionFalloffPower)

                        let alpha = strength * 0.55 * fall
                        if alpha <= 0.000_01 { continue }

                        let sizeJitter = RainSurfaceMath.lerp(0.75, 1.85, rng.nextDouble01())
                        let r = particleBaseSize * CGFloat(sizeJitter)

                        let circle = Path(ellipseIn: CGRect(x: x - Double(r), y: y - Double(r), width: Double(r * 2), height: Double(r * 2)))
                        layer.fill(circle, with: .color(configuration.fillTopColor.opacity(alpha)))
                    }
                }
            }
        }

        context.blendMode = savedBlendMode
    }

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
        let strokeStyle = StrokeStyle(lineWidth: max(0.5, onePixel), lineCap: .round, lineJoin: .round)

        let savedBlendMode = context.blendMode
        context.blendMode = .plusLighter

        // Inner ridge highlight (tight, minimal blur)
        do {
            let alpha = min(1.0, configuration.glowMaxAlpha * 0.60) * meanGlowStrength
            if alpha > 0.000_01 {
                for seg in segments {
                    context.stroke(seg.topEdgePath, with: .color(configuration.glowColor.opacity(alpha)), style: strokeStyle)
                }
            }
        }

        // Outer soft glow layers
        let layers = max(1, configuration.glowLayers)
        for k in 0..<layers {
            let t = (layers <= 1) ? 1.0 : Double(k) / Double(layers - 1)
            let radius = max(0.0, Double(maxRadius) * pow(t, 1.10))
            let fall = pow(1.0 - t, configuration.glowFalloffPower)
            let alpha = configuration.glowMaxAlpha * meanGlowStrength * fall
            if alpha <= 0.000_01 { continue }

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

// MARK: - Math

private enum RainSurfaceMath {
    static func clamp01(_ v: Double) -> Double { max(0.0, min(1.0, v)) }

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

    static func smooth(_ values: [CGFloat], passes: Int) -> [CGFloat] {
        guard values.count >= 3, passes > 0 else { return values }

        var out = values
        var tmp = values

        for _ in 0..<passes {
            tmp[0] = out[0]
            tmp[values.count - 1] = out[values.count - 1]

            for i in 1..<(values.count - 1) {
                tmp[i] = (out[i - 1] + out[i] + out[i + 1]) / 3.0
            }

            out = tmp
        }

        return out
    }
}

// MARK: - Deterministic PRNG

private struct RainSurfacePRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        // SplitMix64
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func nextDouble01() -> Double {
        Double(nextUInt64()) / Double(UInt64.max)
    }

    static func seed(sampleIndex: Int, saltA: Int, saltB: Int = 0) -> UInt64 {
        let a = UInt64(bitPattern: Int64(sampleIndex &* 0x1F123BB5 ^ saltA &* 0x6A09E667 ^ saltB &* 0x9E3779B9))
        var x = a &+ 0xD1B54A32D192ED03
        x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
        x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
        x = x ^ (x >> 31)
        return x
    }
}
