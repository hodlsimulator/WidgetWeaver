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
    // MARK: - Surface (mask + fields)

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

        // Core mask raster (source of truth for fields).
        guard let raster = rasteriseCoreMask(
            corePath: corePath,
            chartRect: chartRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        ) else {
            context.fill(corePath, with: .color(configuration.coreBodyColor.opacity(1.0)))
            return
        }

        // Outer bloom is optional and must not read as a traced line.
        if configuration.rimEnabled, configuration.rimOuterOpacity > 0.0001 {
            drawOuterBloom(
                in: &context,
                chartRect: chartRect,
                raster: raster,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // Fuzz (speckled mist) outside-only, above-baseline-only.
        if configuration.fuzzEnabled, configuration.fuzzMaxOpacity > 0.0001 {
            drawFuzzMist(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                certainties: certainties,
                raster: raster,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // Core body: opaque solid fill.
        context.fill(corePath, with: .color(configuration.coreBodyColor.opacity(1.0)))

        // Inside lighting: surface-driven (distance to surface), masked to core.
        if configuration.glossEnabled, configuration.glossMaxOpacity > 0.0001 {
            drawInsideLighting(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                raster: raster,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        // Optional glint (off by default in the template config).
        if configuration.glintEnabled {
            drawGlint(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }
    }

    // MARK: - Raster (core mask)

    private struct CoreRaster {
        let width: Int
        let height: Int
        let rasterScale: CGFloat
        let baselinePx: Int
        let mask: [UInt8]
        let insideThreshold: UInt8

        var count: Int { width * height }
    }

    private static func rasteriseCoreMask(
        corePath: Path,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) -> CoreRaster? {
        let scale = max(1.0, displayScale)

        // Desired raster scale starts at display scale (optionally supersampled), then is capped.
        var rasterScale = max(1.0, scale * max(1.0, configuration.rasterSupersample))

        let maxW = max(64, configuration.rasterMaxWidthPixels)
        let maxH = max(64, configuration.rasterMaxHeightPixels)
        rasterScale = min(rasterScale, CGFloat(maxW) / max(1.0, chartRect.width))
        rasterScale = min(rasterScale, CGFloat(maxH) / max(1.0, chartRect.height))
        rasterScale = max(1.0, rasterScale)

        var w = max(2, Int(ceil(chartRect.width * rasterScale)))
        var h = max(2, Int(ceil(chartRect.height * rasterScale)))

        // Hard total pixel budget.
        let maxTotal = max(90_000, configuration.rasterMaxTotalPixels)
        let total = w * h
        if total > maxTotal {
            let s = sqrt(Double(maxTotal) / Double(total))
            rasterScale = max(1.0, rasterScale * CGFloat(s))
            w = max(2, Int(ceil(chartRect.width * rasterScale)))
            h = max(2, Int(ceil(chartRect.height * rasterScale)))
        }

        let baselinePx = max(0, min(h - 1, Int((baselineY * rasterScale).rounded(.toNearestOrAwayFromZero))))
        let insideThreshold: UInt8 = configuration.maskInsideThreshold

        var mask = [UInt8](repeating: 0, count: w * h)
        mask.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let gray = CGColorSpaceCreateDeviceGray()
            guard let cg = CGContext(
                data: base,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: gray,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }

            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)
            cg.interpolationQuality = .none

            cg.setFillColor(gray: 0, alpha: 1)
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))

            // Match SwiftUI's top-left origin (y down).
            cg.translateBy(x: 0, y: CGFloat(h))
            cg.scaleBy(x: rasterScale, y: -rasterScale)

            cg.setFillColor(gray: 1, alpha: 1)
            cg.addPath(corePath.cgPath)
            cg.fillPath()
        }

        return CoreRaster(
            width: w,
            height: h,
            rasterScale: rasterScale,
            baselinePx: baselinePx,
            mask: mask,
            insideThreshold: insideThreshold
        )
    }

    // MARK: - Inside lighting (distance to surface, inside-only)

    private static func drawInsideLighting(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        raster: CoreRaster,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let w = raster.width
        let h = raster.height
        let baselinePx = min(raster.baselinePx, h - 1)

        // Traversable (inside) mask.
        var inside = [UInt8](repeating: 0, count: raster.count)
        for i in 0..<raster.count {
            inside[i] = (raster.mask[i] > raster.insideThreshold) ? 1 : 0
        }

        // Sources: thin band just inside the top surface (per-column scan).
        let scale = max(1.0, displayScale)
        let minSourceHeightPxRaster = max(2, Int((configuration.insideLightMinHeightPixels * Double(raster.rasterScale / scale)).rounded()))
        var sources = [UInt8](repeating: 0, count: raster.count)

        if baselinePx > 1 {
            for x in 0..<w {
                var yTop: Int? = nil
                let yMax = baselinePx - 1
                if yMax <= 0 { continue }

                for y in 0..<yMax {
                    let idx = y * w + x
                    if raster.mask[idx] > raster.insideThreshold {
                        yTop = y
                        break
                    }
                }

                guard let yTop else { continue }
                let heightPx = baselinePx - yTop
                if heightPx < minSourceHeightPxRaster { continue }

                // Thicken sources slightly to avoid pinholes.
                for dx in -1...1 {
                    let xx = x + dx
                    if xx < 0 || xx >= w { continue }
                    let i0 = yTop * w + xx
                    sources[i0] = 1
                    if yTop + 1 < yMax {
                        sources[(yTop + 1) * w + xx] = 1
                    }
                }
            }
        }

        let dist = RainSurfaceMath.chamferDistance3_4(
            width: w,
            height: h,
            sources: sources,
            traversable: inside
        )
        guard dist.count == raster.count else { return }

        let depthPxDisplay = RainSurfaceMath.clamp(
            configuration.glossDepthPixels.mid,
            min: configuration.glossDepthPixels.lowerBound,
            max: configuration.glossDepthPixels.upperBound
        )
        let depthPxRaster = max(1.0, depthPxDisplay * Double(raster.rasterScale / scale))
        let maxA = RainSurfaceMath.clamp(configuration.glossMaxOpacity, min: 0.0, max: 1.0)

        let colour = rgbaComponents(from: configuration.coreTopColor, fallback: (0.12, 0.45, 1.0, 1.0))

        var bytes = [UInt8](repeating: 0, count: w * h * 4)

        for y in 0..<h {
            let yRow = y * w
            let outRow = yRow * 4
            let belowBaseline = (y >= baselinePx)
            for x in 0..<w {
                let idx = yRow + x
                let out = outRow + x * 4

                if belowBaseline || inside[idx] == 0 { continue }

                let d = Double(dist[idx]) / 3.0
                let v = exp(-d / depthPxRaster)
                var a = v * maxA

                if a < 0.0005 { continue }
                a = min(a, maxA)

                let a8 = UInt8((a * 255.0).rounded())
                let r8 = UInt8((Double(colour.r) * a).rounded())
                let g8 = UInt8((Double(colour.g) * a).rounded())
                let b8 = UInt8((Double(colour.b) * a).rounded())

                bytes[out + 0] = r8
                bytes[out + 1] = g8
                bytes[out + 2] = b8
                bytes[out + 3] = a8
            }
        }

        guard let img = makeCGImageRGBA(width: w, height: h, rgba: bytes) else { return }
        let swiftUIImage = Image(decorative: img, scale: 1.0, orientation: .up)

        context.drawLayer { layer in
            layer.blendMode = .screen
            layer.draw(swiftUIImage, in: chartRect)
        }
    }

    // MARK: - Outer bloom (outside-only, wide, low opacity)

    private static func drawOuterBloom(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        raster: CoreRaster,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let w = raster.width
        let h = raster.height

        var sources = [UInt8](repeating: 0, count: raster.count)
        for i in 0..<raster.count {
            sources[i] = (raster.mask[i] > raster.insideThreshold) ? 1 : 0
        }

        let dist = RainSurfaceMath.chamferDistance3_4(
            width: w,
            height: h,
            sources: sources,
            traversable: nil
        )
        guard dist.count == raster.count else { return }

        let scale = max(1.0, displayScale)
        let outerWDisplay = max(8.0, configuration.rimOuterWidthPixels)
        let outerW = max(2.0, outerWDisplay * Double(raster.rasterScale / scale))
        let maxA = RainSurfaceMath.clamp(configuration.rimOuterOpacity, min: 0.0, max: 1.0) * 0.55
        if maxA <= 0.0001 { return }

        let baselinePx = min(raster.baselinePx, h - 1)
        let colour = rgbaComponents(from: configuration.rimColor, fallback: (0.62, 0.88, 1.0, 1.0))

        var bytes = [UInt8](repeating: 0, count: w * h * 4)

        for y in 0..<h {
            let yRow = y * w
            let outRow = yRow * 4
            let belowBaseline = (y >= baselinePx)
            for x in 0..<w {
                let idx = yRow + x
                let out = outRow + x * 4

                if belowBaseline { continue }
                if raster.mask[idx] > raster.insideThreshold { continue }

                let d = Double(dist[idx]) / 3.0
                if d <= 0.0 || d > outerW { continue }

                let v = exp(-d / (outerW * 0.65))
                let a = min(maxA, v * maxA)
                if a < 0.0005 { continue }

                let a8 = UInt8((a * 255.0).rounded())
                let r8 = UInt8((Double(colour.r) * a).rounded())
                let g8 = UInt8((Double(colour.g) * a).rounded())
                let b8 = UInt8((Double(colour.b) * a).rounded())

                bytes[out + 0] = r8
                bytes[out + 1] = g8
                bytes[out + 2] = b8
                bytes[out + 3] = a8
            }
        }

        guard let img = makeCGImageRGBA(width: w, height: h, rgba: bytes) else { return }
        let swiftUIImage = Image(decorative: img, scale: 1.0, orientation: .up)

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.draw(swiftUIImage, in: chartRect)
        }
    }

    // MARK: - Fuzz mist (dense granular speckle; outside-only; distance-banded; deterministic)

    private static func drawFuzzMist(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        certainties: [Double],
        raster: CoreRaster,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let w = raster.width
        let h = raster.height
        let baselinePx = min(raster.baselinePx, h - 1)
        if baselinePx <= 1 { return }

        let scale = max(1.0, displayScale)

        // Fuzz width in raster pixels.
        let desiredPx = Double(chartRect.height * configuration.fuzzWidthFraction * scale)
        let clampedPx = RainSurfaceMath.clamp(
            desiredPx,
            min: configuration.fuzzWidthPixelsClamp.lowerBound,
            max: configuration.fuzzWidthPixelsClamp.upperBound
        )
        let fuzzWidthPxRaster = max(2.0, clampedPx * Double(raster.rasterScale / scale))

        // Distance-to-core field (from inside pixels).
        var sources = [UInt8](repeating: 0, count: raster.count)
        for i in 0..<raster.count {
            sources[i] = (raster.mask[i] > raster.insideThreshold) ? 1 : 0
        }

        let dist = RainSurfaceMath.chamferDistance3_4(
            width: w,
            height: h,
            sources: sources,
            traversable: nil
        )
        guard dist.count == raster.count else { return }

        // Render fuzz at a slightly reduced raster resolution, then upscale for a mistier read.
        let fuzzRenderScale = Double(RainSurfaceMath.clamp(configuration.fuzzRenderScale, min: 0.55, max: 1.0))
        let fw = max(2, Int((Double(w) * fuzzRenderScale).rounded(.toNearestOrAwayFromZero)))
        let fh = max(2, Int((Double(h) * fuzzRenderScale).rounded(.toNearestOrAwayFromZero)))
        let xMap = Double(w) / Double(fw)
        let yMap = Double(h) / Double(fh)
        let baselineF = max(0, min(fh - 1, Int((Double(baselinePx) / yMap).rounded(.toNearestOrAwayFromZero))))

        // Deterministic seed mixed with size so patterns remain stable per widget size.
        let sizeSalt = RainSurfacePRNG.combine(UInt64(w), UInt64(h))
        let baseSeed = RainSurfacePRNG.combine(configuration.noiseSeed, sizeSalt)
        let seedHi = RainSurfacePRNG.combine(baseSeed, 0xA7F0_9C3B_1B33_6F1D)
        let seedAlpha = RainSurfacePRNG.combine(baseSeed, 0xC8A1_5D2E_77D4_0B13)
        let seedFogA = RainSurfacePRNG.combine(baseSeed, 0x0D25_82C1_9C7E_DA11)
        let seedFogB = RainSurfacePRNG.combine(baseSeed, 0x9E33_7A6D_51B4_0C29)

        let maxA = RainSurfaceMath.clamp(configuration.fuzzMaxOpacity, min: 0.0, max: 1.0)
        let baseDensity = RainSurfaceMath.clamp(configuration.fuzzBaseDensity, min: 0.0, max: 1.0)
        let lowHeightPower = max(0.6, configuration.fuzzLowHeightPower)
        let uncertaintyFloor = RainSurfaceMath.clamp(configuration.fuzzUncertaintyFloor, min: 0.0, max: 1.0)

        let maxHeightPoints = max(heights.max() ?? 0, CGFloat(1.0 / scale))
        let maxHeightPxRaster = max(1.0, Double(maxHeightPoints) * Double(raster.rasterScale))
        let maxHeightPxF = max(1.0, maxHeightPxRaster / yMap)

        // Precompute per-x certainty and a gentle slope cue (in fuzz raster coordinates).
        let nHeights = max(2, heights.count)
        var certaintyByX = [Double](repeating: 1.0, count: fw)
        var slopeByX = [Double](repeating: 0.0, count: fw)
        for x in 0..<fw {
            let t = (fw <= 1) ? 0.0 : Double(x) / Double(fw - 1)
            certaintyByX[x] = RainSurfaceMath.sampleLinear(certainties, t: t)

            let fx = t * Double(nHeights - 1)
            let i = Int(floor(fx))
            let i0 = max(0, min(nHeights - 1, i))
            let i1 = max(0, min(nHeights - 1, i0 + 1))
            let ip = max(0, i0 - 1)
            let inx = min(nHeights - 1, i1 + 1)

            let dh = Double(abs(heights[inx] - heights[ip]))
            let denom = max(1e-6, Double(stepX) * 2.0)
            let slope = dh / denom
            slopeByX[x] = RainSurfaceMath.clamp01(slope * 0.85)
        }

        // Fog clumping cell sizes in fuzz raster pixels.
        let cellBaseDisplay = max(8.0, configuration.fuzzFogCellPixels)
        let cellBaseRaster = max(4.0, cellBaseDisplay * Double(raster.rasterScale / scale) * fuzzRenderScale)
        let cellA = max(4, Int(cellBaseRaster.rounded(.toNearestOrAwayFromZero)))
        let cellB = max(6, Int((cellBaseRaster * 2.2).rounded(.toNearestOrAwayFromZero)))

        let colour = rgbaComponents(from: configuration.fuzzColor, fallback: (0.65, 0.90, 1.0, 1.0))
        let cr = Int(colour.r)
        let cg = Int(colour.g)
        let cb = Int(colour.b)

        var bytes = [UInt8](repeating: 0, count: fw * fh * 4)

        @inline(__always)
        func addPremultipliedPixel(x: Int, y: Int, alpha: Double) {
            if x < 0 || x >= fw || y < 0 || y >= fh { return }
            if y >= baselineF { return }

            // Map to original raster for inside/outside test and distance sample.
            let ox = max(0, min(w - 1, Int((Double(x) + 0.5) * xMap)))
            let oy = max(0, min(h - 1, Int((Double(y) + 0.5) * yMap)))
            let oIdx = oy * w + ox
            if raster.mask[oIdx] > raster.insideThreshold { return }

            let a = RainSurfaceMath.clamp(alpha, min: 0.0, max: 1.0)
            let a8 = Int((a * 255.0).rounded(.toNearestOrAwayFromZero))
            if a8 <= 0 { return }

            let out = (y * fw + x) * 4
            let oldA = Int(bytes[out + 3])
            let newA = min(255, oldA + a8)
            let deltaA = newA - oldA
            if deltaA <= 0 { return }

            bytes[out + 3] = UInt8(newA)
            bytes[out + 0] = UInt8(min(255, Int(bytes[out + 0]) + (cr * deltaA) / 255))
            bytes[out + 1] = UInt8(min(255, Int(bytes[out + 1]) + (cg * deltaA) / 255))
            bytes[out + 2] = UInt8(min(255, Int(bytes[out + 2]) + (cb * deltaA) / 255))
        }

        // Primary pass: fill full region (no early break) to avoid directional artefacts.
        var active = 0
        for y in 0..<fh {
            if y >= baselineF { continue }

            let heightAboveBaselinePx = Double(baselineF - y)
            let heightNorm = RainSurfaceMath.clamp01(heightAboveBaselinePx / maxHeightPxF)

            // Stronger near baseline, but keep a visible floor near the crest.
            let heightFactor = 0.28 + 0.72 * pow(max(0.0, 1.0 - heightNorm), lowHeightPower)

            // Soft clumping for the fog.
            let fogA = RainSurfacePRNG.valueNoise2D01(x: y * 7 + 13, y: y * 3 + 5, seed: seedFogA, cell: cellA)
            _ = fogA

            for x in 0..<fw {
                
                // Original raster sample for distance.
                let ox = max(0, min(w - 1, Int((Double(x) + 0.5) * xMap)))
                let oy = max(0, min(h - 1, Int((Double(y) + 0.5) * yMap)))
                let oIdx = oy * w + ox

                // Outside-only.
                if raster.mask[oIdx] > raster.insideThreshold { continue }

                let d = Double(dist[oIdx]) / 3.0
                if d <= 0.0 || d > fuzzWidthPxRaster { continue }

                let td = RainSurfaceMath.clamp01(d / fuzzWidthPxRaster)

                // Distance falloff (dense near edge).
                let distanceWeight = pow(max(0.0, 1.0 - td), 1.10)

                // Bands: near / mid / far.
                let bandScale: Double
                let bandAlphaScale: Double
                if td < 0.26 {
                    bandScale = 1.05
                    bandAlphaScale = 1.00
                } else if td < 0.60 {
                    bandScale = 0.78
                    bandAlphaScale = 0.78
                } else {
                    bandScale = 0.40
                    bandAlphaScale = 0.55
                }

                // Uncertainty term (higher fuzz when certainty is low), with a visible floor.
                let c = RainSurfaceMath.clamp01(certaintyByX[x])
                let uncertainty = RainSurfaceMath.clamp01(uncertaintyFloor + (1.0 - uncertaintyFloor) * (1.0 - c))

                // Gentle slope cue (boost shoulders).
                let slopeBias = 0.78 + 0.22 * slopeByX[x]

                // Clumpy fog modulation: two octaves.
                let fog1 = RainSurfacePRNG.valueNoise2D01(x: x, y: y, seed: seedFogA, cell: cellA)
                let fog2 = RainSurfacePRNG.valueNoise2D01(x: x, y: y, seed: seedFogB, cell: cellB)
                let fog = RainSurfaceMath.clamp01(0.62 * fog1 + 0.38 * fog2)

                // Probability for whether this pixel contributes to the mist.
                var p = baseDensity
                p *= bandScale
                p *= distanceWeight
                p *= (0.80 + 0.40 * (fog - 0.5)) // mild clumping
                p *= uncertainty
                p *= heightFactor
                p *= slopeBias
                p = RainSurfaceMath.clamp01(p)

                let r = RainSurfacePRNG.hash2D01(x: x, y: y, seed: seedHi)
                if r >= p { continue }

                // Alpha for this speckle; also clumped.
                let rA = RainSurfacePRNG.hash2D01(x: x, y: y, seed: seedAlpha)
                let grain = 0.55 + 0.45 * rA
                var a = maxA
                a *= bandAlphaScale
                a *= (0.55 + 0.45 * uncertainty)
                a *= pow(distanceWeight, 0.85)
                a *= (0.70 + 0.30 * heightFactor)
                a *= (0.72 + 0.28 * fog)
                a *= grain

                if a < 0.0009 { continue }

                // Stamp tiny clusters (still granular, avoids “lonely dots” at widget scale).
                let rP = RainSurfacePRNG.hash2D01(x: x, y: y, seed: RainSurfacePRNG.combine(seedHi, 0x5B2C_9D1E_7A11_33F9))
                let near = (td < 0.26)
                let mid = (td >= 0.26 && td < 0.60)

                addPremultipliedPixel(x: x, y: y, alpha: a)
                active += 1

                if near {
                    if rP < 0.55 {
                        addPremultipliedPixel(x: x + 1, y: y, alpha: a * 0.55)
                    } else if rP < 0.85 {
                        addPremultipliedPixel(x: x, y: y - 1, alpha: a * 0.45)
                        addPremultipliedPixel(x: x + 1, y: y, alpha: a * 0.40)
                    } else {
                        addPremultipliedPixel(x: x + 1, y: y, alpha: a * 0.40)
                        addPremultipliedPixel(x: x, y: y + 1, alpha: a * 0.32)
                        addPremultipliedPixel(x: x + 1, y: y + 1, alpha: a * 0.26)
                    }
                } else if mid {
                    if rP < 0.30 {
                        addPremultipliedPixel(x: x + 1, y: y, alpha: a * 0.40)
                    } else if rP < 0.55 {
                        addPremultipliedPixel(x: x, y: y + 1, alpha: a * 0.34)
                    } else if rP < 0.70 {
                        addPremultipliedPixel(x: x + 1, y: y, alpha: a * 0.28)
                        addPremultipliedPixel(x: x, y: y + 1, alpha: a * 0.24)
                    }
                } else {
                    if rP < 0.18 {
                        addPremultipliedPixel(x: x + 1, y: y, alpha: a * 0.28)
                        addPremultipliedPixel(x: x, y: y + 1, alpha: a * 0.22)
                    } else if rP < 0.26 {
                        addPremultipliedPixel(x: x - 1, y: y, alpha: a * 0.22)
                    }
                }
            }
        }

        // Deterministic thinning if the fill becomes too heavy.
        let hardBudget = max(6_000, configuration.fuzzSpeckleBudget)
        if active > hardBudget {
            let keepFrac = Double(hardBudget) / Double(max(1, active))
            let thinningSeed = RainSurfacePRNG.combine(baseSeed, 0x4E2C_1A9D_0B77_3F21)

            for y in 0..<fh {
                let row = y * fw
                for x in 0..<fw {
                    let out = (row + x) * 4
                    let a8 = bytes[out + 3]
                    if a8 == 0 { continue }

                    let r = RainSurfacePRNG.hash2D01(x: x, y: y, seed: thinningSeed)
                    if r <= keepFrac {
                        continue
                    } else {
                        bytes[out + 0] = 0
                        bytes[out + 1] = 0
                        bytes[out + 2] = 0
                        bytes[out + 3] = 0
                    }
                }
            }
        }

        guard let img = makeCGImageRGBA(width: fw, height: fh, rgba: bytes) else { return }
        let swiftUIImage = Image(decorative: img, scale: 1.0, orientation: .up)

        // Composite: additively, then mask to outside-of-core and above-baseline in vector space.
        let outsideMask = RainSurfaceGeometry.makeOutsideMaskPath(clipRect: chartRect, corePath: corePath)
        let aboveBaselineRect = Path(CGRect(x: chartRect.minX, y: chartRect.minY, width: chartRect.width, height: max(0, baselineY - chartRect.minY)))

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.draw(swiftUIImage, in: chartRect)

            layer.blendMode = .destinationIn
            layer.fill(outsideMask, with: .color(.white), style: FillStyle(eoFill: true))

            layer.blendMode = .destinationIn
            layer.fill(aboveBaselineRect, with: .color(.white))
        }
    }

    // MARK: - Glint (single apex, very subtle)

    private static func drawGlint(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        guard heights.count >= 3 else { return }

        var bestIdx = 0
        var bestH: CGFloat = 0
        for (i, h) in heights.enumerated() {
            if h > bestH {
                bestH = h
                bestIdx = i
            }
        }

        let maxHeight = max(bestH, onePixel)
        let minFrac = RainSurfaceMath.clamp(configuration.glintMinHeightFraction, min: 0.35, max: 0.95)
        if bestH < maxHeight * CGFloat(minFrac) { return }

        let x = chartRect.minX + (CGFloat(bestIdx) + 0.5) * stepX
        let y = baselineY - bestH

        let a0 = RainSurfaceMath.clamp(configuration.glintMaxOpacity, min: 0.0, max: 1.0) * 0.55
        let a1 = RainSurfaceMath.clamp(configuration.glintMaxOpacity, min: 0.0, max: 1.0)

        let r0 = max(onePixel * 4.8, onePixel * 6.2)
        let r1 = max(onePixel * 2.2, onePixel * 3.2)

        let e0 = CGRect(x: x - r0, y: y - r0 * 0.65, width: r0 * 2, height: r0 * 1.55)
        let e1 = CGRect(x: x - r1, y: y - r1 * 0.65, width: r1 * 2, height: r1 * 1.55)

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.fill(Path(ellipseIn: e0), with: .color(configuration.glintColor.opacity(a0)))
            layer.fill(Path(ellipseIn: e1), with: .color(configuration.glintColor.opacity(a1)))

            layer.blendMode = .destinationIn
            layer.fill(corePath, with: .color(.white))
        }
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

        let fadeFrac = RainSurfaceMath.clamp(configuration.baselineEndFadeFraction, min: 0.03, max: 0.06)
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

        let base = RainSurfaceMath.clamp(configuration.baselineLineOpacity, min: 0.0, max: 1.0)

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            // Subtle glow only; kept behind the body visually.
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.10)),
                style: StrokeStyle(lineWidth: onePixel * 3.0, lineCap: .round, lineJoin: .round)
            )
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.18)),
                style: StrokeStyle(lineWidth: onePixel * 1.8, lineCap: .round, lineJoin: .round)
            )

            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base)),
                style: StrokeStyle(lineWidth: onePixel, lineCap: .butt, lineJoin: .miter)
            )

            layer.blendMode = .destinationIn
            var fadeRect = Path()
            fadeRect.addRect(chartRect)
            layer.fill(fadeRect, with: alphaMask)
        }
    }

    // MARK: - Colour helpers / image helpers

    private struct RGBA8 {
        let r: UInt8
        let g: UInt8
        let b: UInt8
        let a: UInt8
    }

    private static func rgbaComponents(from color: Color, fallback: (Double, Double, Double, Double)) -> RGBA8 {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return RGBA8(
                r: UInt8((Double(r) * 255.0).rounded()),
                g: UInt8((Double(g) * 255.0).rounded()),
                b: UInt8((Double(b) * 255.0).rounded()),
                a: UInt8((Double(a) * 255.0).rounded())
            )
        }
        #endif
        return RGBA8(
            r: UInt8((fallback.0 * 255.0).rounded()),
            g: UInt8((fallback.1 * 255.0).rounded()),
            b: UInt8((fallback.2 * 255.0).rounded()),
            a: UInt8((fallback.3 * 255.0).rounded())
        )
    }

    private static func makeCGImageRGBA(width: Int, height: Int, rgba: [UInt8]) -> CGImage? {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }

        let cfData = Data(rgba) as CFData
        guard let provider = CGDataProvider(data: cfData) else { return nil }

        let space = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
}

private extension ClosedRange where Bound == Double {
    var mid: Double { (lowerBound + upperBound) * 0.5 }
}
