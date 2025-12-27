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
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard !heights.isEmpty else { return }

        let corePath = RainSurfaceGeometry.makeCorePath(
            chartRect: chartRect,
            baselineY: baselineY,
            stepX: stepX,
            heights: heights
        )
        let topEdgePath = RainSurfaceGeometry.makeTopEdgePath(
            chartRect: chartRect,
            baselineY: baselineY,
            stepX: stepX,
            heights: heights
        )

        context.fill(corePath, with: .color(configuration.coreBodyColor))

        if configuration.canEnableFuzz, certainties.count == heights.count {
            drawFuzzReplacingEdge(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                certainties: certainties,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        if configuration.rimEnabled {
            drawRim(
                in: &context,
                topEdgePath: topEdgePath,
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
                configuration: configuration,
                displayScale: displayScale
            )
        }

        drawBaseline(
            in: &context,
            chartRect: chartRect,
            baselineY: baselineY,
            configuration: configuration,
            displayScale: displayScale
        )
    }

    // MARK: - Baseline

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let alpha = max(0.0, min(1.0, configuration.baselineLineOpacity))
        if alpha <= 0.000_1 { return }

        let y = RainSurfaceMath.alignToPixelCenter(baselineY, displayScale: displayScale)
        let fade = RainSurfaceMath.clamp(configuration.baselineEndFadeFraction, min: 0.0, max: 0.45)

        var path = Path()
        path.move(to: CGPoint(x: chartRect.minX, y: y))
        path.addLine(to: CGPoint(x: chartRect.maxX, y: y))

        if fade <= 0.000_1 {
            context.stroke(path, with: .color(configuration.baselineColor.opacity(alpha)), lineWidth: 1.0 / displayScale)
            return
        }

        let w = chartRect.width
        let leftW = w * fade
        let rightW = w * fade

        let x0 = chartRect.minX
        let x1 = chartRect.minX + leftW
        let x2 = chartRect.maxX - rightW
        let x3 = chartRect.maxX

        func strokeSegment(xa: CGFloat, xb: CGFloat, a0: Double, a1: Double) {
            var seg = Path()
            seg.move(to: CGPoint(x: xa, y: y))
            seg.addLine(to: CGPoint(x: xb, y: y))

            let steps = 12
            for i in 0..<steps {
                let t = Double(i) / Double(max(1, steps - 1))
                let a = RainSurfaceMath.lerp(a0, a1, t)
                context.stroke(seg, with: .color(configuration.baselineColor.opacity(alpha * a)), lineWidth: 1.0 / displayScale)
            }
        }

        strokeSegment(xa: x0, xb: x1, a0: 0.0, a1: 1.0)
        strokeSegment(xa: x1, xb: x2, a0: 1.0, a1: 1.0)
        strokeSegment(xa: x2, xb: x3, a0: 1.0, a1: 0.0)
    }

    // MARK: - Rim

    private static func drawRim(
        in context: inout GraphicsContext,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let innerA = max(0.0, min(1.0, configuration.rimInnerOpacity))
        let outerA = max(0.0, min(1.0, configuration.rimOuterOpacity))
        let innerW = max(0.0, configuration.rimInnerWidthPixels) / Double(displayScale)
        let outerBlur = max(0.0, configuration.rimOuterWidthPixels) / Double(displayScale)

        if innerA > 0.000_1, innerW > 0.000_1 {
            context.stroke(topEdgePath, with: .color(configuration.rimColor.opacity(innerA)), lineWidth: innerW)
        }

        if outerA > 0.000_1, outerBlur > 0.000_1 {
            context.drawLayer { layer in
                layer.addFilter(.blur(radius: outerBlur))
                layer.stroke(topEdgePath, with: .color(configuration.rimColor.opacity(outerA)), lineWidth: 1.0 / displayScale)
            }
        }
    }

    // MARK: - Glints

    private static func drawGlints(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let maxCount = max(0, configuration.glintMaxCount)
        if maxCount == 0 { return }

        let maxH = max(0.000_1, heights.max() ?? 0.0)
        let minFrac = RainSurfaceMath.clamp(configuration.glintMinHeightFraction, min: 0.0, max: 1.0)

        var peaks: [(idx: Int, h: CGFloat)] = []
        for i in 1..<(heights.count - 1) {
            let h0 = heights[i - 1]
            let h1 = heights[i]
            let h2 = heights[i + 1]
            if h1 >= h0, h1 >= h2, h1 >= maxH * CGFloat(minFrac) {
                peaks.append((i, h1))
            }
        }

        peaks.sort(by: { $0.h > $1.h })
        if peaks.count > maxCount {
            peaks = Array(peaks.prefix(maxCount))
        }

        let blur = max(0.0, configuration.glintBlurPixels) / Double(displayScale)
        let a = max(0.0, min(1.0, configuration.glintMaxOpacity))
        if a <= 0.000_1 { return }

        context.drawLayer { layer in
            if blur > 0.000_1 {
                layer.addFilter(.blur(radius: blur))
            }

            for p in peaks {
                let x = chartRect.minX + (CGFloat(p.idx) + 0.5) * stepX
                let y = baselineY - p.h
                let r: CGFloat = max(2.0, min(9.0, chartRect.height * 0.05))
                let rect = CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)
                layer.fill(Path(ellipseIn: rect), with: .color(configuration.glintColor.opacity(a)))
            }
        }
    }

    // MARK: - Fuzz (replaces the surface edge)

    private static func drawFuzzReplacingEdge(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        certainties: [Double],
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let maxPixels = max(10_000, configuration.fuzzRasterMaxPixels)

        let baseScale = min(displayScale, 0.85)
        var rasterScale = max(0.35, baseScale)

        var w = max(2, Int((chartRect.width * rasterScale).rounded(.up)))
        var h = max(2, Int((chartRect.height * rasterScale).rounded(.up)))

        if w * h > maxPixels {
            let s = sqrt(Double(maxPixels) / Double(max(1, w * h)))
            rasterScale = max(0.35, rasterScale * CGFloat(s))
            w = max(2, Int((chartRect.width * rasterScale).rounded(.up)))
            h = max(2, Int((chartRect.height * rasterScale).rounded(.up)))
        }

        let invScale = 1.0 / rasterScale

        let rgba = colorRGBA(configuration.fuzzColor)
        let maxOpacity = RainSurfaceMath.clamp(configuration.fuzzMaxOpacity, min: 0.0, max: 1.0)
        if maxOpacity <= 0.000_1 { return }

        var ySurfacePxByX = [Double](repeating: 0.0, count: w)
        var bandOutByX = [Double](repeating: 0.0, count: w)
        var bandInByX = [Double](repeating: 0.0, count: w)
        var strengthByX = [Double](repeating: 0.0, count: w)
        var wetMaskByX = [Bool](repeating: false, count: w)

        let bandBasePxUnclamped = Double(chartRect.height) * Double(rasterScale) * configuration.fuzzWidthFraction
        let bandBasePx = RainSurfaceMath.clamp(
            bandBasePxUnclamped,
            min: configuration.fuzzWidthPixelsClamp.lowerBound,
            max: configuration.fuzzWidthPixelsClamp.upperBound
        )

        let maxH = max(0.000_001, Double(heights.max() ?? 0.0))
        let baselineYPx = Double((baselineY - chartRect.minY) * rasterScale)

        let insideWidthFactor = RainSurfaceMath.clamp(configuration.fuzzInsideWidthFactor, min: 0.10, max: 1.00)

        func sampleHeightAtXPixel(_ xPix: Int) -> Double {
            let xPoints = Double(chartRect.minX) + (Double(xPix) + 0.5) * Double(invScale)
            let pos = (xPoints - Double(chartRect.minX)) / Double(stepX) - 0.5

            if heights.count == 1 { return Double(heights[0]) }

            let i0 = Int(floor(pos))
            let t = pos - Double(i0)

            if i0 <= 0 { return Double(heights[0]) }
            if i0 >= heights.count - 1 { return Double(heights[heights.count - 1]) }

            let a = Double(heights[i0])
            let b = Double(heights[i0 + 1])
            return RainSurfaceMath.lerp(a, b, t)
        }

        func sampleCertaintyAtXPixel(_ xPix: Int) -> Double {
            let xPoints = Double(chartRect.minX) + (Double(xPix) + 0.5) * Double(invScale)
            let pos = (xPoints - Double(chartRect.minX)) / Double(stepX) - 0.5

            if certainties.count == 1 { return RainSurfaceMath.clamp01(certainties[0]) }

            let i0 = Int(floor(pos))
            let t = pos - Double(i0)

            if i0 <= 0 { return RainSurfaceMath.clamp01(certainties[0]) }
            if i0 >= certainties.count - 1 { return RainSurfaceMath.clamp01(certainties[certainties.count - 1]) }

            let a = RainSurfaceMath.clamp01(certainties[i0])
            let b = RainSurfaceMath.clamp01(certainties[i0 + 1])
            return RainSurfaceMath.lerp(a, b, t)
        }

        func fuzzStrengthFromChance(_ chance: Double) -> Double {
            let t = RainSurfaceMath.clamp01(configuration.fuzzChanceThreshold)
            let w = max(0.000_001, configuration.fuzzChanceTransition)

            let low = t - 0.5 * w
            let high = t + 0.5 * w

            if chance <= low { return 1.0 }
            if chance >= high { return 0.0 }

            let u = (chance - low) / (high - low)
            return 1.0 - RainSurfaceMath.smoothstep01(u)
        }

        for x in 0..<w {
            let hPt = sampleHeightAtXPixel(x)
            wetMaskByX[x] = hPt > (Double(invScale) * 0.35)
        }

        // Tight proximity: avoids the long “after-stop” smear.
        let proxRadiusPx = max(6.0, min(28.0, Double(w) * 0.035))
        var distToWet = [Int](repeating: Int.max / 4, count: w)

        var lastWet = -10_000
        for x in 0..<w {
            if wetMaskByX[x] { lastWet = x }
            distToWet[x] = x - lastWet
        }

        lastWet = 10_000
        for x in stride(from: w - 1, through: 0, by: -1) {
            if wetMaskByX[x] { lastWet = x }
            let d = lastWet - x
            distToWet[x] = min(distToWet[x], d)
        }

        func wetProximity(_ x: Int) -> Double {
            let d = Double(max(0, distToWet[x]))
            return exp(-d / proxRadiusPx)
        }

        for x in 0..<w {
            let hPt = max(0.0, sampleHeightAtXPixel(x))
            let chance = RainSurfaceMath.clamp01(sampleCertaintyAtXPixel(x))

            let ySurfPoints = Double(baselineY - CGFloat(hPt))
            let ySurfPx = (ySurfPoints - Double(chartRect.minY)) * Double(rasterScale)
            ySurfacePxByX[x] = ySurfPx

            let hNorm = RainSurfaceMath.clamp01(hPt / maxH)
            let presence = sqrt(hNorm)

            let prox = wetProximity(x)

            // Only treat low-height widening as “tail shaping” while still meaningfully wet.
            let wetGate = RainSurfaceMath.smoothstep01(RainSurfaceMath.clamp01(hNorm / 0.10))

            // Steep-wall boost so vertical sides carry fuzz.
            let xL = max(0, x - 1)
            let xR = min(w - 1, x + 1)
            let hL = max(0.0, sampleHeightAtXPixel(xL))
            let hR = max(0.0, sampleHeightAtXPixel(xR))
            let dxPts = max(0.000_001, 2.0 * Double(invScale))
            let slopeAbs = abs(hR - hL) / dxPts
            let slopeN = RainSurfaceMath.clamp01(slopeAbs / 2.0)
            let slopeBoost = pow(slopeN, 0.55) * 0.55 * (0.35 + 0.65 * prox)

            let lowH = pow(1.0 - hNorm, configuration.fuzzLowHeightPower)
            let lowStrengthBoost = configuration.fuzzLowHeightBoost * lowH * wetGate * (0.25 + 0.75 * prox)

            let threshFuzz = fuzzStrengthFromChance(chance)
            let invChance = 1.0 - chance
            let uncertainty = max(configuration.fuzzUncertaintyFloor, pow(invChance, configuration.fuzzUncertaintyExponent))

            var sTarget = max(threshFuzz, max(uncertainty, max(lowStrengthBoost, slopeBoost)))

            // Floor ensures fuzz remains visible even in high-certainty plateaus.
            let minStrength = max(configuration.fuzzChanceMinStrength, 0.22)
            sTarget = minStrength + (1.0 - minStrength) * sTarget
            sTarget = RainSurfaceMath.clamp01(sTarget)

            // Baseline fuzz fades quickly away from the wet segment.
            let baselineStrength = (0.05 + 0.18 * sTarget) * pow(prox, 1.60)

            let s = RainSurfaceMath.lerp(baselineStrength, sTarget, presence)
            strengthByX[x] = RainSurfaceMath.clamp01(s)

            let proxW = pow(prox, 0.90)
            let lowFactor = 1.0 + configuration.fuzzLowHeightBoost * lowH * proxW * wetGate
            let widthMod = (0.62 + 1.05 * s) * lowFactor

            let outBand = RainSurfaceMath.clamp(bandBasePx * widthMod, min: 6.0, max: bandBasePx * 1.90)
            let inBand = RainSurfaceMath.clamp(outBand * insideWidthFactor, min: 4.0, max: outBand)

            bandOutByX[x] = outBand
            bandInByX[x] = inBand
        }

        let searchRadius = Int(RainSurfaceMath.clamp(bandBasePx * 0.33, min: 6.0, max: 26.0))

        let maxBandIn = bandInByX.max() ?? 0.0
        let maxBandOut = bandOutByX.max() ?? 0.0

        let minSurf = ySurfacePxByX.min() ?? 0.0
        let yMin = max(0, Int(floor(minSurf - maxBandOut - 2.0)))
        let yMax = min(h - 1, Int(ceil(baselineYPx + maxBandIn + 2.0)))
        if yMax <= yMin { return }

        var fuzzPixels = [UInt8](repeating: 0, count: w * h * 4)
        var erodePixels = [UInt8](repeating: 0, count: w * h * 4)

        let seed = configuration.noiseSeed

        func hash01(_ ax: Int, _ ay: Int, salt: UInt64) -> Double {
            var s = RainSurfacePRNG.combine(seed ^ salt, UInt64(bitPattern: Int64(ax)))
            s = RainSurfacePRNG.combine(s, UInt64(bitPattern: Int64(ay)))
            return RainSurfacePRNG.float01(s)
        }

        func valueNoise01(_ x: Double, _ y: Double, salt: UInt64) -> Double {
            let x0 = Int(floor(x))
            let y0 = Int(floor(y))
            let tx = x - Double(x0)
            let ty = y - Double(y0)

            let v00 = hash01(x0, y0, salt: salt)
            let v10 = hash01(x0 + 1, y0, salt: salt)
            let v01 = hash01(x0, y0 + 1, salt: salt)
            let v11 = hash01(x0 + 1, y0 + 1, salt: salt)

            let sx = RainSurfaceMath.smoothstep01(tx)
            let sy = RainSurfaceMath.smoothstep01(ty)

            let a = RainSurfaceMath.lerp(v00, v10, sx)
            let b = RainSurfaceMath.lerp(v01, v11, sx)
            return RainSurfaceMath.lerp(a, b, sy)
        }

        let baseDensity = RainSurfaceMath.clamp(configuration.fuzzBaseDensity, min: 0.0, max: 1.0)
        let hazeStrength = RainSurfaceMath.clamp(configuration.fuzzHazeStrength, min: 0.0, max: 2.0)
        let speckStrength = RainSurfaceMath.clamp(configuration.fuzzSpeckStrength, min: 0.0, max: 3.0)

        let edgePower = max(0.50, configuration.fuzzEdgePower)
        let distPowOut = max(0.25, configuration.fuzzDistancePowerOutside)
        let distPowIn = max(0.25, configuration.fuzzDistancePowerInside)

        let insideOpacityFactor = RainSurfaceMath.clamp(configuration.fuzzInsideOpacityFactor, min: 0.0, max: 1.0)
        let insideSpeckFrac = RainSurfaceMath.clamp(configuration.fuzzInsideSpeckleFraction, min: 0.0, max: 1.0)

        let erodeEnabled = configuration.fuzzErodeEnabled
        let erodeStrength = RainSurfaceMath.clamp(configuration.fuzzErodeStrength, min: 0.0, max: 1.0)
        let erodeEdgePower = max(0.50, configuration.fuzzErodeEdgePower)

        let cell = max(1.0, configuration.fuzzClumpCellPixels)

        for y in yMin...yMax {
            for x in 0..<w {

                var bestX = x
                var bestDy = Double(y) - ySurfacePxByX[x]
                var bestD2 = bestDy * bestDy

                if searchRadius > 0 {
                    let lo = max(0, x - searchRadius)
                    let hi = min(w - 1, x + searchRadius)
                    if lo < hi {
                        for xx in lo...hi where xx != x {
                            let dy = Double(y) - ySurfacePxByX[xx]
                            let dx = Double(xx - x)
                            let d2 = dx * dx + dy * dy
                            if d2 < bestD2 {
                                bestD2 = d2
                                bestDy = dy
                                bestX = xx
                            }
                        }
                    }
                }

                let inside = bestDy >= 0.0
                let band = inside ? bandInByX[bestX] : bandOutByX[bestX]
                if band <= 0.000_1 { continue }

                let dist = sqrt(bestD2)
                if dist > band { continue }

                let u = 1.0 - (dist / band)
                let edge = pow(max(0.0, u), edgePower)

                let sCurve = strengthByX[bestX]
                if sCurve <= 0.000_1 { continue }

                let clump = valueNoise01(Double(x) / cell, Double(y) / cell, salt: 0xC1A0_F00D)
                let micro = valueNoise01(Double(x) / 2.6, Double(y) / 2.6, salt: 0xBADC_0FFE)

                let dPow = inside ? distPowIn : distPowOut
                let distFalloff = pow(max(0.0, u), dPow)

                let sideMul = inside ? insideOpacityFactor : 1.0

                // Stronger continuous haze so the fuzz is visible again.
                let haze = (0.12 + 0.32 * hazeStrength * (0.55 + 0.45 * clump)) * sideMul

                let speckProbBase = (0.18 + 0.74 * baseDensity) * (0.55 + 0.45 * micro)
                let speckFrac = inside ? insideSpeckFrac : 1.0
                let speckProb = RainSurfaceMath.clamp(speckProbBase * speckFrac, min: 0.0, max: 0.95)

                var a = maxOpacity * sCurve * (0.85 * haze + 0.65 * speckStrength * distFalloff) * edge
                a += maxOpacity * sCurve * 0.06 * edge

                let r = hash01(x, y, salt: 0xFACE_FEED)
                if r < speckProb {
                    a += maxOpacity * sCurve * 0.70 * edge
                }

                a = RainSurfaceMath.clamp(a, min: 0.0, max: 1.0)
                if a <= 0.000_1 { continue }

                let idx = (y * w + x) * 4

                let alpha8 = UInt8((a * 255.0).rounded())
                let pr = UInt8((rgba.r * a * 255.0).rounded())
                let pg = UInt8((rgba.g * a * 255.0).rounded())
                let pb = UInt8((rgba.b * a * 255.0).rounded())

                fuzzPixels[idx + 0] = pr
                fuzzPixels[idx + 1] = pg
                fuzzPixels[idx + 2] = pb
                fuzzPixels[idx + 3] = alpha8

                if erodeEnabled, inside, erodeStrength > 0.000_1 {
                    let ek = erodeStrength * (0.30 + 0.70 * sCurve)
                    let erEdge = pow(max(0.0, u), erodeEdgePower)
                    let holes = (hash01(x, y, salt: 0xDEAD_BEEF) < (0.06 + 0.10 * baseDensity)) ? 1.0 : 0.0
                    var ea = ek * erEdge * (0.14 + 0.14 * clump) + ek * erEdge * holes * 0.25
                    ea = RainSurfaceMath.clamp(ea, min: 0.0, max: 1.0)

                    if ea > 0.000_1 {
                        let e8 = UInt8((ea * 255.0).rounded())
                        erodePixels[idx + 0] = 255
                        erodePixels[idx + 1] = 255
                        erodePixels[idx + 2] = 255
                        erodePixels[idx + 3] = e8
                    }
                }
            }
        }

        guard let fuzzImage = makeCGImage(width: w, height: h, pixelsRGBA: fuzzPixels) else { return }
        guard let erodeImage = makeCGImage(width: w, height: h, pixelsRGBA: erodePixels) else { return }

        let fuzz = Image(decorative: fuzzImage, scale: rasterScale, orientation: .up)
        let erode = Image(decorative: erodeImage, scale: rasterScale, orientation: .up)

        let savedBlend = context.blendMode
        context.blendMode = .destinationOut
        context.draw(erode, in: chartRect)
        context.blendMode = savedBlend

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            let blurPx = max(0.0, configuration.fuzzMicroBlurPixels)
            let blurPts = blurPx / Double(rasterScale)
            if blurPts > 0.000_1 {
                layer.addFilter(.blur(radius: blurPts))
            }
            layer.draw(fuzz, in: chartRect)
        }
    }

    // MARK: - CGImage helper

    private static func makeCGImage(width: Int, height: Int, pixelsRGBA: [UInt8]) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        guard pixelsRGBA.count == width * height * 4 else { return nil }

        let data = Data(pixelsRGBA)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )

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

    // MARK: - Colour conversion

    private struct RGBA {
        var r: Double
        var g: Double
        var b: Double
        var a: Double
    }

    private static func colorRGBA(_ color: Color) -> RGBA {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        return RGBA(r: Double(r), g: Double(g), b: Double(b), a: Double(a))
        #else
        return RGBA(r: 1, g: 1, b: 1, a: 1)
        #endif
    }
}
