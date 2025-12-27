//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Core fill + fuzz-band replacement edge.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum RainSurfaceDrawing {

    // MARK: - Public entry

    static func drawSurface(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        denseHeights: [CGFloat],
        denseCertainties: [Double],
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard denseHeights.count >= 2 else { return }

        let baselineY = alignToPixelCenter(baselineY, displayScale: displayScale)

        // Core fill
        let corePath = makeCorePath(chartRect: chartRect, baselineY: baselineY, heights: denseHeights)
        context.fill(corePath, with: .color(configuration.coreBodyColor))

        // Optional gloss inside fill (kept subtle; your nowcast config disables it)
        if configuration.glossEnabled, configuration.glossMaxOpacity > 0.0001, configuration.glossDepthPixels > 0.0001 {
            drawGloss(
                in: &context,
                chartRect: chartRect,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // Fuzz (also erodes the core edge so the hard surface disappears under the fuzz)
        if configuration.canEnableFuzz, denseCertainties.count == denseHeights.count {
            drawFuzzReplacingEdge(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                denseHeights: denseHeights,
                denseCertainties: denseCertainties,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // Rim on top
        if configuration.rimEnabled {
            let surfacePath = makeSurfaceStrokePath(chartRect: chartRect, baselineY: baselineY, heights: denseHeights)
            drawRim(
                in: &context,
                surfacePath: surfacePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // Glints on top (kept for completeness; your nowcast config disables it)
        if configuration.glintEnabled, configuration.glintCount > 0, configuration.glintMaxOpacity > 0.0001 {
            let surfacePath = makeSurfaceStrokePath(chartRect: chartRect, baselineY: baselineY, heights: denseHeights)
            drawGlints(
                in: &context,
                chartRect: chartRect,
                surfacePath: surfacePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // Baseline last so it stays crisp
        if configuration.baselineLineOpacity > 0.0001, configuration.baselineEndFadeFraction > 0.0 {
            drawBaseline(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                configuration: configuration,
                displayScale: displayScale
            )
        }
    }

    // MARK: - Paths

    private static func makeCorePath(chartRect: CGRect, baselineY: CGFloat, heights: [CGFloat]) -> Path {
        let n = heights.count
        let stepX = chartRect.width / CGFloat(max(1, n - 1))

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: baselineY))

        for i in 0..<n {
            let x = chartRect.minX + CGFloat(i) * stepX
            let y = baselineY - heights[i]
            p.addLine(to: CGPoint(x: x, y: y))
        }

        p.addLine(to: CGPoint(x: chartRect.maxX, y: baselineY))
        p.closeSubpath()
        return p
    }

    private static func makeSurfaceStrokePath(chartRect: CGRect, baselineY: CGFloat, heights: [CGFloat]) -> Path {
        let n = heights.count
        let stepX = chartRect.width / CGFloat(max(1, n - 1))

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: baselineY - heights[0]))

        for i in 1..<n {
            let x = chartRect.minX + CGFloat(i) * stepX
            let y = baselineY - heights[i]
            p.addLine(to: CGPoint(x: x, y: y))
        }

        return p
    }

    // MARK: - Baseline

    private static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let y = alignToPixelCenter(baselineY, displayScale: displayScale)

        var baseline = Path()
        baseline.move(to: CGPoint(x: chartRect.minX, y: y))
        baseline.addLine(to: CGPoint(x: chartRect.maxX, y: y))

        let fade = clamp01(configuration.baselineEndFadeFraction)
        let alpha = clamp01(configuration.baselineLineOpacity)

        let stops: [Gradient.Stop] = [
            .init(color: configuration.baselineColor.opacity(0.0), location: 0.0),
            .init(color: configuration.baselineColor.opacity(alpha), location: fade),
            .init(color: configuration.baselineColor.opacity(alpha), location: 1.0 - fade),
            .init(color: configuration.baselineColor.opacity(0.0), location: 1.0)
        ]

        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(stops: stops),
            startPoint: CGPoint(x: chartRect.minX, y: y),
            endPoint: CGPoint(x: chartRect.maxX, y: y)
        )

        let lineWidth = max(0.5, 1.0 / Double(displayScale))
        context.stroke(baseline, with: shading, lineWidth: lineWidth)
    }

    // MARK: - Rim

    private static func drawRim(
        in context: inout GraphicsContext,
        surfacePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let innerWidthPt = max(0.5 / Double(displayScale), configuration.rimInnerWidthPixels / Double(displayScale))
        let outerWidthPt = max(0.5 / Double(displayScale), configuration.rimOuterWidthPixels / Double(displayScale))

        let innerA = clamp01(configuration.rimInnerOpacity)
        let outerA = clamp01(configuration.rimOuterOpacity)

        let savedBlend = context.blendMode
        context.blendMode = .plusLighter

        if innerA > 0.0001, innerWidthPt > 0.0001 {
            context.stroke(surfacePath, with: .color(configuration.rimColor.opacity(innerA)), lineWidth: innerWidthPt)
        }

        if outerA > 0.0001, outerWidthPt > 0.0001 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.addFilter(.blur(radius: outerWidthPt * 0.35))
                layer.stroke(surfacePath, with: .color(configuration.rimColor.opacity(outerA)), lineWidth: outerWidthPt)
            }
        }

        context.blendMode = savedBlend
    }

    // MARK: - Gloss

    private static func drawGloss(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let depthPt = max(0.0, configuration.glossDepthPixels / Double(displayScale))
        guard depthPt > 0.0001 else { return }

        let maxA = clamp01(configuration.glossMaxOpacity)
        guard maxA > 0.0001 else { return }

        let blurPt = max(0.0, configuration.glossSoftBlurPixels / Double(displayScale))

        let gradient = Gradient(stops: [
            .init(color: configuration.glossColor.opacity(maxA), location: 0.0),
            .init(color: configuration.glossColor.opacity(0.0), location: 1.0)
        ])

        let fillRect = CGRect(
            x: chartRect.minX,
            y: chartRect.minY,
            width: chartRect.width,
            height: CGFloat(depthPt)
        )

        context.drawLayer { layer in
            layer.clip(to: corePath)
            if blurPt > 0.0001 {
                layer.addFilter(.blur(radius: blurPt))
            }
            layer.blendMode = .plusLighter
            layer.fill(
                fillRect,
                with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: chartRect.midX, y: chartRect.minY),
                    endPoint: CGPoint(x: chartRect.midX, y: chartRect.minY + CGFloat(depthPt))
                )
            )
        }
    }

    // MARK: - Glints

    private static func drawGlints(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        surfacePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let count = max(0, configuration.glintCount)
        guard count > 0 else { return }

        let maxA = clamp01(configuration.glintMaxOpacity)
        guard maxA > 0.0001 else { return }

        let sigmaPt = max(0.1, configuration.glintSigmaPixels / Double(displayScale))
        let yOffPt = configuration.glintVerticalOffsetPixels / Double(displayScale)

        // Evenly distributed deterministic positions across the width
        for i in 0..<count {
            let t = (Double(i) + 0.35) / (Double(count) + 0.7)
            let x = chartRect.minX + CGFloat(t) * chartRect.width

            let glintRect = CGRect(
                x: x - CGFloat(3.5 * sigmaPt),
                y: chartRect.minY + CGFloat(yOffPt) - CGFloat(3.5 * sigmaPt),
                width: CGFloat(7.0 * sigmaPt),
                height: CGFloat(7.0 * sigmaPt)
            )

            context.drawLayer { layer in
                layer.clip(to: surfacePath, style: .init(eoFill: false, antialiased: true))
                layer.blendMode = .plusLighter
                layer.addFilter(.blur(radius: sigmaPt))
                layer.fill(glintRect, with: .color(configuration.glintColor.opacity(maxA * 0.65)))
            }
        }
    }

    // MARK: - Fuzz

    private static func drawFuzzReplacingEdge(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        denseHeights: [CGFloat],
        denseCertainties: [Double],
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard let raster = buildRasterImages(
            chartRect: chartRect,
            baselineY: baselineY,
            denseHeights: denseHeights,
            denseCertainties: denseCertainties,
            configuration: configuration,
            displayScale: displayScale
        ) else { return }

        // 1) Erode the core edge FIRST (so the hard surface disappears under the fuzz)
        if configuration.fuzzErodeEnabled, let erode = raster.erodeImage {
            let erodeBlurPx = max(
                configuration.fuzzMicroBlurPixels,
                raster.bandBasePx * 0.06
            )
            let erodeBlurPt = max(0.0, erodeBlurPx / Double(displayScale))

            context.drawLayer { layer in
                layer.blendMode = .destinationOut
                if erodeBlurPt > 0.0001 {
                    layer.addFilter(.blur(radius: erodeBlurPt))
                }
                layer.draw(erode, in: chartRect)
            }
        }

        // 2) Draw fuzz in two passes: broad glow + micro texture
        let savedBlend = context.blendMode
        context.blendMode = .plusLighter

        // Broad glow pass (gives the “glowy blue” look)
        do {
            let glowBlurPx = max(2.0, raster.bandBasePx * 0.32)
            let glowBlurPt = max(0.0, glowBlurPx / Double(displayScale))
            let glowOpacity = clamp01(0.72 + 0.28 * clamp01(configuration.fuzzHazeStrength))

            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.opacity = glowOpacity
                if glowBlurPt > 0.0001 {
                    layer.addFilter(.blur(radius: glowBlurPt))
                }
                layer.draw(raster.fuzzImage, in: chartRect)
            }
        }

        // Micro texture pass (keeps grain/speckles visible)
        do {
            let microBlurPt = max(0.0, configuration.fuzzMicroBlurPixels / Double(displayScale))
            let microOpacity = clamp01(0.92 + 0.18 * clamp01(configuration.fuzzSpeckStrength))

            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.opacity = microOpacity
                if microBlurPt > 0.0001 {
                    layer.addFilter(.blur(radius: microBlurPt))
                }
                layer.draw(raster.fuzzImage, in: chartRect)
            }
        }

        context.blendMode = savedBlend
    }

    private struct RasterBuildResult {
        let fuzzImage: Image
        let erodeImage: Image?
        let bandBasePx: Double
        let rasterScale: Int
    }

    private static func buildRasterImages(
        chartRect: CGRect,
        baselineY: CGFloat,
        denseHeights: [CGFloat],
        denseCertainties: [Double],
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) -> RasterBuildResult? {
        let n = denseHeights.count
        guard n >= 2, denseCertainties.count == n else { return nil }

        // Decide raster scale to stay under max pixels
        let fullWidthPx = max(1, Int((chartRect.width * displayScale).rounded(.up)))
        let fullHeightPx = max(1, Int((chartRect.height * displayScale).rounded(.up)))

        var rasterScale = 1
        while true {
            let w = max(1, fullWidthPx / rasterScale)
            let h = max(1, fullHeightPx / rasterScale)
            if w * h <= max(1, cfg.fuzzRasterMaxPixels) { break }
            rasterScale += 1
            if rasterScale >= 8 { break }
        }

        let widthPx = max(1, fullWidthPx / rasterScale)
        let heightPx = max(1, fullHeightPx / rasterScale)

        let pxPerPoint = Double(displayScale) / Double(rasterScale)

        // Baseline in local pixel coordinates (0..heightPx)
        let baselineLocalY = Double(baselineY - chartRect.minY)
        let baselineYPx = baselineLocalY * pxPerPoint

        // Map xPx -> sample index
        let xPxToSample = Double(n - 1) / Double(max(1, widthPx - 1))

        var ySurfacePxByX = [Double](repeating: baselineYPx, count: widthPx)
        var chanceByX = [Double](repeating: 1.0, count: widthPx)
        var heightPxByX = [Double](repeating: 0.0, count: widthPx)
        var wetMaskByX = [Bool](repeating: false, count: widthPx)

        var maxHeightPx: Double = 0.0
        for xPx in 0..<widthPx {
            let f = Double(xPx) * xPxToSample
            let i0 = min(n - 1, max(0, Int(f.rounded(.down))))
            let i1 = min(n - 1, i0 + 1)
            let t = f - Double(i0)

            let hPt = mix(Double(denseHeights[i0]), Double(denseHeights[i1]), t)
            let c = clamp01(mix(denseCertainties[i0], denseCertainties[i1], t))

            let hPx = max(0.0, hPt * pxPerPoint)
            heightPxByX[xPx] = hPx
            chanceByX[xPx] = c
            ySurfacePxByX[xPx] = baselineYPx - hPx

            maxHeightPx = max(maxHeightPx, hPx)

            // “Wet” threshold (in pixels). Keeps fuzz from smearing along an empty baseline.
            wetMaskByX[xPx] = hPx > 0.9
        }

        // If there is no rain surface at all, do not draw fuzz.
        if wetMaskByX.allSatisfy({ !$0 }) {
            return nil
        }

        // Distance-to-wet (in x pixels), used to stop fuzz shortly after the last wet segment
        var distToWet = [Int](repeating: Int.max / 4, count: widthPx)

        var lastWet: Int? = nil
        for x in 0..<widthPx {
            if wetMaskByX[x] {
                distToWet[x] = 0
                lastWet = x
            } else if let lw = lastWet {
                distToWet[x] = x - lw
            }
        }

        lastWet = nil
        if widthPx > 1 {
            for x in stride(from: widthPx - 1, through: 0, by: -1) {
                if wetMaskByX[x] {
                    distToWet[x] = 0
                    lastWet = x
                } else if let lw = lastWet {
                    distToWet[x] = min(distToWet[x], lw - x)
                }
            }
        }

        // Band width (in raster pixels)
        let bandBasePxUnclamped = Double(chartRect.height) * pxPerPoint * cfg.fuzzWidthFraction
        let clampMinPx = cfg.fuzzWidthPixelsClamp.lowerBound / Double(rasterScale)
        let clampMaxPx = cfg.fuzzWidthPixelsClamp.upperBound / Double(rasterScale)
        let bandBasePx = max(0.0, min(clampMaxPx, max(clampMinPx, bandBasePxUnclamped)))

        // Strength profile per-x
        var strengthByX = [Double](repeating: 0.0, count: widthPx)
        var bandOutByX = [Double](repeating: bandBasePx, count: widthPx)
        var bandInByX = [Double](repeating: bandBasePx * cfg.fuzzInsideWidthFactor, count: widthPx)

        // Proximity falloff: how far fuzz can “linger” past the wet region
        let proxRadiusPx = max(6.0, Double(widthPx) * 0.090)

        for xPx in 0..<widthPx {
            let chance = chanceByX[xPx]
            var s = fuzzStrengthFromChance(chance, cfg: cfg)

            // Reinforce fuzz at tapered ends (low height) but only if near wet region.
            let hFrac = maxHeightPx > 0.0001 ? clamp01(heightPxByX[xPx] / maxHeightPx) : 0.0
            let lowBoost = fuzzStrengthFromHeight(heightFraction: hFrac, cfg: cfg)
            s = clamp01(s + (1.0 - s) * lowBoost)

            // Kill fuzz far away from wet segments.
            let d = Double(distToWet[xPx])
            let prox = exp(-d / proxRadiusPx)
            s *= prox

            // Apply a floor close to wet only (prevents fully “clean” edges)
            if prox > 0.02 {
                s = max(s, cfg.fuzzChanceMinStrength * prox)
            }

            strengthByX[xPx] = s

            // Slightly widen band where fuzz is stronger (keeps thick parts only where needed)
            bandOutByX[xPx] = bandBasePx * (0.55 + 0.45 * s)
            bandInByX[xPx] = bandBasePx * cfg.fuzzInsideWidthFactor * (0.78 + 0.22 * s)
        }

        // Raster buffers
        var fuzzBytes = [UInt8](repeating: 0, count: widthPx * heightPx * 4)
        var erodeBytes = cfg.fuzzErodeEnabled ? [UInt8](repeating: 0, count: widthPx * heightPx * 4) : []

        // Colour (slight boost to get closer to the mockup’s blue glow)
        var (fuzzR, fuzzG, fuzzB, fuzzA) = rgba(from: cfg.fuzzColor)
        fuzzR = min(1.0, max(0.0, fuzzR * 1.10))
        fuzzG = min(1.0, max(0.0, fuzzG * 1.08))
        fuzzB = min(1.0, max(0.0, fuzzB * 1.18))

        let seed = cfg.noiseSeed
        let microSeed = RainSurfacePRNG.combine(seed, 0x1234_5678_9ABC_DEF0)
        let speckSeed = RainSurfacePRNG.combine(seed, 0x0A1B_2C3D_4E5F_6071)
        let hazeSeed = RainSurfacePRNG.combine(seed, 0x0DDC_0FFE_E0DD_F00D)
        let clumpSeed = RainSurfacePRNG.combine(seed, 0xBADC_0FFE_E0DD_F00D)
        let holeSeed = RainSurfacePRNG.combine(seed, 0xFEED_FACE_CAFE_BEEF)

        let clumpCellPx = max(4.0, cfg.fuzzClumpCellPixels / Double(rasterScale))
        let hazeCellPx = max(6.0, (cfg.fuzzClumpCellPixels * 1.35) / Double(rasterScale))
        let tangentCellPx = max(6.0, (cfg.fuzzClumpCellPixels * 1.75) / Double(rasterScale))

        let clumpCell = max(2, Int(clumpCellPx.rounded()))
        let hazeCell = max(2, Int(hazeCellPx.rounded()))
        let tangentCell = max(2, Int(tangentCellPx.rounded()))

        // Search radius for “nearest surface” (important for vertical sides)
        let searchRadiusPx = max(6, Int((18.0 * pxPerPoint).rounded()))

        for yPx in 0..<heightPx {
            let y = Double(yPx)

            for xPx in 0..<widthPx {
                let sX = strengthByX[xPx]
                if sX <= 0.0005 { continue }

                // Find nearest surface point in a small horizontal neighbourhood
                var bestDist = Double.greatestFiniteMagnitude
                var bestSigned = 0.0

                let x0 = max(0, xPx - searchRadiusPx)
                let x1 = min(widthPx - 1, xPx + searchRadiusPx)

                for xi in x0...x1 {
                    let dx = Double(xi - xPx)
                    let dy = y - ySurfacePxByX[xi]
                    let d = (dx * dx + dy * dy).squareRoot()
                    if d < bestDist {
                        bestDist = d
                        bestSigned = dy
                    }
                }

                let outside = bestSigned <= 0.0
                let band = outside ? bandOutByX[xPx] : bandInByX[xPx]
                if band <= 0.0001 || bestDist > band { continue }

                let u = clamp01(1.0 - bestDist / max(1e-6, band))
                let distPow = outside ? cfg.fuzzDistancePowerOutside : cfg.fuzzDistancePowerInside

                // Edge weighting:
                // - distance power controls the band falloff
                // - edge power tightens brightness closer to the surface
                let bandEdge = pow(u, max(0.01, distPow))
                let tightEdge = pow(u, max(0.01, cfg.fuzzEdgePower))

                // Clump / haze fields (smooth, low frequency)
                let clump = RainSurfacePRNG.valueNoise2D01(x: xPx, y: yPx, cell: clumpCell, seed: clumpSeed)
                let hazeNoise = RainSurfacePRNG.valueNoise2D01(x: xPx, y: yPx, cell: hazeCell, seed: hazeSeed)
                let tangentNoise = RainSurfacePRNG.valueNoise2D01(x: xPx, y: yPx, cell: tangentCell, seed: hazeSeed ^ 0x9E37_79B9_7F4A_7C15)

                // Micro noise (high frequency)
                let micro = RainSurfacePRNG.hash2D01(x: xPx, y: yPx, seed: microSeed)
                let speckN = RainSurfacePRNG.hash2D01(x: xPx, y: yPx, seed: speckSeed)

                // A tiny deterministic “warp” along the tangent direction
                let jitterAmp = (0.15 + 0.85 * sX) * (0.45 + 0.55 * clump)
                let warp = (tangentNoise - 0.5) * 2.0 * jitterAmp

                // Haze component (continuous, glowy)
                var haze = (0.18 + 0.82 * hazeNoise) * (0.62 + 0.38 * clump)
                haze *= (0.80 + 0.20 * micro)
                haze *= cfg.fuzzHazeStrength
                haze *= bandEdge

                // Speck component (sparkly grain)
                let density = clamp01(cfg.fuzzBaseDensity) * (0.70 + 0.30 * clump)
                let threshold = 0.78 - 0.24 * density
                let rawSpeck = clamp01((speckN + 0.10 * warp - threshold) / max(1e-6, 1.0 - threshold))
                var speck = pow(rawSpeck, 2.0) * cfg.fuzzSpeckStrength
                speck *= tightEdge

                // Outside vs inside shaping
                var baseA = cfg.fuzzMaxOpacity * sX * fuzzA
                if !outside {
                    baseA *= cfg.fuzzInsideOpacityFactor
                    speck *= cfg.fuzzInsideSpeckleFraction
                }

                // Final alpha (cap at 1)
                let alpha = clamp01(baseA * (haze + speck))

                if alpha > 0.00001 {
                    let idx = (yPx * widthPx + xPx) * 4
                    let a8 = UInt8((alpha * 255.0).rounded())

                    let pr = UInt8((clamp01(fuzzR * alpha) * 255.0).rounded())
                    let pg = UInt8((clamp01(fuzzG * alpha) * 255.0).rounded())
                    let pb = UInt8((clamp01(fuzzB * alpha) * 255.0).rounded())

                    fuzzBytes[idx + 0] = pr
                    fuzzBytes[idx + 1] = pg
                    fuzzBytes[idx + 2] = pb
                    fuzzBytes[idx + 3] = a8
                }

                // Erode mask (continuous cut-out inside the edge band, so the solid surface disappears)
                if cfg.fuzzErodeEnabled, !outside {
                    let eU = clamp01(1.0 - bestDist / max(1e-6, band))
                    let eEdge = pow(eU, max(0.01, cfg.fuzzErodeEdgePower))
                    var e = cfg.fuzzErodeStrength * eEdge * (0.62 + 0.38 * clump)

                    // Add “holes” so the edge dissolves into grain instead of a clean fade
                    let hole = RainSurfacePRNG.hash2D01(x: xPx, y: yPx, seed: holeSeed)
                    e += 0.22 * cfg.fuzzErodeStrength * pow(hole, 6.0) * eEdge

                    let eAlpha = clamp01(e)
                    if eAlpha > 0.00001 {
                        let idx = (yPx * widthPx + xPx) * 4
                        let a8 = UInt8((eAlpha * 255.0).rounded())
                        erodeBytes[idx + 0] = a8
                        erodeBytes[idx + 1] = a8
                        erodeBytes[idx + 2] = a8
                        erodeBytes[idx + 3] = a8
                    }
                }
            }
        }

        guard let fuzzImage = makeImage(
            widthPx: widthPx,
            heightPx: heightPx,
            bytesRGBA: fuzzBytes,
            scale: displayScale / CGFloat(rasterScale)
        ) else {
            return nil
        }

        let erodeImage: Image? = {
            guard cfg.fuzzErodeEnabled else { return nil }
            return makeImage(
                widthPx: widthPx,
                heightPx: heightPx,
                bytesRGBA: erodeBytes,
                scale: displayScale / CGFloat(rasterScale)
            )
        }()

        return RasterBuildResult(
            fuzzImage: fuzzImage,
            erodeImage: erodeImage,
            bandBasePx: bandBasePx,
            rasterScale: rasterScale
        )
    }

    // MARK: - Strength mapping

    private static func fuzzStrengthFromChance(_ chance: Double, cfg: RainForecastSurfaceConfiguration) -> Double {
        let t = clamp01(cfg.fuzzChanceThreshold)
        let w = max(1e-6, cfg.fuzzChanceTransition)

        // Under threshold => fuzzy; above threshold => clean.
        // Smooth transition around the threshold.
        let lo = t - w * 0.5
        let hi = t + w * 0.5

        if chance <= lo { return 1.0 }
        if chance >= hi { return 0.0 }

        let u = (hi - chance) / (hi - lo) // chance ↑ => u ↓
        return smoothstep01(u)
    }

    private static func fuzzStrengthFromHeight(heightFraction: Double, cfg: RainForecastSurfaceConfiguration) -> Double {
        let h = clamp01(heightFraction)
        let k = pow(1.0 - h, max(0.01, cfg.fuzzLowHeightPower))
        return clamp01(k * cfg.fuzzLowHeightBoost)
    }

    // MARK: - Utilities

    private static func alignToPixelCenter(_ y: CGFloat, displayScale: CGFloat) -> CGFloat {
        let s = max(1.0, displayScale)
        return (floor(y * s) + 0.5) / s
    }

    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private static func clamp01(_ x: Double) -> Double {
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }

    private static func smoothstep01(_ x: Double) -> Double {
        let t = clamp01(x)
        return t * t * (3.0 - 2.0 * t)
    }

    private static func rgba(from color: Color) -> (Double, Double, Double, Double) {
        #if canImport(UIKit)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #elseif canImport(AppKit)
        let ns = NSColor(color)
        let c = ns.usingColorSpace(.deviceRGB) ?? ns
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
        #else
        return (1.0, 1.0, 1.0, 1.0)
        #endif
    }

    private static func makeImage(
        widthPx: Int,
        heightPx: Int,
        bytesRGBA: [UInt8],
        scale: CGFloat
    ) -> Image? {
        guard widthPx > 0, heightPx > 0 else { return nil }

        let data = Data(bytesRGBA)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitsPerComponent = 8
        let bitsPerPixel = 32
        let bytesPerRow = widthPx * 4

        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )

        guard let cg = CGImage(
            width: widthPx,
            height: heightPx,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else {
            return nil
        }

        return Image(decorative: cg, scale: scale)
    }
}
