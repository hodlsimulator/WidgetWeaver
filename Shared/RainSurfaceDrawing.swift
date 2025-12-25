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
            let softWidth = max(configuration.baselineLineWidth, configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier)
            let softOpacity = max(0.0, min(1.0, configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier))
            let softStyle = StrokeStyle(lineWidth: max(onePixel, softWidth), lineCap: .round)
            context.stroke(base, with: .color(configuration.baselineColor.opacity(softOpacity)), style: softStyle)
        }

        let stroke = StrokeStyle(lineWidth: max(onePixel, configuration.baselineLineWidth), lineCap: .round)
        context.stroke(base, with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)), style: stroke)

        context.blendMode = savedBlend
    }

    // MARK: - 3 masks + 3 passes: core, ridge, mist

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
        let coreMaxH = max(1.0, heights.max() ?? 1.0)

        // Per-sample drivers
        var coreAlpha = [Double](repeating: 0.0, count: n)
        var ridgeAlpha = [Double](repeating: 0.0, count: n)
        var mistAlpha = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let v = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certainty[i])
            let taper = RainSurfaceMath.clamp01(edgeFactors[i])

            // Step 2: taper mask applies to all layers
            coreAlpha[i] = taper

            let prev = heights[max(0, i - 1)]
            let next = heights[min(n - 1, i + 1)]

            let dh = abs(next - prev) * 0.5
            let slope01 = RainSurfaceMath.clamp01(Double(dh / max(onePixel, coreMaxH * 0.25)))

            let peakRaw = (h - 0.5 * (prev + next))
            let peak01 = RainSurfaceMath.clamp01(Double(peakRaw / max(onePixel, coreMaxH * 0.22)))

            // Ridge highlight: stronger at peaks, weaker on flats
            if configuration.ridgeEnabled, configuration.ridgeMaxOpacity > 0.000_01 {
                let base = configuration.ridgeMaxOpacity
                    * taper
                    * (0.22 + 0.78 * pow(v, 0.85))
                    * (0.55 + 0.45 * pow(c, 1.15))

                let boost = 1.0 + configuration.ridgePeakBoost * peak01
                ridgeAlpha[i] = RainSurfaceMath.clamp01(base * boost)
            }

            // Mist strength proxy (uncertainty-aware without a true uncertainty metric):
            // - more when c is lower
            // - more when v is low/moderate
            // - more when slope is high
            if configuration.mistEnabled, configuration.mistMaxOpacity > 0.000_01 {
                let u = RainSurfaceMath.clamp01(1.0 - c)
                let lowV = 1.0 - pow(v, 0.75)

                var proxy = (0.55 * u) + (0.25 * lowV) + (0.20 * slope01)
                proxy = RainSurfaceMath.clamp01(proxy)

                // Suppress on high, stable peaks
                let stable = pow(v, 1.7) * (1.0 - slope01)
                proxy *= (1.0 - 0.65 * stable)

                mistAlpha[i] = RainSurfaceMath.clamp01(configuration.mistMaxOpacity * taper * pow(proxy, 1.10))
            }
        }

        let width = max(1.0, plotRect.width)

        let fillGradient = Gradient(stops: [
            .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
            .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0)
        ])

        for seg in segments {
            let r = seg.range
            guard !r.isEmpty else { continue }

            let first = r.lowerBound
            let last = max(first, r.upperBound - 1)

            let startEdgeX = plotRect.minX + CGFloat(r.lowerBound) * stepX
            let endEdgeX = plotRect.minX + CGFloat(r.upperBound) * stepX

            let clipRect = CGRect(
                x: startEdgeX,
                y: plotRect.minY,
                width: max(0, endEdgeX - startEdgeX),
                height: max(0, baselineY - plotRect.minY)
            )
            if clipRect.width <= 0 || clipRect.height <= 0 { continue }

            // Authoritative core mask
            let coreMaskPath = seg.surfacePath
            let topEdgePath = seg.topEdgePath

            // Build per-x stop arrays (mask alpha)
            var xPoints: [CGFloat] = []
            var coreA: [Double] = []
            var ridgeA: [Double] = []
            var mistA: [Double] = []

            xPoints.reserveCapacity(r.count + 2)
            coreA.reserveCapacity(r.count + 2)
            ridgeA.reserveCapacity(r.count + 2)
            mistA.reserveCapacity(r.count + 2)

            func appendEdgePoint(x: CGFloat, idx: Int) {
                xPoints.append(x)
                coreA.append(coreAlpha[idx])
                ridgeA.append(ridgeAlpha[idx])
                mistA.append(mistAlpha[idx])
            }

            appendEdgePoint(x: startEdgeX, idx: first)
            for i in r {
                let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                appendEdgePoint(x: x, idx: i)
            }
            appendEdgePoint(x: endEdgeX, idx: last)

            // PASS 1 — Core fill
            let coreStops = makeHorizontalStops(
                plotRect: plotRect,
                width: width,
                xPoints: xPoints,
                alphas: coreA
            )

            let coreMaskShading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: coreStops),
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
            )

            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))

                layer.fill(coreMaskPath, with: coreMaskShading)

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

            // PASS 2 — Ridge highlight (blurred) clipped back to core
            if configuration.ridgeEnabled, configuration.ridgeMaxOpacity > 0.000_01, (ridgeA.max() ?? 0.0) > 0.000_5 {
                let ridgeThickness = max(onePixel, configuration.ridgeThicknessPoints)
                let ridgeLineWidth = ridgeThickness * 2.0
                let ridgeBlur = max(0.0, configuration.ridgeBlurRadiusPoints)

                let ridgeBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: ridgeLineWidth, lineCap: .round, lineJoin: .round)
                )

                let ridgeStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: ridgeA,
                    colour: configuration.ridgeColor
                )

                let ridgeShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: ridgeStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .screen

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

                    if ridgeBlur > 0.000_01 {
                        layer.addFilter(.blur(radius: ridgeBlur))
                    }

                    layer.fill(ridgeBand, with: ridgeShading)

                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // PASS 3 — Mist band + 2D texture (outside-only and band-clipped)
            if configuration.mistEnabled, configuration.mistMaxOpacity > 0.000_01, (mistA.max() ?? 0.0) > 0.000_5 {
                let mistHeightCap = max(onePixel, configuration.mistHeightPoints)
                let mistHeightFrac = max(0.05, min(1.0, configuration.mistHeightFractionOfPlotHeight))
                let mistHeight = min(mistHeightCap, plotRect.height * mistHeightFrac)

                let mistBlur: CGFloat = {
                    if configuration.mistBlurRadiusPoints > 0.000_01 { return configuration.mistBlurRadiusPoints }
                    return max(onePixel, mistHeight * 0.33)
                }()

                let mistStrokeWidth = max(onePixel, configuration.ridgeThicknessPoints * 0.65)

                let mistBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: mistHeight * 2.0, lineCap: .round, lineJoin: .round)
                )

                var outside = Path()
                outside.addRect(clipRect)
                outside.addPath(coreMaskPath)

                let mistStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: mistA,
                    colour: configuration.mistColor
                )

                let mistShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: mistStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .screen

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

                    layer.drawLayer { base in
                        base.addFilter(.blur(radius: mistBlur))

                        let crestStroke = topEdgePath.strokedPath(
                            StrokeStyle(lineWidth: mistStrokeWidth, lineCap: .round, lineJoin: .round)
                        )
                        base.fill(crestStroke, with: mistShading)
                    }

                    if configuration.mistNoiseEnabled {
                        drawMistParticles(
                            in: &layer,
                            plotRect: plotRect,
                            baselineY: baselineY,
                            stepX: stepX,
                            range: r,
                            heights: heights,
                            mistHeight: mistHeight,
                            mistAlpha: mistAlpha,
                            falloffPower: max(0.35, configuration.mistFalloffPower),
                            edgeSofteningWidth: RainSurfaceMath.clamp01(configuration.mistEdgeSofteningWidth),
                            colour: configuration.mistColor,
                            noiseInfluence: RainSurfaceMath.clamp01(configuration.mistNoiseInfluence),
                            puffsPerSampleMax: max(0, configuration.mistPuffsPerSampleMax),
                            finePerSampleMax: max(0, configuration.mistFineGrainPerSampleMax),
                            puffMinR: max(onePixel * 0.55, configuration.mistParticleMinRadiusPoints),
                            puffMaxR: max(onePixel * 0.75, configuration.mistParticleMaxRadiusPoints),
                            fineMinR: max(onePixel * 0.40, configuration.mistFineParticleMinRadiusPoints),
                            fineMaxR: max(onePixel * 0.55, configuration.mistFineParticleMaxRadiusPoints),
                            onePixel: onePixel
                        )
                    }

                    layer.blendMode = .destinationIn
                    layer.fill(mistBand, with: .color(.white))
                    layer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                }

                context.blendMode = savedBlend
            }
        }
    }

    // MARK: - Glow (mask-derived, clipped)

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

        let glowCertaintyPower = max(0.01, configuration.glowCertaintyPower)

        var glowAlpha = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            let v = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certainty[i])
            let taper = RainSurfaceMath.clamp01(edgeFactors[i])

            let a = configuration.glowMaxAlpha
                * taper
                * (0.18 + 0.82 * pow(v, 0.75))
                * pow(c, glowCertaintyPower)

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
                coreMaskPath: seg.surfacePath,
                glowRadius: glowRadius,
                alphaBySample: glowAlpha,
                layers: max(2, configuration.glowLayers),
                falloffPower: max(0.01, configuration.glowFalloffPower),
                colour: configuration.glowColor,
                onePixel: onePixel
            )
        }

        context.blendMode = savedBlend
    }

    private static func drawGlowBands(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        coreMaskPath: Path,
        glowRadius: CGFloat,
        alphaBySample: [Double],
        layers: Int,
        falloffPower: Double,
        colour: Color,
        onePixel: CGFloat
    ) {
        guard let first = range.first else { return }
        let last = max(first, range.upperBound - 1)

        let startEdgeX = plotRect.minX + CGFloat(range.lowerBound) * stepX
        let endEdgeX = plotRect.minX + CGFloat(range.upperBound) * stepX

        var points: [CGPoint] = []
        var baseAlpha: [Double] = []

        points.reserveCapacity(range.count + 2)
        baseAlpha.reserveCapacity(range.count + 2)

        points.append(CGPoint(x: startEdgeX, y: baselineY - heights[first]))
        baseAlpha.append(alphaBySample[first])

        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            points.append(CGPoint(x: x, y: y))
            baseAlpha.append(alphaBySample[i])
        }

        points.append(CGPoint(x: endEdgeX, y: baselineY - heights[last]))
        baseAlpha.append(alphaBySample[last])

        let peakAlpha = baseAlpha.max() ?? 0.0
        guard peakAlpha > 0.000_5, glowRadius > (0.5 * onePixel) else { return }

        let width = max(0.000_01, plotRect.width)
        let denom = Double(max(1, layers - 1))

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
            stops.reserveCapacity(points.count)

            for j in 0..<points.count {
                let locRaw = (points[j].x - plotRect.minX) / width
                let loc = max(0.0, min(1.0, locRaw))
                let a = RainSurfaceMath.clamp01(baseAlpha[j] * w)
                stops.append(.init(color: colour.opacity(a), location: loc))
            }

            if stops.count >= 2 {
                let shading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: stops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                context.drawLayer { layer in
                    layer.clip(to: coreMaskPath)
                    layer.fill(band, with: shading)
                }
            }
        }
    }

    // MARK: - Mist particles (isotropic 2D)

    private static func drawMistParticles(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        mistHeight: CGFloat,
        mistAlpha: [Double],
        falloffPower: Double,
        edgeSofteningWidth: Double,
        colour: Color,
        noiseInfluence: Double,
        puffsPerSampleMax: Int,
        finePerSampleMax: Int,
        puffMinR: CGFloat,
        puffMaxR: CGFloat,
        fineMinR: CGFloat,
        fineMaxR: CGFloat,
        onePixel: CGFloat
    ) {
        guard mistHeight > onePixel else { return }

        for i in range {
            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let baseA0 = RainSurfaceMath.clamp01(mistAlpha[i])
            if baseA0 <= 0.000_8 { continue }

            let edgeSoft = segmentEdgeSofteningFactor(index: i, range: range, widthFraction: edgeSofteningWidth)
            let baseA = baseA0 * edgeSoft
            if baseA <= 0.000_8 { continue }

            let topY = baselineY - h
            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            // Seed locally to avoid relying on RainSurfacePRNG.seed(...) signature.
            var prng = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_000C_7A11, saltB: 0x0000_0000_B16B_00B5))

            // Low-to-mid frequency puffs
            if puffsPerSampleMax > 0 {
                let desired = Double(puffsPerSampleMax) * (0.65 + 2.20 * baseA)
                let puffCount = min(220, max(1, Int(desired + 0.5)))

                for _ in 0..<puffCount {
                    let rx = prng.nextDouble01()
                    let ry = prng.nextDouble01()

                    let yT = pow(ry, 1.55)
                    let yOffset = CGFloat(yT) * mistHeight
                    let y = topY - yOffset

                    let x = RainSurfaceMath.clamp(CGFloat(x0) + CGFloat(rx) * stepX, min: x0, max: x1)

                    let vf = pow(max(0.0, 1.0 - Double(yOffset / max(onePixel, mistHeight))), falloffPower)

                    // 2D modulation per particle (not per x-column)
                    let nf = (0.85 + 0.30 * prng.nextDouble01())
                    let amp = (1.0 + noiseInfluence * (nf - 1.0))

                    let rT = prng.nextDouble01()
                    let r = RainSurfaceMath.clamp(
                        puffMinR + (puffMaxR - puffMinR) * CGFloat(rT),
                        min: puffMinR,
                        max: puffMaxR
                    )

                    let a = RainSurfaceMath.clamp01(baseA * 0.030 * vf * amp)
                    if a <= 0.000_01 { continue }

                    let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
                    context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(a)))
                }
            }

            // Fine grain layer (very subtle)
            if finePerSampleMax > 0 {
                let desired = Double(finePerSampleMax) * (0.55 + 1.80 * baseA)
                let fineCount = min(240, max(1, Int(desired + 0.5)))

                var prng2 = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0091_F1EE, saltB: 0x0000_0000_0123_4567))

                for _ in 0..<fineCount {
                    let rx = prng2.nextDouble01()
                    let ry = prng2.nextDouble01()

                    let yT = pow(ry, 1.25)
                    let yOffset = CGFloat(yT) * mistHeight
                    let y = topY - yOffset

                    let x = RainSurfaceMath.clamp(CGFloat(x0) + CGFloat(rx) * stepX, min: x0, max: x1)

                    let vf = pow(max(0.0, 1.0 - Double(yOffset / max(onePixel, mistHeight))), falloffPower + 0.35)

                    let rT = prng2.nextDouble01()
                    let r = RainSurfaceMath.clamp(
                        fineMinR + (fineMaxR - fineMinR) * CGFloat(rT),
                        min: fineMinR,
                        max: fineMaxR
                    )

                    let a = RainSurfaceMath.clamp01(baseA * 0.010 * vf * (0.85 + 0.30 * prng2.nextDouble01()))
                    if a <= 0.000_01 { continue }

                    let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
                    context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(a)))
                }
            }
        }
    }

    // MARK: - Helpers

    private static func makeHorizontalStops(
        plotRect: CGRect,
        width: CGFloat,
        xPoints: [CGFloat],
        alphas: [Double]
    ) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(xPoints.count)

        for i in 0..<xPoints.count {
            let locRaw = (xPoints[i] - plotRect.minX) / max(1.0, width)
            let loc = max(0.0, min(1.0, locRaw))
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: Color.white.opacity(a), location: loc))
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
        colour: Color
    ) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(xPoints.count)

        for i in 0..<xPoints.count {
            let locRaw = (xPoints[i] - plotRect.minX) / max(1.0, width)
            let loc = max(0.0, min(1.0, locRaw))
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: colour.opacity(a), location: loc))
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
        range: Range<Int>,
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

    @inline(__always)
    private static func makeSeed(sampleIndex: Int, saltA: UInt64, saltB: UInt64) -> UInt64 {
        var x = UInt64(truncatingIfNeeded: sampleIndex)
        x &*= 0x9E3779B97F4A7C15
        x ^= saltA &+ (x << 6) &+ (x >> 2)
        x ^= saltB &+ (x << 17) &+ (x >> 3)
        x &*= 0xBF58476D1CE4E5B9
        x ^= x >> 31
        return x
    }
}
