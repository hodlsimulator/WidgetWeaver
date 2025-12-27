//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

enum RainSurfaceDrawing {

    static func drawSurface(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        certainties: [Double],
        corePath: Path,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard chartRect.width > 1, chartRect.height > 1 else { return }
        guard !heights.isEmpty else { return }

        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)
        let maxHeight = max(heights.max() ?? 0, onePixel)

        drawCore(
            in: &context,
            corePath: corePath,
            topEdgePath: topEdgePath,
            configuration: configuration,
            displayScale: displayScale
        )

        if configuration.canEnableFuzz {
            drawFuzzBandRaster(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                certainties: certainties,
                maxHeight: maxHeight,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        if configuration.rimEnabled {
            drawRim(
                in: &context,
                topEdgePath: topEdgePath,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        if configuration.glintEnabled {
            drawGlints(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                maxHeight: maxHeight,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }
    }

    // MARK: - Fuzz (bounded surface band, raster, inside + outside, plus core-edge erosion)

    private static func drawFuzzBandRaster(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        certainties: [Double],
        maxHeight: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard chartRect.width > 2, chartRect.height > 2 else { return }
        guard heights.count >= 2 else { return }

        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let desiredPx = Double(chartRect.height * configuration.fuzzWidthFraction * scale)
        let clampedPx = RainSurfaceMath.clamp(
            desiredPx,
            min: configuration.fuzzWidthPixelsClamp.lowerBound,
            max: configuration.fuzzWidthPixelsClamp.upperBound
        )
        let bandPoints = CGFloat(clampedPx / Double(scale))
        if bandPoints <= onePixel { return }

        let clipH = max(onePixel, baselineY - chartRect.minY)
        let clipRect = CGRect(x: chartRect.minX, y: chartRect.minY, width: chartRect.width, height: clipH)

        let maxPixels = max(24_000, configuration.fuzzRasterMaxPixels)
        let areaPoints = max(1.0, Double(clipRect.width * clipRect.height))
        let maxScaleBudget = sqrt(Double(maxPixels) / areaPoints)
        let rasterScale = CGFloat(max(0.45, min(Double(scale), maxScaleBudget)))

        let w = max(2, Int(ceil(chartRect.width * rasterScale)))
        let h = max(2, Int(ceil(chartRect.height * rasterScale)))

        let baselinePx = Double((baselineY - chartRect.minY) * rasterScale)
        let yMax = max(1, min(h, Int(floor(baselinePx))))

        let bandPxBase = Double(bandPoints * rasterScale)
        if bandPxBase <= 1.0 { return }

        let insideWidthFactor = RainSurfaceMath.clamp(configuration.fuzzInsideWidthFactor, min: 0.10, max: 1.00)
        let insideOpacityFactor = RainSurfaceMath.clamp(configuration.fuzzInsideOpacityFactor, min: 0.0, max: 1.0)
        let insideSpeckleFrac = RainSurfaceMath.clamp(configuration.fuzzInsideSpeckleFraction, min: 0.0, max: 1.0)

        let maxOpacity = RainSurfaceMath.clamp(configuration.fuzzMaxOpacity, min: 0.02, max: 0.75)
        let baseDensity = RainSurfaceMath.clamp(configuration.fuzzBaseDensity, min: 0.05, max: 0.995)

        let uncertaintyFloor = RainSurfaceMath.clamp(configuration.fuzzUncertaintyFloor, min: 0.0, max: 0.95)
        let uncertaintyExponent = RainSurfaceMath.clamp(configuration.fuzzUncertaintyExponent, min: 0.35, max: 7.0)

        let chanceThreshold = RainSurfaceMath.clamp01(configuration.fuzzChanceThreshold)
        let chanceTransition = max(0.000_001, configuration.fuzzChanceTransition)
        let chanceMinStrength = RainSurfaceMath.clamp(configuration.fuzzChanceMinStrength, min: 0.0, max: 1.0)

        let lowHeightPower = max(0.8, configuration.fuzzLowHeightPower)
        let lowHeightBoost = RainSurfaceMath.clamp(configuration.fuzzLowHeightBoost, min: 0.0, max: 1.6)

        let edgePower = max(0.20, configuration.fuzzEdgePower)
        let hazeStrength = RainSurfaceMath.clamp(configuration.fuzzHazeStrength, min: 0.0, max: 2.0)
        let speckStrength = RainSurfaceMath.clamp(configuration.fuzzSpeckStrength, min: 0.0, max: 2.0)

        let speckEdgeOutPow = RainSurfaceMath.clamp(configuration.fuzzDistancePowerOutside, min: 1.0, max: 4.0)
        let speckEdgeInPow = RainSurfaceMath.clamp(configuration.fuzzDistancePowerInside, min: 1.0, max: 4.0)

        let erodeEnabled = configuration.fuzzErodeEnabled
        let erodeStrength = RainSurfaceMath.clamp(configuration.fuzzErodeStrength, min: 0.0, max: 1.0)
        let erodeEdgePower = max(0.60, configuration.fuzzErodeEdgePower)

        let clumpCell = max(2.0, configuration.fuzzClumpCellPixels)

        let seed = configuration.noiseSeed
        let sizeSalt = RainSurfacePRNG.combine(
            UInt64(w) &* 0x9E3779B97F4A7C15,
            UInt64(h) &* 0xD6E8FEB86659FD93
        )
        let baseSeed = RainSurfacePRNG.combine(seed, sizeSalt)
        let seedClump = RainSurfacePRNG.combine(baseSeed, 0xA71D6A4F3FDC5A19)
        let seedFine = RainSurfacePRNG.combine(baseSeed, 0xC6BC279692B5C323)
        let seedFine2 = RainSurfacePRNG.combine(baseSeed, 0xD1B54A32D192ED03)

        let rgb = rgbComponents(from: configuration.fuzzColor, fallback: (r: 13, g: 82, b: 255))

        let n = heights.count
        let maxHeightSafe = max(maxHeight, onePixel)

        var ySurfacePxByX = [Double](repeating: 0.0, count: w)
        var strengthByX = [Double](repeating: 0.0, count: w)
        var erodeByX = [Double](repeating: 0.0, count: w)
        var bandOutByX = [Double](repeating: bandPxBase, count: w)
        var bandInByX = [Double](repeating: bandPxBase * insideWidthFactor, count: w)

        for x in 0..<w {
            let t = (w <= 1) ? 0.0 : (Double(x) / Double(w - 1))
            let idxF = t * Double(n - 1)
            let i0 = max(0, min(n - 2, Int(floor(idxF))))
            let i1 = i0 + 1
            let frac = idxF - Double(i0)

            let hPt = Double(RainSurfaceMath.lerp(heights[i0], heights[i1], CGFloat(frac)))
            let chance0 = (i0 < certainties.count) ? RainSurfaceMath.clamp01(certainties[i0]) : 1.0
            let chance1 = (i1 < certainties.count) ? RainSurfaceMath.clamp01(certainties[i1]) : chance0
            let chance = RainSurfaceMath.clamp01(RainSurfaceMath.lerp(chance0, chance1, frac))

            let lowH = 1.0 - RainSurfaceMath.clamp01(hPt / Double(maxHeightSafe))
            let lowBoost = pow(max(0.0, lowH), lowHeightPower) * lowHeightBoost

            let legacyUncertainty = pow(
                RainSurfaceMath.clamp01(uncertaintyFloor + (1.0 - uncertaintyFloor) * (1.0 - chance)),
                uncertaintyExponent
            )

            let threshFuzz = fuzzStrengthFromChance(
                chance: chance,
                threshold: chanceThreshold,
                transition: chanceTransition
            )

            var s = max(chanceMinStrength, max(legacyUncertainty, threshFuzz))
            s = max(s, lowBoost)
            s = RainSurfaceMath.clamp01(s)

            strengthByX[x] = s

            let widthMod = (0.85 + 1.15 * s) * (0.80 + 0.55 * lowH)
            let outW = max(1.0, bandPxBase * widthMod)
            bandOutByX[x] = outW
            bandInByX[x] = max(1.0, outW * insideWidthFactor)

            if erodeEnabled && erodeStrength > 0.001 {
                let ek = erodeStrength * (0.25 + 0.75 * s)
                erodeByX[x] = RainSurfaceMath.clamp01(ek)
            } else {
                erodeByX[x] = 0.0
            }

            let ySurfacePoints = baselineY - CGFloat(hPt)
            ySurfacePxByX[x] = Double((ySurfacePoints - chartRect.minY) * rasterScale)
        }

        var fuzzBytes = [UInt8](repeating: 0, count: w * h * 4)
        var erodeBytes = [UInt8](repeating: 0, count: w * h * 4)

        var hasAnyFuzz = false
        var hasAnyErode = false

        for y in 0..<yMax {
            for x in 0..<w {
                let ySurface = ySurfacePxByX[x]
                let dy = Double(y) - ySurface
                let inside = dy >= 0.0

                let dist = abs(dy)
                let band = inside ? bandInByX[x] : bandOutByX[x]
                if dist > band { continue }

                let u = max(0.0, 1.0 - (dist / max(1e-6, band)))
                if u <= 0.0 { continue }

                let s = strengthByX[x]
                if s <= 0.0005 { continue }

                let edge = pow(u, edgePower)

                let clump = RainSurfacePRNG.valueNoise2D01(
                    x: Double(x),
                    y: Double(y),
                    cell: clumpCell,
                    seed: seedClump
                )
                let r0 = RainSurfacePRNG.hash2D01(x: x, y: y, seed: seedFine)
                let r1 = RainSurfacePRNG.hash2D01(x: x &+ 17, y: y &+ 31, seed: seedFine2)

                let sCurve = pow(max(0.0, s), 0.92)

                let sideOpacity = inside ? (maxOpacity * insideOpacityFactor) : maxOpacity
                let sideHazeMul = inside ? 1.08 : 1.0
                let sideSpeckMul = inside ? (insideSpeckleFrac * insideOpacityFactor) : 1.0

                var alpha = 0.0

                // Continuous haze (this is the “surface is made of fuzz” base layer).
                alpha += sideOpacity
                    * sCurve
                    * edge
                    * (0.090 + 0.260 * hazeStrength * sideHazeMul * (0.50 + 0.50 * clump))

                // Speckles: grain sits inside the haze and provides structure.
                let speckEdgePow = inside ? speckEdgeInPow : speckEdgeOutPow
                let speckEdge = pow(u, speckEdgePow)
                let speckPos = 0.25 + 0.75 * speckEdge

                var speckProb = baseDensity
                    * speckStrength
                    * sideSpeckMul
                    * sCurve
                    * speckPos
                    * (0.55 + 0.45 * clump)

                speckProb = min(speckProb, 0.82)

                if r0 < speckProb {
                    alpha += sideOpacity
                        * sCurve
                        * edge
                        * (0.65 + 0.35 * r1)
                        * (0.70 + 0.30 * clump)
                }

                // Occasional extra haze clumps.
                let hazeProb = baseDensity
                    * hazeStrength
                    * sCurve
                    * edge
                    * 0.12
                    * (0.50 + 0.50 * clump)

                if r1 < hazeProb {
                    alpha += sideOpacity
                        * sCurve
                        * edge
                        * 0.22
                        * (0.35 + 0.65 * r0)
                }

                alpha = min(alpha, sideOpacity)

                if alpha > 0.001 {
                    let idx = y * w + x
                    let o = idx * 4
                    fuzzBytes[o + 0] = UInt8(min(255.0, (Double(rgb.r) * alpha).rounded()))
                    fuzzBytes[o + 1] = UInt8(min(255.0, (Double(rgb.g) * alpha).rounded()))
                    fuzzBytes[o + 2] = UInt8(min(255.0, (Double(rgb.b) * alpha).rounded()))
                    fuzzBytes[o + 3] = UInt8(min(255.0, (alpha * 255.0).rounded()))
                    hasAnyFuzz = true
                }

                // Core-edge erosion mask (inside only).
                if erodeEnabled && inside {
                    let ek = erodeByX[x]
                    if ek > 0.0005 {
                        let erodeEdge = pow(u, erodeEdgePower)

                        // Continuous soft erosion keeps the anti-aliased edge from reading as “clean”.
                        var maskAlpha = ek * erodeEdge * (0.18 + 0.10 * clump)

                        // Hole bursts: these create the broken, fuzzy boundary that fuzz fills.
                        let holeProb = min(
                            1.0,
                            ek * erodeEdge * baseDensity * (0.35 + 0.45 * clump)
                        )

                        if r1 < holeProb {
                            maskAlpha += ek * erodeEdge * (0.35 + 0.65 * r0)
                        }

                        maskAlpha = RainSurfaceMath.clamp01(maskAlpha)

                        if maskAlpha > 0.001 {
                            let idx = y * w + x
                            let o = idx * 4
                            erodeBytes[o + 0] = 255
                            erodeBytes[o + 1] = 255
                            erodeBytes[o + 2] = 255
                            erodeBytes[o + 3] = UInt8(min(255.0, (maskAlpha * 255.0).rounded()))
                            hasAnyErode = true
                        }
                    }
                }
            }
        }

        if hasAnyErode, let erodeCG = makeCGImageRGBA(bytes: erodeBytes, width: w, height: h) {
            context.drawLayer { layer in
                layer.blendMode = .destinationOut
                layer.clip(to: Path(chartRect))
                layer.clip(to: Path(clipRect))
                let img = Image(decorative: erodeCG, scale: rasterScale, orientation: .up)
                layer.draw(img, in: chartRect)
            }
        }

        if hasAnyFuzz, let fuzzCG = makeCGImageRGBA(bytes: fuzzBytes, width: w, height: h) {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.clip(to: Path(chartRect))
                layer.clip(to: Path(clipRect))

                let blurPoints = CGFloat(configuration.fuzzMicroBlurPixels / Double(scale))
                if blurPoints > 0.01 {
                    layer.addFilter(.blur(radius: blurPoints))
                }

                let img = Image(decorative: fuzzCG, scale: rasterScale, orientation: .up)
                layer.draw(img, in: chartRect)
            }
        }
    }

    private static func fuzzStrengthFromChance(chance: Double, threshold: Double, transition: Double) -> Double {
        // Returns 1 below threshold, 0 above, with smooth transition band.
        let t = RainSurfaceMath.clamp01(threshold)
        let w = max(0.000_001, transition)
        let t0 = RainSurfaceMath.clamp01(t - w)
        let t1 = RainSurfaceMath.clamp01(t + w)
        let u = RainSurfaceMath.clamp01((chance - t0) / max(1e-9, (t1 - t0)))
        let s = RainSurfaceMath.smoothstep01(u) // 0..1
        return 1.0 - s
    }

    // MARK: - Core / Rim / Glints / Baseline

    private static func drawCore(
        in context: inout GraphicsContext,
        corePath: Path,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        context.fill(corePath, with: .color(configuration.coreBodyColor.opacity(1.0)))

        if configuration.glossEnabled {
            let depthPx = RainSurfaceMath.clamp(
                (configuration.glossDepthPixels.lowerBound + configuration.glossDepthPixels.upperBound) * 0.5,
                min: configuration.glossDepthPixels.lowerBound,
                max: configuration.glossDepthPixels.upperBound
            )
            let depth = CGFloat(depthPx / scale)

            let opacity = RainSurfaceMath.clamp(configuration.glossMaxOpacity, min: 0.0, max: 1.0)

            let shiftY = max(onePixel, depth * 0.33)
            let bandPath = topEdgePath.applying(CGAffineTransform(translationX: 0, y: shiftY))
            let bandPath2 = topEdgePath.applying(CGAffineTransform(translationX: 0, y: shiftY + max(onePixel, depth * 0.32)))

            context.drawLayer { layer in
                layer.blendMode = .screen

                if configuration.glossSoftBlurPixels > 0.01 {
                    layer.addFilter(.blur(radius: CGFloat(configuration.glossSoftBlurPixels / Double(scale))))
                }

                layer.stroke(
                    bandPath2,
                    with: .color(configuration.coreTopColor.opacity(opacity * 0.50)),
                    style: StrokeStyle(lineWidth: max(onePixel, depth * 2.35), lineCap: .round, lineJoin: .round)
                )
                layer.stroke(
                    bandPath,
                    with: .color(configuration.coreTopColor.opacity(opacity)),
                    style: StrokeStyle(lineWidth: max(onePixel, depth * 1.45), lineCap: .round, lineJoin: .round)
                )

                layer.blendMode = .destinationIn
                layer.fill(corePath, with: .color(.white))
            }
        }
    }

    private static func drawRim(
        in context: inout GraphicsContext,
        topEdgePath: Path,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let innerW = max(onePixel, CGFloat(configuration.rimInnerWidthPixels / scale))
        let outerW = max(innerW, CGFloat(configuration.rimOuterWidthPixels / scale))

        let innerA = RainSurfaceMath.clamp(configuration.rimInnerOpacity, min: 0.0, max: 1.0)
        let outerA = RainSurfaceMath.clamp(configuration.rimOuterOpacity, min: 0.0, max: 1.0)

        if outerA > 0.0001 && outerW > onePixel {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.stroke(
                    topEdgePath,
                    with: .color(configuration.rimColor.opacity(outerA)),
                    style: StrokeStyle(lineWidth: outerW, lineCap: .round, lineJoin: .round)
                )

                layer.blendMode = .destinationOut
                layer.fill(corePath, with: .color(.white))
            }
        }

        if innerA > 0.0001 {
            context.drawLayer { layer in
                layer.blendMode = .screen
                layer.stroke(
                    topEdgePath,
                    with: .color(configuration.rimColor.opacity(innerA)),
                    style: StrokeStyle(lineWidth: innerW, lineCap: .round, lineJoin: .round)
                )

                layer.blendMode = .destinationIn
                layer.fill(corePath, with: .color(.white))
            }
        }
    }

    private static func drawGlints(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        maxHeight: CGFloat,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let minFrac = RainSurfaceMath.clamp(configuration.glintMinHeightFraction, min: 0.35, max: 0.90)
        let minH = maxHeight * CGFloat(minFrac)

        let peakIndices = localMaximaIndices(
            heights: heights,
            minHeight: minH,
            maxCount: max(0, configuration.glintMaxCount),
            minSeparationPoints: max(onePixel * 10, chartRect.width * 0.08),
            stepX: stepX
        )

        guard !peakIndices.isEmpty else { return }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            if configuration.glintBlurPixels > 0.01 {
                layer.addFilter(.blur(radius: CGFloat(configuration.glintBlurPixels / Double(scale))))
            }

            for idx in peakIndices {
                let h = heights[idx]
                let x = chartRect.minX + (CGFloat(idx) + 0.5) * stepX
                let y = baselineY - h

                let w0 = max(onePixel * 7.0, onePixel * 9.0)
                let h0 = max(onePixel * 1.2, onePixel * 1.6)
                let rect0 = CGRect(x: x - w0 * 0.5, y: y - h0 * 0.6, width: w0, height: h0)

                layer.fill(
                    Path(roundedRect: rect0, cornerRadius: h0 * 0.5),
                    with: .color(configuration.glintColor.opacity(configuration.glintMaxOpacity * 0.52))
                )

                let w1 = max(onePixel * 4.0, onePixel * 5.5)
                let h1 = max(onePixel * 0.9, onePixel * 1.2)
                let rect1 = CGRect(x: x - w1 * 0.5, y: y - h1 * 0.6, width: w1, height: h1)

                layer.fill(
                    Path(roundedRect: rect1, cornerRadius: h1 * 0.5),
                    with: .color(configuration.glintColor.opacity(configuration.glintMaxOpacity))
                )
            }

            layer.blendMode = .destinationIn
            layer.fill(corePath, with: .color(.white))
        }
    }

    private static func localMaximaIndices(
        heights: [CGFloat],
        minHeight: CGFloat,
        maxCount: Int,
        minSeparationPoints: CGFloat,
        stepX: CGFloat
    ) -> [Int] {
        guard heights.count >= 3, maxCount > 0 else { return [] }

        var peaks: [(idx: Int, h: CGFloat)] = []
        peaks.reserveCapacity(8)

        for i in 1..<(heights.count - 1) {
            let a = heights[i - 1]
            let b = heights[i]
            let c = heights[i + 1]
            if b >= minHeight && b > a && b >= c {
                peaks.append((i, b))
            }
        }

        guard !peaks.isEmpty else { return [] }

        peaks.sort { $0.h > $1.h }

        var chosen: [Int] = []
        chosen.reserveCapacity(min(maxCount, peaks.count))

        for p in peaks {
            if chosen.count >= maxCount { break }
            let xP = CGFloat(p.idx) * stepX
            let tooClose = chosen.contains { j in
                abs(CGFloat(j) * stepX - xP) < minSeparationPoints
            }
            if !tooClose {
                chosen.append(p.idx)
            }
        }

        return chosen
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard chartRect.width > 1 else { return }

        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let x0 = chartRect.minX
        let x1 = chartRect.maxX

        let fadeFrac = RainSurfaceMath.clamp(configuration.baselineEndFadeFraction, min: 0.03, max: 0.08)
        let fadeW = max(onePixel, chartRect.width * fadeFrac)

        let leftStop = min(1.0, Double(fadeW / chartRect.width))
        let rightStop = max(0.0, 1.0 - Double(fadeW / chartRect.width))

        let gradient = Gradient(stops: [
            .init(color: .white.opacity(0.0), location: 0.0),
            .init(color: .white.opacity(1.0), location: leftStop),
            .init(color: .white.opacity(1.0), location: rightStop),
            .init(color: .white.opacity(0.0), location: 1.0)
        ])

        let alphaMask = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: x0, y: baselineY),
            endPoint: CGPoint(x: x1, y: baselineY)
        )

