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

    // MARK: - Probability-masked surface
    //
    // Key goals:
    // - No detached “cloud”: fuzz must stay ridge-attached.
    // - No “second surface”: avoid coherent contour bands.
    // - Diffusion must define the silhouette in low-certainty regions:
    //   pull the core down proportional to fuzz strength so the fuzz becomes the edge.

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

        let minSigmaPoints = max(onePixel, CGFloat(max(0.0, configuration.diffusionMinRadiusPoints)))
        let hardMaxSigmaPoints = max(minSigmaPoints, CGFloat(max(0.0, configuration.diffusionMaxRadiusPoints)))

        let fracMax = max(0.05, CGFloat(configuration.diffusionMaxRadiusFractionOfHeight))
        let maxFromHeight = max(minSigmaPoints, (maxHeight * fracMax))
        let maxSigmaPoints = min(hardMaxSigmaPoints, maxFromHeight)

        let radiusPower = max(0.01, configuration.diffusionRadiusUncertaintyPower)
        let strengthMax = max(0.0, configuration.diffusionStrengthMax)

        let jitterAmp = CGFloat(max(0.0, configuration.diffusionJitterAmplitudePoints)) / max(1.0, displayScale)
        let fuzzMultiplier = max(0.0, configuration.fuzzParticleAlphaMultiplier > 0 ? configuration.fuzzParticleAlphaMultiplier : 1.0)

        let dotsOn = configuration.fuzzDotsEnabled && configuration.fuzzDotsPerSampleMax > 0
        let maxDots = max(0, configuration.fuzzDotsPerSampleMax)

        // Blur for the fuzz mask. Too big creates a detached cloud.
        let fuzzBlurBase = CGFloat(max(0.0, configuration.fuzzGlobalBlurRadiusPoints))
        let fuzzBlur = max(0.0, fuzzBlurBase * 1.20)

        var sigma = [CGFloat](repeating: 0, count: n)
        var coreAlpha = [Double](repeating: 0, count: n)
        var fuzzAlpha = [Double](repeating: 0, count: n)
        var coreHeights = [CGFloat](repeating: 0, count: n)

        let certaintySmoothed = RainSurfaceMath.smooth(Array(certainty.prefix(n)), passes: 2)

        for i in 0..<n {
            let h = heights[i]
            if h <= 0.000_01 {
                sigma[i] = onePixel
                coreAlpha[i] = 0.0
                fuzzAlpha[i] = 0.0
                coreHeights[i] = 0.0
                continue
            }

            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certaintySmoothed[i])
            let u = RainSurfaceMath.clamp01(1.0 - c)
            let edge = RainSurfaceMath.clamp01(edgeFactors[i])

            // Sigma: thicker when certainty is low.
            var s = minSigmaPoints + (maxSigmaPoints - minSigmaPoints) * CGFloat(pow(u, radiusPower))

            // Cap sigma by local height so taper tails do not spawn wide haze.
            let sigmaCap = max(onePixel, min(maxSigmaPoints, (h * (0.34 + 0.96 * CGFloat(u))) + (6.0 / max(1.0, displayScale))))
            s = min(s, sigmaCap)

            // Micro-jitter: texture without streaks.
            if jitterAmp > 0.000_01, s > 0.000_01 {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0x51A7E, saltB: 0xC0FFEE))
                let jr = randTriangle(&prng)
                s += CGFloat(jr) * jitterAmp
            }

            s = max(onePixel, s)
            sigma[i] = s

            // Core opacity: high certainty = solid; low certainty = less solid.
            let core = RainSurfaceMath.clamp01(
                (0.26 + 0.74 * pow(c, 0.88))
                * (0.62 + 0.38 * pow(inorm, 0.72))
                * edge
            )
            coreAlpha[i] = core

            // Fuzz strength: low certainty drives it, intensity supports it.
            let fuzz = RainSurfaceMath.clamp01(
                strengthMax
                * pow(u, 0.86)
                * (0.38 + 0.62 * pow(inorm, 0.62))
                * edge
                * fuzzMultiplier
            )
            fuzzAlpha[i] = fuzz

            // IMPORTANT: core height is pulled down proportional to fuzz strength
            // so fuzz becomes the silhouette in low-certainty regions (no smooth edge underneath).
            let fa = fuzzAlpha[i] // 0...1
            let cutScale = RainSurfaceMath.clamp(0.25 + 1.90 * fa, min: 0.25, max: 2.15)
            let cut = min(h - onePixel * 0.25, s * CGFloat(cutScale))

            coreHeights[i] = max(0.0, h - max(0.0, cut))
        }

        let fillGradient = Gradient(stops: [
            .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
            .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0),
        ])

        let width = max(1.0, plotRect.width)

        for seg in segments {
            let r = seg.range
            guard !r.isEmpty else { continue }

            let startEdgeX = plotRect.minX + CGFloat(r.lowerBound) * stepX
            let endEdgeX = plotRect.minX + CGFloat(r.upperBound) * stepX

            // Hard clip to segment bounds and never below baseline.
            let clipRect = CGRect(
                x: startEdgeX,
                y: plotRect.minY,
                width: max(0, endEdgeX - startEdgeX),
                height: max(0, baselineY - plotRect.minY)
            )
            if clipRect.width <= 0 || clipRect.height <= 0 { continue }

            let corePath = RainSurfaceGeometry.makeSurfacePath(
                for: r,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: coreHeights
            )

            // Horizontal alpha mapping points (include edges).
            let first = r.lowerBound
            let last = max(first, r.upperBound - 1)

            var xPoints: [CGFloat] = []
            var pointCoreA: [Double] = []
            xPoints.reserveCapacity(r.count + 2)
            pointCoreA.reserveCapacity(r.count + 2)

            func appendEdgePoint(x: CGFloat, idx: Int) {
                xPoints.append(x)
                pointCoreA.append(coreAlpha[idx])
            }

            appendEdgePoint(x: startEdgeX, idx: first)

            for i in r {
                let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                appendEdgePoint(x: x, idx: i)
            }

            appendEdgePoint(x: endEdgeX, idx: last)

            let coreStops = makeHorizontalStops(
                plotRect: plotRect,
                width: width,
                xPoints: xPoints,
                alphas: pointCoreA,
                stride: 1
            )

            let coreShading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: coreStops),
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
            )

            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))

                // --- MASK STAGE ---
                layer.fill(corePath, with: coreShading)

                if dotsOn, maxDots > 0 {
                    layer.drawLayer { fuzzLayer in
                        if fuzzBlur > 0.000_01 {
                            fuzzLayer.addFilter(.blur(radius: fuzzBlur))
                        }

                        drawFuzzDots(
                            in: &fuzzLayer,
                            plotRect: plotRect,
                            baselineY: baselineY,
                            stepX: stepX,
                            range: r,
                            heights: heights,
                            sigma: sigma,
                            fuzzAlpha: fuzzAlpha,
                            intensityNorm: intensityNorm,
                            maxDotsPerSample: maxDots,
                            onePixel: onePixel
                        )
                    }
                }

                // --- COLOUR STAGE ---
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

    // MARK: - Fuzz dots (mask grain)
    //
    // No blobs. Lots of small dots close to the ridge, with modest blur.
    // This removes the detached “cloud” and brings back the dithered edge.

    private static func drawFuzzDots(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        sigma: [CGFloat],
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

            let fa = RainSurfaceMath.clamp01(fuzzAlpha[i])
            if fa <= 0.000_5 { continue }

            let s = max(onePixel, sigma[i])
            let topY = baselineY - h

            // Density: driven by fuzz strength, with intensity support.
            let density = RainSurfaceMath.clamp01(0.18 + 0.82 * fa)
            let desired = Double(maxDotsPerSample) * density * (0.55 + 0.45 * pow(inorm, 0.65))
            let dotCount = max(1, Int(desired.rounded(.toNearestOrAwayFromZero)))

            // Keep fuzz ridge-attached: limit vertical span.
            let upSpan = s * (0.45 + 0.55 * CGFloat(fa))                 // max above ridge
            let downSpan = min(h * 0.65, s * (0.35 + 0.55 * CGFloat(fa))) // max inside

            let outsideWeight = RainSurfaceMath.clamp01(0.46 + 0.42 * fa)

            for j in 0..<dotCount {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xD07D07D0, saltB: (j &* 173) &+ 19))

                let rx = prng.nextDouble01()
                let x = plotRect.minX + (CGFloat(i) + CGFloat(rx)) * stepX

                let pick = prng.nextDouble01()
                let y: CGFloat
                if pick < outsideWeight {
                    let t = prng.nextDouble01()
                    let up = CGFloat(pow(t, 1.20)) * upSpan
                    y = max(plotRect.minY, topY - up)
                } else {
                    let t = prng.nextDouble01()
                    let down = CGFloat(pow(t, 1.10)) * max(onePixel, downSpan)
                    y = min(baselineY, topY + down)
                }

                // Small dots only (prevents “cloud blobs”).
                let rr = prng.nextDouble01()
                let baseR = onePixel * (0.60 + 1.85 * rr)
                let scale = (0.78 + 0.62 * CGFloat(fa))
                let r = max(onePixel * 0.55, baseR * scale)

                // Fade with distance from ridge.
                let dy = abs(y - topY)
                let tFade = RainSurfaceMath.clamp01(Double(dy / max(onePixel, s)))
                let ridgeFade = pow(1.0 - tFade, 1.85)

                let ra = prng.nextDouble01()
                let a = RainSurfaceMath.clamp01(fa * (0.055 + 0.160 * ra) * ridgeFade)

                if a <= 0.000_5 { continue }

                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(a)))
            }
        }
    }

    // MARK: - Glow (optional, certainty-weighted)

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
        xPoints: [CGFloat],
        alphas: [Double],
        stride: Int
    ) -> [Gradient.Stop] {
        let s = max(1, stride)

        var stops: [Gradient.Stop] = []
        stops.reserveCapacity((xPoints.count / s) + 2)

        var i = 0
        while i < xPoints.count {
            let locRaw = (xPoints[i] - plotRect.minX) / max(1.0, width)
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
