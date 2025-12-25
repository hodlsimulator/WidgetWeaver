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

    // MARK: - Baseline (drawn behind)
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

        if configuration.baselineSoftOpacityMultiplier > 0,
           configuration.baselineSoftWidthMultiplier > 1
        {
            let softWidth = max(configuration.baselineLineWidth, configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier)
            let softOpacity = max(0.0, min(1.0, configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier))
            let softStyle = StrokeStyle(lineWidth: max(onePixel, softWidth), lineCap: .round)
            context.stroke(base, with: .color(configuration.baselineColor.opacity(softOpacity)), style: softStyle)
        }

        let stroke = StrokeStyle(lineWidth: max(onePixel, configuration.baselineLineWidth), lineCap: .round)
        context.stroke(base, with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)), style: stroke)

        context.blendMode = savedBlend
    }

    // MARK: - Masks + layered passes (order matters)
    //
    // Order:
    // 1) core fill (coreMask, smooth)
    // 2) broad bloom (mask-derived, clipped)
    // 3) above-surface mist (outside-only, drawn behind ridge)
    // 4) surface shell fuzz (boundary-attached)
    // 5) ridge highlight (inside core, drawn last to stay crisp)
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
        let plotH = max(1.0, plotRect.height)
        let width = max(1.0, plotRect.width)

        // Effective blur radii derived from plot height.
        let ridgeBlur = max(onePixel, plotH * max(0.0, configuration.ridgeBlurFractionOfPlotHeight))
        let bloomBlur = max(onePixel, plotH * max(0.0, configuration.bloomBlurFractionOfPlotHeight))
        let shellBlur = max(onePixel, plotH * max(0.0, configuration.shellBlurFractionOfPlotHeight))

        // Per-sample alphas (end tapers are ALPHA ONLY).
        var coreAlpha = [Double](repeating: 0.0, count: n)
        var ridgeAlpha = [Double](repeating: 0.0, count: n)
        var bloomAlpha = [Double](repeating: 0.0, count: n)
        var shellAlpha = [Double](repeating: 0.0, count: n)
        var mistAlpha = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let v = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certainty[i])
            let proxy = 1.0 - c
            let lowV = pow(1.0 - v, 1.20)

            let taper = RainSurfaceMath.clamp01(edgeFactors[i])

            if configuration.baselineOpacity > 0.000_01 {
                // Baseline handled elsewhere; kept here for completeness.
            }

            if configuration.ridgeEnabled, configuration.ridgeMaxOpacity > 0.000_01 {
                let base = configuration.ridgeMaxOpacity * taper
                    * (0.22 + 0.78 * pow(v, 0.85))
                    * (0.55 + 0.45 * pow(c, 1.10))

                ridgeAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.bloomEnabled, configuration.bloomMaxOpacity > 0.000_01 {
                let base = configuration.bloomMaxOpacity * taper
                    * (0.20 + 0.80 * pow(v, 0.75))

                let unc = (0.40 + 0.60 * proxy)
                bloomAlpha[i] = RainSurfaceMath.clamp01(base * unc)
            }

            if configuration.shellEnabled, configuration.shellMaxOpacity > 0.000_01 {
                let base = configuration.shellMaxOpacity * taper
                    * pow(proxy, 0.92)
                    * (0.70 + 0.30 * lowV)

                shellAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.mistEnabled, configuration.mistMaxOpacity > 0.000_01 {
                let base = configuration.mistMaxOpacity * taper * pow(proxy, 1.08)
                mistAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            // Core alpha: primarily intensity, moderated by certainty so low-confidence fades.
            let core = (0.20 + 0.80 * pow(v, 0.70)) * (0.35 + 0.65 * pow(c, 0.90)) * taper
            coreAlpha[i] = RainSurfaceMath.clamp01(core)
        }

        // Core fill gradient: dark baseline -> lifted mid -> slightly brighter crest.
        let fillGradient = Gradient(stops: [
            .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
            .init(color: configuration.fillMidColor.opacity(configuration.fillMidOpacity), location: 0.55),
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
                width: max(0.0, endEdgeX - startEdgeX),
                height: max(0.0, baselineY - plotRect.minY)
            )
            if clipRect.width <= 0 || clipRect.height <= 0 { continue }

            let coreMaskPath = seg.surfacePath
            let topEdgePath = seg.topEdgePath

            // Outside-of-core region (used for bloom/mist/shellAbove).
            var outside = Path()
            outside.addRect(clipRect)
            outside.addPath(coreMaskPath)

            // Per-x stop arrays (same xPoints for every layer).
            var xPoints: [CGFloat] = []
            var coreA: [Double] = []
            var ridgeA: [Double] = []
            var bloomA: [Double] = []
            var shellA: [Double] = []
            var mistA: [Double] = []

            xPoints.reserveCapacity(r.count + 2)
            coreA.reserveCapacity(r.count + 2)
            ridgeA.reserveCapacity(r.count + 2)
            bloomA.reserveCapacity(r.count + 2)
            shellA.reserveCapacity(r.count + 2)
            mistA.reserveCapacity(r.count + 2)

            func appendEdgePoint(x: CGFloat, idx: Int) {
                xPoints.append(x)
                coreA.append(coreAlpha[idx])
                ridgeA.append(ridgeAlpha[idx])
                bloomA.append(bloomAlpha[idx])
                shellA.append(shellAlpha[idx])
                mistA.append(mistAlpha[idx])
            }

            appendEdgePoint(x: startEdgeX, idx: first)

            for i in r {
                let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                appendEdgePoint(x: x, idx: i)
            }

            appendEdgePoint(x: endEdgeX, idx: last)

            // -------------------------
            // PASS 1 — Core fill (smooth)
            // -------------------------
            let coreStops = makeHorizontalStops(plotRect: plotRect, width: width, xPoints: xPoints, alphas: coreA)
            let coreMaskShading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: coreStops),
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
            )

            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))

                // Mask stage.
                layer.fill(coreMaskPath, with: coreMaskShading)

                // Colour stage.
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

            // Optional smooth crest lift inside the fill (still no noise).
            if configuration.crestLiftEnabled, configuration.crestLiftMaxOpacity > 0.000_01 {
                let liftThickness = max(onePixel, min(plotH * 0.10, 18.0))
                let liftBlur = max(onePixel, min(plotH * 0.06, 12.0))
                let liftAlpha = configuration.crestLiftMaxOpacity

                let liftBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: liftThickness, lineCap: .round, lineJoin: .round)
                )

                let liftStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: coreA.map { RainSurfaceMath.clamp01($0 * liftAlpha) },
                    colour: configuration.fillTopColor
                )

                let liftShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: liftStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .screen

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if liftBlur > 0 { layer.addFilter(.blur(radius: liftBlur)) }

                    layer.fill(liftBand, with: liftShading)

                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 2 — Broad bloom (mask-derived, clipped to a band above)
            // -------------------------
            if configuration.bloomEnabled,
               configuration.bloomMaxOpacity > 0.000_01,
               (bloomA.max() ?? 0.0) > 0.000_5
            {
                let ridgeR = max(onePixel, configuration.ridgeThicknessPoints)
                let ridgeBandForBloom = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: ridgeR * 2.0, lineCap: .round, lineJoin: .round)
                )

                let bloomBandHeight = max(onePixel, plotH * max(0.10, min(1.0, configuration.bloomBandHeightFractionOfPlotHeight)))
                let bloomClipBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: bloomBandHeight * 2.0, lineCap: .round, lineJoin: .round)
                )

                let bloomStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: bloomA,
                    colour: configuration.bloomColor
                )

                let bloomShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: bloomStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .screen

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

                    layer.drawLayer { inner in
                        inner.addFilter(.blur(radius: bloomBlur))
                        inner.fill(ridgeBandForBloom, with: bloomShading)
                    }

                    // Clamp bloom to a bounded region and outside-only (prevents ghost silhouettes).
                    layer.blendMode = .destinationIn
                    layer.fill(bloomClipBand, with: .color(.white))
                    layer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 3 — Above-surface mist (outside-only, drawn behind ridge)
            // -------------------------
            if configuration.mistEnabled,
               configuration.mistMaxOpacity > 0.000_01,
               (mistA.max() ?? 0.0) > 0.000_5
            {
                let mistHeightCap = max(onePixel, configuration.mistHeightPoints)
                let mistHeightFrac = max(0.10, min(1.0, configuration.mistHeightFractionOfPlotHeight))
                let mistHeight = min(mistHeightCap, plotH * mistHeightFrac)

                let mistBlur = max(onePixel, min(mistHeight * 0.33, plotH * 0.40))
                let mistBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: mistHeight * 2.0, lineCap: .round, lineJoin: .round)
                )

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

                    // Base mist body (smooth), then clipped.
                    layer.drawLayer { base in
                        base.addFilter(.blur(radius: mistBlur))

                        let crestStroke = topEdgePath.strokedPath(
                            StrokeStyle(
                                lineWidth: max(onePixel, configuration.ridgeThicknessPoints * 0.85),
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        base.fill(crestStroke, with: mistShading)
                    }

                    // Texture (2D isotropic; no streaks).
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

                    // Final clamp: band + outside-only (never inside core).
                    layer.blendMode = .destinationIn
                    layer.fill(mistBand, with: .color(.white))
                    layer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 4 — Surface shell fuzz (boundary-attached; texture only here)
            // -------------------------
            if configuration.shellEnabled,
               configuration.shellMaxOpacity > 0.000_01,
               (shellA.max() ?? 0.0) > 0.000_5
            {
                let insideT = max(onePixel, configuration.shellInsideThicknessPoints)
                let aboveT = max(onePixel, configuration.shellAboveThicknessPoints)

                let shellInsideBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: insideT * 2.0, lineCap: .round, lineJoin: .round)
                )
                let shellAboveBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: aboveT * 2.0, lineCap: .round, lineJoin: .round)
                )

                var shellMask = Path()
                shellMask.addPath(shellInsideBand)
                shellMask.addPath(shellAboveBand)

                let shellStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: shellA,
                    colour: configuration.shellColor
                )

                let shellShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: shellStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .screen

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

                    // Inside portion: small and smooth (no texture).
                    layer.drawLayer { inner in
                        if shellBlur > 0 { inner.addFilter(.blur(radius: shellBlur)) }
                        inner.fill(shellInsideBand, with: shellShading)

                        inner.blendMode = .destinationIn
                        inner.fill(coreMaskPath, with: .color(.white))
                    }

                    // Outside portion: texture lives here (outside-only).
                    layer.drawLayer { outer in
                        if shellBlur > 0 { outer.addFilter(.blur(radius: shellBlur)) }

                        // Draw first (screen), then clamp.
                        outer.fill(shellAboveBand, with: shellShading)

                        if configuration.shellNoiseAmount > 0.000_01,
                           configuration.shellPuffsPerSampleMax > 0
                        {
                            drawShellPuffs(
                                in: &outer,
                                plotRect: plotRect,
                                baselineY: baselineY,
                                stepX: stepX,
                                range: r,
                                heights: heights,
                                shellAlpha: shellAlpha,
                                colour: configuration.shellColor,
                                amount: RainSurfaceMath.clamp01(configuration.shellNoiseAmount),
                                maxPuffsPerSample: max(1, configuration.shellPuffsPerSampleMax),
                                shellAboveThickness: aboveT,
                                minR: max(onePixel * 0.60, configuration.shellPuffMinRadiusPoints),
                                maxR: max(onePixel * 0.80, configuration.shellPuffMaxRadiusPoints),
                                onePixel: onePixel
                            )
                        }

                        outer.blendMode = .destinationIn
                        outer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                    }

                    // Final clamp to the shell mask (prevents detached fragments).
                    layer.blendMode = .destinationIn
                    layer.fill(shellMask, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 5 — Ridge highlight (ridgeMask inside core; drawn last)
            // -------------------------
            if configuration.ridgeEnabled,
               configuration.ridgeMaxOpacity > 0.000_01,
               (ridgeA.max() ?? 0.0) > 0.000_5
            {
                let ridgeR = max(onePixel, configuration.ridgeThicknessPoints)
                let ridgeBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: ridgeR * 2.0, lineCap: .round, lineJoin: .round)
                )

                // Peak boost.
                let peak01 = RainSurfaceMath.clamp01(intensityNorm[last])
                let boostedRidgeA = ridgeA.map { a in
                    let boost = 1.0 + configuration.ridgePeakBoost * peak01
                    return RainSurfaceMath.clamp01(a * boost)
                }

                let ridgeStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: boostedRidgeA,
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
                    if ridgeBlur > 0 { layer.addFilter(.blur(radius: ridgeBlur)) }

                    layer.fill(ridgeBand, with: ridgeShading)

                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }
        }
    }

    // MARK: - Shell puffs (noise only in the shellAbove region)
    private static func drawShellPuffs(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        shellAlpha: [Double],
        colour: Color,
        amount: Double,
        maxPuffsPerSample: Int,
        shellAboveThickness: CGFloat,
        minR: CGFloat,
        maxR: CGFloat,
        onePixel: CGFloat
    ) {
        let n = heights.count
        let hSpan = max(onePixel, shellAboveThickness)

        for i in range {
            if i < 0 || i >= n { continue }

            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let a0 = RainSurfaceMath.clamp01(shellAlpha[i])
            if a0 <= 0.000_8 { continue }

            let desired = Double(maxPuffsPerSample) * (0.55 + 2.10 * a0)
            let puffCount = min(90, max(1, Int(desired + 0.5)))

            let topY = baselineY - h
            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            var prng = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0A11_CAFE, saltB: 0x0000_0000_00B0_0B1E))

            for _ in 0..<puffCount {
                let rx = prng.random01()
                let rr = prng.random01()
                let ry = prng.random01()

                let x = x0 + (x1 - x0) * rx
                let r = minR + (maxR - minR) * pow(rr, 0.70)

                // Centres sit slightly below the ridge; outside-only clipping reveals the top portion.
                let y = topY + r * 0.10 - hSpan * (0.35 * ry)

                let jitter = 0.35 + 0.65 * prng.random01()
                let a = RainSurfaceMath.clamp01(a0 * amount * 0.16 * jitter)

                var circle = Path()
                circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                context.fill(circle, with: .color(colour.opacity(a)))
            }
        }
    }

    // MARK: - Mist particles (outside-only, boundary-attached)
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

        let n = heights.count
        let heightSpan = max(onePixel, mistHeight)

        for i in range {
            if i < 0 || i >= n { continue }

            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let baseA = RainSurfaceMath.clamp01(mistAlpha[i])
            if baseA <= 0.000_8 { continue }

            let topY = baselineY - h
            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            var prng = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_00C7_A11C, saltB: 0x0000_0000_B16B_00B5))

            if puffsPerSampleMax > 0 {
                let desired = Double(puffsPerSampleMax) * (0.55 + 1.90 * baseA)
                let puffCount = min(220, max(1, Int(desired + 0.5)))

                for _ in 0..<puffCount {
                    let rx = prng.random01()
                    let rr = prng.random01()
                    let ru = prng.random01()

                    let x = x0 + (x1 - x0) * rx
                    let r = puffMinR + (puffMaxR - puffMinR) * pow(rr, 0.70)

                    // Strongly biased toward the boundary: most particles are very close to the ridge.
                    let near = ru * ru
                    let hAbove = heightSpan * (0.55 * near)

                    // Centre sits slightly below ridge; outside-only clip reveals the top portion.
                    let y = topY + r * 0.12 - hAbove

                    let t = RainSurfaceMath.clamp01(1.0 - Double(hAbove / heightSpan))
                    let fall = pow(t, falloffPower)

                    let grain = 0.70 + 0.30 * prng.random01()
                    let a = RainSurfaceMath.clamp01(baseA * fall * (0.10 + 0.14 * noiseInfluence) * grain)

                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                    context.fill(circle, with: .color(colour.opacity(a)))
                }
            }

            if finePerSampleMax > 0 {
                let desired = Double(finePerSampleMax) * (0.55 + 1.60 * baseA)
                let fineCount = min(240, max(1, Int(desired + 0.5)))

                var prng2 = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0091_F1EE, saltB: 0x0000_0000_0123_4567))

                for _ in 0..<fineCount {
                    let rx = prng2.random01()
                    let rr = prng2.random01()
                    let ru = prng2.random01()

                    let x = x0 + (x1 - x0) * rx
                    let r = fineMinR + (fineMaxR - fineMinR) * pow(rr, 0.85)

                    let near = ru * ru
                    let hAbove = heightSpan * (0.40 * near)

                    let y = topY + r * 0.10 - hAbove

                    let t = RainSurfaceMath.clamp01(1.0 - Double(hAbove / heightSpan))
                    let fall = pow(t, max(0.6, falloffPower * 0.85))

                    let grain = 0.65 + 0.35 * prng2.random01()
                    let a = RainSurfaceMath.clamp01(baseA * fall * (0.06 + 0.10 * noiseInfluence) * grain)

                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                    context.fill(circle, with: .color(colour.opacity(a)))
                }
            }
        }
    }

    // MARK: - Horizontal gradient stops (alpha-only mask)
    private static func makeHorizontalStops(
        plotRect: CGRect,
        width: CGFloat,
        xPoints: [CGFloat],
        alphas: [Double]
    ) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(xPoints.count)

        let denom = max(1.0, width)

        for i in 0..<min(xPoints.count, alphas.count) {
            let x = xPoints[i]
            let a = RainSurfaceMath.clamp01(alphas[i])
            let loc = RainSurfaceMath.clamp01(Double((x - plotRect.minX) / denom))
            stops.append(.init(color: Color.white.opacity(a), location: loc))
        }

        return stops
    }

    // MARK: - Horizontal colour stops (colour + alpha)
    private static func makeHorizontalColourStops(
        plotRect: CGRect,
        width: CGFloat,
        xPoints: [CGFloat],
        alphas: [Double],
        colour: Color
    ) -> [Gradient.Stop] {
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(xPoints.count)

        let denom = max(1.0, width)

        for i in 0..<min(xPoints.count, alphas.count) {
            let x = xPoints[i]
            let a = RainSurfaceMath.clamp01(alphas[i])
            let loc = RainSurfaceMath.clamp01(Double((x - plotRect.minX) / denom))
            stops.append(.init(color: colour.opacity(a), location: loc))
        }

        return stops
    }

    // MARK: - Seed mixing
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
