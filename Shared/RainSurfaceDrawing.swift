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
        context.blendMode = .plusLighter

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
    // 4) shell halo (smooth) + below-surface uncertainty grain
    // 5) ridge highlight (inside core)
    // 6) specular glint (peak highlight, inside core)
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
        let globalMaxHeight = heights.max() ?? 0.0

        // Effective blur radii derived from plot height (clamped to avoid broad halos on small charts).
        let ridgeBlur = min(
            max(onePixel, plotH * max(0.0, configuration.ridgeBlurFractionOfPlotHeight)),
            max(onePixel, 14.0)
        )
        let bloomBlur = min(
            max(onePixel, plotH * max(0.0, configuration.bloomBlurFractionOfPlotHeight)),
            max(onePixel, 28.0)
        )
        let shellBlur = min(
            max(onePixel, plotH * max(0.0, configuration.shellBlurFractionOfPlotHeight)),
            max(onePixel, 6.0)
        )

        // Per-sample alphas (end tapers are ALPHA ONLY).
        var coreAlpha = [Double](repeating: 0.0, count: n)
        var ridgeAlpha = [Double](repeating: 0.0, count: n)
        var bloomAlpha = [Double](repeating: 0.0, count: n)
        var shellAlpha = [Double](repeating: 0.0, count: n)
        var mistAlpha = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let v = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certainty[i])
            let proxy = RainSurfaceMath.clamp01(1.0 - c) // 0 => certain, 1 => uncertain
            let taper = RainSurfaceMath.clamp01(edgeFactors[i])

            let lowV = pow(v, 0.70)

            if configuration.ridgeEnabled, configuration.ridgeMaxOpacity > 0.000_01 {
                // Ridge reads mostly from intensity, with a modest certainty influence.
                let base = configuration.ridgeMaxOpacity * taper
                    * (0.28 + 0.72 * pow(v, 0.90))
                    * (0.78 + 0.22 * pow(c, 0.65))
                ridgeAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.bloomEnabled, configuration.bloomMaxOpacity > 0.000_01 {
                // Bloom is intentionally subtle; it is optional and can be disabled by callers.
                let base = configuration.bloomMaxOpacity * taper * (0.20 + 0.80 * pow(v, 0.80))
                let unc = (0.40 + 0.60 * proxy)
                bloomAlpha[i] = RainSurfaceMath.clamp01(base * unc)
            }

            if configuration.shellEnabled, configuration.shellMaxOpacity > 0.000_01 {
                // Shell fuzz is the primary uncertainty cue.
                // For high certainty, the surface (and under-fill) should stay perfectly smooth.
                let gate = RainSurfaceMath.smoothstep01((proxy - 0.12) / 0.38)
                let unc = pow(gate, 0.85)
                let base = configuration.shellMaxOpacity * taper
                    * unc
                    * (0.25 + 0.75 * lowV)

                shellAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.mistEnabled, configuration.mistMaxOpacity > 0.000_01 {
                // Mist is outside-only and fades upward; it is a secondary uncertainty cue.
                let unc = pow(proxy, 0.70)
                let base = configuration.mistMaxOpacity * taper * unc * (0.25 + 0.75 * lowV)
                mistAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            // Core alpha: stays bright even when certainty is lower; uncertainty is expressed in the shell/mist.
            let intensityFactor = (0.20 + 0.80 * pow(v, 0.70))
            let confidenceFloor = (0.82 + 0.18 * pow(c, 0.75))
            let uncertaintyDim = (1.0 - 0.28 * pow(proxy, 0.80))
            let core = intensityFactor * confidenceFloor * uncertaintyDim * taper
            coreAlpha[i] = RainSurfaceMath.clamp01(core)
        }

        // Core fill gradient: deep base -> saturated mid -> bright crest.
        let fillGradient = Gradient(stops: [
            .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
            .init(color: configuration.fillMidColor.opacity(configuration.fillMidOpacity), location: 0.55),
            .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0)
        ])

        let clipPadX = min(max(onePixel, configuration.shellAboveThicknessPoints * 1.10), 20.0)

        for seg in segments {
            let r = seg.range
            guard !r.isEmpty else { continue }

            let first = r.lowerBound
            let last = max(first, r.upperBound - 1)

            let startEdgeX = plotRect.minX + CGFloat(r.lowerBound) * stepX
            let endEdgeX = plotRect.minX + CGFloat(r.upperBound) * stepX

            let baseClipRect = CGRect(
                x: startEdgeX,
                y: plotRect.minY,
                width: max(0.0, endEdgeX - startEdgeX),
                height: max(0.0, baselineY - plotRect.minY)
            )
            if baseClipRect.width <= 0 || baseClipRect.height <= 0 { continue }

            // Allow effects to extend slightly past segment ends (avoids hard cutoffs at wet region boundaries).
            let clipRect = baseClipRect.insetBy(dx: -clipPadX, dy: 0).intersection(plotRect)
            if clipRect.width <= 0 || clipRect.height <= 0 { continue }

            let coreMaskPath = seg.surfacePath
            let topEdgePath = seg.topEdgePath

            // Outside-of-core region (used for bloom/mist/halo).
            var outside = Path()
            outside.addRect(clipRect)
            outside.addPath(coreMaskPath)

            // Segment peak (used for ridge boost + glint).
            var peakIndex = first
            var peakHeight: CGFloat = 0.0
            for i in r {
                let h = heights[i]
                if h > peakHeight {
                    peakHeight = h
                    peakIndex = i
                }
            }

            let peakV01 = RainSurfaceMath.clamp01(intensityNorm[peakIndex])
            let peakC01 = RainSurfaceMath.clamp01(certainty[peakIndex])
            let peakTaper = RainSurfaceMath.clamp01(edgeFactors[peakIndex])
            let peakHeightFractionOfGlobal = (globalMaxHeight > 0) ? Double(peakHeight / globalMaxHeight) : 0.0

            // Glint alpha envelope (computed here to reuse xPoints indexing).
            let glintSpan = max(1, configuration.glintSpanSamples)
            let glintPeakAlpha: Double = {
                guard configuration.glintEnabled,
                      configuration.glintMaxOpacity > 0.000_01,
                      peakHeightFractionOfGlobal >= configuration.glintMinPeakHeightFractionOfSegmentMax
                else { return 0.0 }

                let base = configuration.glintMaxOpacity * peakTaper
                    * (0.30 + 0.70 * pow(peakV01, 0.92))
                    * (0.75 + 0.25 * pow(peakC01, 0.85))
                return RainSurfaceMath.clamp01(base)
            }()

            func glintAlphaAtIndex(_ idx: Int) -> Double {
                guard glintPeakAlpha > 0.000_5 else { return 0.0 }
                let d = abs(idx - peakIndex)
                if d > glintSpan { return 0.0 }
                let t = 1.0 - Double(d) / Double(glintSpan + 1)
                let w = RainSurfaceMath.smoothstep01(t)
                return RainSurfaceMath.clamp01(glintPeakAlpha * w)
            }

            // Per-x stop arrays (same xPoints for every layer).
            var xPoints: [CGFloat] = []
            var coreA: [Double] = []
            var ridgeA: [Double] = []
            var bloomA: [Double] = []
            var shellA: [Double] = []
            var mistA: [Double] = []
            var glintA: [Double] = []

            xPoints.reserveCapacity(r.count + 2)
            coreA.reserveCapacity(r.count + 2)
            ridgeA.reserveCapacity(r.count + 2)
            bloomA.reserveCapacity(r.count + 2)
            shellA.reserveCapacity(r.count + 2)
            mistA.reserveCapacity(r.count + 2)
            glintA.reserveCapacity(r.count + 2)

            func appendEdgePoint(x: CGFloat, idx: Int) {
                xPoints.append(x)
                coreA.append(coreAlpha[idx])
                ridgeA.append(ridgeAlpha[idx])
                bloomA.append(bloomAlpha[idx])
                shellA.append(shellAlpha[idx])
                mistA.append(mistAlpha[idx])
                glintA.append(glintAlphaAtIndex(idx))
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
                context.blendMode = .plusLighter

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
                context.blendMode = .plusLighter

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
            // PASS 3 — Above-surface mist (outside-only)
            // -------------------------
            if configuration.mistEnabled,
               configuration.mistMaxOpacity > 0.000_01,
               (mistA.max() ?? 0.0) > 0.000_5
            {
                let mistHeightCap = max(onePixel, configuration.mistHeightPoints)
                let mistHeightFrac = max(0.10, min(1.0, configuration.mistHeightFractionOfPlotHeight))
                let mistHeight = min(mistHeightCap, plotH * mistHeightFrac)

                let mistBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: mistHeight * 2.0, lineCap: .round, lineJoin: .round)
                )

                let savedBlend = context.blendMode
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

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
            // PASS 4 — Shell halo (smooth) + below-surface uncertainty grain
            // -------------------------
            if configuration.shellEnabled,
               configuration.shellMaxOpacity > 0.000_01,
               (shellA.max() ?? 0.0) > 0.000_5
            {
                let insideT = max(onePixel, configuration.shellInsideThicknessPoints)
                let belowT = max(onePixel, configuration.shellAboveThicknessPoints)

                let shellInsideBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: insideT * 2.0, lineCap: .round, lineJoin: .round)
                )
                let shellBelowBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: belowT * 2.0, lineCap: .round, lineJoin: .round)
                )

                // Used only for the smooth halo clamp (NOT for below-fill grain).
                var shellHaloMask = Path()
                shellHaloMask.addPath(shellInsideBand)
                shellHaloMask.addPath(shellBelowBand)

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
                context.blendMode = .plusLighter

                // 4a) Smooth halo: keep it clean above the ridge (no fuzzy texture above the surface).
                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

                    // Inside lip (smooth)
                    layer.drawLayer { inner in
                        if shellBlur > 0 { inner.addFilter(.blur(radius: shellBlur)) }
                        inner.fill(shellInsideBand, with: shellShading)

                        inner.blendMode = .destinationIn
                        inner.fill(coreMaskPath, with: .color(.white))
                    }

                    // Outside halo (smooth, outside-only)
                    layer.drawLayer { outer in
                        if shellBlur > 0 { outer.addFilter(.blur(radius: shellBlur)) }

                        // Draw first (additive), then clamp.
                        outer.fill(shellBelowBand, with: shellShading)

                        outer.blendMode = .destinationIn
                        outer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                    }

                    // Final clamp for halo-only (prevents detached fragments).
                    layer.blendMode = .destinationIn
                    layer.fill(shellHaloMask, with: .color(.white))
                }

                // 4b) Below-surface grain: uncertainty speckle inside the fill, extending down to the baseline.
                //     Drawn separately so it is NOT clipped by the halo mask.
                if configuration.shellNoiseAmount > 0.000_01,
                   configuration.shellPuffsPerSampleMax > 0
                {
                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))

                        drawShellPuffs(
                            in: &layer,
                            plotRect: plotRect,
                            baselineY: baselineY,
                            stepX: stepX,
                            range: r,
                            heights: heights,
                            shellAlpha: shellAlpha,
                            colour: configuration.shellColor,
                            amount: RainSurfaceMath.clamp01(configuration.shellNoiseAmount),
                            maxPuffsPerSample: max(1, configuration.shellPuffsPerSampleMax),
                            shellAboveThickness: belowT,
                            minR: max(onePixel * 0.60, configuration.shellPuffMinRadiusPoints),
                            maxR: max(onePixel * 0.80, configuration.shellPuffMaxRadiusPoints),
                            onePixel: onePixel
                        )

                        layer.blendMode = .destinationIn
                        layer.fill(coreMaskPath, with: .color(.white))
                    }
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 5 — Ridge highlight (inside core)
            // -------------------------
            if configuration.ridgeEnabled,
               configuration.ridgeMaxOpacity > 0.000_01,
               (ridgeA.max() ?? 0.0) > 0.000_5
            {
                let ridgeR = max(onePixel, configuration.ridgeThicknessPoints)
                let ridgeBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: ridgeR * 2.0, lineCap: .round, lineJoin: .round)
                )

                // Peak boost uses the segment peak, not the segment tail.
                let boostedRidgeA = ridgeA.map { a in
                    let boost = 1.0 + configuration.ridgePeakBoost * peakV01
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
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if ridgeBlur > 0 { layer.addFilter(.blur(radius: ridgeBlur)) }

                    layer.fill(ridgeBand, with: ridgeShading)

                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 6 — Specular glint (peak highlight, inside core)
            // -------------------------
            if configuration.glintEnabled,
               configuration.glintMaxOpacity > 0.000_01,
               (glintA.max() ?? 0.0) > 0.000_5
            {
                let glintR = max(onePixel, configuration.glintThicknessPoints)
                let glintBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: glintR * 2.0, lineCap: .round, lineJoin: .round)
                )

                let glintStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: glintA,
                    colour: configuration.glintColor
                )

                let glintShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: glintStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if configuration.glintBlurRadiusPoints > 0 {
                        layer.addFilter(.blur(radius: max(onePixel, configuration.glintBlurRadiusPoints)))
                    }

                    layer.fill(glintBand, with: glintShading)

                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }
        }
    }

    // MARK: - Gradient stops helpers

    private static func makeHorizontalStops(
        plotRect: CGRect,
        width: CGFloat,
        xPoints: [CGFloat],
        alphas: [Double]
    ) -> [Gradient.Stop] {
        let n = min(xPoints.count, alphas.count)
        if n <= 1 {
            let a = RainSurfaceMath.clamp01(alphas.first ?? 0.0)
            return [
                .init(color: Color.white.opacity(a), location: 0.0),
                .init(color: Color.white.opacity(a), location: 1.0)
            ]
        }

        let w = max(1e-6, Double(width))
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(n)

        for i in 0..<n {
            let x = Double(xPoints[i])
            let t = RainSurfaceMath.clamp01((x - Double(plotRect.minX)) / w)
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: Color.white.opacity(a), location: t))
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
        let n = min(xPoints.count, alphas.count)
        if n <= 1 {
            let a = RainSurfaceMath.clamp01(alphas.first ?? 0.0)
            return [
                .init(color: colour.opacity(a), location: 0.0),
                .init(color: colour.opacity(a), location: 1.0)
            ]
        }

        let w = max(1e-6, Double(width))
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(n)

        for i in 0..<n {
            let x = Double(xPoints[i])
            let t = RainSurfaceMath.clamp01((x - Double(plotRect.minX)) / w)
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: colour.opacity(a), location: t))
        }
        return stops
    }

    // MARK: - Shell puffs (below-surface uncertainty grain)
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
        if n == 0 { return }

        // Widgets have tight render budgets. Cap complexity so heavy-rain locations don't get
        // terminated and replaced with the system placeholder.
        let isAppExtension = WidgetWeaverRuntime.isRunningInAppExtension
        let densityScale: Double = isAppExtension ? 0.55 : 1.0
        let sampleStride: Int = isAppExtension ? 2 : 1

        // Treat `shellAboveThickness` as a "below-surface" band thickness (legacy name).
        let band = max(onePixel, shellAboveThickness)

        var i = range.lowerBound
        while i < range.upperBound {
            if i < 0 || i >= n {
                i += sampleStride
                continue
            }

            let h = heights[i]
            if h <= onePixel * 0.25 {
                i += sampleStride
                continue
            }

            let a0 = RainSurfaceMath.clamp01(shellAlpha[i])
            if a0 <= 0.000_8 {
                i += sampleStride
                continue
            }

            let topY = baselineY - h
            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            let depthSpan = max(onePixel, baselineY - topY)

            // Larger puffs (near-surface, just under the ridge)
            let desired = Double(maxPuffsPerSample) * (0.80 + 2.80 * a0)
            let puffCap = isAppExtension ? 24 : 120
            let puffCount = min(puffCap, max(0, Int(desired * densityScale + 0.5)))

            var prng = RainSurfacePRNG(
                seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0A11_CAFE, saltB: 0x0000_0000_00B0_0B1E)
            )

            if puffCount > 0 {
                for _ in 0..<puffCount {
                    let rx = prng.random01()
                    let rr = prng.random01()
                    let ry = prng.random01()

                    // Mild horizontal jitter improves grain continuity along slopes.
                    let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.40
                    let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                    let r = minR + (maxR - minR) * pow(rr, 0.70)

                    // Strictly below the surface (no fuzz above).
                    let y = topY + r * 0.08 + band * (0.10 + 0.90 * ry)

                    let grain = 0.65 + 0.35 * prng.random01()
                    let a = RainSurfaceMath.clamp01(a0 * amount * 0.42 * grain)

                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                    context.fill(circle, with: .color(colour.opacity(a)))
                }
            }

            // Fine grain (near-surface, denser but smaller)
            let fineDesired = Double(maxPuffsPerSample) * (2.40 + 5.20 * a0)
            let fineCap = isAppExtension ? 40 : 220
            let fineCount = min(fineCap, max(0, Int(fineDesired * densityScale + 0.5)))

            let fineMinR = max(onePixel * 0.35, minR * 0.45)
            let fineMaxR = max(onePixel * 0.55, maxR * 0.55)

            if fineCount > 0 {
                for _ in 0..<fineCount {
                    let rx = prng.random01()
                    let rr = prng.random01()
                    let ry = prng.random01()

                    let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.55
                    let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                    let r = fineMinR + (fineMaxR - fineMinR) * pow(rr, 0.82)

                    // Tight to the ridge, still below the surface.
                    let y = topY + r * 0.05 + band * (0.06 + 0.94 * pow(ry, 1.9))

                    let grain = 0.55 + 0.45 * prng.random01()
                    let a = RainSurfaceMath.clamp01(a0 * amount * 0.26 * grain)

                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                    context.fill(circle, with: .color(colour.opacity(a)))
                }
            }

            // Deep grain (extends down to the baseline to express uncertainty)
            let deepDesired = Double(maxPuffsPerSample) * (0.90 + 8.50 * a0)
            let deepCap = isAppExtension ? 26 : 72
            let deepCount = min(deepCap, max(0, Int(deepDesired * densityScale + 0.5)))

            if deepCount > 0 {
                // Independent seed to avoid visible repetition patterns.
                var prngDeep = RainSurfacePRNG(
                    seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0D0F_0A5E, saltB: 0x0000_0000_0C0F_EC0F)
                )

                for _ in 0..<deepCount {
                    let rx = prngDeep.random01()
                    let rr = prngDeep.random01()
                    let ry = prngDeep.random01()

                    let xJitter = (prngDeep.random01() - 0.5) * Double(stepX) * 0.70
                    let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                    let r = fineMinR + (fineMaxR - fineMinR) * pow(rr, 0.92)

                    // Bias towards the baseline so fuzz "falls" downwards in uncertain regions.
                    let u = 1.0 - pow(ry, 2.0)
                    let y = topY + depthSpan * CGFloat(0.12 + 0.88 * u)

                    let depth01 = RainSurfaceMath.clamp01(Double((y - topY) / max(0.000_001, depthSpan)))
                    let depthBoost = 0.45 + 0.55 * depth01

                    let grain = 0.60 + 0.40 * prngDeep.random01()
                    let a = RainSurfaceMath.clamp01(a0 * amount * 0.16 * depthBoost * grain)

                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                    context.fill(circle, with: .color(colour.opacity(a)))
                }
            }

            i += sampleStride
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
            let a0 = RainSurfaceMath.clamp01(mistAlpha[i])
            if a0 <= 0.000_8 { continue }

            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let topY = baselineY - h

            // Falloff with height above ridge so particles stick near boundary.
            let falloff = pow(RainSurfaceMath.clamp01(Double(h / heightSpan)), falloffPower)
            let a = RainSurfaceMath.clamp01(a0 * falloff)

            if a <= 0.000_8 { continue }

            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            let puffCount = max(0, min(64, Int(Double(puffsPerSampleMax) * (0.70 + 2.60 * a))))
            let fineCount = max(0, min(96, Int(Double(finePerSampleMax) * (1.10 + 3.60 * a))))

            var prng = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0C0F_FEEE, saltB: 0x0000_0000_0B1F_F00D))

            // Large puffs
            for _ in 0..<puffCount {
                let rx = prng.random01()
                let rr = prng.random01()
                let ry = prng.random01()

                let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.65
                let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                let r = puffMinR + (puffMaxR - puffMinR) * pow(rr, 0.70)
                let y = topY - heightSpan * (0.05 + 0.95 * ry)

                let grain = 0.65 + 0.35 * prng.random01()
                let alpha = RainSurfaceMath.clamp01(a * (0.30 + 0.70 * noiseInfluence) * grain)

                var circle = Path()
                circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                context.fill(circle, with: .color(colour.opacity(alpha)))
            }

            // Fine grain
            for _ in 0..<fineCount {
                let rx = prng.random01()
                let rr = prng.random01()
                let ry = prng.random01()

                let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.80
                let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                let r = fineMinR + (fineMaxR - fineMinR) * pow(rr, 0.85)
                let y = topY - heightSpan * (0.05 + 0.95 * ry)

                let grain = 0.55 + 0.45 * prng.random01()
                let alpha = RainSurfaceMath.clamp01(a * (0.16 + 0.84 * noiseInfluence) * grain)

                var circle = Path()
                circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                context.fill(circle, with: .color(colour.opacity(alpha)))
            }
        }
    }

    // MARK: - Deterministic seeding
    private static func makeSeed(sampleIndex: Int, saltA: UInt64, saltB: UInt64) -> UInt64 {
        var x = UInt64(bitPattern: Int64(sampleIndex &* 0x9E37_79B9))
        x ^= saltA
        x &*= 0xBF58_476D_1CE4_E5B9
        x ^= (x >> 27)
        x ^= saltB
        x &*= 0x94D0_49BB_1331_11EB
        x ^= (x >> 31)
        return x
    }
}
