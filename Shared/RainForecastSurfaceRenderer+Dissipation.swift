//
//  RainForecastSurfaceRenderer+Dissipation.swift
//  WidgetWeaver
//
//  Created by . . on 12/31/25.
//

import Foundation
import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Dissipation fuzz (subtractive erosion + optional outer dust)

extension RainForecastSurfaceRenderer {
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

        let clipRect = CGRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.width,
            height: max(0.0, baselineY - rect.minY)
        )

        var strength = computeFuzzStrengthPerPoint(
            heights: heights,
            certainties01: certainties01.map { Double($0) },
            configuration: cfg
        )

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

        let maxStrength = strength.max() ?? 0.0
        guard maxStrength > 0.00001 else { return }

        var maxAlpha = clamp01(cfg.fuzzMaxOpacity)
        maxAlpha *= max(0.0, cfg.fuzzSpeckStrength)

        let maxStopCap = isExtension ? 18 : 64
        let stopCount = max(8, min(cfg.fuzzTextureGradientStops, maxStopCap))

        let dissipationColor = cfg.coreBodyColor

        let colourGradient = makeAlphaGradient(
            baseColor: dissipationColor,
            strength: strength,
            maxAlpha: maxAlpha,
            stops: stopCount
        )

        let maskGradient = makeAlphaGradient(
            baseColor: Color.white,
            strength: strength,
            maxAlpha: 1.0,
            stops: stopCount
        )

        let tilePx = max(32, min(cfg.fuzzTextureTilePixels, isExtension ? 256 : 512))
        let baseNoiseTileScale = fuzzNoiseTileScale(desiredTilePixels: tilePx)
        let erodeNoiseTileScale = baseNoiseTileScale * 0.82
        let dustNoiseTileScale = baseNoiseTileScale

        let baseSeed = RainSurfacePRNG.combine(
            cfg.noiseSeed,
            UInt64(curvePoints.count &* 977) &+ 0xA5A5_A5A5_A5A5_A5A5
        )

        // Sparse breakup is required for the mockup look.
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
                noiseTileScale: erodeNoiseTileScale,
                configuration: cfg,
                seed: RainSurfacePRNG.combine(baseSeed, 0xBEE1_BEE1_BEE1_BEE1)
            )
        }

        let allowOuterDust = cfg.fuzzOuterDustEnabled && (!isExtension || cfg.fuzzOuterDustEnabledInAppExtension)
        if allowOuterDust {
            let passCount = isExtension ? cfg.fuzzOuterDustPassCountInAppExtension : cfg.fuzzOuterDustPassCount
            if passCount > 0 {
                drawOuterDust(
                    in: &context,
                    rect: rect,
                    clipRect: clipRect,
                    corePath: corePath,
                    curvePath: curvePath,
                    bandHalfWidth: bandHalfWidth,
                    colourGradient: colourGradient,
                    noiseImage: dustNoise,
                    noiseTileScale: dustNoiseTileScale,
                    passCount: passCount,
                    configuration: cfg,
                    seed: RainSurfacePRNG.combine(baseSeed, 0xD005_700D_D005_700D)
                )
            }
        }

        if !isExtension, cfg.fuzzHazeStrength > 0.0001 {
            let hazeAlpha = clamp01(cfg.fuzzHazeStrength) * clamp01(maxStrength) * maxAlpha
            if hazeAlpha > 0.00001 {
                context.blendMode = .normal
                context.stroke(
                    curvePath,
                    with: .color(dissipationColor.opacity(hazeAlpha)),
                    lineWidth: bandHalfWidth * 2.0 * CGFloat(max(0.10, cfg.fuzzHazeStrokeWidthFactor))
                )
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
        let wideMul = max(narrowMul * 4.50, narrowMul + 2.00)

        // Wide smooth subtraction establishes the slope fade.
        context.blendMode = .destinationOut
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))
            layer.clip(to: corePath)

            let wideStroke = curvePath.strokedPath(
                StrokeStyle(lineWidth: bandHalfWidth * 2.0 * CGFloat(wideMul), lineCap: .round, lineJoin: .round)
            )
            let wideGrad = scaledGradient(maskGradient, alphaMultiplier: 0.55 * strength)

            layer.fill(
                wideStroke,
                with: .linearGradient(
                    wideGrad,
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )
        }
        context.blendMode = .normal

        // Narrow grain subtraction breaks the fade into speckles.
        context.blendMode = .destinationOut
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))
            layer.clip(to: corePath)

            let narrowStroke = curvePath.strokedPath(
                StrokeStyle(lineWidth: bandHalfWidth * 2.0 * CGFloat(narrowMul), lineCap: .round, lineJoin: .round)
            )
            let narrowGrad = scaledGradient(maskGradient, alphaMultiplier: 1.25 * strength)

            layer.fill(
                narrowStroke,
                with: .linearGradient(
                    narrowGrad,
                    startPoint: CGPoint(x: rect.minX, y: rect.midY),
                    endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )

            if let noiseImage {
                var prng = RainSurfacePRNG(seed: seed)
                let ox = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.95
                let oy = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.95

                let origin = CGPoint(x: rect.minX + ox, y: rect.minY + oy)
                let shading = GraphicsContext.Shading.tiledImage(
                    noiseImage,
                    origin: origin,
                    sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    scale: noiseTileScale
                )

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
            default: return [0.0, 0.33, 0.66, 1.0]
            }
        }()

        context.blendMode = .normal
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))

            for t in ts {
                let wMul = lerp(innerW, outerW, t)
                let aMul = lerp(innerA, outerA, t)
                if aMul <= 0.00001 { continue }

                let stroke = curvePath.strokedPath(
                    StrokeStyle(lineWidth: bandHalfWidth * 2.0 * CGFloat(wMul), lineCap: .round, lineJoin: .round)
                )

                let g = scaledGradient(colourGradient, alphaMultiplier: aMul)

                layer.fill(
                    stroke,
                    with: .linearGradient(
                        g,
                        startPoint: CGPoint(x: rect.minX, y: rect.midY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.midY)
                    )
                )
            }

            if let noiseImage {
                var prng = RainSurfacePRNG(seed: seed)
                let ox = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.65
                let oy = CGFloat(prng.nextSignedFloat()) * bandHalfWidth * 0.65 + bandHalfWidth * 0.20

                let origin = CGPoint(x: rect.minX + ox, y: rect.minY + oy)
                let shading = GraphicsContext.Shading.tiledImage(
                    noiseImage,
                    origin: origin,
                    sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                    scale: noiseTileScale
                )

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
}

