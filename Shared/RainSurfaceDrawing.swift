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

    // MARK: - Baseline (drawn last)

    static func drawBaseline(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let onePixel = RainSurfaceMath.onePixel(displayScale: displayScale)
        let y = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)

        let fadeFrac: CGFloat = 0.035
        let fadeWidth = plotRect.width * fadeFrac

        let x0 = plotRect.minX
        let x1 = plotRect.maxX

        let linePath: Path = {
            var p = Path()
            p.move(to: CGPoint(x: x0, y: y))
            p.addLine(to: CGPoint(x: x1, y: y))
            return p
        }()

        func endFadeShading(color: Color, opacity: Double) -> GraphicsContext.Shading {
            let c0 = color.opacity(0)
            let c1 = color.opacity(opacity)

            let stops = [
                Gradient.Stop(color: c0, location: 0.0),
                Gradient.Stop(color: c1, location: Double(RainSurfaceMath.clamp(fadeWidth / max(plotRect.width, 0.0001), min: 0, max: 0.25))),
                Gradient.Stop(color: c1, location: Double(1.0 - RainSurfaceMath.clamp(fadeWidth / max(plotRect.width, 0.0001), min: 0, max: 0.25))),
                Gradient.Stop(color: c0, location: 1.0)
            ]

            return .linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(x: x0, y: y),
                endPoint: CGPoint(x: x1, y: y)
            )
        }

        // Additive/screen-like blending so the baseline reads through the core.
        let savedBlend = context.blendMode
        context.blendMode = .plusLighter

        let base = RainSurfaceMath.clamp(configuration.baselineOpacity, min: 0.0, max: 1.0)
        let color = configuration.baselineColor

        // Glow: strongest at the line, quick falloff (~2px), faint tail (~5–6px).
        let outerWidth = onePixel * 11.0   // ~5.5px radius
        let midWidth = onePixel * 6.0      // ~3px radius
        let innerWidth = onePixel * 3.0    // ~1.5px radius
        let coreWidth = onePixel * max(1.0, configuration.baselineLineWidth)

        context.stroke(
            linePath,
            with: endFadeShading(color: color, opacity: base * 0.10),
            style: StrokeStyle(lineWidth: outerWidth, lineCap: .butt)
        )
        context.stroke(
            linePath,
            with: endFadeShading(color: color, opacity: base * 0.18),
            style: StrokeStyle(lineWidth: midWidth, lineCap: .butt)
        )
        context.stroke(
            linePath,
            with: endFadeShading(color: color, opacity: base * 0.28),
            style: StrokeStyle(lineWidth: innerWidth, lineCap: .butt)
        )
        context.stroke(
            linePath,
            with: endFadeShading(color: color, opacity: base * 0.60),
            style: StrokeStyle(lineWidth: coreWidth, lineCap: .butt)
        )

        context.blendMode = savedBlend
    }

    // MARK: - Core + fuzz + glint (baseline handled separately)

    static func drawProbabilityMaskedSurface(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        baselineLabelSafeBottom: CGFloat,
        heights: [CGFloat],
        alphas: [CGFloat],
        intensities: [CGFloat],
        certainties: [CGFloat],
        segments: [RainSurfaceGeometry.SurfaceSegment],
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard !segments.isEmpty else { return }
        guard heights.count >= 2 else { return }

        let onePixel = RainSurfaceMath.onePixel(displayScale: displayScale)
        let stepX = plotRect.width / CGFloat(max(1, heights.count - 1))

        // Spec constants (fixed geometry; renderer sets baseline to match).
        let maxCoreHeightBudget = plotRect.height * 0.195
        let fuzzWidthPoints = {
            let minPts = 40.0 / max(displayScale, 1.0)
            let maxPts = 120.0 / max(displayScale, 1.0)
            return RainSurfaceMath.clamp(plotRect.height * 0.22, min: minPts, max: maxPts)
        }()

        let coreMask = RainSurfaceGeometry.unionCoreMaskPath(segments: segments)
        let outsideMask = RainSurfaceGeometry.outsideMaskPath(clipRect: plotRect, coreMask: coreMask)

        // 2) Fuzz layer: speckled, outside-core only, additive/screen-like.
        if configuration.shellEnabled && configuration.shellMaxOpacity > 0 {
            let baseSeed = (configuration.noiseSeed == 0) ? 0xA7F0C2D3B4E59687 : configuration.noiseSeed
            let edgeFadeWidth = plotRect.width * 0.045
            let microBlur = min(onePixel * 0.95, max(0.0, plotRect.height * configuration.shellBlurFractionOfPlotHeight))

            context.drawLayer { layer in
                layer.clip(to: Path(plotRect))

                if microBlur > 0 {
                    layer.addFilter(.blur(radius: microBlur))
                }

                layer.blendMode = .plusLighter

                // Density calibration. shellNoiseAmount in the existing config is tuned low; scale it into a usable probability.
                let baseDensity = RainSurfaceMath.clamp(configuration.shellNoiseAmount * 2.4, min: 0.0, max: 1.0)
                let maxAttemptsPerColumn = 18

                let sampleStride = max(1, Int(round(max(1.0, displayScale))) )  // stable, avoids overdraw on higher scales

                for i in stride(from: 0, to: heights.count, by: sampleStride) {
                    let h = heights[i]
                    if h <= onePixel * 0.35 { continue }

                    let c = (i < certainties.count) ? RainSurfaceMath.clamp01(certainties[i]) : 1.0
                    let intensity01 = (i < intensities.count) ? RainSurfaceMath.clamp01(intensities[i]) : 1.0

                    // Low-height emphasis: stronger near baseline, suppressed near higher portions.
                    let height01 = RainSurfaceMath.clamp01(h / max(maxCoreHeightBudget, onePixel))
                    let lowHeightFactor = 0.15 + 0.85 * pow(max(0.0, 1.0 - height01), 1.6)

                    // Uncertainty drives fuzz.
                    let uncertainty = pow(max(0.0, 1.0 - c), 0.85)

                    // Still scale a little by intensity.
                    let intensityFactor = pow(max(0.0, intensity01), 0.55)

                    let columnStrength = RainSurfaceMath.clamp(baseDensity * Double(lowHeightFactor) * Double(uncertainty) * Double(intensityFactor), min: 0.0, max: 1.0)
                    if columnStrength <= 0 { continue }

                    let xBase = plotRect.minX + CGFloat(i) * stepX
                    let edgeFade = RainSurfaceMath.edgeFadeFactor(x: xBase, minX: plotRect.minX, maxX: plotRect.maxX, fadeWidth: edgeFadeWidth)
                    if edgeFade <= 0 { continue }

                    // Deterministic per-column RNG.
                    let columnSeed = RainSurfacePRNG.hash64(baseSeed ^ (UInt64(i) &* 0xD6E8FEB86659FD93))
                    var prng = RainSurfacePRNG(seed: columnSeed)

                    let attempts = max(2, Int(Double(maxAttemptsPerColumn) * columnStrength))
                    for _ in 0..<attempts {
                        // Bias towards the boundary (distance ~ 0).
                        let u = prng.nextDouble01()
                        let d = fuzzWidthPoints * CGFloat(pow(u, 2.2))
                        let d01 = RainSurfaceMath.clamp01(d / max(fuzzWidthPoints, 0.0001))
                        let distanceFactor = pow(max(0.0, 1.0 - Double(d01)), 1.35)

                        // Decide speckle presence via thresholding (dither-like).
                        let p = columnStrength * Double(distanceFactor) * Double(edgeFade)
                        if prng.nextDouble01() > p { continue }

                        let jitterU = prng.nextCGFloat01() - 0.5
                        let jitterV = prng.nextCGFloat01() - 0.5

                        let x = xBase + jitterU * (stepX * 1.15 + d * 0.6)
                        if x < plotRect.minX - 2 || x > plotRect.maxX + 2 { continue }

                        let xi = Int(round((x - plotRect.minX) / stepX))
                        let idx = min(max(0, xi), heights.count - 1)
                        let topYAtX = baselineY - heights[idx]

                        let y = topYAtX - d + jitterV * onePixel
                        if y < plotRect.minY { continue }
                        if y > baselineY - onePixel * 1.0 { continue } // keep baseline crisp

                        // Tiny speckles.
                        let rPx = 0.45 + 0.70 * prng.nextCGFloat01()
                        let r = (rPx / max(displayScale, 1.0))

                        let alpha = RainSurfaceMath.clamp(
                            configuration.shellMaxOpacity
                            * (0.55 + 0.45 * Double(distanceFactor))
                            * Double(edgeFade),
                            min: 0.0,
                            max: 1.0
                        )

                        let speck = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                        layer.fill(speck, with: .color(configuration.shellColor.opacity(alpha)))
                    }
                }

                // Mask to outside-of-core (even-odd fill).
                layer.blendMode = .destinationIn
                layer.fill(outsideMask, with: .color(.white), style: FillStyle(eoFill: true))
            }
        }

        // 3) Core: opaque fill + interior shading + inside-only gloss band.
        for seg in segments {
            let peakH = max(seg.peakHeight, onePixel)
            let topY = baselineY - peakH

            // Base vertical luminance structure (stays blue all the way down).
            let bottom = configuration.fillBottomColor.opacity(1.0)
            let mid = configuration.fillMidColor.opacity(1.0)
            let top = configuration.fillTopColor.opacity(1.0)

            let stops = [
                Gradient.Stop(color: bottom, location: 0.0),
                Gradient.Stop(color: mid, location: 0.58),
                Gradient.Stop(color: top, location: 1.0)
            ]

            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(stops: stops),
                startPoint: CGPoint(x: plotRect.midX, y: baselineY),
                endPoint: CGPoint(x: plotRect.midX, y: topY)
            )

            context.fill(seg.surfacePath, with: shading)

            // Very subtle side shading (one side marginally darker).
            let sideStops = [
                Gradient.Stop(color: Color.black.opacity(0.10), location: 0.0),
                Gradient.Stop(color: Color.black.opacity(0.00), location: 1.0)
            ]
            let sideShade = GraphicsContext.Shading.linearGradient(
                Gradient(stops: sideStops),
                startPoint: CGPoint(x: seg.startX, y: baselineY),
                endPoint: CGPoint(x: seg.endX, y: baselineY)
            )
            context.fill(seg.surfacePath, with: sideShade)

            // Inside-only gloss band (~8–14px beneath the top curve), clipped inside the core.
            if configuration.crestLiftEnabled && configuration.crestLiftMaxOpacity > 0 {
                let depthPx = RainSurfaceMath.clamp(plotRect.height * 0.04 * displayScale, min: 8.0, max: 14.0)
                let depth = depthPx / max(displayScale, 1.0)
                let inset = onePixel * 2.0

                let glossPath = seg.topEdgePath.applying(CGAffineTransform(translationX: 0, y: inset))
                let glossStroke = glossPath.strokedPath(
                    StrokeStyle(lineWidth: depth * 2.0, lineCap: .round, lineJoin: .round)
                )

                context.drawLayer { layer in
                    layer.clip(to: seg.surfacePath)

                    // Small blur to blend inward; avoids a rim.
                    layer.addFilter(.blur(radius: onePixel * 0.85))
                    layer.blendMode = .screen

                    let alpha = RainSurfaceMath.clamp(configuration.crestLiftMaxOpacity, min: 0.0, max: 1.0)
                    layer.fill(glossStroke, with: .color(configuration.fillTopColor.opacity(alpha)))
                }
            }
        }

        // 4) Optional apex glint(s): tiny and localised.
        if configuration.glintEnabled && configuration.glintMaxOpacity > 0 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter

                let blur = min(configuration.glintBlurRadiusPoints, onePixel * 2.0)
                if blur > 0 {
                    layer.addFilter(.blur(radius: blur))
                }

                for seg in segments {
                    let peakH = seg.peakHeight
                    if peakH <= onePixel { continue }

                    // Only for clearer peaks.
                    let peakNorm = peakH / max(maxCoreHeightBudget, onePixel)
                    if peakNorm < 0.70 { continue }

                    let x = plotRect.minX + CGFloat(seg.peakIndex) * stepX
                    let y = (baselineY - peakH) + onePixel * 2.0

                    let rPx: CGFloat = 1.2 + 0.6 * RainSurfaceMath.clamp01(peakNorm)
                    let r = rPx / max(displayScale, 1.0)

                    let a = RainSurfaceMath.clamp(configuration.glintMaxOpacity * 0.28, min: 0.0, max: 1.0)
                    let p = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                    layer.fill(p, with: .color(configuration.glintColor.opacity(a)))
                }
            }
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0 && index < count else { return nil }
        return self[index]
    }
}
