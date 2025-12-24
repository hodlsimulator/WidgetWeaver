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

    // MARK: - Probability-masked surface (core + fuzz blobs + fuzz dots)

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

        // Sigma controls fuzzy thickness.
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

        let fuzzBlurBase = CGFloat(max(0.0, configuration.fuzzGlobalBlurRadiusPoints))
        let fuzzBlur = max(0.0, fuzzBlurBase * 1.55)

        // Precompute per-sample parameters.
        var sigma = [CGFloat](repeating: 0, count: n)
        var coreAlpha = [Double](repeating: 0, count: n)
        var fuzzAlpha = [Double](repeating: 0, count: n)
        var coreHeights = [CGFloat](repeating: 0, count: n)

        // Mild certainty smoothing avoids patchy per-minute stepping.
        let certaintySmoothed = RainSurfaceMath.smooth(Array(certainty.prefix(n)), passes: 2)

        for i in 0..<n {
            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certaintySmoothed[i])
            let u = RainSurfaceMath.clamp01(1.0 - c)
            let edge = RainSurfaceMath.clamp01(edgeFactors[i])

            let h = heights[i]
            if h <= 0.000_01 {
                sigma[i] = onePixel
                coreAlpha[i] = 0.0
                fuzzAlpha[i] = 0.0
                coreHeights[i] = 0.0
                continue
            }

            // Sigma grows as certainty drops.
            var s = minSigmaPoints + (maxSigmaPoints - minSigmaPoints) * CGFloat(pow(u, radiusPower))

            // Cap sigma by local column height so tiny tails do not produce big clouds.
            let sigmaCap = max(onePixel, min(maxSigmaPoints, (h * (0.42 + 0.95 * CGFloat(u))) + (6.0 / max(1.0, displayScale))))
            s = min(s, sigmaCap)

            // Deterministic micro-jitter (texture, no streaks).
            if jitterAmp > 0.000_01, s > 0.000_01 {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0x51A7E, saltB: 0xC0FFEE))
                let jr = randTriangle(&prng)
                s += CGFloat(jr) * jitterAmp
            }

            s = max(onePixel, s)
            sigma[i] = s

            // Solid core opacity (higher certainty => more solid).
            let core = RainSurfaceMath.clamp01(
                (0.18 + 0.82 * pow(c, 0.78))
                * (0.55 + 0.45 * pow(inorm, 0.55))
                * edge
            )
            coreAlpha[i] = core

            // Fuzz strength (lower certainty => stronger fuzz).
            let fuzz = RainSurfaceMath.clamp01(
                strengthMax
                * (0.06 + 0.94 * pow(u, 0.92))
                * pow(inorm, 0.68)
                * edge
                * fuzzMultiplier
            )
            fuzzAlpha[i] = fuzz

            // Core height is pulled down when fuzz is present to avoid “double edges”.
            // Cut increases with uncertainty, and sigma already grows with uncertainty.
            let cutMult = RainSurfaceMath.clamp(
                0.55 + 0.95 * pow(u, 0.72),
                min: 0.45,
                max: 1.55
            )
            let cut = min(h - onePixel * 0.25, s * CGFloat(cutMult))
            coreHeights[i] = max(0.0, h - max(0.0, cut))
        }

        // Vertical fill gradient applied through the mask.
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

            // Core interior path.
            let corePath = RainSurfaceGeometry.makeSurfacePath(
                for: r,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: coreHeights
            )

            // Points for horizontal alpha mapping (include edges).
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
                // Core
                layer.fill(corePath, with: coreShading)

                // Fuzz is *only* stochastic blobs + dots (no contour bands),
                // so there is no secondary smooth silhouette above the grain.
                layer.drawLayer { fuzzLayer in
                    if fuzzBlur > 0.000_01 {
                        fuzzLayer.addFilter(.blur(radius: fuzzBlur))
                    }

                    drawFuzzBlobs(
                        in: &fuzzLayer,
                        plotRect: plotRect,
                        baselineY: baselineY,
                        stepX: stepX,
                        range: r,
                        heights: heights,
                        sigma: sigma,
                        fuzzAlpha: fuzzAlpha,
                        intensityNorm: intensityNorm,
                        onePixel: onePixel
                    )

                    if dotsOn, maxDots > 0 {
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

    // MARK: - Fuzz blobs (mask)

    private static func drawFuzzBlobs(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        sigma: [CGFloat],
        fuzzAlpha: [Double],
        intensityNorm: [Double],
        onePixel: CGFloat
    ) {
        for i in range {
            let h = heights[i]
            if h <= 0.000_01 { continue }

            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            if inorm <= 0.000_01 { continue }

            let fa = RainSurfaceMath.clamp01(fuzzAlpha[i])
            if fa <= 0.000_5 { continue }

            let s = max(onePixel, sigma[i])
            let topY = baselineY - h

            // Blob count scales with fuzz strength.
            let blobCount = max(1, min(5, 1 + Int((fa * 4.0).rounded(.toNearestOrAwayFromZero))))

            for b in 0..<blobCount {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xB10B5, saltB: (b &* 911) &+ 7))

                let ox = CGFloat(randSigned(&prng)) * stepX * 0.32
                let x = (plotRect.minX + (CGFloat(i) + 0.5) * stepX) + ox

                let chooseInside = prng.nextDouble01() < (0.28 + 0.22 * fa)

                // Centres hover around the ridge (mostly above), with some inside blobs to avoid any seam.
                let y: CGFloat
                if chooseInside {
                    let t = CGFloat(prng.nextDouble01())
                    y = min(baselineY, topY + (0.04 + 0.42 * t) * s)
                } else {
                    let t = CGFloat(prng.nextDouble01())
                    y = max(plotRect.minY, topY - (0.12 + 0.72 * t) * s)
                }

                let rr = CGFloat(prng.nextDouble01())
                let r = max(onePixel * 0.85, (0.28 + 0.78 * rr) * s)

                // Fade with distance from ridge so the fuzz does not form a second coherent silhouette.
                let dy = abs(y - topY)
                let tFade = RainSurfaceMath.clamp01(Double(dy / max(onePixel, s)))
                let ridgeFade = pow(1.0 - tFade, 1.25)

                let ra = prng.nextDouble01()
                let a = RainSurfaceMath.clamp01(fa * (0.14 + 0.46 * ra) * ridgeFade)

                if a <= 0.000_5 { continue }

                let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(a)))
            }
        }
    }

    // MARK: - Fuzz dots (mask grain)

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

            let density = RainSurfaceMath.clamp01(0.10 + 0.90 * fa)
            let desired = Double(maxDotsPerSample) * density * (0.50 + 0.50 * pow(inorm, 0.55))
            let dotCount = max(1, Int(desired.rounded(.toNearestOrAwayFromZero)))

            let outsideWeight = RainSurfaceMath.clamp01(0.52 + 0.34 * fa)
            let insideCap = min(h * 0.70, s * 0.90)

            for j in 0..<dotCount {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xD07D07D0, saltB: (j &* 173) &+ 19))

                let rx = prng.nextDouble01()
                let x = plotRect.minX + (CGFloat(i) + CGFloat(rx)) * stepX

                let pick = prng.nextDouble01()
                let y: CGFloat
                if pick < outsideWeight {
                    let t = prng.nextDouble01()
                    let up = CGFloat(pow(t, 1.25)) * (s * 0.95)
                    y = max(plotRect.minY, topY - up)
                } else {
                    let t = prng.nextDouble01()
                    let down = CGFloat(pow(t, 1.15)) * max(onePixel, insideCap)
                    y = min(baselineY, topY + down)
                }

                let rr = prng.nextDouble01()
                let r = max(onePixel * 0.65, onePixel * (0.85 + 2.75 * rr) * (0.70 + 0.80 * CGFloat(fa)))

                let dy = abs(y - topY)
                let tFade = RainSurfaceMath.clamp01(Double(dy / max(onePixel, s)))
                let ridgeFade = pow(1.0 - tFade, 1.35)

                let ra = prng.nextDouble01()
                let a = RainSurfaceMath.clamp01(fa * (0.035 + 0.090 * ra) * ridgeFade)

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
            addSmoothBandPath(&band, outer: said(outer), inner: said(inner))

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

    private static func said(_ pts: [CGPoint]) -> [CGPoint] { pts }

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

    private static func randSigned(_ prng: inout RainSurfacePRNG) -> Double {
        (prng.nextDouble01() * 2.0) - 1.0
    }
}
