//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Rendering helpers for the forecast surface.
//

import Foundation
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
        guard configuration.baselineOpacity > 0.000_01 else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let lineW = max(onePixel, configuration.baselineLineWidth)

        let inset = max(0.0, configuration.baselineInsetPoints)
        let x0 = plotRect.minX + inset
        let x1 = max(x0, plotRect.maxX - inset)

        let y = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        var p = Path()
        p.move(to: CGPoint(x: x0, y: y))
        p.addLine(to: CGPoint(x: x1, y: y))

        context.stroke(
            p,
            with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)),
            style: StrokeStyle(lineWidth: lineW, lineCap: .round)
        )

        let softW = max(lineW, lineW * max(1.0, configuration.baselineSoftWidthMultiplier))
        let softA = RainSurfaceMath.clamp01(configuration.baselineOpacity * max(0.0, configuration.baselineSoftOpacityMultiplier))

        if softA > 0.000_01 {
            context.stroke(
                p,
                with: .color(configuration.baselineColor.opacity(softA)),
                style: StrokeStyle(lineWidth: softW, lineCap: .round)
            )
        }
    }

    // MARK: - Probability-masked surface (core + effects)

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
        let n = heights.count
        guard n > 0 else { return }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        var coreAlpha = [Double](repeating: 0.0, count: n)
        var ridgeAlpha = [Double](repeating: 0.0, count: n)
        var glintAlpha = [Double](repeating: 0.0, count: n)
        var bloomAlpha = [Double](repeating: 0.0, count: n)
        var shellAlpha = [Double](repeating: 0.0, count: n)
        var mistAlpha = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let v = RainSurfaceMath.clamp01(intensityNorm[i])
            let c = RainSurfaceMath.clamp01(certainty[i])
            let u = RainSurfaceMath.clamp01(1.0 - c)

            let endFactor = (i < edgeFactors.count) ? RainSurfaceMath.clamp01(edgeFactors[i]) : 1.0

            let pGate = RainSurfaceMath.lerp(0.20, 1.0, pow(c, 0.85))
            coreAlpha[i] = RainSurfaceMath.clamp01(pGate * endFactor)

            let tall = pow(v, 0.70)
            ridgeAlpha[i] = RainSurfaceMath.clamp01(configuration.ridgeMaxOpacity * tall * pow(c, 0.92) * endFactor)
            glintAlpha[i] = RainSurfaceMath.clamp01(configuration.glintMaxOpacity * pow(tall, 1.35) * pow(c, 1.05) * endFactor)

            bloomAlpha[i] = RainSurfaceMath.clamp01(configuration.bloomMaxOpacity * pow(tall, 0.55) * (0.35 + 0.65 * u) * endFactor)

            let lowV = pow(1.0 - v, 1.15)
            let shellBase = configuration.shellMaxOpacity * (0.35 + 0.65 * u) * (0.30 + 0.70 * lowV)
            shellAlpha[i] = RainSurfaceMath.clamp01(shellBase * endFactor)

            mistAlpha[i] = RainSurfaceMath.clamp01(configuration.mistMaxOpacity * (0.25 + 0.75 * u) * endFactor)
        }

        let plotH = max(onePixel, plotRect.height)

        let ridgeBlur = max(0.0, plotH * max(0.0, configuration.ridgeBlurFractionOfPlotHeight))
        let bloomBlur = max(0.0, plotH * max(0.0, configuration.bloomBlurFractionOfPlotHeight))
        let shellBlur = max(0.0, plotH * max(0.0, configuration.shellBlurFractionOfPlotHeight))

        let bloomBandHeight = max(onePixel, plotH * max(0.0, configuration.bloomBandHeightFractionOfPlotHeight))

        let mistHeightFromFraction = plotH * max(0.0, configuration.mistHeightFractionOfPlotHeight)
        let mistHeight = min(max(0.0, configuration.mistHeightPoints), mistHeightFromFraction)

        let clipPadX = min(max(onePixel, configuration.shellAboveThicknessPoints * 1.10), 20.0)
        let clipPadY = min(max(onePixel, max(bloomBandHeight, mistHeight) * 0.60), 40.0)

        for seg in segments {
            let r = seg.range
            if r.isEmpty { continue }

            let surfacePath = seg.surfacePath
            let topEdgePath = seg.topEdgePath

            let segX0 = plotRect.minX + CGFloat(r.lowerBound) * stepX
            let segX1 = plotRect.minX + CGFloat(r.upperBound) * stepX

            let clipRect = CGRect(
                x: segX0 - clipPadX,
                y: plotRect.minY - clipPadY,
                width: (segX1 - segX0) + clipPadX * 2.0,
                height: plotRect.height + clipPadY * 2.0
            )

            let outside = RainSurfaceGeometry.makeOutsideMaskPath(plotRect: clipRect, surfacePath: surfacePath, padding: 0.0)

            let width = max(onePixel, plotRect.width)
            var xPoints: [CGFloat] = []
            xPoints.reserveCapacity(r.count + 2)

            xPoints.append(segX0)

            for idx in r {
                let x = plotRect.minX + (CGFloat(idx) + 0.5) * stepX
                xPoints.append(x)
            }

            xPoints.append(segX1)

            func paddedStops(_ values: [Double]) -> [Double] {
                var out: [Double] = []
                out.reserveCapacity(r.count + 2)

                let first = max(0, r.lowerBound)
                let last = min(n - 1, max(first, r.upperBound - 1))

                out.append(values[first])
                for idx in r { out.append(values[idx]) }
                out.append(values[last])

                return out
            }

            let coreA = paddedStops(coreAlpha)
            let ridgeA = paddedStops(ridgeAlpha)
            let glintA = paddedStops(glintAlpha)
            let bloomA = paddedStops(bloomAlpha)

            var shellA: [Double] = []
            shellA.reserveCapacity(r.count + 2)

            let first = max(0, r.lowerBound)
            let last = min(n - 1, max(first, r.upperBound - 1))

            shellA.append(shellAlpha[first])
            for idx in r { shellA.append(shellAlpha[idx]) }
            shellA.append(shellAlpha[last])

            let mistA = paddedStops(mistAlpha)

            let segmentPeakH = heights[r].max() ?? 0.0
            let segmentPeakV = (segmentPeakH <= onePixel) ? 0.0 : Double(segmentPeakH / max(onePixel, plotRect.height))
            let peakV01 = RainSurfaceMath.clamp01(segmentPeakV)

            // PASS 1 — Core fill (smooth)
            let coreStops: [Gradient.Stop] = [
                .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
                .init(color: configuration.fillMidColor.opacity(configuration.fillMidOpacity), location: 0.58),
                .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0)
            ]

            let coreGradient = GraphicsContext.Shading.linearGradient(
                Gradient(stops: coreStops),
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.minX, y: plotRect.minY)
            )

            let coreMaskStops = makeHorizontalStops(
                plotRect: plotRect,
                width: width,
                xPoints: xPoints,
                alphas: coreA
            )

            let coreMask = GraphicsContext.Shading.linearGradient(
                Gradient(stops: coreMaskStops),
                startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
            )

            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))
                layer.fill(surfacePath, with: coreGradient)

                layer.blendMode = .destinationIn
                layer.fill(surfacePath, with: coreMask)
            }

            if configuration.crestLiftEnabled, configuration.crestLiftMaxOpacity > 0.000_01 {
                let crestA = coreA.map { a in
                    let boost = configuration.crestLiftMaxOpacity * (0.25 + 0.75 * peakV01)
                    return RainSurfaceMath.clamp01(a * boost)
                }

                let crestStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: crestA,
                    colour: configuration.fillTopColor
                )

                let crestShading = GraphicsContext.Shading.linearGradient(
                    Gradient(stops: crestStops),
                    startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                )

                let savedBlend = context.blendMode
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    layer.fill(surfacePath, with: crestShading)

                    layer.blendMode = .destinationIn
                    layer.fill(surfacePath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // PASS 2 — Broad bloom (outside-only; vertically clamped)
            if configuration.bloomEnabled,
               configuration.bloomMaxOpacity > 0.000_01,
               (bloomA.max() ?? 0.0) > 0.000_5
            {
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

                let topY = max(plotRect.minY, baselineY - (segmentPeakH + bloomBandHeight * 0.50))
                let bottomY = min(baselineY, topY + bloomBandHeight)

                var band = Path()
                band.addRect(CGRect(x: clipRect.minX, y: topY, width: clipRect.width, height: max(onePixel, bottomY - topY)))

                let savedBlend = context.blendMode
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if bloomBlur > 0 { layer.addFilter(.blur(radius: bloomBlur)) }

                    layer.fill(Path(clipRect), with: bloomShading)

                    layer.blendMode = .destinationIn
                    layer.fill(band, with: .color(.white))
                    layer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                }

                context.blendMode = savedBlend
            }

            // PASS 3 — Above-surface mist (outside-only; optional)
            if configuration.mistEnabled,
               configuration.mistMaxOpacity > 0.000_01,
               mistHeight > onePixel,
               (mistA.max() ?? 0.0) > 0.000_5
            {
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

                let topY = max(plotRect.minY, baselineY - (segmentPeakH + mistHeight))
                let bottomY = max(plotRect.minY, baselineY - max(onePixel, segmentPeakH))

                var mistBand = Path()
                mistBand.addRect(CGRect(x: clipRect.minX, y: topY, width: clipRect.width, height: max(onePixel, bottomY - topY)))

                let savedBlend = context.blendMode
                context.blendMode = .plusLighter

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))

                    if configuration.mistNoiseEnabled, configuration.mistNoiseInfluence > 0.000_01 {
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

                    if shellBlur > 0 { layer.addFilter(.blur(radius: shellBlur)) }
                    layer.fill(mistBand, with: mistShading)

                    layer.blendMode = .destinationIn
                    layer.fill(mistBand, with: .color(.white))
                    layer.fill(outside, with: .color(.white), style: FillStyle(eoFill: true))
                }

                context.blendMode = savedBlend
            }

            // PASS 4 — Surface shell fuzz (boundary-attached; texture lives on/under the ridge)
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
                let belowFillMultiplier = RainSurfaceMath.clamp(
                    1.0 - noise * 1.55,
                    min: 0.06,
                    max: 1.0
                )

                let shellBelowStops = makeHorizontalColourStops(
                    plotRect: plotRect,
                    width: width,
                    xPoints: xPoints,
                    alphas: shellA.map { RainSurfaceMath.clamp01($0 * belowFillMultiplier) },
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

                    layer.drawLayer { inner in
                        if shellBlur > 0 { inner.addFilter(.blur(radius: shellBlur)) }
                        inner.fill(shellInsideBand, with: shellShading)

                        inner.blendMode = .destinationIn
                        inner.fill(surfacePath, with: .color(.white))
                    }

                    layer.drawLayer { fuzz in

                        if belowFillMultiplier > 0.000_01 {
                            fuzz.drawLayer { base in
                                if shellBlur > 0 { base.addFilter(.blur(radius: shellBlur)) }
                                base.fill(shellBelowBand, with: shellBelowShading)

                                base.blendMode = .destinationIn
                                base.fill(surfacePath, with: .color(.white))
                                base.fill(shellBelowBand, with: .color(.white))
                            }
                        }

                        if noise > 0.000_01,
                           configuration.shellPuffsPerSampleMax > 0
                        {
                            drawShellPuffs(
                                in: &fuzz,
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
                                minR: max(onePixel * 0.55, configuration.shellPuffMinRadiusPoints),
                                maxR: max(onePixel * 0.75, configuration.shellPuffMaxRadiusPoints),
                                onePixel: onePixel
                            )
                        }

                        fuzz.blendMode = .destinationIn
                        fuzz.fill(surfacePath, with: .color(.white))
                        fuzz.fill(shellBelowBand, with: .color(.white))
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
                    layer.fill(surfacePath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }

            // PASS 6 — Specular glint (small peak highlight; inside core)
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

                if configuration.glintHaloOpacityMultiplier > 0.000_01, configuration.glintBlurRadiusPoints > 0.000_01 {
                    let haloA = glintA.map { a in
                        RainSurfaceMath.clamp01(a * configuration.glintHaloOpacityMultiplier)
                    }

                    let haloStops = makeHorizontalColourStops(
                        plotRect: plotRect,
                        width: width,
                        xPoints: xPoints,
                        alphas: haloA,
                        colour: configuration.glintColor
                    )

                    let haloShading = GraphicsContext.Shading.linearGradient(
                        Gradient(stops: haloStops),
                        startPoint: CGPoint(x: plotRect.minX, y: baselineY),
                        endPoint: CGPoint(x: plotRect.maxX, y: baselineY)
                    )

                    let haloBlur = max(0.0, configuration.glintBlurRadiusPoints * 2.0)

                    let haloBand = topEdgePath.strokedPath(
                        StrokeStyle(lineWidth: max(onePixel, glintR * 2.2) * 2.0, lineCap: .round, lineJoin: .round)
                    )

                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))
                        if haloBlur > 0 { layer.addFilter(.blur(radius: haloBlur)) }
                        layer.fill(haloBand, with: haloShading)

                        layer.blendMode = .destinationIn
                        layer.fill(surfacePath, with: .color(.white))
                    }
                }

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    if configuration.glintBlurRadiusPoints > 0 { layer.addFilter(.blur(radius: configuration.glintBlurRadiusPoints)) }

                    layer.fill(glintBand, with: glintShading)

                    layer.blendMode = .destinationIn
                    layer.fill(surfacePath, with: .color(.white))
                }

                context.blendMode = savedBlend
            }
        }
    }

    // MARK: - Shell puffs (noise in the below-surface shell band)

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
        let amt = RainSurfaceMath.clamp01(amount)

        for i in range {
            if i < 0 || i >= n { continue }

            let h = heights[i]
            if h <= onePixel * 0.25 { continue }

            let a0 = RainSurfaceMath.clamp01(shellAlpha[i])
            if a0 <= 0.000_8 { continue }

            let topY = baselineY - h
            let x0 = plotRect.minX + CGFloat(i) * stepX
            let x1 = x0 + stepX

            var prng = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0A11_CAFE, saltB: 0x0000_0000_00B0_0B1E))

            let sampleJitter = 0.55 + 0.85 * prng.random01()

            let desired = Double(maxPuffsPerSample) * (0.70 + 3.10 * a0) * sampleJitter
            let puffCount = min(140, max(1, Int(desired + 0.5)))

            for _ in 0..<puffCount {
                let rx = prng.random01()
                let rr = prng.random01()
                let ry = prng.random01()

                let xJitter = (prng.random01() - 0.5) * Double(stepX) * 0.55
                let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                let r = minR + (maxR - minR) * pow(rr, 0.65)

                let depth01 = pow(ry, 1.25)
                let y = topY + hSpan * CGFloat(depth01) - r * 0.18

                let fall = pow(max(0.0, 1.0 - depth01), 0.55)

                let grain = 0.55 + 0.45 * prng.random01()
                let a = RainSurfaceMath.clamp01(a0 * amt * fall * 0.62 * grain)

                var circle = Path()
                circle.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2.0, height: r * 2.0))
                context.fill(circle, with: .color(colour.opacity(a)))
            }

            let fineDesired = Double(maxPuffsPerSample) * (3.10 + 7.20 * a0) * (0.70 + 0.70 * sampleJitter)
            let fineCount = min(260, max(1, Int(fineDesired + 0.5)))

            var prng2 = RainSurfacePRNG(seed: makeSeed(sampleIndex: i, saltA: 0x0000_0000_0F1E_EEED, saltB: 0x0000_0000_0BEE_F00D))

            let fineMinR = max(onePixel * 0.28, minR * 0.32)
            let fineMaxR = max(onePixel * 0.55, maxR * 0.52)

            for _ in 0..<fineCount {
                let rx = prng2.random01()
                let rr = prng2.random01()
                let ry = prng2.random01()

                let xJitter = (prng2.random01() - 0.5) * Double(stepX) * 0.70
                let x = x0 + (x1 - x0) * rx + CGFloat(xJitter)

                let r = fineMinR + (fineMaxR - fineMinR) * pow(rr, 0.85)

                let depth01 = pow(ry, 1.05)
                let y = topY + hSpan * CGFloat(depth01) - r * 0.12

                let fall = pow(max(0.0, 1.0 - depth01), 0.65)

                let grain = 0.50 + 0.50 * prng2.random01()
                let a = RainSurfaceMath.clamp01(a0 * amt * fall * 0.26 * grain)

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