        var line = Path()
        line.move(to: CGPoint(x: x0, y: baselineY))
        line.addLine(to: CGPoint(x: x1, y: baselineY))

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            let base = RainSurfaceMath.clamp(configuration.baselineLineOpacity, min: 0.05, max: 0.60)

            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.08)),
                style: StrokeStyle(lineWidth: onePixel * 6.0, lineCap: .round)
            )
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.16)),
                style: StrokeStyle(lineWidth: onePixel * 3.2, lineCap: .round)
            )
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base)),
                style: StrokeStyle(lineWidth: onePixel * 0.85, lineCap: .butt)
            )

            layer.blendMode = .destinationIn
            var fadeRect = Path()
            fadeRect.addRect(chartRect)
            layer.fill(fadeRect, with: alphaMask)
        }
    }

    // MARK: - Utilities

    private static func rgbComponents(from color: Color, fallback: (r: UInt8, g: UInt8, b: UInt8)) -> (r: UInt8, g: UInt8, b: UInt8) {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (
                r: UInt8(RainSurfaceMath.clamp(r, min: 0, max: 1) * 255.0),
                g: UInt8(RainSurfaceMath.clamp(g, min: 0, max: 1) * 255.0),
                b: UInt8(RainSurfaceMath.clamp(b, min: 0, max: 1) * 255.0)
            )
        }
        #endif
        return fallback
    }

    private static func makeCGImageRGBA(bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}
