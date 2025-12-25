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

        var coreAlpha = [Double](repeating: 0.0, count: n)
        var ridgeAlpha = [Double](repeating: 0.0, count: n)
        var bloomAlpha = [Double](repeating: 0.0, count: n)
        var shellAlpha = [Double](repeating: 0.0, count: n)
        var mistAlpha = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let v = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certainty[i])
            let proxy = 1.0 - c
            let lowV = pow(1.0 - v, 1.15)
            let taper = RainSurfaceMath.clamp01(edgeFactors[i])

            // Uncertainty gate: ensures high-certainty regions are perfectly smooth (no fuzz at all).
            // proxy = 0.0 when certainty is 1.0. We start fuzz only once proxy rises past ~0.22.
            let uT = RainSurfaceMath.clamp01((proxy - 0.22) / 0.28)
            let uGate = RainSurfaceMath.smoothstep01(uT)
            let uncShell = pow(uGate, 1.70)
            let uncMist = pow(uGate, 1.35)

            if configuration.ridgeEnabled, configuration.ridgeMaxOpacity > 0.000_01 {
                let base = configuration.ridgeMaxOpacity * taper
                    * (0.28 + 0.72 * pow(v, 0.90))
                    * (0.78 + 0.22 * pow(c, 0.65))

                ridgeAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.bloomEnabled, configuration.bloomMaxOpacity > 0.000_01 {
                let base = configuration.bloomMaxOpacity * taper
                    * (0.20 + 0.80 * pow(v, 0.80))

                // Bloom can respond to uncertainty but remains subtle.
                let unc = (0.45 + 0.55 * pow(proxy, 0.85))
                bloomAlpha[i] = RainSurfaceMath.clamp01(base * unc)
            }

            if configuration.shellEnabled, configuration.shellMaxOpacity > 0.000_01 {
                // Shell fuzz expresses uncertainty, and is forced to 0 for high certainty.
                let base = configuration.shellMaxOpacity * taper
                    * uncShell
                    * (0.20 + 0.80 * lowV)

                shellAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.mistEnabled, configuration.mistMaxOpacity > 0.000_01 {
                let base = configuration.mistMaxOpacity * taper
                    * uncMist
                    * (0.25 + 0.75 * lowV)

                mistAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            // Core alpha stays smooth; uncertainty is signalled via shell/mist, not by roughening the fill.
            let intensityFactor = (0.20 + 0.80 * pow(v, 0.70))
            let confidenceFloor = (0.82 + 0.18 * pow(c, 0.75))
            let uncertaintyDim = (1.0 - 0.28 * pow(proxy, 0.80))
            let core = intensityFactor * confidenceFloor * uncertaintyDim * taper
            coreAlpha[i] = RainSurfaceMath.clamp01(core)
        }

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

            let clipRect = baseClipRect.insetBy(dx: -clipPadX, dy: 0).intersection(plotRect)
            if clipRect.width <= 0 || clipRect.height <= 0 { continue }

            let coreMaskPath = seg.surfacePath
            let topEdgePath = seg.topEdgePath

            var outside = Path()
            outside.addRect(clipRect)
            outside.addPath(coreMaskPath)

            // Segment peak
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

            // Per-x stop arrays
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

            // Crest lift (still smooth)
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
            // PASS 2 — Broad bloom (optional)
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

                    layer.blendMode = .destinationIn
                    layer.fill(bloomClipBand, with: .color(.white))
                    layer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 3 — Above-surface mist (optional, outside-only)
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

                    layer.blendMode = .destinationIn
                    layer.fill(mistBand, with: .color(.white))
                    layer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 4 — Surface shell fuzz (inside/below + strong downfill to baseline)
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

                let noise = RainSurfaceMath.clamp01(configuration.shellNoiseAmount)
                let baseFillMul = RainSurfaceMath.clamp(1.0 - noise * 1.55, min: 0.06, max: 1.0)

                let shellBelowStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: shellA.map { RainSurfaceMath.clamp01($0 * baseFillMul) },
                    colour: configuration.shellColor
                )

                let shellBelowShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: shellBelowStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

                    // Inside lip: smooth and subtle (no texture).
                    layer.drawLayer { inner in
                        if shellBlur > 0 { inner.addFilter(.blur(radius: shellBlur)) }
                        inner.fill(shellInsideBand, with: shellShading)

                        inner.blendMode = .destinationIn
                        inner.fill(coreMaskPath, with: .color(.white))
                    }

                    // Boundary fuzz just under the ridge (inside-only).
                    layer.drawLayer { boundary in
                        boundary.drawLayer { base in
                            if shellBlur > 0 { base.addFilter(.blur(radius: shellBlur)) }
                            base.fill(shellBelowBand, with: shellBelowShading)

                            base.blendMode = .destinationIn
                            base.fill(coreMaskPath, with: .color(.white))
                            base.fill(shellBelowBand, with: .color(.white))
                        }

                        if noise > 0.000_01,
                           configuration.shellPuffsPerSampleMax > 0
                        {
                            drawShellPuffs(
                                in: &boundary,
                                plotRect: plotRect,
                                baselineY: baselineY,
                                stepX: stepX,
                                range: r,
                                heights: heights,
                                shellAlpha: shellAlpha,
                                colour: configuration.shellColor,
                                amount: noise,
                                maxPuffsPerSample: max(1, configuration.shellPuffsPerSampleMax),
                                shellBelowThickness: belowT,
                                minR: max(onePixel * 0.60, configuration.shellPuffMinRadiusPoints),
                                maxR: max(onePixel * 0.80, configuration.shellPuffMaxRadiusPoints),
                                onePixel: onePixel
                            )
                        }

                        boundary.blendMode = .destinationIn
                        boundary.fill(coreMaskPath, with: .color(.white))
                        boundary.fill(shellBelowBand, with: .color(.white))
                    }

                    // Strong downfill grain: only where uncertainty is high, and it reaches the baseline.
                    if noise > 0.000_01,
                       configuration.shellPuffsPerSampleMax > 0
                    {
                        layer.drawLayer { deep in
                            drawDownfillGrain(
                                in: &deep,
                                plotRect: plotRect,
                                baselineY: baselineY,
                                stepX: stepX,
                                range: r,
                                heights: heights,
                                intensityNorm: intensityNorm,
                                certainty: certainty,
                                edgeFactors: edgeFactors,
                                shellAlpha: shellAlpha,
                                colour: configuration.shellColor,
                                amount: noise,
                                maxFinePerSample: max(1, configuration.shellPuffsPerSampleMax),
                                onePixel: onePixel
                            )

                            deep.blendMode = .destinationIn
                            deep.fill(coreMaskPath, with: .color(.white))
                        }
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
            // PASS 6 — Specular glint (inside core)
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

                if configuration.glintHaloOpacityMultiplier > 0.000_01 {
                    let haloR = max(onePixel, glintR * 3.5)
                    let haloBlur = max(onePixel, configuration.glintBlurRadiusPoints * 3.2)

                    let haloBand = topEdgePath.strokedPath(
                        StrokeStyle(lineWidth: haloR * 2.0, lineCap: .round, lineJoin: .round)
                    )

                    let haloStops = makeHorizontalColourStops(
                        plotRect: plotRect,
                        width: width,
                        xPoints: xPoints,
                        alphas: glintA.map { RainSurfaceMath.clamp01($0 * configuration.glintHaloOpacityMultiplier) },
                        colour: configuration.glintColor
                    )

                    let haloShading = GraphicsContext.Shading.linearGradient(
                        Gradient(stops: haloStops),
                        startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                        endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                    )

                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))
                        if haloBlur > 0 { layer.addFilter(.blur(radius: haloBlur)) }
                        layer.fill(haloBand, with: haloShading)

                        layer.blendMode = .destinationIn
                        layer.fill(coreMaskPath, with: .color(.white))
                    }
                }

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if configuration.glintBlurRadiusPoints > 0 { layer.addFilter(.blur(radius: configuration.glintBlurRadiusPoints)) }

                    layer.fill(glintBand, with: glintShading)

                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }
        }
    }

    // MARK: - Shell puffs (noise in the below band)
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
        shellBelowThickness: CGFloat,
        minR: CGFloat,
        maxR: CGFloat,
        onePixel: CGFloat
    ) {
        let n = heights.count
        let hSpan = max(onePixel, shellBelowThickness)

        for i in range {
            if i < 0 || i >= n { continue }

            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let a0 = RainSurfaceMath.clamp01(shellAlpha[i])
            if a0 <= 0.000_8 { continue }

            let desired = Double(maxPuffsPerSample) * (0.80 + 2.80 * a0)
            let puffCount = min(120, max(1, Int(desired + 0.5)))

            let topY = baselineY - h
            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            var prng = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0A11_CAFE, saltB: 0x0000_0000_00B0_0B1E))

            for _ in 0..<puffCount {
                let rx = prng.random01()
                let rr = prng.random01()
                let ry = prng.random01()

                let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.40
                let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                let r = minR + (maxR - minR) * pow(rr, 0.70)
                let y = topY + r * 0.12 + hSpan * (0.08 + 0.92 * ry)

                let grain = 0.65 + 0.35 * prng.random01()
                let a = RainSurfaceMath.clamp01(a0 * amount * 0.42 * grain)

                var circle = Path()
                circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                context.fill(circle, with: .color(colour.opacity(a)))
            }

            let fineDesired = Double(maxPuffsPerSample) * (2.40 + 5.20 * a0)
            let fineCount = min(220, max(1, Int(fineDesired + 0.5)))

            var prng2 = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0F1E_EEED, saltB: 0x0000_0000_0BEE_F00D))

            let fineMinR = max(onePixel * 0.35, minR * 0.45)
            let fineMaxR = max(onePixel * 0.55, maxR * 0.55)

            for _ in 0..<fineCount {
                let rx = prng2.random01()
                let rr = prng2.random01()
                let ry = prng2.random01()

                let xJitter = (prng2.random01() - 0.5) * Double(stepX) * 0.55
                let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                let r = fineMinR + (fineMaxR - fineMinR) * pow(rr, 0.85)
                let y = topY + r * 0.10 + hSpan * (0.08 + 0.92 * ry)

                let grain = 0.55 + 0.45 * prng2.random01()
                let a = RainSurfaceMath.clamp01(a0 * amount * 0.22 * grain)

                var circle = Path()
                circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                context.fill(circle, with: .color(colour.opacity(a)))
            }
        }
    }

    // MARK: - Downfill grain (inside-only; uncertainty-only; reaches baseline)
    private static func drawDownfillGrain(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        intensityNorm: [Double],
        certainty: [Double],
        edgeFactors: [Double],
        shellAlpha: [Double],
        colour: Color,
        amount: Double,
        maxFinePerSample: Int,
        onePixel: CGFloat
    ) {
        let n = min(heights.count, min(intensityNorm.count, min(certainty.count, min(edgeFactors.count, shellAlpha.count))))
        guard n > 0 else { return }

        let amt = RainSurfaceMath.clamp01(amount)
        if amt <= 0.000_01 { return }

        // Stable dot radii for “fuzz”, not “sparkle”
        let minR = max(onePixel * 0.30, 0.32)
        let maxR = max(onePixel * 0.80, 1.20)

        for i in range {
            if i < 0 || i >= n { continue }

            let h = heights[i]
            if h <= onePixel * 0.75 { continue }

            let c = RainSurfaceMath.clamp01(certainty[i])
            let proxy = RainSurfaceMath.clamp01(1.0 - c)

            // Hard-ish uncertainty gating: absolutely no downfill fuzz under “smooth/likely” regions.
            let gateT = RainSurfaceMath.clamp01((proxy - 0.24) / 0.26)
            let gate = RainSurfaceMath.smoothstep01(gateT)
            if gate <= 0.000_8 { continue }

            let v = RainSurfaceMath.clamp01(intensityNorm[i])
            let lowV = pow(1.0 - v, 1.05)

            let taper = RainSurfaceMath.clamp01(edgeFactors[i])
            let edgeDepth = pow(1.0 - taper, 0.75)

            let a0 = RainSurfaceMath.clamp01(shellAlpha[i])
            if a0 <= 0.000_8 { continue }

            // Strength is primarily uncertainty-driven; edgeDepth adds extra weight near segment tails but never suppresses mid-segment uncertainty.
            let u = pow(gate, 1.05)
            var strength = u * (0.28 + 0.72 * lowV) * (0.80 + 0.20 * edgeDepth)
            strength = RainSurfaceMath.clamp01(strength)

            if strength <= 0.02 { continue }

            // Denser + deeper than before so it clearly reaches the baseline.
            let desiredFine = Double(maxFinePerSample) * (10.0 + 90.0 * strength)
            let fineCount = min(520, max(0, Int(desiredFine + 0.5)))
            if fineCount == 0 { continue }

            let topY = baselineY - h
            let depthSpan = max(onePixel, baselineY - topY)

            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            var prng = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0D0F_1A11, saltB: 0x0000_0000_5EED_F00D))

            // Deep bias: in high uncertainty this pushes most grain toward the baseline.
            let deepProb = RainSurfaceMath.clamp01(0.55 + 0.45 * u)

            // A few larger “smudges” help it read as fuzz (still inside-only after clipping).
            let smudgeCount = min(8, max(0, Int(Double(maxFinePerSample) * (0.8 + 3.2 * strength))))
            if smudgeCount > 0 {
                for _ in 0..<smudgeCount {
                    let rx = prng.random01()
                    let rr = prng.random01()
                    let rDepth = prng.random01()

                    let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.90
                    let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                    let r = maxR * 2.2 + (maxR * 4.6 - maxR * 2.2) * pow(rr, 0.65)

                    // Bias smudges toward the lower half.
                    let f = 1.0 - pow(rDepth, 0.55)
                    let y = topY + depthSpan * CGFloat(f)

                    let fall = 0.80
                    let depthBoost = 0.90 + 0.35 * f
                    let grain = 0.60 + 0.40 * prng.random01()
                    let a = RainSurfaceMath.clamp01(a0 * amt * strength * fall * 0.06 * depthBoost * grain)

                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                    context.fill(circle, with: .color(colour.opacity(a)))
                }
            }

            // Fine grain all the way down to baseline.
            for _ in 0..<fineCount {
                let rx = prng.random01()
                let rr = prng.random01()
                let ru = prng.random01()
                let rDepth = prng.random01()

                let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.95
                let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                let r = minR + (maxR - minR) * pow(rr, 0.88)

                // Depth fraction 0..1 (0 = ridge, 1 = baseline)
                let f: Double
                if ru < deepProb {
                    // Strong baseline bias
                    f = 1.0 - pow(rDepth, 0.28)
                } else {
                    // Some grain remains nearer the ridge
                    f = pow(rDepth, 2.25)
                }

                let y = topY + depthSpan * CGFloat(f)

                // Keep visibility at the baseline (no “fade out before bottom”).
                let fall = 0.70 + 0.30 * pow(1.0 - f, 0.45)

                // Slightly stronger near baseline to satisfy “all the way down”.
                let depthBoost = 0.88 + 0.55 * f

                let grain = 0.55 + 0.45 * prng.random01()
                let a = RainSurfaceMath.clamp01(a0 * amt * strength * fall * 0.34 * depthBoost * grain)

                var circle = Path()
                circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                context.fill(circle, with: .color(colour.opacity(a)))
            }
        }
    }

    // MARK: - Mist particles (outside-only)
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

                    let near = ru * ru
                    let hAbove = heightSpan * (0.55 * near)
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
