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
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

enum RainSurfaceDrawing {
    // MARK: - Surface (fuzz + core + rim + optional glints)

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

        // (2) Fuzz layer: granular mist outside core only; additive.
        if configuration.fuzzEnabled {
            drawFuzz(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                certainties: certainties,
                maxHeight: maxHeight,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // (3) Core layer: opaque solid fill + inside-only gloss band.
        drawCore(
            in: &context,
            chartRect: chartRect,
            baselineY: baselineY,
            maxHeight: maxHeight,
            corePath: corePath,
            topEdgePath: topEdgePath,
            configuration: configuration,
            displayScale: displayScale
        )

        // Crisp rim (inner edge + outer halo).
        if configuration.rimEnabled {
            drawRim(
                in: &context,
                topEdgePath: topEdgePath,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // (4) Optional tiny local glints near local maxima.
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

    // MARK: - Fuzz (granular, outside-only, dense near boundary)

    private static func drawFuzz(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        certainties: [Double],
        maxHeight: CGFloat,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard chartRect.width > 2, chartRect.height > 2 else { return }

        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        // fuzzWidth ≈ fraction of chart height, clamped in pixels at displayScale.
        let desiredPx = Double(chartRect.height * configuration.fuzzWidthFraction * scale)
        let clampedPx = RainSurfaceMath.clamp(
            desiredPx,
            min: configuration.fuzzWidthPixelsClamp.lowerBound,
            max: configuration.fuzzWidthPixelsClamp.upperBound
        )
        let fuzzWidthPoints = CGFloat(clampedPx / scale)
        if fuzzWidthPoints <= onePixel { return }

        // Raster scale for fuzz: bounded by a hard pixel budget (widget safe).
        let maxPixels = max(40_000, configuration.fuzzRasterMaxPixels)
        let areaPoints = max(1.0, Double(chartRect.width * chartRect.height))
        let maxScaleBudget = sqrt(Double(maxPixels) / areaPoints)
        let rasterScale = CGFloat(max(0.55, min(Double(scale), maxScaleBudget)))

        let w = max(2, Int(ceil(chartRect.width * rasterScale)))
        let h = max(2, Int(ceil(chartRect.height * rasterScale)))

        // Rasterise the core to an 8-bit mask.
        guard let coreMask = rasterizeMask(
            path: corePath,
            rect: chartRect,
            rasterScale: rasterScale,
            width: w,
            height: h
        ) else { return }

        // Outside distance field (chamfer 3/4).
        let dist = chamferDistanceTransformOutside(
            mask: coreMask,
            width: w,
            height: h,
            insideThreshold: configuration.fuzzInsideThreshold
        )

        let baselinePx = Int(round((baselineY - chartRect.minY) * rasterScale))
        if baselinePx <= 1 { return }

        let fuzzWidthPx = Double(fuzzWidthPoints * rasterScale)
        if fuzzWidthPx <= 1.0 { return }

        let maxOpacity = RainSurfaceMath.clamp(configuration.fuzzMaxOpacity, min: 0.02, max: 0.50)
        let baseDensity = RainSurfaceMath.clamp(configuration.fuzzBaseDensity, min: 0.10, max: 0.98)
        let uncertaintyFloor = RainSurfaceMath.clamp(configuration.fuzzUncertaintyFloor, min: 0.0, max: 0.70)
        let edgePower = max(0.25, configuration.fuzzEdgePower)

        let hazeStrength = RainSurfaceMath.clamp(configuration.fuzzHazeStrength, min: 0.0, max: 1.0)
        let speckStrength = RainSurfaceMath.clamp(configuration.fuzzSpeckStrength, min: 0.0, max: 1.25)

        let lowHeightPower = max(0.6, configuration.fuzzLowHeightPower)

        // Deterministic seed mixed with size for stability across widget families/sizes.
        let seed = configuration.noiseSeed
        let sizeSalt = RainSurfacePRNG.combine(UInt64(w) &* 0x9E3779B97F4A7C15, UInt64(h) &* 0xD6E8FEB86659FD93)
        let baseSeed = RainSurfacePRNG.combine(seed, sizeSalt)

        let seedClump = RainSurfacePRNG.combine(baseSeed, 0xA71D6A4F3FDC5A19)
        let seedFine = RainSurfacePRNG.combine(baseSeed, 0xC6BC279692B5C323)
        let seedSpeck = RainSurfacePRNG.combine(baseSeed, 0x3B4B0F6F9A1B2C77)
        let seedSpeckAmp = RainSurfacePRNG.combine(baseSeed, 0x9E3779B97F4A7C15)

        // Colour components (blue-only; avoid grey haze).
        let rgb = rgbComponents(from: configuration.fuzzColor, fallback: (r: 13, g: 82, b: 255))

        // Precompute certainty/slope/height per x in raster space.
        let n = max(2, heights.count)
        var idxByX = [Int](repeating: 0, count: w)
        var certaintyByX = [Double](repeating: 1.0, count: w)
        var slopeByX = [Double](repeating: 0.0, count: w)
        var curveHeightNormByX = [Double](repeating: 0.0, count: w)

        for x in 0..<w {
            // Map raster x -> bin index in the dense series.
            let t = (Double(x) + 0.5) / Double(w)
            let i = min(n - 1, max(0, Int(floor(t * Double(n)))))
            idxByX[x] = i

            let c = (i < certainties.count) ? certainties[i] : (certainties.last ?? 1.0)
            certaintyByX[x] = RainSurfaceMath.clamp01(c)

            let ip = max(0, i - 1)
            let inx = min(n - 1, i + 1)
            let dy = Double(abs(heights[inx] - heights[ip])) * Double(rasterScale)
            let dx = max(1.0, Double(inx - ip) * Double(stepX) * Double(rasterScale))
            slopeByX[x] = RainSurfaceMath.clamp01((dy / dx) * 0.95)

            curveHeightNormByX[x] = RainSurfaceMath.clamp01(Double(heights[i] / maxHeight))
        }

        let maxHeightPx = max(1.0, Double(maxHeight) * Double(rasterScale))
        let yMax = min(h, baselinePx)

        var rgba = [UInt8](repeating: 0, count: w * h * 4)

        // Build the mist. This is intentionally per-pixel, not spawned circles.
        for y in 0..<yMax {
            let yD = Double(y)

            for x in 0..<w {
                let idx = y * w + x

                // Outside-only.
                if coreMask[idx] > configuration.fuzzInsideThreshold { continue }

                // Distance to the core in (approx) pixels.
                let d = Double(dist[idx]) / 3.0
                if d <= 0.0001 { continue }

                // Low-height bias based on the curve height at this x.
                let hNormCurve = curveHeightNormByX[x]
                let lowHeight = pow(max(0.0, 1.0 - hNormCurve), lowHeightPower)

                // Make the fuzz envelope thinner near crests, wider near baseline/shoulders.
                let widthFactor = 0.55 + 0.95 * lowHeight
                let effectiveWidth = fuzzWidthPx * widthFactor
                if d > effectiveWidth { continue }

                let t = RainSurfaceMath.clamp01(d / max(1e-6, effectiveWidth))
                let edge = pow(max(0.0, 1.0 - t), edgePower)

                // Certainty -> uncertainty (kept gentle; avoids “grey” confidence haze).
                let certainty = certaintyByX[x]
                let uncertainty = RainSurfaceMath.clamp01(uncertaintyFloor + (1.0 - uncertaintyFloor) * (1.0 - certainty))

                // Slope bias (stronger on sides; still present on gentle slopes).
                let slope = slopeByX[x]
                let slopeBias = 0.72 + 0.28 * slope

                // Clumped haze field (low frequency) + fine grain.
                let clumpCell = max(6.0, configuration.fuzzClumpCellPixels)
                let clump = RainSurfacePRNG.valueNoise2D01(
                    x: Double(x),
                    y: yD,
                    cell: clumpCell,
                    seed: seedClump
                )
                let fine = RainSurfacePRNG.hash2D01(x: x, y: y, seed: seedFine)

                // Continuous haze component: dense near edge, granular via noise modulation.
                var alpha = 0.0
                if hazeStrength > 0.0001 {
                    let hazeNoise = 0.30 + 0.70 * pow(fine, 2.2)
                    let hazeAmp = 0.55 + 0.45 * clump
                    let a = maxOpacity
                        * hazeStrength
                        * edge
                        * (0.45 + 0.55 * uncertainty)
                        * slopeBias
                        * (0.22 + 0.78 * hazeNoise)
                        * (0.55 + 0.45 * hazeAmp)
                    alpha += a
                }

                // Bright speck component: sparser flecks that read as “mist” at widget scale.
                if speckStrength > 0.0001 {
                    let p = RainSurfaceMath.clamp01(baseDensity * 0.40 * uncertainty * slopeBias * (0.28 + 0.72 * edge))
                    let r = RainSurfacePRNG.hash2D01(x: x, y: y, seed: seedSpeck)
                    if r < p {
                        let amp = RainSurfacePRNG.hash2D01(x: x, y: y, seed: seedSpeckAmp)
                        let a = maxOpacity
                            * speckStrength
                            * edge * edge
                            * (0.38 + 0.62 * amp)
                            * (0.60 + 0.40 * uncertainty)
                        alpha += a
                    }
                }

                if alpha <= 0.0005 { continue }
                alpha = min(alpha, maxOpacity)

                let o = idx * 4
                rgba[o + 0] = UInt8(min(255.0, Double(rgb.r) * alpha))
                rgba[o + 1] = UInt8(min(255.0, Double(rgb.g) * alpha))
                rgba[o + 2] = UInt8(min(255.0, Double(rgb.b) * alpha))
                rgba[o + 3] = UInt8(min(255.0, alpha * 255.0))
            }
        }

        guard let cgImage = makeCGImageRGBA(bytes: rgba, width: w, height: h) else { return }
        let image = Image(decorative: cgImage, scale: 1.0)

        // Draw additively, clipped above the baseline.
        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            var clip = Path()
            clip.addRect(CGRect(x: chartRect.minX, y: chartRect.minY, width: chartRect.width, height: max(0, baselineY - chartRect.minY)))
            layer.clip(to: clip)

            layer.draw(image, in: chartRect)
        }
    }

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
        return fallback
        #else
        return fallback
        #endif
    }

    private static func rasterizeMask(
        path: Path,
        rect: CGRect,
        rasterScale: CGFloat,
        width: Int,
        height: Int
    ) -> [UInt8]? {
        let count = width * height
        var bytes = [UInt8](repeating: 0, count: count)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bytesPerRow = width

        let ok = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            guard let ctx = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }

            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setFillColor(gray: 1.0, alpha: 1.0)

            // Match SwiftUI's top-left origin / y-down coordinate space.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: rasterScale, y: -rasterScale)

            // Shift rect origin to (0,0) in the mask.
            ctx.translateBy(x: -rect.minX, y: -rect.minY)

            ctx.addPath(path.cgPath)
            ctx.fillPath()

            return true
        }

        return ok ? bytes : nil
    }

