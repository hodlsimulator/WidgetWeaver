//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Rendering helpers for the forecast surface.

import SwiftUI
import Darwin

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

        func baselineShading(opacity: Double) -> GraphicsContext.Shading {
            let c = configuration.baselineColor
            let o = RainSurfaceMath.clamp01(opacity)
            let stops: [Gradient.Stop] = [
                .init(color: c.opacity(o * 0.00), location: 0.00),
                .init(color: c.opacity(o * 0.10), location: 0.18),
                .init(color: c.opacity(o * 1.00), location: 0.50),
                .init(color: c.opacity(o * 0.10), location: 0.82),
                .init(color: c.opacity(o * 0.00), location: 1.00),
            ]
            return .linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(x: x0, y: baselineY),
                endPoint: CGPoint(x: x1, y: baselineY)
            )
        }

        let savedBlend = context.blendMode
        context.blendMode = .screen

        if configuration.baselineSoftOpacityMultiplier > 0, configuration.baselineSoftWidthMultiplier > 1 {
            let softWidth = max(configuration.baselineLineWidth, configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier)
            let softOpacity = configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier
            let softStyle = StrokeStyle(lineWidth: max(onePixel, softWidth), lineCap: .round)
            context.stroke(base, with: baselineShading(opacity: softOpacity), style: softStyle)
        }

        let stroke = StrokeStyle(lineWidth: max(onePixel, configuration.baselineLineWidth), lineCap: .round)
        context.stroke(base, with: baselineShading(opacity: configuration.baselineOpacity), style: stroke)

        context.blendMode = savedBlend
    }

    // MARK: - Masks + layered passes (order matters)

    // Order:
    // 1) core fill (coreMask, smooth)
    // 2) smooth crest lift (optional)
    // 3) broad bloom (mask-derived, clipped)
    // 4) ridge highlight (ridgeMask)
    // 5) specular glint (peak-only)
    // 6) surface shell fuzz (surfaceShellMask; noise only here)
    // 7) above-surface mist (mistMask; outside-only)

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
        let maxH = max(1.0, heights.max() ?? 1.0)

        // Effective blur radii derived from plot rect height.
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
            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let v = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certainty[i])
            let taper = RainSurfaceMath.clamp01(edgeFactors[i])
            let lowV = RainSurfaceMath.clamp01(1.0 - v)
            let proxy = RainSurfaceMath.clamp01(1.0 - c) // uncertainty proxy

            // Local peak estimator (used to slightly boost ridge highlight at true maxima).
            let prevH = heights[max(0, i - 1)]
            let nextH = heights[min(n - 1, i + 1)]
            let neighbourMax = max(prevH, nextH)
            let delta = max(0.0, h - neighbourMax)
            let peak01 = RainSurfaceMath.clamp01(Double(delta / max(onePixel, maxH * 0.18)))

            // Core mask opacity (smooth, no texture).
            if configuration.fillBottomOpacity > 0.000_01 {
                let shapedV = Darwin.pow(v, 0.70)
                let shapedC = Darwin.pow(c, 0.78)
                let base = taper * (0.28 + 0.72 * shapedV) * (0.22 + 0.78 * shapedC)
                coreAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.ridgeEnabled, configuration.ridgeMaxOpacity > 0.000_01 {
                let shapedV = Darwin.pow(v, 0.85)
                let shapedC = Darwin.pow(c, 1.10)
                let base = configuration.ridgeMaxOpacity * taper
                    * (0.22 + 0.78 * shapedV)
                    * (0.55 + 0.45 * shapedC)
                let boost = 1.0 + configuration.ridgePeakBoost * peak01
                ridgeAlpha[i] = RainSurfaceMath.clamp01(base * boost)
            }

            if configuration.bloomEnabled, configuration.bloomMaxOpacity > 0.000_01 {
                let shapedV = Darwin.pow(v, 0.75)
                let base = configuration.bloomMaxOpacity * taper * (0.20 + 0.80 * shapedV)
                let unc = (0.40 + 0.60 * proxy)
                bloomAlpha[i] = RainSurfaceMath.clamp01(base * unc)
            }

            if configuration.shellEnabled, configuration.shellMaxOpacity > 0.000_01 {
                let shapedProxy = Darwin.pow(proxy, 0.92)
                let base = configuration.shellMaxOpacity * taper * shapedProxy * (0.70 + 0.30 * lowV)
                shellAlpha[i] = RainSurfaceMath.clamp01(base)
            }

            if configuration.mistEnabled, configuration.mistMaxOpacity > 0.000_01 {
                let shapedProxy = Darwin.pow(proxy, 1.08)
                let base = configuration.mistMaxOpacity * taper * shapedProxy
                mistAlpha[i] = RainSurfaceMath.clamp01(base)
            }
        }

        // Core fill gradient: dark baseline -> lifted mid -> slightly brighter crest.
        let fillGradient = Gradient(stops: [
            .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.00),
            .init(color: configuration.fillMidColor.opacity(configuration.fillMidOpacity), location: 0.55),
            .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.00),
        ])

        let width = max(1.0, plotRect.width)

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

            // Authoritative core mask (filled under curve).
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
                layer.clip(to: rectPath(clipRect))

                // Mask stage
                layer.fill(coreMaskPath, with: coreMaskShading)

                // Colour stage
                let saved = layer.blendMode
                layer.blendMode = .sourceIn

                let fillShading = GraphicsContext.Shading.linearGradient(
                    fillGradient,
                    startPoint: CGPoint(x: plotRect.midX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.midX, y: plotRect.minY)
                )
                layer.fill(rectPath(clipRect), with: fillShading)
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
                    layer.clip(to: rectPath(clipRect))
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

            if configuration.bloomEnabled, configuration.bloomMaxOpacity > 0.000_01, (bloomA.max() ?? 0.0) > 0.000_5 {
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
                    layer.clip(to: rectPath(clipRect))

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
            // PASS 3 — Ridge highlight (ridgeMask inside core)
            // -------------------------

            if configuration.ridgeEnabled, configuration.ridgeMaxOpacity > 0.000_01, (ridgeA.max() ?? 0.0) > 0.000_5 {
                let ridgeR = max(onePixel, configuration.ridgeThicknessPoints)

                let ridgeBand = topEdgePath.strokedPath(
                    StrokeStyle(lineWidth: ridgeR * 2.0, lineCap: .round, lineJoin: .round)
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
                    layer.clip(to: rectPath(clipRect))
                    if ridgeBlur > 0 { layer.addFilter(.blur(radius: ridgeBlur)) }
                    layer.fill(ridgeBand, with: ridgeShading)

                    // Clip back to the authoritative core mask.
                    layer.blendMode = .destinationIn
                    layer.fill(coreMaskPath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 4 — Specular glint (peak-only, very small)
            // -------------------------

            if configuration.glintEnabled, configuration.glintMaxOpacity > 0.000_01 {
                let segmentCount = r.count
                if segmentCount >= 3 {
                    // Find the peak sample index (score is height, lightly weighted by certainty).
                    var peakIdx = first
                    var peakScore: CGFloat = 0.0
                    var segmentMaxHeight: CGFloat = 0.0

                    for i in r {
                        let h = heights[i]
                        segmentMaxHeight = max(segmentMaxHeight, h)
                        let w = CGFloat(0.65 + 0.35 * RainSurfaceMath.clamp01(certainty[i]))
                        let score = h * w
                        if score > peakScore {
                            peakScore = score
                            peakIdx = i
                        }
                    }

                    if segmentMaxHeight > onePixel * 2.0 {
                        let peakHeight = heights[peakIdx]
                        let minPeak = CGFloat(configuration.glintMinPeakHeightFractionOfSegmentMax) * segmentMaxHeight

                        if peakHeight >= minPeak {
                            let span = max(3, configuration.glintSpanSamples)
                            let sigma = max(1.0, Double(span) * 0.40)

                            var glintA: [Double] = []
                            glintA.reserveCapacity(xPoints.count)

                            func glintAlpha(at idx: Int) -> Double {
                                let d = Double(abs(idx - peakIdx))
                                let g = Darwin.exp(-0.5 * (d * d) / (sigma * sigma))

                                let h01 = RainSurfaceMath.clamp01(Double(heights[idx] / segmentMaxHeight))
                                let c = RainSurfaceMath.clamp01(certainty[idx])
                                let v = RainSurfaceMath.clamp01(intensityNorm[idx])
                                let taper = RainSurfaceMath.clamp01(edgeFactors[idx])

                                let peakMask = Darwin.pow(h01, 1.85)
                                let base = configuration.glintMaxOpacity * g * peakMask
                                return RainSurfaceMath.clamp01(base * taper * (0.55 + 0.45 * v) * Darwin.pow(c, 1.15))
                            }

                            // Align to xPoints: start edge, sample centres, end edge.
                            glintA.append(glintAlpha(at: first))
                            for i in r { glintA.append(glintAlpha(at: i)) }
                            glintA.append(glintAlpha(at: last))

                            if (glintA.max() ?? 0.0) > 0.000_5 {
                                let glintThickness = max(onePixel, configuration.glintThicknessPoints)
                                let glintBand = topEdgePath.strokedPath(
                                    StrokeStyle(lineWidth: glintThickness * 2.0, lineCap: .round, lineJoin: .round)
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
                                context.blendMode = .screen

                                context.drawLayer { layer in
                                    layer.clip(to: rectPath(clipRect))

                                    // Crisp core glint.
                                    layer.fill(glintBand, with: glintShading)

                                    // Tiny halo bloom.
                                    if configuration.glintHaloOpacityMultiplier > 0.000_01, configuration.glintBlurRadiusPoints > 0 {
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

                                        layer.drawLayer { halo in
                                            halo.addFilter(.blur(radius: max(onePixel, configuration.glintBlurRadiusPoints)))
                                            halo.fill(glintBand, with: haloShading)
                                        }
                                    }

                                    // Keep the glint attached to the core.
                                    layer.blendMode = .destinationIn
                                    layer.fill(coreMaskPath, with: .color(.white))
                                }

                                context.blendMode = savedBlend
                            }
                        }
                    }
                }
            }

            // -------------------------
            // PASS 5 — Surface shell fuzz (boundary-attached; texture only here)
            // -------------------------

            if configuration.shellEnabled, configuration.shellMaxOpacity > 0.000_01, (shellA.max() ?? 0.0) > 0.000_5 {
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
                    layer.clip(to: rectPath(clipRect))

                    // Inside portion: very small and smooth (no texture).
                    layer.drawLayer { base in
                        if shellBlur > 0 { base.addFilter(.blur(radius: shellBlur)) }
                        base.fill(shellInsideBand, with: shellShading)
                        base.blendMode = .destinationIn
                        base.fill(coreMaskPath, with: .color(.white))
                    }

                    // Outside portion: texture lives here (outside-only).
                    layer.drawLayer { outer in
                        if shellBlur > 0 { outer.addFilter(.blur(radius: shellBlur)) }

                        // Base outside glow.
                        outer.fill(shellAboveBand, with: shellShading)

                        // Noise modulation as isotropic 2D puffs (no column artefacts).
                        if configuration.shellNoiseAmount > 0.000_01, configuration.shellPuffsPerSampleMax > 0 {
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

                        // Outside-only clamp (applies to both base glow and puffs).
                        outer.blendMode = .destinationIn
                        outer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                    }

                    // Final clamp to the shell mask (prevents any detached fragments).
                    layer.blendMode = .destinationIn
                    layer.fill(shellMask, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // -------------------------
            // PASS 6 — Above-surface mist (outside-only, fades upward; isotropic 2D)
            // -------------------------

            if configuration.mistEnabled, configuration.mistMaxOpacity > 0.000_01, (mistA.max() ?? 0.0) > 0.000_5 {
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
                    layer.clip(to: rectPath(clipRect))

                    // Base mist body (smooth), then clipped.
                    layer.drawLayer { base in
                        base.addFilter(.blur(radius: mistBlur))
                        let crestStroke = topEdgePath.strokedPath(
                            StrokeStyle(lineWidth: max(onePixel, configuration.ridgeThicknessPoints * 0.85), lineCap: .round, lineJoin: .round)
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

                    // Final clamp: band + outside-only (NEVER inside core).
                    layer.blendMode = .destinationIn
                    layer.fill(mistBand, with: .color(.white))
                    layer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
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

            var prng = RainSurfacePRNG(
                seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0A11_CAFE, saltB: 0x0000_0000_00B0_0B1E)
            )

            for _ in 0..<puffCount {
                let ux: Double = prng.nextDouble01()
                let uy: Double = prng.nextDouble01()
                let ur: Double = prng.nextDouble01()
                let uv: Double = prng.nextDouble01()

                let dyFrac: Double = Darwin.pow(uy, 1.65) // densest at the boundary
                let y = topY - CGFloat(dyFrac) * hSpan + CGFloat((uv - 0.5) * Double(onePixel) * 0.60)

                let x = lerp(x0, x1, ux)
                let r = lerp(minR, maxR, Darwin.pow(ur, 1.35))

                let falloff = Darwin.pow(max(0.0, 1.0 - dyFrac), 2.25)
                let alpha = RainSurfaceMath.clamp01(a0 * amount * 0.55 * falloff)

                if alpha <= 0.000_5 { continue }

                let rect = CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0)
                context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(alpha)))
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

        for i in range {
            if i < 0 || i >= n { continue }

            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let baseA = RainSurfaceMath.clamp01(mistAlpha[i])
            if baseA <= 0.000_8 { continue }

            let topY = baselineY - h
            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            // Coarser puffs.
            if puffsPerSampleMax > 0 {
                var prng = RainSurfacePRNG(
                    seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_00C7_A11C, saltB: 0x0000_0000_B16B_00B5)
                )
                let desired = Double(puffsPerSampleMax) * (0.65 + 2.20 * baseA)
                let puffCount = min(220, max(1, Int(desired + 0.5)))

                for _ in 0..<puffCount {
                    let ux: Double = prng.nextDouble01()
                    let uy: Double = prng.nextDouble01()
                    let ur: Double = prng.nextDouble01()
                    let un: Double = prng.nextDouble01()

                    let yDist: Double = Darwin.pow(uy, 1.40) * Double(mistHeight)
                    let y = topY - CGFloat(yDist)
                    let x = lerp(x0, x1, ux)
                    let r = lerp(puffMinR, puffMaxR, Darwin.pow(ur, 1.30))

                    let t = max(0.0, 1.0 - yDist / Double(mistHeight))
                    let falloff = Darwin.pow(t, falloffPower)

                    let noise = (1.0 - noiseInfluence) + (2.0 * noiseInfluence * un)
                    let alpha = RainSurfaceMath.clamp01(baseA * 0.24 * falloff * noise)

                    if alpha <= 0.000_5 { continue }

                    let rect = CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0)
                    context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(alpha)))
                }
            }

            // Fine grain.
            if finePerSampleMax > 0 {
                var prng2 = RainSurfacePRNG(
                    seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0091_F1EE, saltB: 0x0000_0000_0123_4567)
                )
                let desired = Double(finePerSampleMax) * (0.55 + 1.80 * baseA)
                let fineCount = min(240, max(1, Int(desired + 0.5)))

                for _ in 0..<fineCount {
                    let ux: Double = prng2.nextDouble01()
                    let uy: Double = prng2.nextDouble01()
                    let ur: Double = prng2.nextDouble01()
                    let un: Double = prng2.nextDouble01()

                    let yDist: Double = Darwin.pow(uy, 1.25) * Double(mistHeight)
                    let y = topY - CGFloat(yDist)
                    let x = lerp(x0, x1, ux)
                    let r = lerp(fineMinR, fineMaxR, Darwin.pow(ur, 1.20))

                    let t = max(0.0, 1.0 - yDist / Double(mistHeight))
                    let falloff = Darwin.pow(t, falloffPower * 1.10)

                    let noise = (1.0 - noiseInfluence) + (2.0 * noiseInfluence * un)
                    let alpha = RainSurfaceMath.clamp01(baseA * 0.13 * falloff * noise)

                    if alpha <= 0.000_5 { continue }

                    let rect = CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0)
                    context.fill(Path(ellipseIn: rect), with: .color(colour.opacity(alpha)))
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
        guard xPoints.count == alphas.count, xPoints.count >= 2 else {
            return [
                .init(color: .white.opacity(0.0), location: 0.0),
                .init(color: .white.opacity(0.0), location: 1.0),
            ]
        }

        let w = max(1.0, width)
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(xPoints.count)

        for i in 0..<xPoints.count {
            let x = xPoints[i]
            let loc = RainSurfaceMath.clamp01(Double((x - plotRect.minX) / w))
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: .white.opacity(a), location: CGFloat(loc)))
        }

        // Ensure exact endpoints.
        if let first = stops.first {
            stops[0] = .init(color: first.color, location: 0.0)
        }
        if let last = stops.last {
            stops[stops.count - 1] = .init(color: last.color, location: 1.0)
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
        guard xPoints.count == alphas.count, xPoints.count >= 2 else {
            return [
                .init(color: colour.opacity(0.0), location: 0.0),
                .init(color: colour.opacity(0.0), location: 1.0),
            ]
        }

        let w = max(1.0, width)
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(xPoints.count)

        for i in 0..<xPoints.count {
            let x = xPoints[i]
            let loc = RainSurfaceMath.clamp01(Double((x - plotRect.minX) / w))
            let a = RainSurfaceMath.clamp01(alphas[i])
            stops.append(.init(color: colour.opacity(a), location: CGFloat(loc)))
        }

        // Ensure exact endpoints.
        if let first = stops.first {
            stops[0] = .init(color: first.color, location: 0.0)
        }
        if let last = stops.last {
            stops[stops.count - 1] = .init(color: last.color, location: 1.0)
        }

        return stops
    }

    // MARK: - Seed helper (stable per-sample)

    private static func makeSeed(sampleIndex: Int, saltA: UInt64, saltB: UInt64) -> UInt64 {
        var x = UInt64(truncatingIfNeeded: sampleIndex)
        x &*= 0x9E3779B97F4A7C15
        x ^= saltA &+ (x << 6) &+ (x >> 2)
        x ^= saltB &+ (x << 17) &+ (x >> 3)
        x &*= 0xBF58476D1CE4E5B9
        x ^= x >> 31
        return x
    }

    // MARK: - Small helpers

    private static func rectPath(_ rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        return p
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }
}
