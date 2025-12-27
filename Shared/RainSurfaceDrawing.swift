//
// RainSurfaceDrawing.swift
// WidgetWeaver
//
// Created by . . on 12/23/25.
//
// Rendering helpers for the forecast surface.
//

import Foundation
import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

enum RainSurfaceDrawing {

    // MARK: - Public entry points

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
        let maxHeight = max(heights.max() ?? 0.0, onePixel)

        // Core first so the inside-band fuzz can live below the surface (inside the volume),
        // matching the mock’s “fuzz makes the surface” behaviour.
        drawCore(
            in: &context,
            corePath: corePath,
            topEdgePath: topEdgePath,
            configuration: configuration,
            displayScale: scale
        )

        let fuzzOK =
            configuration.fuzzEnabled
            && configuration.fuzzMaxOpacity > 0.001
            && configuration.fuzzBaseDensity > 0.001
            && configuration.fuzzWidthFraction > 0.001

        if fuzzOK {
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
                displayScale: scale
            )
        }

        if configuration.rimEnabled {
            drawRim(
                in: &context,
                corePath: corePath,
                topEdgePath: topEdgePath,
                configuration: configuration,
                displayScale: scale
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
                configuration: configuration,
                displayScale: scale
            )
        }
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let opacity = RainSurfaceMath.clamp01(configuration.baselineLineOpacity)
        guard opacity > 0.0001 else { return }

        let y = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: scale)

        let fadeFrac = RainSurfaceMath.clamp(configuration.baselineEndFadeFraction, min: 0.0, max: 0.25)
        let leftStop = Double(fadeFrac)
        let rightStop = Double(1.0 - fadeFrac)

        let base = configuration.baselineColor

        let linePath = Path { p in
            p.move(to: CGPoint(x: chartRect.minX, y: y))
            p.addLine(to: CGPoint(x: chartRect.maxX, y: y))
        }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            // Crisp core line + two softer passes to match the mock’s thin baseline with a restrained glow.
            let widthsPx: [CGFloat] = [1.0, 2.2, 5.2]
            let opMul: [Double] = [1.0, 0.45, 0.18]
            let blur: [CGFloat] = [0.0, 0.55, 1.15]

            for i in 0..<3 {
                let w = widthsPx[i] / scale
                let a = RainSurfaceMath.clamp01(opacity * opMul[i])

                layer.drawLayer { l2 in
                    if blur[i] > 0 {
                        l2.addFilter(.blur(radius: blur[i]))
                    }

                    l2.stroke(
                        linePath,
                        with: .linearGradient(
                            Gradient(stops: [
                                .init(color: base.opacity(0.0), location: 0.0),
                                .init(color: base.opacity(a), location: leftStop),
                                .init(color: base.opacity(a), location: rightStop),
                                .init(color: base.opacity(0.0), location: 1.0)
                            ]),
                            startPoint: CGPoint(x: chartRect.minX, y: y),
                            endPoint: CGPoint(x: chartRect.maxX, y: y)
                        ),
                        lineWidth: w
                    )
                }
            }
        }
    }

    // MARK: - Fuzz (signed-distance surface band: above + below)

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
        guard heights.count == certainties.count, heights.count >= 2 else { return }

        let maxOpacity = RainSurfaceMath.clamp01(configuration.fuzzMaxOpacity)
        let baseDensity = max(0.0, configuration.fuzzBaseDensity)
        guard maxOpacity > 0.0001, baseDensity > 0.0001 else { return }

        // Base fuzz band width derived from chart height (in pixels), then clamped.
        let desiredWidthPx = Double(chartRect.height * configuration.fuzzWidthFraction) * Double(displayScale)
        let baseBandWidthPx = RainSurfaceMath.clamp(
            desiredWidthPx,
            min: configuration.fuzzWidthPixelsClamp.lowerBound,
            max: configuration.fuzzWidthPixelsClamp.upperBound
        )

        // Raster scale limited by a pixel budget (keeps it affordable in the extension).
        let rawWPx = Double(chartRect.width * displayScale)
        let rawHPx = Double(chartRect.height * displayScale)
        let rawArea = max(1.0, rawWPx * rawHPx)
        let pixelBudget = max(1, configuration.fuzzRasterMaxPixels)
        let budgetScale = min(1.0, sqrt(Double(pixelBudget) / rawArea))
        let rasterScale = max(1.0, CGFloat(Double(displayScale) * budgetScale))

        let w = max(2, Int(ceil(chartRect.width * rasterScale)))
        let h = max(2, Int(ceil(chartRect.height * rasterScale)))
        let baselinePx = Int(round((baselineY - chartRect.minY) * rasterScale))
        let yMax = max(0, min(h, baselinePx))   // keep background pure black below baseline

        // Per-x surface controls.
        var strengthByX = [Double](repeating: 0.0, count: w)
        var lowHeightByX = [Double](repeating: 0.0, count: w)
        var slopeBiasByX = [Double](repeating: 1.0, count: w)
        var outsideWidthByX = [Double](repeating: 0.0, count: w)
        var insideWidthByX = [Double](repeating: 0.0, count: w)

        let n = heights.count
        let maxHeightSafe = max(maxHeight, 0.000_001)

        let insideWidthFactor = RainSurfaceMath.clamp(configuration.fuzzInsideWidthFactor, min: 0.25, max: 0.95)
        let insideOpacityFactor = RainSurfaceMath.clamp(configuration.fuzzInsideOpacityFactor, min: 0.0, max: 1.0)
        let lowHeightBoost = RainSurfaceMath.clamp(configuration.fuzzLowHeightBoost, min: 0.0, max: 1.0)

        var maxStrength = 0.0

        for x in 0..<w {
            let t = (w <= 1) ? 0.0 : (Double(x) / Double(w - 1))
            let sampleF = t * Double(n - 1)
            let i = min(n - 1, max(0, Int(round(sampleF))))

            let certainty = RainSurfaceMath.clamp01(certainties[i])

            // Uncertainty drives fuzz (low certainty => fuzzier).
            let uncertainty = pow(
                RainSurfaceMath.clamp01((1.0 - certainty) + configuration.fuzzUncertaintyFloor),
                max(0.10, configuration.fuzzUncertaintyExponent)
            )

            // Low height drives fuzz too (ensures tapered ends are always fuzzy).
            let heightNorm = RainSurfaceMath.clamp01(Double(heights[i] / maxHeightSafe))
            let lowHeight = pow(
                RainSurfaceMath.clamp01(1.0 - heightNorm),
                max(0.10, configuration.fuzzLowHeightPower)
            )

            let s = RainSurfaceMath.clamp01(max(uncertainty, lowHeight * lowHeightBoost))

            // Mild slope emphasis (matches inset texture along slopes).
            let i0 = max(0, i - 1)
            let i1 = min(n - 1, i + 1)
            let dy = Double(abs(heights[i1] - heights[i0]))
            let dx = max(0.000_001, Double(i1 - i0) * Double(stepX))
            let slope = RainSurfaceMath.clamp01((dy / dx) * 0.90)
            let slopeBias = 0.72 + 0.28 * slope

            // Band width: bounded and concentrated near the edge, but wide enough at low heights.
            let widthLow = 0.52 + 1.05 * lowHeight
            let widthS = 0.35 + 0.65 * s
            let outsideW = baseBandWidthPx * widthLow * widthS
            let insideW = outsideW * insideWidthFactor * (0.92 + 0.08 * lowHeight)

            strengthByX[x] = s
            lowHeightByX[x] = lowHeight
            slopeBiasByX[x] = slopeBias
            outsideWidthByX[x] = outsideW
            insideWidthByX[x] = insideW

            if s > maxStrength { maxStrength = s }
        }

        guard maxStrength > 0.0008 else { return }

        // Rasterise the filled core as an 8-bit mask.
        let coreMask = rasterizeMask(
            path: corePath,
            rect: chartRect,
            width: w,
            height: h,
            rasterScale: rasterScale,
            baselineY: baselineY,
            insideThreshold: configuration.fuzzInsideThreshold
        )

        // Distance to inside for outside pixels, and distance to outside for inside pixels.
        let distToInside = chamferDistanceTransform(mask: coreMask, width: w, height: h, threshold: configuration.fuzzInsideThreshold, zeroForInside: true)
        let distToOutside = chamferDistanceTransform(mask: coreMask, width: w, height: h, threshold: configuration.fuzzInsideThreshold, zeroForInside: false)

        let (fr, fg, fb, _) = rgbComponents(configuration.fuzzColor)

        let edgePower = max(0.05, configuration.fuzzEdgePower)
        let hazeStrength = RainSurfaceMath.clamp01(configuration.fuzzHazeStrength)
        let speckStrength = RainSurfaceMath.clamp01(configuration.fuzzSpeckStrength)
        let clumpCell = max(1.0, configuration.fuzzClumpCellPixels)

        // Different seeds so haze/speck/clump don’t align.
        let seedA = configuration.noiseSeed
        let seedB = RainSurfacePRNG.combine(configuration.noiseSeed, 0xA5A5_A5A5_A5A5_A5A5)
        let seedC = RainSurfacePRNG.combine(configuration.noiseSeed, 0xC3C3_C3C3_C3C3_C3C3)

        var rgba = [UInt8](repeating: 0, count: w * h * 4)

        for y in 0..<yMax {
            for x in 0..<w {
                let idx = y * w + x

                let maskV = coreMask[idx]
                let isInside = maskV > configuration.fuzzInsideThreshold

                // Signed distance in pixels (negative inside).
                let dPx: Double
                if isInside {
                    dPx = -Double(distToOutside[idx]) / 3.0
                } else {
                    dPx = Double(distToInside[idx]) / 3.0
                }

                let bandW = isInside ? insideWidthByX[x] : outsideWidthByX[x]
                if bandW <= 0.0001 { continue }

                let ad = abs(dPx)
                if ad > bandW { continue }

                // Edge factor: concentrated at the surface, fades quickly.
                let u = max(0.0, 1.0 - (ad / bandW))
                var edge = pow(u, edgePower)
                if isInside { edge = pow(edge, 1.25) }

                let s = strengthByX[x]
                let sCurve = pow(RainSurfaceMath.clamp01(s), 1.25)
                if sCurve <= 0.000_25 { continue }

                let lowH = lowHeightByX[x]
                let slopeBias = slopeBiasByX[x]

                // Low-frequency clumping (kept bounded; avoids a “cloud above the surface” look).
                let clumpRaw = RainSurfacePRNG.valueNoise2D01(x: Double(x), y: Double(y), cell: clumpCell, seed: seedC)
                let clump = RainSurfaceMath.smoothstep01(clumpRaw)

                let r0 = RainSurfacePRNG.hash2D01(x: x, y: y, seed: seedA)
                let r1 = RainSurfacePRNG.hash2D01(x: x, y: y, seed: seedB)

                // Inside fuzz: denser but softer, and it must exist so fuzz straddles the surface.
                let sideOpacity = isInside ? (maxOpacity * insideOpacityFactor) : maxOpacity
                let sideSpeckMul = isInside ? 0.35 : 1.0
                let sideHazeMul = isInside ? 1.15 : 1.0

                // Continuous base haze anchors fuzz to the surface (avoids “floating fuzz”).
                var alpha = sideOpacity
                    * 0.10
                    * sCurve
                    * edge
                    * (0.55 + 0.45 * clump)
                    * (0.75 + 0.25 * slopeBias)

                // Haze.
                let hazeProb =
                    baseDensity
                    * (0.85 + 0.15 * lowH)
                    * sCurve
                    * edge
                    * hazeStrength
                    * sideHazeMul
                    * (0.55 + 0.45 * clump)

                if r0 < hazeProb {
                    alpha += sideOpacity
                        * hazeStrength
                        * (0.28 + 0.72 * r1)
                        * edge
                        * (0.55 + 0.45 * clump)
                        * (0.70 + 0.30 * slopeBias)
                        * (0.80 + 0.20 * lowH)
                }

                // Specks (mostly outside).
                let speckProb =
                    baseDensity
                    * sCurve
                    * pow(edge, 1.35)
                    * speckStrength
                    * 0.18
                    * sideSpeckMul
                    * (0.50 + 0.50 * clump)

                if r1 < speckProb {
                    let r2 = RainSurfacePRNG.hash2D01(x: x &+ 17, y: y &+ 31, seed: seedC)
                    alpha += sideOpacity
                        * speckStrength
                        * (0.55 + 0.45 * r2)
                        * edge
                        * (0.65 + 0.35 * clump)
                        * (0.75 + 0.25 * slopeBias)
                }

                alpha = RainSurfaceMath.clamp01(alpha)
                if alpha <= 0.0001 { continue }

                let o = idx * 4
                rgba[o + 0] = UInt8((alpha * fr * 255.0).rounded())
                rgba[o + 1] = UInt8((alpha * fg * 255.0).rounded())
                rgba[o + 2] = UInt8((alpha * fb * 255.0).rounded())
                rgba[o + 3] = UInt8((alpha * 255.0).rounded())
            }
        }

        guard let cg = makeCGImageRGBA(width: w, height: h, rgba: rgba) else { return }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            // Keep fuzz bounded strictly to the plot rect and above the baseline.
            layer.clip(to: Path(chartRect))
            let clipRect = CGRect(
                x: chartRect.minX,
                y: chartRect.minY,
                width: chartRect.width,
                height: max(0, baselineY - chartRect.minY)
            )
            layer.clip(to: Path(clipRect))

            let img = Image(decorative: cg, scale: rasterScale, orientation: .up)
            layer.draw(img, in: chartRect)
        }
    }

    // MARK: - Core / rim / glints

    private static func drawCore(
        in context: inout GraphicsContext,
        corePath: Path,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        context.fill(corePath, with: .color(configuration.coreBodyColor))

        guard configuration.glossEnabled, configuration.glossMaxOpacity > 0.0001 else { return }

        let u = RainSurfacePRNG.hash2D01(
            x: 911,
            y: 733,
            seed: RainSurfacePRNG.combine(configuration.noiseSeed, 0xD1B5_4A32_D192_ED03)
        )
        let depthPx = RainSurfaceMath.lerp(configuration.glossDepthPixels.lowerBound, configuration.glossDepthPixels.upperBound, u)
        let depth = CGFloat(depthPx) / displayScale
        guard depth > 0.0001 else { return }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .screen
            layer.addFilter(.blur(radius: depth * 0.35))
            layer.stroke(
                topEdgePath,
                with: .color(configuration.coreTopColor.opacity(RainSurfaceMath.clamp01(configuration.glossMaxOpacity))),
                lineWidth: depth
            )
        }
    }

    private static func drawRim(
        in context: inout GraphicsContext,
        corePath: Path,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard configuration.rimEnabled else { return }

        let innerOpacity = RainSurfaceMath.clamp01(configuration.rimInnerOpacity)
        let outerOpacity = RainSurfaceMath.clamp01(configuration.rimOuterOpacity)
        let innerW = max(0.0, configuration.rimInnerWidthPixels) / Double(displayScale)
        let outerW = max(0.0, configuration.rimOuterWidthPixels) / Double(displayScale)

        let rimColor = configuration.rimColor

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            if innerOpacity > 0.0001, innerW > 0.0001 {
                layer.drawLayer { inner in
                    inner.clip(to: corePath)
                    inner.stroke(
                        topEdgePath,
                        with: .color(rimColor.opacity(innerOpacity)),
                        lineWidth: CGFloat(innerW)
                    )
                }
            }

            if outerOpacity > 0.0001, outerW > 0.0001 {
                layer.drawLayer { outer in
                    outer.stroke(
                        topEdgePath,
                        with: .color(rimColor.opacity(outerOpacity)),
                        lineWidth: CGFloat(outerW)
                    )

                    // Punch out the part that overlaps the core so the glow is outside-only.
                    outer.blendMode = .destinationOut
                    outer.fill(corePath, with: .color(.white))
                }
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
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard configuration.glintEnabled, configuration.glintMaxOpacity > 0.0001 else { return }
        guard heights.count >= 3 else { return }

        let maxima = localMaximaIndices(heights: heights)
        guard !maxima.isEmpty else { return }

        let maxCount = min(3, maxima.count)
        let chosen = Array(maxima.prefix(maxCount))

        let glintOpacity = RainSurfaceMath.clamp01(configuration.glintMaxOpacity)
        let glintColor = configuration.glintColor.opacity(glintOpacity)

        let radius = CGFloat(10.0) / displayScale
        let blur = CGFloat(6.0) / displayScale

        for idx in chosen {
            let x = chartRect.minX + CGFloat(idx) * stepX
            let y = baselineY - heights[idx]
            let r = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)

            context.drawLayer { layer in
                layer.clip(to: Path(chartRect))
                layer.blendMode = .screen
                layer.addFilter(.blur(radius: blur))
                layer.fill(Path(ellipseIn: r), with: .color(glintColor))
            }
        }

        _ = maxHeight
    }

    private static func localMaximaIndices(heights: [CGFloat]) -> [Int] {
        guard heights.count >= 3 else { return [] }
        var out: [Int] = []
        out.reserveCapacity(8)

        for i in 1..<(heights.count - 1) {
            if heights[i] > heights[i - 1], heights[i] > heights[i + 1] {
                out.append(i)
            }
        }
        return out
    }

    // MARK: - Mask + distance helpers

    private static func rasterizeMask(
        path: Path,
        rect: CGRect,
        width: Int,
        height: Int,
        rasterScale: CGFloat,
        baselineY: CGFloat,
        insideThreshold: UInt8
    ) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height)
        let cs = CGColorSpaceCreateDeviceGray()
        let bpr = width

        bytes.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            guard let ctx = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bpr,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }

            ctx.setShouldAntialias(true)
            ctx.setAllowsAntialiasing(true)
            ctx.interpolationQuality = .high
            ctx.setFillColor(gray: 1.0, alpha: 1.0)

            // Map SwiftUI coords (origin top-left, y down) into the bitmap.
            ctx.translateBy(x: 0, y: CGFloat(height))
            ctx.scaleBy(x: rasterScale, y: -rasterScale)
            ctx.translateBy(x: -rect.minX, y: -rect.minY)

            ctx.addPath(path.cgPath)
            ctx.fillPath()
        }

        // Ensure y=0 indexes the top row by checking where the filled region sits relative to baseline.
        let baselinePx = Int(round((baselineY - rect.minY) * rasterScale))
        if baselinePx > 0, baselinePx < height {
            var above = 0
            var below = 0

            let stepY = max(1, height / 64)
            let stepX = max(1, width / 64)

            for y in stride(from: 0, to: height, by: stepY) {
                let row = y * width
                for x in stride(from: 0, to: width, by: stepX) {
                    if bytes[row + x] > insideThreshold {
                        if y < baselinePx { above &+= 1 } else { below &+= 1 }
                    }
                }
            }

            if below > above {
                let half = height / 2
                for y in 0..<half {
                    let y2 = height - 1 - y
                    let r0 = y * width
                    let r1 = y2 * width
                    for x in 0..<width {
                        let i0 = r0 + x
                        let i1 = r1 + x
                        let tmp = bytes[i0]
                        bytes[i0] = bytes[i1]
                        bytes[i1] = tmp
                    }
                }
            }
        }

        return bytes
    }

    private static func chamferDistanceTransform(
        mask: [UInt8],
        width: Int,
        height: Int,
        threshold: UInt8,
        zeroForInside: Bool
    ) -> [UInt16] {
        let count = width * height
        let maxD: UInt16 = 16_000
        var dist = [UInt16](repeating: maxD, count: count)

        for i in 0..<count {
            let isInside = mask[i] > threshold
            let isFeature = zeroForInside ? isInside : !isInside
            dist[i] = isFeature ? 0 : maxD
        }

        // Forward pass.
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                var best = dist[idx]

                if x > 0 { best = min(best, dist[idx - 1] &+ 3) }
                if y > 0 { best = min(best, dist[idx - width] &+ 3) }
                if x > 0, y > 0 { best = min(best, dist[idx - width - 1] &+ 4) }
                if x + 1 < width, y > 0 { best = min(best, dist[idx - width + 1] &+ 4) }

                dist[idx] = best
            }
        }

        // Backward pass.
        if width >= 2, height >= 2 {
            for y in stride(from: height - 1, through: 0, by: -1) {
                for x in stride(from: width - 1, through: 0, by: -1) {
                    let idx = y * width + x
                    var best = dist[idx]

                    if x + 1 < width { best = min(best, dist[idx + 1] &+ 3) }
                    if y + 1 < height { best = min(best, dist[idx + width] &+ 3) }
                    if x + 1 < width, y + 1 < height { best = min(best, dist[idx + width + 1] &+ 4) }
                    if x > 0, y + 1 < height { best = min(best, dist[idx + width - 1] &+ 4) }

                    dist[idx] = best
                }
            }
        }

        return dist
    }

    private static func makeCGImageRGBA(width: Int, height: Int, rgba: [UInt8]) -> CGImage? {
        guard rgba.count == width * height * 4 else { return nil }

        let cs = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )

        let data = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func rgbComponents(_ color: Color) -> (Double, Double, Double, Double) {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
        #elseif canImport(AppKit)
        let ns = NSColor(color)
        let c = ns.usingColorSpace(.deviceRGB) ?? ns
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
        #else
        return (1.0, 1.0, 1.0, 1.0)
        #endif
    }
}
