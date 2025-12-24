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

    // MARK: - Core surface + ridge highlight + atmospheric diffusion band

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

        // Sigma bounds for the diffusion band thickness
        let minSigmaPoints = max(onePixel, CGFloat(max(0.0, configuration.diffusionMinRadiusPoints)))
        let hardMaxSigmaPoints = max(minSigmaPoints, CGFloat(max(0.0, configuration.diffusionMaxRadiusPoints)))
        let fracMax = max(0.05, CGFloat(configuration.diffusionMaxRadiusFractionOfHeight))
        let maxFromHeight = max(minSigmaPoints, (maxHeight * fracMax))
        let maxSigmaPoints = min(hardMaxSigmaPoints, maxFromHeight)

        let certaintySmoothed = RainSurfaceMath.smooth(Array(certainty.prefix(n)), passes: 2)

        // Certainty mapping for “uncertainty”
        let smoothChanceCutoff: Double = 0.94
        let fullFuzzChance: Double = 0.58
        let chanceDenom = max(0.000_001, smoothChanceCutoff - fullFuzzChance)

        let radiusPower = max(0.01, configuration.diffusionRadiusUncertaintyPower)
        let strengthMax = max(0.0, configuration.diffusionStrengthMax)

        let strengthPower = max(0.01, configuration.diffusionStrengthUncertaintyPower)
        let minUncertainTerm = RainSurfaceMath.clamp01(configuration.diffusionStrengthMinUncertainTerm)

        let jitterAmp = CGFloat(max(0.0, configuration.diffusionJitterAmplitudePoints)) / max(1.0, displayScale)
        let fuzzMultiplier = max(0.0, configuration.fuzzParticleAlphaMultiplier > 0 ? configuration.fuzzParticleAlphaMultiplier : 1.0)

        let hazeDotsOn = configuration.fuzzEnabled && configuration.fuzzDotsEnabled && configuration.fuzzDotsPerSampleMax > 0
        let maxDots = max(0, configuration.fuzzDotsPerSampleMax)

        // Arrays per sample
        var sigma = [CGFloat](repeating: 0, count: n)
        var coreAlpha = [Double](repeating: 0, count: n)
        var hazeAlpha = [Double](repeating: 0, count: n)
        var coreHeights = [CGFloat](repeating: 0, count: n)
        var crestAlpha = [Double](repeating: 0, count: n)

        for i in 0..<n {
            let h = max(0.0, heights[i])
            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            let cRaw = RainSurfaceMath.clamp01(certaintySmoothed[i])
            let edge = RainSurfaceMath.clamp01(edgeFactors[i])

            // Local slope proxy (promotes diffusion near transitions)
            let hl = heights[max(0, i - 1)]
            let hr = heights[min(n - 1, i + 1)]
            let dh = abs(hr - hl) * 0.5
            let slope01 = RainSurfaceMath.clamp01(Double(dh / max(onePixel, maxHeight * 0.18)))

            // Uncertainty in 0..1 (0 = very certain, 1 = very uncertain)
            let uRaw = RainSurfaceMath.clamp01((smoothChanceCutoff - cRaw) / chanceDenom)
            let uPowForRadius = pow(uRaw, radiusPower)

            // Sigma (diffusion thickness)
            var s = minSigmaPoints + (maxSigmaPoints - minSigmaPoints) * CGFloat(uPowForRadius)

            // Stronger diffusion for low/moderate intensities + transitions, weaker on stable peaks
            let lowI = 1.0 - pow(inorm, 0.60)
            let intensitySupport = 0.35 + 0.65 * (0.80 * lowI + 0.20 * slope01)
            s *= CGFloat(0.75 + 0.25 * intensitySupport)

            if jitterAmp > 0.000_01, s > 0.000_01 {
                var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0x51A7E, saltB: 0xC0FFEE))
                let jr = randTriangle(&prng)
                s += CGFloat(jr) * jitterAmp
            }
            s = max(onePixel, s)
            sigma[i] = s

            // Haze strength (0..1)
            let uPow = pow(uRaw, strengthPower)
            let uTerm = (uRaw <= 0.000_01) ? 0.0 : (minUncertainTerm + (1.0 - minUncertainTerm) * uPow)
            let haze = RainSurfaceMath.clamp01(strengthMax * uTerm * intensitySupport * edge * fuzzMultiplier)
            hazeAlpha[i] = haze

            // Core alpha (clean + readable)
            let baseCore = (0.18 + 0.82 * pow(cRaw, 1.35)) * (0.55 + 0.45 * pow(inorm, 0.85)) * edge
            let coreFade = max(0.0, 1.0 - 0.80 * haze) // haze defines the silhouette when strong
            coreAlpha[i] = RainSurfaceMath.clamp01(baseCore * coreFade)

            // Cut the core down so the atmospheric band becomes the visible edge in uncertainty
            if h > 0.000_01 {
                let cutScale = RainSurfaceMath.clamp(0.18 + 2.80 * uRaw + 0.90 * slope01, min: 0.18, max: 3.60)
                let cutAmount = min(h - onePixel * 0.25, s * CGFloat(cutScale) * CGFloat(0.35 + 0.65 * haze))
                coreHeights[i] = max(0.0, h - max(0.0, cutAmount))
            } else {
                coreHeights[i] = 0.0
            }

            // Crest highlight (thin, blurred, suppressed when haze is strong)
            if configuration.crestEnabled, configuration.crestMaxOpacity > 0.000_01 {
                let prev = heights[max(0, i - 1)]
                let next = heights[min(n - 1, i + 1)]
                let peakness = RainSurfaceMath.clamp01(Double((h - 0.5 * (prev + next)) / max(onePixel, maxHeight * 0.22)))

                let peakBoost = 1.0 + configuration.crestPeakBoost * peakness
                let crestBase = configuration.crestMaxOpacity
                    * (0.25 + 0.75 * pow(inorm, 0.85))
                    * (0.35 + 0.65 * pow(cRaw, 1.25))
                    * edge
                    * max(0.0, 1.0 - 0.65 * haze)

                crestAlpha[i] = RainSurfaceMath.clamp01(crestBase * peakBoost)
            } else {
                crestAlpha[i] = 0.0
            }
        }

        // Core fill gradient (dark base -> bright crest)
        let fillGradient = Gradient(stops: [
            .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
            .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0)
        ])

        let width = max(1.0, plotRect.width)

        for seg in segments {
            let r = seg.range
            guard !r.isEmpty else { continue }

            let startEdgeX = plotRect.minX + CGFloat(r.lowerBound) * stepX
            let endEdgeX = plotRect.minX + CGFloat(r.upperBound) * stepX

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

            let coreTopEdge = RainSurfaceGeometry.makeTopEdgePath(
                for: r,
                plotRect: plotRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: coreHeights
            )

            let first = r.lowerBound
            let last = max(first, r.upperBound - 1)

            // X positions + per-point alphas for horizontal shading
            var xPoints: [CGFloat] = []
            var pointCoreA: [Double] = []
            var pointHazeA: [Double] = []
            var pointCrestA: [Double] = []

            xPoints.reserveCapacity(r.count + 2)
            pointCoreA.reserveCapacity(r.count + 2)
            pointHazeA.reserveCapacity(r.count + 2)
            pointCrestA.reserveCapacity(r.count + 2)

            func appendEdgePoint(x: CGFloat, idx: Int) {
                xPoints.append(x)
                pointCoreA.append(coreAlpha[idx])
                pointHazeA.append(hazeAlpha[idx])
                pointCrestA.append(crestAlpha[idx])
            }

            appendEdgePoint(x: startEdgeX, idx: first)
            for i in r {
                let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                appendEdgePoint(x: x, idx: i)
            }
            appendEdgePoint(x: endEdgeX, idx: last)

            // --- 1) Core fill (clean, deterministic) ---
            let coreStops = makeHorizontalStops(
                plotRect: plotRect,
                width: width,
                xPoints: xPoints,
                alphas: pointCoreA,
                stopStride: 1
            )

            let coreMaskShading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: coreStops),
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
            )

            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))

                // Mask stage
                layer.fill(corePath, with: coreMaskShading)

                // Colour stage
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

            // --- 2) Crest / ridge highlight (thin band, blurred, no hard outline) ---
            if configuration.crestEnabled, configuration.crestMaxOpacity > 0.000_01 {
                let lineWidth = max(onePixel, configuration.crestLineWidthPoints)
                let blurR = max(0.0, configuration.crestBlurRadiusPoints)

                let strokeShape = coreTopEdge.strokedPath(
                    StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                )

                let crestStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: pointCrestA,
                    colour: configuration.crestColor,
                    stopStride: 1
                )

                let crestShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: crestStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .screen

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if blurR > 0.000_01 {
                        layer.addFilter(.blur(radius: blurR))
                    }

                    layer.fill(strokeShape, with: crestShading)

                    // Clip after blur so the highlight cannot form an outside “ghost”
                    layer.blendMode = .destinationIn
                    layer.fill(corePath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // --- 3) Atmospheric diffusion band above the surface (outside only, textured, fast falloff) ---
            if configuration.fuzzEnabled, strengthMax > 0.000_01, (pointHazeA.max() ?? 0.0) > 0.000_5 {
                let blurR = max(0.0, configuration.fuzzGlobalBlurRadiusPoints)
                let edgeSoftWidth = configuration.diffusionEdgeSofteningWidth

                // Segment max sigma controls the band’s thickness
                var maxS: CGFloat = 0
                for idx in r { maxS = max(maxS, sigma[idx]) }

                let bandWidth = max(onePixel, min(maxHeight * 0.34, maxS * 2.20))
                let band = coreTopEdge.strokedPath(
                    StrokeStyle(lineWidth: bandWidth, lineCap: .round, lineJoin: .round)
                )

                // Outside-of-core clip path (even-odd): clipRect minus corePath
                var outside = Path()
                outside.addRect(clipRect)
                outside.addPath(corePath)

                let hazeStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: pointHazeA.map { a in RainSurfaceMath.clamp01(a * 0.22) },
                    colour: configuration.glowColor,
                    stopStride: max(1, configuration.diffusionStopStride)
                )

                let hazeStrokeShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: hazeStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .screen

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

                    // Outside-only
                    layer.clip(to: outside, style: FillStyle(eoFill: true))

                    // Ridge-attached band
                    layer.clip(to: band)

                    if blurR > 0.000_01 {
                        layer.addFilter(.blur(radius: blurR))
                    }

                    // Subtle continuous haze body (very low alpha), avoids a hard second silhouette.
                    if configuration.fuzzLineWidthMultiplier > 0.000_01 {
                        let strokeW = max(onePixel, min(bandWidth, bandWidth * max(0.10, configuration.fuzzLineWidthMultiplier)))
                        let strokeShape = coreTopEdge.strokedPath(
                            StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
                        )
                        layer.fill(strokeShape, with: hazeStrokeShading)
                    }

                    // Dots supply true 2D texture (no vertical streaking)
                    if hazeDotsOn, maxDots > 0 {
                        drawHazeDots(
                            in: &layer,
                            plotRect: plotRect,
                            baselineY: baselineY,
                            stepX: stepX,
                            range: r,
                            coreHeights: coreHeights,
                            sigma: sigma,
                            hazeAlpha: hazeAlpha,
                            intensityNorm: intensityNorm,
                            maxDotsPerSample: maxDots,
                            falloffPower: max(0.35, configuration.diffusionFalloffPower),
                            edgeSofteningWidth: edgeSoftWidth,
                            colour: configuration.glowColor,
                            onePixel: onePixel
                        )
                    }
                }

                context.blendMode = savedBlend
            }
        }
    }

    // MARK: - Glow (controlled, derived from the same surface geometry)

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

        // Glow radius in pixels then back to points
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
            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certaintySmoothed[i])
            let edge = RainSurfaceMath.clamp01(edgeFactors[i])

            let a = configuration.glowMaxAlpha
                * (0.20 + 0.80 * pow(inorm, 0.72))
                * pow(c, glowCertaintyPower)
                * edge

            glowAlpha[i] = RainSurfaceMath.clamp01(a)
        }

        let savedBlend = context.blendMode
        context.blendMode = .screen

        for seg in segments {
            drawGlowBands(
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
                colour: configuration.glowColor,
                edgeSofteningWidth: configuration.diffusionEdgeSofteningWidth,
                onePixel: onePixel,
                stopStride: max(1, configuration.diffusionStopStride)
            )
        }

        context.blendMode = savedBlend
    }

    private static func drawGlowBands(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Swift.Range<Int>,
        heights: [CGFloat],
        glowRadius: CGFloat,
        alphaBySample: [Double],
        layers: Int,
        falloffPower: Double,
        colour: Color,
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
                stops.append(.init(color: colour.opacity(a), location: loc))
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

    // MARK: - Haze dots (true 2D noise, outside-only, fades upward)

    private static func drawHazeDots(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Swift.Range<Int>,
        coreHeights: [CGFloat],
        sigma: [CGFloat],
        hazeAlpha: [Double],
        intensityNorm: [Double],
        maxDotsPerSample: Int,
        falloffPower: Double,
        edgeSofteningWidth: Double,
        colour: Color,
        onePixel: CGFloat
    ) {
        guard maxDotsPerSample > 0 else { return }

        for i in range {
            let h = coreHeights[i]
            if h <= 0.000_01 { continue }

            let inorm = RainSurfaceMath.clamp01(intensityNorm[i])
            if inorm <= 0.000_01 { continue }

            let ha = RainSurfaceMath.clamp01(hazeAlpha[i])
            if ha <= 0.002 { continue }

            let soft = segmentEdgeSofteningFactor(index: i, range: range, widthFraction: edgeSofteningWidth)

            let s = max(onePixel, sigma[i])
            let topY = baselineY - h

            // Dot count: more dots at low/moderate intensity and higher haze alpha.
            let lowI = 1.0 - pow(inorm, 0.60)
            let intensitySupport = 0.55 + 0.45 * lowI

            let desired = Double(maxDotsPerSample)
                * (0.75 + 3.00 * ha)
                * intensitySupport
                * soft

            let dotCount = min(260, max(1, Int(desired.rounded(.toNearestOrAwayFromZero))))

            // Upward diffusion band height: sigma-driven, capped to stay ridge-attached.
            let upSpan = min(h * 0.42, s * (0.85 + 1.35 * CGFloat(ha)))

            // Very low per-dot alpha, relies on blur + accumulation.
            let baseDotAlpha = 0.010 + 0.050 * ha * intensitySupport

            var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xBADC0DE, saltB: 0x12345))

            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            for j in 0..<dotCount {
                let rx = prng.nextDouble01()
                let ry = prng.nextDouble01()

                // Concentrate near the ridge (more mass near yOffset = 0)
                let yT = pow(ry, 1.65)
                let yOffset = CGFloat(yT) * upSpan

                let x = RainSurfaceMath.clamp(CGFloat(x0) + CGFloat(rx) * stepX, min: x0, max: x1)
                let y = topY - yOffset

                // Upward falloff
                let vf = pow(max(0.0, 1.0 - Double(yOffset / max(onePixel, upSpan))), falloffPower)

                // Radius stays small; avoids “stars” and prevents directionality.
                let rBase = (0.45 + 0.85 * prng.nextDouble01())
                let r = max(onePixel * 0.55, min(onePixel * 2.4, CGFloat(rBase) * (onePixel * 1.2 + s * 0.020)))

                let a = RainSurfaceMath.clamp01(baseDotAlpha * vf)
                if a <= 0.000_01 { continue }

                let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
                let p = Path(ellipseIn: rect)

                // Fine-grain second pass every few dots (subtle, no streaks)
                let micro = (j % 7 == 0)
                let microAlpha = micro ? (a * 0.55) : a

                context.fill(p, with: .color(colour.opacity(microAlpha)))
            }
        }
    }

    // MARK: - Helpers

    private static func makeHorizontalStops(
        plotRect: CGRect,
        width: CGFloat,
        xPoints: [CGFloat],
        alphas: [Double],
        stopStride: Int
    ) -> [Gradient.Stop] {
        let s = max(1, stopStride)
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

    private static func makeHorizontalColourStops(
        plotRect: CGRect,
        width: CGFloat,
        xPoints: [CGFloat],
        alphas: [Double],
        colour: Color,
        stopStride: Int
    ) -> [Gradient.Stop] {
        let s = max(1, stopStride)
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity((xPoints.count / s) + 2)

        var i = 0
        while i < xPoints.count {
            let locRaw = (xPoints[i] - plotRect.minX) / max(1.0, width)
            let loc = max(0.0, min(1.0, locRaw))
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: colour.opacity(a), location: loc))
            i += s
        }

        if stops.count == 1 {
            let c = stops[0].color
            stops.append(.init(color: c, location: min(1.0, stops[0].location + 0.0001)))
        }

        return stops
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
            var p = out[i]
            p.y = min(baselineY, p.y + dy)
            out[i] = p
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

    private static func segmentEdgeSofteningFactor(
        index: Int,
        range: Swift.Range<Int>,
        widthFraction: Double
    ) -> Double {
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