    private static func chamferDistanceTransformOutside(
        mask: [UInt8],
        width: Int,
        height: Int,
        insideThreshold: UInt8
    ) -> [UInt16] {
        let count = width * height
        var dist = [UInt16](repeating: UInt16.max, count: count)

        // Inside pixels are sources (distance 0).
        for i in 0..<count {
            if mask[i] > insideThreshold {
                dist[i] = 0
            }
        }

        // Forward pass.
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if dist[i] == 0 { continue }

                var best = Int(dist[i])

                if x > 0 { best = min(best, Int(dist[i - 1]) + 3) }
                if y > 0 {
                    best = min(best, Int(dist[i - width]) + 3)

                    if x > 0 { best = min(best, Int(dist[i - width - 1]) + 4) }
                    if x + 1 < width { best = min(best, Int(dist[i - width + 1]) + 4) }
                }

                dist[i] = UInt16(min(best, Int(UInt16.max)))
            }
        }

        // Backward pass.
        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let i = y * width + x
                if dist[i] == 0 { continue }

                var best = Int(dist[i])

                if x + 1 < width { best = min(best, Int(dist[i + 1]) + 3) }
                if y + 1 < height {
                    best = min(best, Int(dist[i + width]) + 3)

                    if x + 1 < width { best = min(best, Int(dist[i + width + 1]) + 4) }
                    if x > 0 { best = min(best, Int(dist[i + width - 1]) + 4) }
                }

                dist[i] = UInt16(min(best, Int(UInt16.max)))
            }
        }

        return dist
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

    // MARK: - Core (opaque volume + inside-only gloss)

    private static func drawCore(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        maxHeight: CGFloat,
        corePath: Path,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        // Solid fill (no vertical gradient).
        context.fill(corePath, with: .color(configuration.coreBodyColor.opacity(1.0)))

        // Inside-only gloss band:
        // draw a softened band slightly below the top curve (not on the edge) and mask to the core.
        if configuration.glossEnabled {
            let depthPx = RainSurfaceMath.clamp(
                configuration.glossDepthPixels.mid,
                min: configuration.glossDepthPixels.lowerBound,
                max: configuration.glossDepthPixels.upperBound
            )
            let depth = CGFloat(depthPx / scale)
            let opacity = configuration.glossMaxOpacity

            let shiftY = max(onePixel, depth * 0.33)
            let bandPath = topEdgePath.applying(CGAffineTransform(translationX: 0, y: shiftY))
            let bandPath2 = topEdgePath.applying(CGAffineTransform(translationX: 0, y: shiftY + max(onePixel, depth * 0.32)))

            context.drawLayer { layer in
                layer.blendMode = .screen

                // Soft inner skin (wider, fainter).
                layer.stroke(
                    bandPath2,
                    with: .color(configuration.coreTopColor.opacity(opacity * 0.50)),
                    style: StrokeStyle(lineWidth: max(onePixel, depth * 2.35), lineCap: .round, lineJoin: .round)
                )

                // Brighter band (narrower).
                layer.stroke(
                    bandPath,
                    with: .color(configuration.coreTopColor.opacity(opacity)),
                    style: StrokeStyle(lineWidth: max(onePixel, depth * 1.45), lineCap: .round, lineJoin: .round)
                )

                // Mask to core so nothing appears outside the silhouette.
                layer.blendMode = .destinationIn
                layer.fill(corePath, with: .color(.white))
            }
        }
    }

    // MARK: - Rim (crisp surface edge + subtle outer halo)

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

        // Outer halo: outside-only.
        if outerA > 0.0001 && outerW > onePixel {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.stroke(
                    topEdgePath,
                    with: .color(configuration.rimColor.opacity(outerA)),
                    style: StrokeStyle(lineWidth: outerW, lineCap: .round, lineJoin: .round)
                )

                // Keep only the part outside the core.
                layer.blendMode = .destinationOut
                layer.fill(corePath, with: .color(.white))
            }
        }

        // Inner rim: inside-only.
        if innerA > 0.0001 {
            context.drawLayer { layer in
                layer.blendMode = .screen
                layer.stroke(
                    topEdgePath,
                    with: .color(configuration.rimColor.opacity(innerA)),
                    style: StrokeStyle(lineWidth: innerW, lineCap: .round, lineJoin: .round)
                )

                // Keep only the part inside the core.
                layer.blendMode = .destinationIn
                layer.fill(corePath, with: .color(.white))
            }
        }
    }

    // MARK: - Glints (tiny, local maxima only)

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

            for idx in peakIndices {
                let h = heights[idx]
                let x = chartRect.minX + (CGFloat(idx) + 0.5) * stepX
                let y = baselineY - h

                // Tiny, localised apex glint.
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

            // Mask to core.
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
            let tooClose = chosen.contains { j in abs(CGFloat(j) * stepX - xP) < minSeparationPoints }
            if !tooClose { chosen.append(p.idx) }
        }

        return chosen
    }

    // MARK: - Baseline (drawn last)

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

        let alphaMask = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.0), location: 0.0),
                .init(color: .white.opacity(1.0), location: min(1.0, Double(fadeW / chartRect.width))),
                .init(color: .white.opacity(1.0), location: max(0.0, 1.0 - Double(fadeW / chartRect.width))),
                .init(color: .white.opacity(0.0), location: 1.0)
            ]),
            startPoint: CGPoint(x: x0, y: baselineY),
            endPoint: CGPoint(x: x1, y: baselineY)
        )

        var line = Path()
        line.move(to: CGPoint(x: x0, y: baselineY))
        line.addLine(to: CGPoint(x: x1, y: baselineY))

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            let base = RainSurfaceMath.clamp(configuration.baselineLineOpacity, min: 0.05, max: 0.60)

            // Subtle glow stack (kept faint so it never competes with the mound).
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

            // Apply end fade to the whole baseline stack.
            layer.blendMode = .destinationIn
            var fadeRect = Path()
            fadeRect.addRect(chartRect)
            layer.fill(fadeRect, with: alphaMask)
        }
    }
}

private extension ClosedRange where Bound == Double {
    var mid: Double { (lowerBound + upperBound) * 0.5 }
}
