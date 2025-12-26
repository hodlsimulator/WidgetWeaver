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
        let y = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        var base = Path()
        base.move(to: CGPoint(x: x0, y: y))
        base.addLine(to: CGPoint(x: x1, y: y))

        let savedBlend = context.blendMode
        context.blendMode = .plusLighter

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

    // MARK: - Surface (order matters)
    //
    // 1) core fill (smooth)
    // 2) crest lift (inside)
    // 3) shell halo (inside + outside)
    // 4) shell spray texture (OUTSIDE the surface — this is what the mockup has)
    // 5) ridge highlight (inside)
    // 6) specular glint (peak highlight, inside)

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
        let plotH = max(onePixel, plotRect.height)
        let width = max(onePixel, plotRect.width)

        let globalMaxHeight = max(onePixel, heights.max() ?? onePixel)

        // Padding so glow/spray aren’t clipped at plot edges.
        let clipPadX = min(max(onePixel, configuration.shellAboveThicknessPoints * 1.10), 22.0)
        let clipPadY = min(max(onePixel, configuration.shellAboveThicknessPoints * 0.85), 26.0)
        let clipRect = plotRect.insetBy(dx: -clipPadX, dy: -clipPadY)

        // Union mask for all wet segments.
        var coreMaskPath = Path()
        for seg in segments {
            coreMaskPath.addPath(seg.surfacePath)
        }

        // Outside-of-core mask (even-odd fill).
        var outsideMaskPath = Path()
        outsideMaskPath.addRect(clipRect)
        outsideMaskPath.addPath(coreMaskPath)

        // Keep texture above the baseline line so the baseline stays crisp.
        var aboveBaselineMask = Path()
        aboveBaselineMask.addRect(
            CGRect(
                x: clipRect.minX,
                y: clipRect.minY,
                width: clipRect.width,
                height: max(onePixel, (baselineY - (onePixel * 1.5)) - clipRect.minY)
            )
        )

        // Precompute x positions for horizontal gradients.
        var xPoints: [CGFloat] = []
        xPoints.reserveCapacity(n)
        for i in 0..<n {
            xPoints.append(plotRect.minX + (CGFloat(i) + 0.5) * stepX)
        }

        // Alpha fields (per-sample), designed to match the mock:
        // - coreAlpha keeps the fill slightly translucent (baseline shows through).
        // - ridgeAlpha is narrower + less “ribbon”.
        // - shellAlpha drives halo + spray.
        var coreAlpha = [Double](repeating: 0.0, count: n)
        var ridgeAlpha = [Double](repeating: 0.0, count: n)
        var shellAlpha = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let v = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certainty[i])
            let taper = RainSurfaceMath.clamp01(edgeFactors[i])

            let unc = RainSurfaceMath.clamp01(1.0 - c)

            // Core: slightly translucent so the baseline line reads “through” the fill.
            // This also avoids the current “flat opaque blob” look.
            let vCore = (0.30 + 0.70 * pow(v, 0.70))
            let cCore = (0.82 + 0.18 * pow(c, 0.85))
            let uDim = (1.0 - 0.18 * pow(unc, 0.85))
            coreAlpha[i] = RainSurfaceMath.clamp01(taper * vCore * cCore * uDim)

            // Ridge: keep it present but not a thick ribbon.
            // (The previous look comes from large thickness + large blur + high opacity.)
            let vR = (0.22 + 0.78 * pow(v, 0.95))
            let cR = (0.78 + 0.22 * pow(c, 0.70))
            ridgeAlpha[i] = RainSurfaceMath.clamp01(configuration.ridgeMaxOpacity * taper * vR * cR * 0.72)

            // Shell: drives halo + spray. Bias toward intensity so the spray appears on the slopes,
            // even when certainty is high.
            let vS = (0.20 + 0.80 * pow(v, 0.75))
            let uS = (0.80 + 0.20 * pow(unc, 0.55))
            shellAlpha[i] = RainSurfaceMath.clamp01(configuration.shellMaxOpacity * taper * vS * uS)
        }

        // Fill gradient (vertical): IMPORTANT change vs current look
        // Anchor the gradient to the *segment height* so the crest gets the saturated top colour.
        let fillGradient = Gradient(stops: [
            .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
            .init(color: configuration.fillMidColor.opacity(configuration.fillMidOpacity), location: 0.60),
            .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0)
        ])

        // Horizontal alpha shading for fill.
        let coreStops = makeHorizontalStops(plotRect: plotRect, width: width, xPoints: xPoints, alphas: coreAlpha)
        let coreAlphaShading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: coreStops),
            startPoint: CGPoint(x: plotRect.minX, y: baselineY),
            endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
        )

        // Draw each wet segment so per-segment peaks can drive glint.
        for seg in segments {
            let r = seg.range
            if r.isEmpty { continue }

            // Peak for glint.
            var peakIndex = r.lowerBound
            var peakHeight: CGFloat = 0.0
            for i in r {
                let h = heights[safe: i] ?? 0.0
                if h > peakHeight {
                    peakHeight = h
                    peakIndex = i
                }
            }
            let segMaxHeight = max(onePixel, peakHeight)
            let peakV01 = RainSurfaceMath.clamp01(Double(segMaxHeight / globalMaxHeight))

            // Segment-anchored vertical gradient endpoint (this is the “make it look like the mockup” part).
            let fillTopY = baselineY - segMaxHeight
            let fillShading = GraphicsContext.Shading.linearGradient(
                fillGradient,
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.minX, y: fillTopY)
            )

            // PASS 1 — Core fill (smooth)
            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))

                layer.fill(seg.surfacePath, with: fillShading)

                // Apply horizontal alpha field so baseline can show through.
                layer.blendMode = .destinationIn
                layer.fill(seg.surfacePath, with: coreAlphaShading)

                // Hard clip to union mask (safety).
                layer.blendMode = .destinationIn
                layer.fill(coreMaskPath, with: .color(.white))
            }

            // PASS 2 — Crest lift (inside)
            if configuration.crestLiftEnabled, configuration.crestLiftMaxOpacity > 0.000_01 {
                let crestOpacity = configuration.crestLiftMaxOpacity * (0.55 + 0.45 * peakV01)
                if crestOpacity > 0.000_8 {
                    let crestStops = makeHorizontalColourStops(
                        plotRect: plotRect,
                        width: width,
                        xPoints: xPoints,
                        alphas: coreAlpha.map { RainSurfaceMath.clamp01($0 * 0.55) },
                        colour: configuration.fillTopColor.opacity(crestOpacity * 0.75)
                    )
                    let crestShading = GraphicsContext.Shading.linearGradient(
                        Gradient(stops: crestStops),
                        startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                        endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                    )

                    let crestBand = seg.topEdgePath.strokedPath(
                        StrokeStyle(
                            lineWidth: max(onePixel, 2.0) * 2.0,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )

                    let savedBlend = context.blendMode
                    context.blendMode = .plusLighter
                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))
                        layer.addFilter(.blur(radius: max(onePixel, 1.6)))
                        layer.fill(crestBand, with: crestShading)

                        layer.blendMode = .destinationIn
                        layer.fill(coreMaskPath, with: .color(.white))
                    }
                    context.blendMode = savedBlend
                }
            }

            // PASS 3 — Shell halo (inside + outside)
            if configuration.shellEnabled, configuration.shellMaxOpacity > 0.000_01 {
                let insideT = max(onePixel, configuration.shellInsideThicknessPoints)
                let belowT = max(onePixel, configuration.shellAboveThicknessPoints)
                let outsideHaloT = max(onePixel, min(belowT * 0.26, 3.0))

                let shellBlur = min(max(onePixel, plotH * max(0.0, configuration.shellBlurFractionOfPlotHeight)), 4.5)

                let insideBand = seg.topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: insideT * 2.0, lineCap: .round, lineJoin: .round)
                )
                let underBand = seg.topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: belowT * 2.0, lineCap: .round, lineJoin: .round)
                )
                let outsideBand = seg.topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: outsideHaloT * 2.0, lineCap: .round, lineJoin: .round)
                )

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

                // Inside soft edge
                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if shellBlur > 0 { layer.addFilter(.blur(radius: shellBlur)) }
                    layer.fill(insideBand, with: shellShading)

                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))
                }

                // Under-edge glow (still inside mask)
                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if shellBlur > 0 { layer.addFilter(.blur(radius: shellBlur)) }
                    layer.fill(underBand, with: shellShading)

                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))
                }

                // Outside halo (outside mask)
                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if shellBlur > 0 { layer.addFilter(.blur(radius: shellBlur)) }
                    layer.fill(outsideBand, with: haloShading)

                    layer.blendMode = .destinationIn
                    layer.fill(outsideMaskPath, with: .color(.white), style: FillStyle(eoFill: true))
                    layer.fill(aboveBaselineMask, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // PASS 4 — Shell spray texture (OUTSIDE the surface)
            // This is the key to matching the mockup’s grainy “spray” edges.
            if configuration.shellEnabled,
               configuration.shellNoiseAmount > 0.000_01,
               configuration.shellPuffsPerSampleMax > 0 {

                let amount = RainSurfaceMath.clamp01(configuration.shellNoiseAmount)

                // Keep it present but widget-safe.
                let isAppExtension = WidgetWeaverRuntime.isRunningInAppExtension
                let densityScale: Double = isAppExtension ? 0.60 : 1.00

                // A little blur turns circles into “misty spray” instead of dotty noise.
                let sprayBlur = max(onePixel, min(1.35, (plotH * 0.010)))

                let savedBlend = context.blendMode
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if sprayBlur > onePixel * 0.85 {
                        layer.addFilter(.blur(radius: sprayBlur))
                    }

                    let maxPuffs = max(1, Int(Double(configuration.shellPuffsPerSampleMax) * densityScale))
                    drawEdgeSprayOutsideSurface(
                        in: &layer,
                        plotRect: plotRect,
                        baselineY: baselineY,
                        stepX: stepX,
                        range: r,
                        heights: heights,
                        alpha: shellAlpha,
                        colour: configuration.shellColor,
                        amount: amount,
                        maxPuffsPerSample: maxPuffs,
                        minR: max(onePixel * 0.55, configuration.shellPuffMinRadiusPoints * 0.55),
                        maxR: max(onePixel * 0.95, configuration.shellPuffMaxRadiusPoints * 0.75),
                        onePixel: onePixel
                    )

                    // Keep only outside-of-surface + above baseline.
                    layer.blendMode = .destinationIn
                    layer.fill(outsideMaskPath, with: .color(.white), style: FillStyle(eoFill: true))
                    layer.fill(aboveBaselineMask, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // PASS 5 — Ridge highlight (inside core) — narrowed to avoid the thick ribbon
            if configuration.ridgeEnabled, configuration.ridgeMaxOpacity > 0.000_01 {
                // Interpret config thickness/blur conservatively so the highlight stays tight like the mock.
                let ridgeR = min(max(onePixel, configuration.ridgeThicknessPoints * 0.42), 2.0)

                let rawBlur = plotH * max(0.0, configuration.ridgeBlurFractionOfPlotHeight)
                let ridgeBlur = min(max(onePixel, rawBlur * 0.55), 4.2)

                let ridgeBand = seg.topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: ridgeR * 2.0, lineCap: .round, lineJoin: .round)
                )

                let boosted = ridgeAlpha.map { a in
                    let boost = 1.0 + configuration.ridgePeakBoost * peakV01
                    return RainSurfaceMath.clamp01(a * boost * 0.78)
                }

                let ridgeStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: boosted,
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
            if configuration.glintEnabled, configuration.glintMaxOpacity > 0.000_01 {
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
                            glintAlphaLocal[i] = RainSurfaceMath.clamp01(configuration.glintMaxOpacity * w)
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

                        let glintR = min(max(onePixel, configuration.glintThicknessPoints), 1.6)
                        let glintBand = seg.topEdgePath.strokedPath(
                            StrokeStyle(lineWidth: glintR * 2.0, lineCap: .round, lineJoin: .round)
                        )

                        let savedBlend = context.blendMode
                        context.blendMode = .plusLighter

                        // Main glint
                        context.drawLayer { layer in
                            layer.clip(to: Path(clipRect))
                            layer.addFilter(.blur(radius: max(onePixel, configuration.glintBlurRadiusPoints)))
                            layer.fill(glintBand, with: glintShading)

                            layer.blendMode = .destinationIn
                            layer.fill(coreMaskPath, with: .color(.white))
                        }

                        // Optional halo (kept very subtle; config controls it)
                        if configuration.glintHaloOpacityMultiplier > 0.000_01 {
                            let haloOpacity = RainSurfaceMath.clamp01(configuration.glintHaloOpacityMultiplier)
                            if haloOpacity > 0.000_8 {
                                let haloBand = seg.topEdgePath.strokedPath(
                                    StrokeStyle(lineWidth: (glintR * 3.4) * 2.0, lineCap: .round, lineJoin: .round)
                                )

                                context.drawLayer { layer in
                                    layer.clip(to: Path(clipRect))
                                    layer.addFilter(.blur(radius: max(onePixel, configuration.glintBlurRadiusPoints * 2.6)))
                                    layer.fill(haloBand, with: glintShading)

                                    layer.blendMode = .destinationIn
                                    layer.fill(coreMaskPath, with: .color(.white))

                                    layer.blendMode = .destinationIn
                                    layer.fill(Path(clipRect), with: .color(.white.opacity(haloOpacity)))
                                }
                            }
                        }

                        context.blendMode = savedBlend
                    }
                }
            }
        }
    }

    // MARK: - Gradient stop helpers

    private static func makeHorizontalStops(
        plotRect: CGRect,
        width: CGFloat,
        xPoints: [CGFloat],
        alphas: [Double]
    ) -> [Gradient.Stop] {
        let n = min(xPoints.count, alphas.count)
        guard n > 0 else {
            return [
                .init(color: .white.opacity(0.0), location: 0.0),
                .init(color: .white.opacity(0.0), location: 1.0)
            ]
        }

        if n == 1 {
            let a = RainSurfaceMath.clamp01(alphas[0])
            return [
                .init(color: .white.opacity(a), location: 0.0),
                .init(color: .white.opacity(a), location: 1.0)
            ]
        }

        let denom = max(1e-6, width)
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(n)

        for i in 0..<n {
            let x = xPoints[i]
            let loc = max(0.0, min(1.0, (x - plotRect.minX) / denom))
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: .white.opacity(a), location: loc))
        }

        // Ensure coverage at ends.
        if stops.first?.location ?? 0.0 > 0.0 {
            stops.insert(.init(color: stops.first?.color ?? .white.opacity(0.0), location: 0.0), at: 0)
        }
        if stops.last?.location ?? 1.0 < 1.0 {
            stops.append(.init(color: stops.last?.color ?? .white.opacity(0.0), location: 1.0))
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
        guard n > 0 else {
            return [
                .init(color: colour.opacity(0.0), location: 0.0),
                .init(color: colour.opacity(0.0), location: 1.0)
            ]
        }

        if n == 1 {
            let a = RainSurfaceMath.clamp01(alphas[0])
            return [
                .init(color: colour.opacity(a), location: 0.0),
                .init(color: colour.opacity(a), location: 1.0)
            ]
        }

        let denom = max(1e-6, width)
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(n)

        for i in 0..<n {
            let x = xPoints[i]
            let loc = max(0.0, min(1.0, (x - plotRect.minX) / denom))
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: colour.opacity(a), location: loc))
        }

        if stops.first?.location ?? 0.0 > 0.0 {
            stops.insert(.init(color: stops.first?.color ?? colour.opacity(0.0), location: 0.0), at: 0)
        }
        if stops.last?.location ?? 1.0 < 1.0 {
            stops.append(.init(color: stops.last?.color ?? colour.opacity(0.0), location: 1.0))
        }

        return stops
    }

    // MARK: - Spray texture (outside the surface)

    private static func drawEdgeSprayOutsideSurface(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        range: Range<Int>,
        heights: [CGFloat],
        alpha: [Double],
        colour: Color,
        amount: Double,
        maxPuffsPerSample: Int,
        minR: CGFloat,
        maxR: CGFloat,
        onePixel: CGFloat
    ) {
        guard amount > 0.000_01 else { return }
        guard maxPuffsPerSample > 0 else { return }

        let n = min(heights.count, alpha.count)
        guard n > 0 else { return }

        // Two layers: coarse puffs + fine grain.
        let fineMultiplier: Double = 1.85
        let coarseCap = 180
        let fineCap = 260

        for i in range {
            if i < 0 || i >= n { continue }

            let a0 = RainSurfaceMath.clamp01(alpha[i])
            if a0 < 0.010 { continue }

            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let topY = baselineY - h
            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            // Density grows fast with alpha to get the mock’s “spray” look.
            let density = amount * (0.55 + 3.40 * a0)

            let coarseCount = min(coarseCap, max(0, Int(Double(maxPuffsPerSample) * density + 0.5)))
            let fineCount = min(fineCap, max(0, Int(Double(maxPuffsPerSample) * fineMultiplier * density + 0.5)))

            if coarseCount == 0, fineCount == 0 { continue }

            var prng = RainSurfacePRNG(seed: RainSurfacePRNG.seed(sampleIndex: i, saltA: 0xA11C_AFE, saltB: 0x0B0B_1E))

            // Coarse puffs: slightly larger, closer to ridge.
            if coarseCount > 0 {
                for _ in 0..<coarseCount {
                    let uX = prng.random01()
                    let uY = prng.random01()
                    let uR = prng.random01()
                    let uA = prng.random01()

                    let xBase = x0 + CGFloat(uX) * stepX
                    let xJitter = CGFloat((prng.random01() - 0.5)) * stepX * 3.2

                    // Mostly above the ridge, with some lateral “spray” lift.
                    let yLift = CGFloat(uY) * min(max(onePixel * 2.0, h * 0.28), 22.0)
                    let y = topY - yLift

                    let r = minR + CGFloat(uR) * max(onePixel, (maxR - minR))

                    // Strong centre, softer tail.
                    let a = RainSurfaceMath.clamp01(a0 * amount * (0.07 + 0.22 * uA) * (1.0 - 0.65 * uY))

                    if a <= 0.000_9 { continue }

                    let rect = CGRect(x: (xBase + xJitter) - r, y: y - r, width: r * 2.0, height: r * 2.0)
                    context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(a)))
                }
            }

            // Fine grain: lots of tiny particles, wider scatter.
            if fineCount > 0 {
                let fineMinR = max(onePixel * 0.45, minR * 0.55)
                let fineMaxR = max(fineMinR + onePixel * 0.25, maxR * 0.55)

                for _ in 0..<fineCount {
                    let uX = prng.random01()
                    let uY = prng.random01()
                    let uR = prng.random01()
                    let uA = prng.random01()

                    let xBase = x0 + CGFloat(uX) * stepX
                    let xJitter = CGFloat((prng.random01() - 0.5)) * stepX * 5.5

                    // Fine grain rises higher and spreads further than coarse puffs.
                    let yLift = CGFloat(uY) * min(max(onePixel * 3.0, h * 0.55), 40.0)
                    let y = topY - yLift

                    let r = fineMinR + CGFloat(uR) * max(onePixel, (fineMaxR - fineMinR))

                    let a = RainSurfaceMath.clamp01(a0 * amount * (0.03 + 0.12 * uA) * (1.0 - 0.80 * uY))

                    if a <= 0.000_9 { continue }

                    let rect = CGRect(x: (xBase + xJitter) - r, y: y - r, width: r * 2.0, height: r * 2.0)
                    context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(a)))
                }
            }
        }
    }
}

// MARK: - Safe indexing

private extension Array {
    subscript(safe index: Int) -> Element? {
        if index < 0 { return nil }
        if index >= count { return nil }
        return self[index]
    }
}
