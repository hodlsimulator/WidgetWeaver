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
            let proxy = RainSurfaceMath.clamp01(1.0 - c)
            let taper = RainSurfaceMath.clamp01(edgeFactors[i])

            let lowV = pow(v, 0.70)

            if configuration.ridgeEnabled, configuration.ridgeMaxOpacity > 0.000_01 {
                let base = configuration.ridgeMaxOpacity * taper
                    * (0.28 + 0.72 * pow(v, 0.90))
                    * (0.78 + 0.22 * pow(c, 0.65))
                ridgeAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.bloomEnabled, configuration.bloomMaxOpacity > 0.000_01 {
                let base = configuration.bloomMaxOpacity * taper * (0.20 + 0.80 * pow(v, 0.80))
                let unc = (0.40 + 0.60 * proxy)
                bloomAlpha[i] = RainSurfaceMath.clamp01(base * unc)
            }

            if configuration.shellEnabled, configuration.shellMaxOpacity > 0.000_01 {
                let gate = RainSurfaceMath.smoothstep01((proxy - 0.18) / 0.32)
                let unc = pow(gate, 1.15)
                let base = configuration.shellMaxOpacity * taper
                    * unc
                    * (0.25 + 0.75 * lowV)

                shellAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.mistEnabled, configuration.mistMaxOpacity > 0.000_01 {
                let unc = pow(proxy, 0.70)
                let base = configuration.mistMaxOpacity * taper * unc * (0.25 + 0.75 * lowV)
                mistAlpha[i] = RainSurfaceMath.clamp01(base)
            }

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
        let clipPadY = min(max(onePixel, configuration.mistHeightPoints * 0.55), 24.0)
        let clipRect = plotRect.insetBy(dx: -clipPadX, dy: -clipPadY)

        var xPoints = [CGFloat]()
        xPoints.reserveCapacity(n)
        for i in 0..<n {
            xPoints.append(plotRect.minX + (CGFloat(i) + 0.5) * stepX)
        }

        for seg in segments {
            let r = seg.range
            if r.isEmpty { continue }

            let surfacePath = seg.surfacePath
            let topEdgePath = seg.topEdgePath
            let coreMaskPath = surfacePath

            var outside = Path()
            outside.addRect(clipRect)
            outside.addPath(coreMaskPath)

            var ridgeA: [Double] = []
            var bloomA: [Double] = []
            var shellA: [Double] = []
            var mistA: [Double] = []

            ridgeA.reserveCapacity(r.count)
            bloomA.reserveCapacity(r.count)
            shellA.reserveCapacity(r.count)
            mistA.reserveCapacity(r.count)

            var peakHeight: CGFloat = 0.0
            var peakIndex: Int = r.lowerBound

            for i in r {
                ridgeA.append(ridgeAlpha[i])
                bloomA.append(bloomAlpha[i])
                shellA.append(shellAlpha[i])
                mistA.append(mistAlpha[i])

                let h = heights[i]
                if h > peakHeight {
                    peakHeight = h
                    peakIndex = i
                }
            }

            let segMaxHeight = max(onePixel, peakHeight)
            let peakV01 = RainSurfaceMath.clamp01(Double(segMaxHeight / max(onePixel, globalMaxHeight)))

            // PASS 1 — Core fill (smooth)
            let coreStops = makeHorizontalStops(
                plotRect: plotRect,
                width: width,
                xPoints: xPoints,
                alphas: coreAlpha
            )

            let coreAlphaShading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: coreStops),
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
            )

            let fillShading = GraphicsContext.Shading.linearGradient(
                fillGradient,
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.minX, y: plotRect.minY)
            )

            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))
                layer.fill(surfacePath, with: fillShading)

                layer.blendMode = .destinationIn
                layer.fill(surfacePath, with: coreAlphaShading)

                layer.blendMode = .destinationIn
                layer.fill(coreMaskPath, with: .color(.white))
            }

            // Crest lift
            if configuration.crestLiftEnabled, configuration.crestLiftMaxOpacity > 0.000_01 {
                let crestOpacity = configuration.crestLiftMaxOpacity * (0.55 + 0.45 * peakV01)
                if crestOpacity > 0.000_8 {
                    let crestStops = makeHorizontalColourStops(
                        plotRect: plotRect,
                        width: width,
                        xPoints: xPoints,
                        alphas: coreAlpha.map { RainSurfaceMath.clamp01($0 * 0.55) },
                        colour: configuration.fillTopColor.opacity(crestOpacity)
                    )

                    let crestShading = GraphicsContext.Shading.linearGradient(
                        Gradient(stops: crestStops),
                        startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                        endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                    )

                    let crestBand = topEdgePath.strokedPath(
                        StrokeStyle(lineWidth: max(onePixel, 3.0) * 2.0, lineCap: .round, lineJoin: .round)
                    )

                    let savedBlend = context.blendMode
                    context.blendMode = .plusLighter

                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))
                        layer.addFilter(.blur(radius: max(onePixel, 2.0)))
                        layer.fill(crestBand, with: crestShading)

                        layer.blendMode = .destinationIn
                        layer.fill(coreMaskPath, with: .color(.white))
                    }

                    context.blendMode = savedBlend
                }
            }

            // PASS 2 — Bloom (inside-only, band-clamped)
            if configuration.bloomEnabled,
               configuration.bloomMaxOpacity > 0.000_01,
               (bloomA.max() ?? 0.0) > 0.000_5
            {
                let bandH = max(onePixel, plotH * max(0.0, configuration.bloomBandHeightFractionOfPlotHeight))
                let y0 = max(plotRect.minY, baselineY - segMaxHeight - bandH * 0.40)
                let y1 = min(plotRect.maxY, baselineY - segMaxHeight + bandH * 0.60)
                let bloomBandRect = CGRect(x: clipRect.minX, y: y0, width: clipRect.width, height: max(onePixel, y1 - y0))

                var bloomBand = Path()
                bloomBand.addRect(bloomBandRect)

                let bloomStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: bloomAlpha,
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
                    if bloomBlur > 0 { layer.addFilter(.blur(radius: bloomBlur)) }

                    layer.fill(surfacePath, with: bloomShading)

                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))

                    layer.blendMode = .destinationIn
                    layer.fill(bloomBand, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // PASS 3 — Mist (outside-only)
            if configuration.mistEnabled,
               configuration.mistMaxOpacity > 0.000_01,
               (mistA.max() ?? 0.0) > 0.000_5
            {
                let mistHeightPoints = max(configuration.mistHeightPoints, plotH * configuration.mistHeightFractionOfPlotHeight)
                let mistHeight = min(mistHeightPoints, plotH * 0.95)

                let bandTop = max(plotRect.minY, baselineY - segMaxHeight - mistHeight)
                let bandHeight = max(onePixel, baselineY - segMaxHeight - bandTop)

                var mistBand = Path()
                mistBand.addRect(CGRect(x: clipRect.minX, y: bandTop, width: clipRect.width, height: bandHeight))

                let mistStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: mistAlpha,
                    colour: configuration.mistColor
                )

                let mistShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: mistStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    layer.addFilter(.blur(radius: max(onePixel, 3.0)))

                    layer.fill(mistBand, with: mistShading)

                    if configuration.mistNoiseEnabled,
                       configuration.mistNoiseInfluence > 0.000_01,
                       (configuration.mistPuffsPerSampleMax > 0 || configuration.mistFineGrainPerSampleMax > 0)
                    {
                        drawMistParticles(
                            in: &layer,
                            plotRect: plotRect,
                            baselineY: baselineY,
                            stepX: stepX,
                            range: r,
                            heights: heights,
                            mistHeight: mistHeight,
                            mistAlpha: mistAlpha,
                            falloffPower: configuration.mistFalloffPower,
                            colour: configuration.mistColor,
                            noiseInfluence: RainSurfaceMath.clamp01(configuration.mistNoiseInfluence),
                            puffsPerSampleMax: max(0, configuration.mistPuffsPerSampleMax),
                            finePerSampleMax: max(0, configuration.mistFineGrainPerSampleMax),
                            puffMinR: max(onePixel, configuration.mistParticleMinRadiusPoints),
                            puffMaxR: max(onePixel * 1.2, configuration.mistParticleMaxRadiusPoints),
                            fineMinR: max(onePixel * 0.70, configuration.mistFineParticleMinRadiusPoints),
                            fineMaxR: max(onePixel, configuration.mistFineParticleMaxRadiusPoints),
                            onePixel: onePixel
                        )
                    }

                    layer.blendMode = .destinationIn
                    layer.fill(mistBand, with: .color(.white))
                    layer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                }

                context.blendMode = savedBlend
            }

            // PASS 4 — Shell halo (smooth) + below-surface uncertainty grain
            if configuration.shellEnabled,
               configuration.shellMaxOpacity > 0.000_01,
               (shellA.max() ?? 0.0) > 0.000_5
            {
                let insideT = max(onePixel, configuration.shellInsideThicknessPoints)
                let belowT = max(onePixel, configuration.shellAboveThicknessPoints)
                let outsideHaloT = max(onePixel, min(belowT * 0.28, 3.2))

                let shellInsideBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: insideT * 2.0, lineCap: .round, lineJoin: .round)
                )

                let shellOutsideHaloBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: outsideHaloT * 2.0, lineCap: .round, lineJoin: .round)
                )

                let shellUnderBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: belowT * 2.0, lineCap: .round, lineJoin: .round)
                )

                var shellHaloMask = Path()
                shellHaloMask.addPath(shellInsideBand)
                shellHaloMask.addPath(shellOutsideHaloBand)
                shellHaloMask.addPath(shellUnderBand)

                let shellStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: shellAlpha,
                    colour: configuration.shellColor
                )

                let haloStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: shellAlpha.map { RainSurfaceMath.clamp01($0 * 0.55) },
                    colour: configuration.shellColor
                )

                let shellShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: shellStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let haloShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: haloStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

                    layer.drawLayer { inner in
                        if shellBlur > 0 { inner.addFilter(.blur(radius: shellBlur)) }
                        inner.fill(shellInsideBand, with: shellShading)

                        inner.blendMode = .destinationIn
                        inner.fill(coreMaskPath, with: .color(.white))
                    }

                    layer.drawLayer { under in
                        if shellBlur > 0 { under.addFilter(.blur(radius: shellBlur)) }
                        under.fill(shellUnderBand, with: shellShading)

                        under.blendMode = .destinationIn
                        under.fill(coreMaskPath, with: .color(.white))
                    }

                    layer.drawLayer { outer in
                        if shellBlur > 0 { outer.addFilter(.blur(radius: shellBlur)) }
                        outer.fill(shellOutsideHaloBand, with: haloShading)

                        outer.blendMode = .destinationIn
                        outer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                    }

                    layer.blendMode = .destinationIn
                    layer.fill(shellHaloMask, with: .color(.white))
                }

                if configuration.shellNoiseAmount > 0.000_01,
                   configuration.shellPuffsPerSampleMax > 0
                {
                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))

                        let isAppExtension = WidgetWeaverRuntime.isRunningInAppExtension
                        layer.blendMode = .screen

                        let grainBlur = max(onePixel, min(2.8, shellBlur * (isAppExtension ? 0.75 : 0.90)))
                        if grainBlur > onePixel * 0.90 {
                            layer.addFilter(.blur(radius: grainBlur))
                        }

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

            // PASS 5 — Ridge highlight (inside core)
            if configuration.ridgeEnabled,
               configuration.ridgeMaxOpacity > 0.000_01,
               (ridgeA.max() ?? 0.0) > 0.000_5
            {
                let ridgeR = max(onePixel, configuration.ridgeThicknessPoints)
                let ridgeBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: ridgeR * 2.0, lineCap: .round, lineJoin: .round)
                )

                let boostedRidgeAlpha = ridgeAlpha.map { a in
                    let boost = 1.0 + configuration.ridgePeakBoost * peakV01
                    return RainSurfaceMath.clamp01(a * boost)
                }

                let ridgeStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: boostedRidgeAlpha,
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

            // PASS 6 — Specular glint (peak highlight, inside core)
            if configuration.glintEnabled,
               configuration.glintMaxOpacity > 0.000_01
            {
                let minPeak = configuration.glintMinPeakHeightFractionOfSegmentMax
                if peakV01 >= minPeak {
                    let span = max(1, configuration.glintSpanSamples)
                    let start = max(r.lowerBound, peakIndex - span)
                    let end = min(r.upperBound - 1, peakIndex + span)

                    if start <= end {
                        var glintAlphaLocal = [Double](repeating: 0.0, count: n)
                        for i in start...end {
                            let dx = abs(i - peakIndex)
                            let t = 1.0 - Double(dx) / Double(max(1, span))
                            let w = RainSurfaceMath.smoothstep01(t)
                            let a = configuration.glintMaxOpacity * w * RainSurfaceMath.clamp01(edgeFactors[i])
                            glintAlphaLocal[i] = RainSurfaceMath.clamp01(a)
                        }

                        let glintStops = makeHorizontalColourStops(
                            plotRect: plotRect,
                            width: width,
                            xPoints: xPoints,
                            alphas: glintAlphaLocal,
                            colour: configuration.glintColor
                        )

                        let glintShading = GraphicsContext.Shading.linearGradient(
                            Gradient(stops: glintStops),
                            startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                            endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                        )

                        let glintR = max(onePixel, configuration.glintThicknessPoints)
                        let glintBand = topEdgePath.strokedPath(
                            StrokeStyle(lineWidth: glintR * 2.0, lineCap: .round, lineJoin: .round)
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
        guard n > 0 else { return }

        let isAppExtension = WidgetWeaverRuntime.isRunningInAppExtension
        let densityScale: Double = isAppExtension ? 0.55 : 1.0
        let sampleStride: Int = isAppExtension ? 2 : 1

        let band = max(onePixel, shellAboveThickness)
        let nearBand = min(band, max(onePixel, 9.0))
        let microBand = min(nearBand * 0.65, max(onePixel, 6.0))

        let baseMinR = max(onePixel * 0.30, minR * (isAppExtension ? 0.40 : 0.55))
        let baseMaxR = max(baseMinR + onePixel * 0.20, maxR * (isAppExtension ? 0.30 : 0.42))

        let microMinR = max(onePixel * 0.22, baseMinR * 0.55)
        let microMaxR = max(microMinR + onePixel * 0.12, baseMaxR * 0.65)

        let deepMinR = microMinR
        let deepMaxR = microMaxR

        let alphaCutoff = isAppExtension ? 0.018 : 0.010

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
            if a0 < alphaCutoff {
                i += sampleStride
                continue
            }

            let topY = baselineY - h
            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            let depthSpan = max(onePixel, baselineY - topY)

            var prng = RainSurfacePRNG(
                seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0A11_CAFE, saltB: 0x0000_0000_00B0_0B1E)
            )

            // Edge grain
            do {
                let desired = Double(maxPuffsPerSample) * (1.20 + 6.50 * a0)
                let cap = isAppExtension ? 26 : 140
                let count = min(cap, max(0, Int(desired * densityScale + 0.5)))

                if count > 0 {
                    for _ in 0..<count {
                        let rx = prng.random01()
                        let rr = prng.random01()
                        let ry = prng.random01()

                        let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.60
                        let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                        let r = baseMinR + (baseMaxR - baseMinR) * pow(rr, 0.78)

                        let yT = pow(ry, 2.20)
                        let y = topY + r * 0.10 + nearBand * CGFloat(yT)

                        let depth01 = RainSurfaceMath.clamp01(Double((y - topY) / max(0.000_001, depthSpan)))
                        let nearBoost = 1.0 - 0.55 * depth01

                        let grain = 0.60 + 0.40 * prng.random01()
                        let a = RainSurfaceMath.clamp01(a0 * amount * 0.18 * nearBoost * grain)

                        var circle = Path()
                        circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                        context.fill(circle, with: .color(colour.opacity(a)))
                    }
                }
            }

            // Micro grain
            do {
                let desired = Double(maxPuffsPerSample) * (1.60 + 9.00 * a0)
                let cap = isAppExtension ? 34 : 220
                let count = min(cap, max(0, Int(desired * densityScale + 0.5)))

                if count > 0 {
                    for _ in 0..<count {
                        let rx = prng.random01()
                        let rr = prng.random01()
                        let ry = prng.random01()

                        let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.75
                        let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                        let r = microMinR + (microMaxR - microMinR) * pow(rr, 0.86)

                        let yT = pow(ry, 3.10)
                        let y = topY + r * 0.08 + microBand * CGFloat(yT)

                        let grain = 0.55 + 0.45 * prng.random01()
                        let a = RainSurfaceMath.clamp01(a0 * amount * 0.10 * grain)

                        var circle = Path()
                        circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                        context.fill(circle, with: .color(colour.opacity(a)))
                    }
                }
            }

            // Deep grain (to baseline)
            do {
                let desired = Double(maxPuffsPerSample) * (1.20 + 20.0 * a0)
                let cap = isAppExtension ? 28 : 120
                let count = min(cap, max(0, Int(desired * densityScale + 0.5)))

                if count > 0 {
                    var prngDeep = RainSurfacePRNG(
                        seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0D0F_0A5E, saltB: 0x0000_0000_0C0F_EC0F)
                    )

                    for _ in 0..<count {
                        let rx = prngDeep.random01()
                        let rr = prngDeep.random01()
                        let ry = prngDeep.random01()

                        let xJitter = (prngDeep.random01() - 0.5) * Double(stepX) * 0.80
                        let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                        let r = deepMinR + (deepMaxR - deepMinR) * pow(rr, 0.92)

                        let u = 1.0 - pow(ry, 1.8)
                        let y = topY + depthSpan * CGFloat(0.08 + 0.92 * u)

                        let depth01 = RainSurfaceMath.clamp01(Double((y - topY) / max(0.000_001, depthSpan)))
                        let depthBoost = 0.30 + 0.70 * depth01

                        let grain = 0.60 + 0.40 * prngDeep.random01()
                        let a = RainSurfaceMath.clamp01(a0 * amount * 0.09 * depthBoost * grain)

                        var circle = Path()
                        circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                        context.fill(circle, with: .color(colour.opacity(a)))
                    }
                }
            }

            i += sampleStride
        }
    }

    // MARK: - Mist particles
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

            let falloff = pow(RainSurfaceMath.clamp01(Double(h / heightSpan)), falloffPower)
            let a = RainSurfaceMath.clamp01(a0 * falloff)
            if a <= 0.000_8 { continue }

            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            let puffCount = max(0, min(64, Int(Double(puffsPerSampleMax) * (0.70 + 2.60 * a))))
            let fineCount = max(0, min(96, Int(Double(finePerSampleMax) * (1.10 + 3.60 * a))))

            var prng = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0C0F_FEEE, saltB: 0x0000_0000_0B1F_F00D))

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