// MARK: - Strength shaping + gradients

extension RainForecastSurfaceRenderer {
    static func computeFuzzStrengthPerPoint(
        heights: [CGFloat],
        certainties01: [Double],
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> [Double] {
        let n = min(heights.count, certainties01.count)
        guard n > 0 else { return [] }

        let maxH = max(0.0001, Double(heights.prefix(n).max() ?? 0.0))
        let invMaxH = 1.0 / maxH

        let thr = clamp01(cfg.fuzzChanceThreshold)
        let trans = max(0.0001, cfg.fuzzChanceTransition)
        let expo = max(0.05, cfg.fuzzChanceExponent)

        let floorBase = clamp01(cfg.fuzzChanceFloor)
        let minStrength = clamp01(cfg.fuzzChanceMinStrength)

        let lowPow = max(0.05, cfg.fuzzLowHeightPower)
        let lowBoost = max(0.0, cfg.fuzzLowHeightBoost)

        var out = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            let c = clamp01(certainties01[i])
            var t = (thr - c) / trans
            t = clamp01(t)
            t = pow(t, expo)

            var s = floorBase + (1.0 - floorBase) * t
            s = max(s, minStrength)

            let hn = clamp01(Double(heights[i]) * invMaxH)
            let low = pow(max(0.0, 1.0 - hn), lowPow)
            s *= (1.0 + lowBoost * low)

            out[i] = clamp01(s)
        }

        return out
    }

    static func makeAlphaGradient(baseColor: Color, strength: [Double], maxAlpha: Double, stops: Int) -> Gradient {
        let n = max(1, strength.count)
        let stopCount = max(2, stops)

        var out: [Gradient.Stop] = []
        out.reserveCapacity(stopCount)

        for i in 0..<stopCount {
            let t = Double(i) / Double(stopCount - 1)
            let idx = min(n - 1, max(0, Int(round(t * Double(n - 1)))))
            let a = clamp01(strength[idx]) * max(0.0, maxAlpha)
            out.append(Gradient.Stop(color: baseColor.opacity(a), location: t))
        }

        return Gradient(stops: out)
    }

    static func scaledGradient(_ g: Gradient, alphaMultiplier: Double) -> Gradient {
        let m = max(0.0, alphaMultiplier)
        if m == 1.0 { return g }

        let scaledStops: [Gradient.Stop] = g.stops.map { s in
            Gradient.Stop(color: s.color.opacity(m), location: s.location)
        }
        return Gradient(stops: scaledStops)
    }
}

// MARK: - Distance transform

extension RainForecastSurfaceRenderer {
    static func distanceToNearestTrue(_ mask: [Bool]) -> [Int] {
        guard !mask.isEmpty else { return [] }
        let n = mask.count
        let inf = n + 10
        var dist = Array(repeating: inf, count: n)

        var lastTrue = -inf
        for i in 0..<n {
            if mask[i] { lastTrue = i }
            dist[i] = i - lastTrue
        }

        lastTrue = inf * 2
        for i in stride(from: n - 1, through: 0, by: -1) {
            if mask[i] { lastTrue = i }
            dist[i] = min(dist[i], lastTrue - i)
        }

        return dist
    }
}

// MARK: - Fuzz noise assets

extension RainForecastSurfaceRenderer {
    enum FuzzNoiseVariant {
        case sparse
        case normal
        case dense

        var assetName: String {
            switch self {
            case .sparse: return "RainFuzzNoise_Sparse"
            case .normal: return "RainFuzzNoise"
            case .dense: return "RainFuzzNoise_Dense"
            }
        }
    }

    static func fuzzNoiseImage(preferred: FuzzNoiseVariant) -> SwiftUI.Image? {
        #if canImport(UIKit)
        if UIKit.UIImage(named: preferred.assetName) != nil { return SwiftUI.Image(preferred.assetName) }
        if UIKit.UIImage(named: FuzzNoiseVariant.normal.assetName) != nil { return SwiftUI.Image(FuzzNoiseVariant.normal.assetName) }
        if UIKit.UIImage(named: FuzzNoiseVariant.sparse.assetName) != nil { return SwiftUI.Image(FuzzNoiseVariant.sparse.assetName) }
        if UIKit.UIImage(named: FuzzNoiseVariant.dense.assetName) != nil { return SwiftUI.Image(FuzzNoiseVariant.dense.assetName) }
        return nil
        #else
        return SwiftUI.Image(preferred.assetName)
        #endif
    }

    static func fuzzNoiseTileScale(desiredTilePixels: Int) -> CGFloat {
        let authored: Double = 256.0
        let desired = Double(max(16, min(desiredTilePixels, 1024)))
        let s = desired / authored
        return CGFloat(max(0.10, min(s, 6.0)))
    }
}
