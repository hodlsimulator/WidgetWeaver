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

        // Baseline needs to stay visible even under the filled ribbon.
        let savedBlend = context.blendMode
        context.blendMode = .screen

        if configuration.baselineSoftOpacityMultiplier > 0, configuration.baselineSoftWidthMultiplier > 1 {
            let softWidth = max(
                configuration.baselineLineWidth,
                configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier
            )
            let softOpacity = max(
                0.0,
                min(1.0, configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier)
            )

            let softStyle = StrokeStyle(lineWidth: max(onePixel, softWidth), lineCap: .round)
            context.stroke(
                base,
                with: .color(configuration.baselineColor.opacity(softOpacity)),
                style: softStyle
            )
        }

        let stroke = StrokeStyle(lineWidth: max(onePixel, configuration.baselineLineWidth), lineCap: .round)
        context.stroke(
            base,
            with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)),
            style: stroke
        )

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
        // No grain, particles, dots, streaks, or noise textures are rendered.
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

        let drizzleThreshold = max(0.000_001, configuration.diffusionDrizzleThreshold)
        let gateMin = RainSurfaceMath.clamp01(configuration.diffusionLowIntensityGateMin)

        let strengthMax = max(0.0, configuration.diffusionStrengthMax)
        let strengthMinFactor = RainSurfaceMath.clamp01(configuration.diffusionStrengthMinUncertainTerm)
        let strengthPower = max(0.01, configuration.diffusionStrengthUncertaintyPower)
        let radiusPower = max(0.01, configuration.diffusionRadiusUncertaintyPower)

        // Heavy rain boost: adds surface energy without any noise.
        let heavyStart = 0.45
        let heavyEnd = 0.85
        let heavyRadiusBoostMax = 0.25
        let heavyStrengthBoostMax = 0.20

        // Certainty is smoothed for rendering to prevent vertical “streak” cut-outs in the diffusion mask.
        let certaintySmoothed = RainSurfaceMath.smooth(Array(certainty.prefix(n)), passes: 3)

        for i in 0..<n {
            if heights[i] <= (0.5 * onePixel) { continue }

            let c = RainSurfaceMath.clamp01(certaintySmoothed[i])
            let u = 1.0 - c
            let iNorm = max(0.0, intensityNorm[i])

            // Intensity gating should only suppress diffusion near zero intensity.
            let gate: Double
            if iNorm <= 0.000_001 {
                gate = gateMin
            } else if iNorm < drizzleThreshold {
                let t = iNorm / drizzleThreshold
                gate = RainSurfaceMath.lerp(gateMin, 1.0, t)
            } else {
                gate = 1.0
            }

            let heavyT = RainSurfaceMath.clamp(
                (iNorm - heavyStart) / max(0.000_001, (heavyEnd - heavyStart)),
                min: 0.0,
                max: 1.0
            )
            let heavyBoost = RainSurfaceMath.smoothstep01(heavyT)

            if diffusionOn {
                let rT = pow(u, radiusPower)
                var r = CGFloat(RainSurfaceMath.lerp(Double(minRadius), Double(maxRadius), rT))
                r *= CGFloat(gate)
                r *= CGFloat(1.0 + heavyRadiusBoostMax * heavyBoost)
                diffusionRadiusBySample[i] = r

                let sT = pow(u, strengthPower)
                var s = strengthMax * (strengthMinFactor + (1.0 - strengthMinFactor) * sT)
                s *= gate
                s *= (1.0 + heavyStrengthBoostMax * heavyBoost)
                s *= edgeFactors[i] // boundary easing is alpha-only
                diffusionAlphaBySample[i] = s
            }

            if glowOn {
                var g = configuration.glowMaxAlpha * pow(c, configuration.glowCertaintyPower)
                g *= edgeFactors[i] // boundary easing is alpha-only
                glowAlphaBySample[i] = g
            }
        }

        // Rendering-only smoothing to remove high-frequency shimmer and vertical streak artefacts.
        diffusionRadiusBySample = RainSurfaceMath.smooth(diffusionRadiusBySample, passes: 2)
        diffusionAlphaBySample = RainSurfaceMath.smooth(diffusionAlphaBySample, passes: 4)
        glowAlphaBySample = RainSurfaceMath.smooth(glowAlphaBySample, passes: 2)

        // Optional blur on the diffusion mask (helps the surface read “diffuse” without adding noise).
        let diffusionBlurPx = max(0.0, Double(configuration.fuzzGlobalBlurRadiusPoints))
        let diffusionBlur = CGFloat(diffusionBlurPx) / max(1.0, displayScale)

        // Clip diffusion/glow inside the ribbon surface.
        context.drawLayer { layer in
            for seg in segments {
                layer.drawLayer { inner in
                    inner.clip(to: seg.surfacePath)

                    if diffusionOn {
                        let savedBlend = inner.blendMode
                        inner.blendMode = .destinationOut

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
                                    stopStride: max(1, configuration.diffusionStopStride)
                                )
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
                                stopStride: max(1, configuration.diffusionStopStride)
                            )
                        }

                        inner.blendMode = savedBlend
                    }

                    if glowOn, glowRadius > 0.000_01 {
                        let savedBlend = inner.blendMode
                        inner.blendMode = .screen

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

                        inner.blendMode = savedBlend
                    }
                }
            }
        }
    }

    // MARK: - Diffusion implementation (Multi-contour stacked-alpha)

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

        // Build top-edge points (including segment edges).
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

        // Skip if diffusion is effectively off for this segment.
        let peakAlpha = baseAlpha.max() ?? 0.0
        let peakRadius = radii.max() ?? 0.0
        guard peakAlpha > 0.000_5, peakRadius > (0.5 * onePixel) else { return }

        // Smooth per-point radii/alpha (rendering only).
        radii = RainSurfaceMath.smooth(radii, passes: 2)
        baseAlpha = RainSurfaceMath.smooth(baseAlpha, passes: 4)

        let width = max(0.000_01, plotRect.width)
        let denom = Double(max(1, layers - 1))
        let stride = max(1, stopStride)

        // Draw strips between contour(k) and contour(k+1).
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

            // Horizontal gradient carries per-sample alpha smoothly.
            var stops: [Gradient.Stop] = []
            stops.reserveCapacity((points.count / stride) + 2)

            var j = 0
            while j < points.count {
                let loc = (points[j].x - plotRect.minX) / width
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
                let loc = (points[j].x - plotRect.minX) / width
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

    private static func insetPointsDown(
        points: [CGPoint],
        radii: [CGFloat],
        baselineY: CGFloat,
        fraction: CGFloat
    ) -> [CGPoint] {
        guard points.count == radii.count else { return points }
        let f = max(0, min(1, fraction))
        var out = points
        for i in 0..<out.count {
            let dy = max(0, radii[i]) * f
            out[i].y = min(baselineY, out[i].y + dy)
        }
        return out
    }

    private static func insetPointsDownConstant(
        points: [CGPoint],
        radius: CGFloat,
        baselineY: CGFloat,
        fraction: CGFloat
    ) -> [CGPoint] {
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
}
