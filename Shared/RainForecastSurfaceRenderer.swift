//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI
import UIKit

/// Canvas renderer for the nowcast “surface” (mound + dissipation).
struct RainForecastSurfaceRenderer {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration
    func render(in context: inout GraphicsContext, size: CGSize, displayScale: CGFloat) {
        guard size.width > 1, size.height > 1 else { return }
        let rect = CGRect(origin: .zero, size: size)
        let cfg = configuration
        let samples = min(intensities.count, certainties.count)
        guard samples >= 3 else { return }
        let baselineY = rect.minY + rect.height * cfg.baselineFractionFromTop + cfg.baselineOffsetPixels / max(1.0, displayScale)
        let topHeadroom = rect.height * cfg.topHeadroomFraction
        let minuteIntensities = Array(intensities.prefix(samples))
        let minuteCertainties = Array(certainties.prefix(samples))
        let intensitiesFilled = fillMissingLinearHoldEnds(minuteIntensities)
        let refMax = robustReferenceMaxMMPerHour(intensities: intensitiesFilled, configuration: cfg)
        guard refMax > 0.000001 else { return }
        let heights = intensitiesFilled.map { v -> CGFloat in
            guard v.isFinite else { return 0 }
            let x = clamp01(v / refMax)
            let g = max(0.01, cfg.intensityGamma)
            let y = pow(x, g)
            return CGFloat(y)
        }
        let certainties01 = minuteCertainties.map { clamp01($0) }
        let maxDense = max(64, cfg.maxDenseSamples)
        let denseCount = denseSampleCount(widthPx: rect.width * displayScale, maxDenseSamples: maxDense)
        let denseHeights = resampleLinear(values: heights, count: denseCount)
        let denseCertainties = resampleLinear(values: certainties01.map { CGFloat($0) }, count: denseCount)
        let eased = applyEdgeEasing(values: denseHeights, configuration: cfg)
        let scaledHeights = scaleToCanvasHeight(
            normalized: eased,
            baselineY: baselineY,
            topHeadroom: topHeadroom,
            typicalPeakFraction: cfg.typicalPeakFraction
        )
        let curvePoints = buildCurvePoints(rect: rect, baselineY: baselineY, heightsInCanvasSpace: scaledHeights)
        let corePath = buildCorePath(rect: rect, baselineY: baselineY, curvePoints: curvePoints)
        drawCore(in: &context, corePath: corePath, curvePoints: curvePoints, baselineY: baselineY, configuration: cfg)
        if cfg.rimEnabled, cfg.rimWidthPixels > 0.01 {
            drawRim(in: &context, rect: rect, curvePoints: curvePoints, baselineY: baselineY, configuration: cfg, displayScale: displayScale)
        }
        if cfg.baselineEnabled, cfg.baselineLineOpacity > 0.0001 {
            drawBaseline(in: &context, rect: rect, baselineY: baselineY, configuration: cfg, displayScale: displayScale)
        }
        if cfg.fuzzEnabled, cfg.canEnableFuzz {
            let bandHalfWidth = computeBandHalfWidthPoints(rect: rect, displayScale: displayScale, configuration: cfg)
            if bandHalfWidth > 0.5 {
                drawDissipationFuzz(
                    in: &context,
                    rect: rect,
                    baselineY: baselineY,
                    corePath: corePath,
                    curvePoints: curvePoints,
                    heights: scaledHeights,
                    certainties01: denseCertainties,
                    bandHalfWidth: bandHalfWidth,
                    displayScale: displayScale,
                    configuration: cfg
                )
            }
        }
    }
}
private extension RainForecastSurfaceRenderer {
    static func drawCore(
        in context: inout GraphicsContext,
        corePath: Path,
        curvePoints: [CGPoint],
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        guard !curvePoints.isEmpty else { return }
        let topY = curvePoints.map(\.y).min() ?? baselineY
        let startPoint = CGPoint(x: curvePoints.first?.x ?? 0.0, y: topY)
        let endPoint = CGPoint(x: curvePoints.first?.x ?? 0.0, y: baselineY)
        let top = cfg.coreTopColor
        let body = cfg.coreBodyColor
        let mid = Color.blend(body, top, t: cfg.coreTopMix)
        let fade = clamp01(cfg.coreFadeFraction)
        let midStop = 0.42
        var stops: [Gradient.Stop] = [
            Gradient.Stop(color: top, location: 0.0),
            Gradient.Stop(color: mid, location: midStop),
        ]
        if fade > 0.0001 {
            let fadeStart = max(midStop, 1.0 - fade)
            stops.append(Gradient.Stop(color: body, location: fadeStart))
            stops.append(Gradient.Stop(color: body.opacity(0.0), location: 1.0))
        } else {
            stops.append(Gradient.Stop(color: body, location: 1.0))
        }
        let gradient = Gradient(stops: stops)
        context.fill(corePath, with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint))
    }
    static func drawRim(
        in context: inout GraphicsContext,
        rect: CGRect,
        curvePoints: [CGPoint],
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale ds: CGFloat
    ) {
        guard curvePoints.count >= 2 else { return }
        let path = buildCurveStrokePath(curvePoints: curvePoints)
        let w = max(0.5, cfg.rimWidthPixels) / max(1.0, ds)
        context.stroke(path, with: .color(cfg.rimColor), lineWidth: w)
    }
    static func drawBaseline(
        in context: inout GraphicsContext,
        rect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale ds: CGFloat
    ) {
        let width = max(0.5, cfg.baselineWidthPixels) / max(1.0, ds)
        let alpha = clamp01(cfg.baselineLineOpacity)
        guard alpha > 0.00001 else { return }
        let y = baselineY
        let fade = clamp01(cfg.baselineEndFadeFraction)
        if fade <= 0.0001 {
            context.stroke(Path { p in
                p.move(to: CGPoint(x: rect.minX, y: y))
                p.addLine(to: CGPoint(x: rect.maxX, y: y))
            }, with: .color(cfg.baselineColor.opacity(alpha)), lineWidth: width)
            return
        }
        let x0 = rect.minX
        let x1 = rect.maxX
        let dx = rect.width
        let fadeW = CGFloat(fade) * dx
        let leftFadeEnd = min(x1, x0 + fadeW)
        let rightFadeStart = max(x0, x1 - fadeW)
        let stops: [Gradient.Stop] = [
            .init(color: cfg.baselineColor.opacity(0.0), location: 0.0),
            .init(color: cfg.baselineColor.opacity(alpha), location: clamp01(Double((leftFadeEnd - x0) / dx))),
            .init(color: cfg.baselineColor.opacity(alpha), location: clamp01(Double((rightFadeStart - x0) / dx))),
            .init(color: cfg.baselineColor.opacity(0.0), location: 1.0),
        ]
        let gradient = Gradient(stops: stops)
        let path = Path { p in
            p.move(to: CGPoint(x: x0, y: y))
            p.addLine(to: CGPoint(x: x1, y: y))
        }
        context.stroke(path, with: .linearGradient(gradient, startPoint: CGPoint(x: x0, y: y), endPoint: CGPoint(x: x1, y: y)), lineWidth: width)
    }
}
private extension RainForecastSurfaceRenderer {
    static func drawDissipationFuzz(
        in context: inout GraphicsContext,
        rect: CGRect,
        baselineY: CGFloat,
        corePath: Path,
        curvePoints: [CGPoint],
        heights: [CGFloat],
        certainties01: [CGFloat],
        bandHalfWidth: CGFloat,
        displayScale ds: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        guard cfg.fuzzMaxOpacity > 0.0001 else { return }
        guard curvePoints.count == heights.count, heights.count == certainties01.count else { return }
        guard heights.count >= 3 else { return }
        let isExtension = WidgetWeaverRuntime.isRunningInAppExtension
        let curvePath = buildCurveStrokePath(curvePoints: curvePoints)
        let clipRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0.0, baselineY - rect.minY))
        var strength = computeFuzzStrengthPerPoint(heights: heights, certainties01: certainties01.map { Double($0) }, configuration: cfg)
        let wetEps = max(0.5 / max(1.0, Double(ds)), 0.0001)
        let wetMask = heights.map { Double($0) > wetEps }
        let distToWet = distanceToNearestTrue(wetMask)
        let samplesPerPx = Double(heights.count) / max(1.0, Double(rect.width))
        let edgeWindowSamples = max(1, Int(round(cfg.fuzzEdgeWindowPx * samplesPerPx)))
        if distToWet.count == strength.count {
            for i in 0..<strength.count where distToWet[i] > edgeWindowSamples {
                strength[i] = 0.0
            }
        }
        let tailMinutes = max(0.0, cfg.fuzzTailMinutes)
        if tailMinutes > 0.01 {
            let tailSamples = max(1, Int(round(tailMinutes / 60.0 * Double(strength.count))))
            if tailSamples > 0 {
                for i in 1..<strength.count {
                    let prevWet = wetMask[i - 1]
                    let curWet = wetMask[i]
                    if prevWet != curWet {
                        let start = max(0, i - tailSamples)
                        let end = min(strength.count - 1, i + tailSamples)
                        for j in start...end {
                            let d = Double(abs(j - i))
                            let t = 1.0 - clamp01(d / Double(tailSamples))
                            strength[j] *= (1.0 + 0.65 * pow(t, 1.25))
                        }
                    }
                }
            }
        }
        let maxH = max(0.0001, Double(heights.max() ?? 0.0))
        let invMaxH = 1.0 / maxH
        var maxSlope: Double = 0.0
        let dx = max(1e-6, Double(rect.width) / Double(max(1, heights.count - 1)))
        var slopes = Array(repeating: 0.0, count: heights.count)
        for i in 0..<heights.count {
            let a = Double(heights[max(0, i - 1)])
            let b = Double(heights[min(heights.count - 1, i + 1)])
            let s = abs(b - a) / (2.0 * dx)
            slopes[i] = s
            maxSlope = max(maxSlope, s)
        }
        for i in 0..<strength.count {
            let hn = clamp01(Double(heights[i]) * invMaxH)
            let low = pow(max(0.0, 1.0 - hn), max(0.05, cfg.fuzzLowHeightPower))
            let heightFade = 0.12 + 0.88 * low
            strength[i] *= heightFade
            if maxSlope > 0.000001 {
                let sn = clamp01(slopes[i] / maxSlope)
                let slopeFactor = 0.22 + 0.78 * pow(sn, 0.65)
                strength[i] *= slopeFactor
            }
        }
        let exp = max(0.05, cfg.fuzzStrengthExponent)
        let gain = max(0.0, cfg.fuzzStrengthGain)
        if abs(exp - 1.0) > 0.000001 || abs(gain - 1.0) > 0.000001 {
            for i in 0..<strength.count {
                let s = clamp01(strength[i])
                strength[i] = clamp01(pow(s, exp) * gain)
            }
        }
        let maxStrength = strength.max() ?? 0.0
        guard maxStrength > 0.00001 else { return }
        var maxAlpha = clamp01(cfg.fuzzMaxOpacity)
        maxAlpha *= max(0.0, cfg.fuzzSpeckStrength)
        let maxStopCap = isExtension ? 20 : 64
        let stopCount = max(8, min(cfg.fuzzTextureGradientStops, maxStopCap))
        let dissipationColor = cfg.coreBodyColor
        let colourGradient = makeAlphaGradient(baseColor: dissipationColor, strength: strength, maxAlpha: maxAlpha, stops: stopCount)
        let maskGradient = makeAlphaGradient(baseColor: Color.white, strength: strength, maxAlpha: 1.0, stops: stopCount)
        let tilePx = max(32, min(cfg.fuzzTextureTilePixels, isExtension ? 256 : 512))
        let baseTileScale = fuzzNoiseTileScale(desiredTilePixels: tilePx)
        let baseSeed = RainSurfacePRNG.combine(cfg.noiseSeed, UInt64(curvePoints.count &* 977) &+ 0xA5A5_A5A5_A5A5_A5A5)
        let dustNoise = fuzzNoiseImage(preferred: .sparse)
        let erodeNoise = fuzzNoiseImage(preferred: .sparse)
        if cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.0001 {
            applyEdgeErosion(
                in: &context,
                rect: rect,
                clipRect: clipRect,
                corePath: corePath,
                curvePath: curvePath,
                bandHalfWidth: bandHalfWidth,
                maskGradient: maskGradient,
                noiseImage: erodeNoise,
                noiseTileScale: baseTileScale * 0.82,
                configuration: cfg,
                seed: RainSurfacePRNG.combine(baseSeed, 0xBEE1_BEE1_BEE1_BEE1)
            )
        }
        let allowOuterDust = cfg.fuzzOuterDustEnabled && (!isExtension || cfg.fuzzOuterDustEnabledInAppExtension)
        let dustPasses = isExtension ? max(0, cfg.fuzzOuterDustPassCountInAppExtension) : max(0, cfg.fuzzOuterDustPassCount)
        if allowOuterDust, dustPasses > 0 {
            drawOuterDust(
                in: &context,
                rect: rect,
                clipRect: clipRect,
                corePath: corePath,
                curvePath: curvePath,
                bandHalfWidth: bandHalfWidth,
                colourGradient: colourGradient,
                noiseImage: dustNoise,
                noiseTileScale: baseTileScale * 1.10,
                passCount: dustPasses,
                configuration: cfg,
                seed: RainSurfacePRNG.combine(baseSeed, 0xD005_700D_D005_700D)
            )
        }
        if !isExtension, cfg.fuzzHazeStrength > 0.0001 {
            let hazeAlpha = clamp01(cfg.fuzzHazeStrength) * clamp01(maxStrength) * maxAlpha
            if hazeAlpha > 0.00001 {
                context.blendMode = .normal
                context.stroke(curvePath, with: .color(dissipationColor.opacity(hazeAlpha)), lineWidth: bandHalfWidth * 2.0 * CGFloat(max(0.10, cfg.fuzzHazeStrokeWidthFactor)))
                context.blendMode = .normal
            }
        }
    }
    static func applyEdgeErosion(
        in context: inout GraphicsContext,
        rect: CGRect,
        clipRect: CGRect,
        corePath: Path,
        curvePath: Path,
        bandHalfWidth: CGFloat,
        maskGradient: Gradient,
        noiseImage: SwiftUI.Image?,
        noiseTileScale: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        seed: UInt64
    ) {
        let strength = clamp01(cfg.fuzzErodeStrength)
        guard strength > 0.0001 else { return }
        let narrowMul = max(0.10, cfg.fuzzErodeStrokeWidthFactor)
        let wideMul = max(narrowMul * 5.0, narrowMul + 3.0)
        context.blendMode = .destinationOut
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))
            layer.clip(to: corePath)
            let wideStroke = curvePath.strokedPath(StrokeStyle(lineWidth: bandHalfWidth * 2.0 * CGFloat(wideMul), lineCap: .round, lineJoin: .round))
            let wideGrad = scaledGradient(maskGradient, alphaMultiplier: 0.55 * strength)
            layer.fill(wideStroke, with: .linearGradient(wideGrad, startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
        }
        context.blendMode = .normal
        context.blendMode = .destinationOut
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))
            layer.clip(to: corePath)
            let narrowStroke = curvePath.strokedPath(StrokeStyle(lineWidth: bandHalfWidth * 2.0 * CGFloat(narrowMul), lineCap: .round, lineJoin: .round))
            let narrowGrad = scaledGradient(maskGradient, alphaMultiplier: 1.25 * strength)
            layer.fill(narrowStroke, with: .linearGradient(narrowGrad, startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
            if let noiseImage {
                var prng = RainSurfacePRNG(seed: seed)
                let ox = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.95
                let oy = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.95
                let origin = CGPoint(x: rect.minX + ox, y: rect.minY + oy)
                let shading = GraphicsContext.Shading.tiledImage(noiseImage, origin: origin, sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: noiseTileScale)
                layer.blendMode = .destinationIn
                layer.fill(Path(rect), with: shading)
                layer.blendMode = .normal
            }
        }
        context.blendMode = .normal
    }
    static func drawOuterDust(
        in context: inout GraphicsContext,
        rect: CGRect,
        clipRect: CGRect,
        corePath: Path,
        curvePath: Path,
        bandHalfWidth: CGFloat,
        colourGradient: Gradient,
        noiseImage: SwiftUI.Image?,
        noiseTileScale: CGFloat,
        passCount: Int,
        configuration cfg: RainForecastSurfaceConfiguration,
        seed: UInt64
    ) {
        let passes = max(0, min(passCount, 4))
        guard passes > 0 else { return }
        let innerW = max(0.10, cfg.fuzzTextureInnerBandMultiplier)
        let outerW = max(innerW, cfg.fuzzTextureOuterBandMultiplier)
        let innerA = max(0.0, cfg.fuzzTextureInnerOpacityMultiplier)
        let outerA = max(0.0, cfg.fuzzTextureOuterOpacityMultiplier)
        let ts: [Double] = {
            switch passes {
            case 1: return [0.0]
            case 2: return [0.0, 1.0]
            case 3: return [0.0, 0.55, 1.0]
            default: return (0..<passes).map { Double($0) / Double(max(1, passes - 1)) }
            }
        }()
        context.blendMode = .normal
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))
            for t in ts {
                let wMul = lerp(innerW, outerW, t)
                let aMul = lerp(innerA, outerA, t)
                if aMul <= 0.00001 { continue }
                let stroke = curvePath.strokedPath(StrokeStyle(lineWidth: bandHalfWidth * 2.0 * CGFloat(wMul), lineCap: .round, lineJoin: .round))
                let g = scaledGradient(colourGradient, alphaMultiplier: aMul)
                layer.fill(stroke, with: .linearGradient(g, startPoint: CGPoint(x: rect.minX, y: rect.midY), endPoint: CGPoint(x: rect.maxX, y: rect.midY)))
            }
            if let noiseImage {
                var prng = RainSurfacePRNG(seed: seed)
                let ox = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.85
                let oy = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.85 + bandHalfWidth * 0.25
                let origin = CGPoint(x: rect.minX + ox, y: rect.minY + oy)
                let shading = GraphicsContext.Shading.tiledImage(noiseImage, origin: origin, sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1), scale: noiseTileScale)
                layer.blendMode = .destinationIn
                layer.fill(Path(rect), with: shading)
                layer.blendMode = .normal
            }
            layer.blendMode = .destinationOut
            layer.fill(corePath, with: .color(Color.white))
            layer.blendMode = .normal
        }
        context.blendMode = .normal
    }
    enum FuzzNoiseVariant: String { case normal = "RainFuzzNoise"; case sparse = "RainFuzzNoise_Sparse"; case dense = "RainFuzzNoise_Dense" }
    static func fuzzNoiseImage(preferred variant: FuzzNoiseVariant) -> SwiftUI.Image? {
        let name = variant.rawValue
        guard UIImage(named: name) != nil else { return nil }
        return Image(name)
    }
    static func fuzzNoiseTileScale(desiredTilePixels: Int, authoredPixels: Int = 256) -> CGFloat {
        let desired = max(1, desiredTilePixels)
        let authored = max(1, authoredPixels)
        return CGFloat(Double(desired) / Double(authored))
    }
}
private extension RainForecastSurfaceRenderer {
    static func computeBandHalfWidthPoints(rect: CGRect, displayScale ds: CGFloat, configuration cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let minDim = min(rect.height * 0.28, rect.width * 0.10)
        let frac = clamp01(cfg.fuzzWidthFraction)
        let px = CGFloat(frac) * minDim * ds
        let clampPx = cfg.fuzzWidthPixelsClamp
        let clampedPx = min(max(px, clampPx.lowerBound), clampPx.upperBound)
        return clampedPx / max(1.0, ds) / 2.0
    }
    static func denseSampleCount(widthPx: CGFloat, maxDenseSamples: Int) -> Int {
        let target = Int(max(24.0, min(1_400.0, widthPx)))
        return min(maxDenseSamples, max(64, target))
    }
    static func robustReferenceMaxMMPerHour(intensities: [Double], configuration cfg: RainForecastSurfaceConfiguration) -> Double {
        let hardMax = max(0.1, cfg.intensityReferenceMaxMMPerHour)
        let p = max(0.50, min(cfg.robustMaxPercentile, 0.995))
        let finite = intensities.filter { $0.isFinite && $0 >= 0 }
        guard !finite.isEmpty else { return hardMax }
        let sorted = finite.sorted()
        let idx = Int(round(p * Double(sorted.count - 1)))
        let robust = sorted[max(0, min(sorted.count - 1, idx))]
        return max(0.05, min(hardMax, robust > 0 ? robust : hardMax))
    }
    static func fillMissingLinearHoldEnds(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return values }
        var v = values
        let n = v.count
        var firstFiniteIdx: Int?
        var lastFiniteIdx: Int?
        for i in 0..<n {
            if v[i].isFinite {
                firstFiniteIdx = i
                break
            }
        }
        for i in stride(from: n - 1, through: 0, by: -1) {
            if v[i].isFinite {
                lastFiniteIdx = i
                break
            }
        }
        if firstFiniteIdx == nil || lastFiniteIdx == nil {
            return Array(repeating: 0.0, count: n)
        }
        let first = firstFiniteIdx!
        let last = lastFiniteIdx!
        for i in 0..<first { v[i] = v[first] }
        for i in (last + 1)..<n { v[i] = v[last] }
        var i = first
        while i <= last {
            if v[i].isFinite { i += 1; continue }
            let start = i - 1
            var j = i
            while j <= last && !v[j].isFinite { j += 1 }
            let end = j
            let a = v[start]
            let b = v[end]
            let span = Double(end - start)
            if span <= 0 {
                for k in i..<end { v[k] = a }
            } else {
                for k in i..<end {
                    let t = Double(k - start) / span
                    v[k] = a + (b - a) * t
                }
            }
            i = end + 1
        }
        return v
    }
    static func resampleLinear<T: BinaryFloatingPoint>(values: [T], count: Int) -> [T] {
        guard count >= 2 else { return values.isEmpty ? [] : [values[0]] }
        guard values.count >= 2 else { return Array(repeating: values.first ?? 0, count: count) }
        let n = values.count
        var out = Array(repeating: T.zero, count: count)
        for i in 0..<count {
            let t = T(i) / T(count - 1)
            let x = t * T(n - 1)
            let lo = Int(floor(Double(x)))
            let hi = min(n - 1, lo + 1)
            let f = x - T(lo)
            out[i] = values[lo] * (1 - f) + values[hi] * f
        }
        return out
    }
    static func applyEdgeEasing(values: [CGFloat], configuration cfg: RainForecastSurfaceConfiguration) -> [CGFloat] {
        guard values.count >= 4 else { return values }
        var out = values
        let n = out.count
        let easeN = max(2, Int(round(0.06 * Double(n))))
        for i in 0..<easeN {
            let t = Double(i) / Double(max(1, easeN - 1))
            let w = pow(t, 1.7)
            out[i] *= CGFloat(w)
            out[n - 1 - i] *= CGFloat(w)
        }
        return out
    }
    static func scaleToCanvasHeight(normalized: [CGFloat], baselineY: CGFloat, topHeadroom: CGFloat, typicalPeakFraction: CGFloat) -> [CGFloat] {
        guard !normalized.isEmpty else { return [] }
        let maxN = max(0.0001, normalized.max() ?? 0.0)
        let available = max(0.0, baselineY - topHeadroom)
        let targetPeak = available * CGFloat(clamp01(typicalPeakFraction))
        let scale = targetPeak / maxN
        return normalized.map { $0 * scale }
    }
    static func buildCurvePoints(rect: CGRect, baselineY: CGFloat, heightsInCanvasSpace: [CGFloat]) -> [CGPoint] {
        let n = heightsInCanvasSpace.count
        guard n >= 2 else { return [] }
        var pts: [CGPoint] = []
        pts.reserveCapacity(n)
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            let x = rect.minX + rect.width * t
            let h = heightsInCanvasSpace[i]
            let y = baselineY - h
            pts.append(CGPoint(x: x, y: y))
        }
        return pts
    }
    static func buildCorePath(rect: CGRect, baselineY: CGFloat, curvePoints: [CGPoint]) -> Path {
        var p = Path()
        guard let first = curvePoints.first, let last = curvePoints.last else { return p }
        p.move(to: CGPoint(x: first.x, y: baselineY))
        p.addLine(to: first)
        for pt in curvePoints.dropFirst() {
            p.addLine(to: pt)
        }
        p.addLine(to: CGPoint(x: last.x, y: baselineY))
        p.closeSubpath()
        return p
    }
    static func buildCurveStrokePath(curvePoints: [CGPoint]) -> Path {
        var p = Path()
        guard let first = curvePoints.first else { return p }
        p.move(to: first)
        for pt in curvePoints.dropFirst() {
            p.addLine(to: pt)
        }
        return p
    }
    static func computeFuzzStrengthPerPoint(
        heights: [CGFloat],
        certainties01: [Double],
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> [Double] {
        let n = min(heights.count, certainties01.count)
        guard n > 0 else { return [] }
        var out = Array(repeating: 0.0, count: n)
        let thr = clamp01(cfg.fuzzChanceThreshold)
        let trans = max(0.0001, cfg.fuzzChanceTransition)
        let exp = max(0.05, cfg.fuzzChanceExponent)
        let floorBase = clamp01(cfg.fuzzChanceFloor)
        let minS = clamp01(cfg.fuzzChanceMinStrength)
        for i in 0..<n {
            let c = clamp01(certainties01[i])
            let t0 = clamp01((thr - c) / trans)
            let t = pow(t0, exp)
            let s = floorBase + (1.0 - floorBase) * t
            out[i] = max(minS, s)
        }
        return out
    }
    static func makeAlphaGradient(baseColor: Color, strength: [Double], maxAlpha: Double, stops: Int) -> Gradient {
        let n = max(2, stops)
        if strength.isEmpty {
            return Gradient(stops: [.init(color: baseColor.opacity(0.0), location: 0.0), .init(color: baseColor.opacity(0.0), location: 1.0)])
        }
        var out: [Gradient.Stop] = []
        out.reserveCapacity(n)
        let count = strength.count
        for i in 0..<n {
            let t = Double(i) / Double(n - 1)
            let idx = Int(round(t * Double(count - 1)))
            let s = clamp01(strength[max(0, min(count - 1, idx))])
            let a = clamp01(s * maxAlpha)
            out.append(.init(color: baseColor.opacity(a), location: t))
        }
        return Gradient(stops: out)
    }
    static func scaledGradient(_ g: Gradient, alphaMultiplier: Double) -> Gradient {
        let m = max(0.0, alphaMultiplier)
        if m == 1.0 { return g }
        let scaledStops = g.stops.map { s in
            Gradient.Stop(color: s.color.opacity(m), location: s.location)
        }
        return Gradient(stops: scaledStops)
    }
    static func distanceToNearestTrue(_ flags: [Bool]) -> [Int] {
        let n = flags.count
        guard n > 0 else { return [] }
        let big = Int.max / 4
        var dist = Array(repeating: big, count: n)
        var last = -big
        for i in 0..<n {
            if flags[i] { last = i }
            dist[i] = i - last
        }
        last = big
        for i in stride(from: n - 1, through: 0, by: -1) {
            if flags[i] { last = i }
            dist[i] = min(dist[i], last - i)
        }
        return dist
    }
    static func clamp01(_ x: Double) -> Double { max(0.0, min(1.0, x)) }
    static func clamp01(_ x: CGFloat) -> CGFloat { max(0.0, min(1.0, x)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
}
private extension Color {
    static func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        let tt = max(0.0, min(1.0, t))
        let ua = UIColor(a)
        let ub = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let r = ar + (br - ar) * CGFloat(tt)
        let g = ag + (bg - ag) * CGFloat(tt)
        let b2 = ab + (bb - ab) * CGFloat(tt)
        let a2 = aa + (ba - aa) * CGFloat(tt)
        return Color(.sRGB, red: Double(r), green: Double(g), blue: Double(b2), opacity: Double(a2))
    }
}
