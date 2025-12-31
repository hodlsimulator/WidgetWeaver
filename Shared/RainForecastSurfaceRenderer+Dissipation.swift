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
    enum FuzzBudgetTier {
        case app
        case widget
        case widgetHeavy
    }

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

        var strength = computeFuzzStrengthPerPoint(
            heights: heights,
            certainties01: certainties01.map { Double($0) },
            configuration: cfg
        )

        let wetEps = max(0.5 / max(1.0, Double(ds)), 0.0001)
        let wetMask = heights.map { Double($0) > wetEps }
        let distToWet = distanceToNearestTrue(wetMask)

        let wetCount = wetMask.reduce(0) { $0 + ($1 ? 1 : 0) }
        let wetCoverage = Double(wetCount) / Double(max(1, wetMask.count))

        let wPx = Double(rect.width * ds)
        let hPx = Double(max(0.0, baselineY - rect.minY) * ds)
        let pixelArea = wPx * hPx

        let tier: FuzzBudgetTier = {
            if !isExtension { return .app }
            let heavyAreaThreshold: Double = 520_000.0
            let heavyCoverageThreshold: Double = 0.62
            if pixelArea >= heavyAreaThreshold || wetCoverage >= heavyCoverageThreshold { return .widgetHeavy }
            return .widget
        }()

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

        let clipRect = computeDissipationClipRect(
            rect: rect,
            baselineY: baselineY,
            heights: heights,
            strength: strength,
            bandHalfWidth: bandHalfWidth,
            configuration: cfg
        )

        var maxAlpha = clamp01(cfg.fuzzMaxOpacity)
        maxAlpha *= max(0.0, cfg.fuzzSpeckStrength)

        let maxStopCap = isExtension ? 18 : 64
        let baseStopCount = max(8, min(cfg.fuzzTextureGradientStops, maxStopCap))
        let stopCount: Int = {
            switch tier {
            case .app:
                return baseStopCount
            case .widget:
                return min(baseStopCount, 18)
            case .widgetHeavy:
                return min(baseStopCount, 12)
            }
        }()

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

        let baseTilePx = max(32, min(cfg.fuzzTextureTilePixels, isExtension ? 256 : 512))
        let tilePx: Int = {
            switch tier {
            case .app:
                return baseTilePx
            case .widget:
                return min(baseTilePx, 160)
            case .widgetHeavy:
                return min(baseTilePx, 128)
            }
        }()
        let baseNoiseTileScale = fuzzNoiseTileScale(desiredTilePixels: tilePx)
        let erodeNoiseTileScale = baseNoiseTileScale * 0.82
        let dustNoiseTileScale = baseNoiseTileScale

        let baseSeed = RainSurfacePRNG.combine(
            cfg.noiseSeed,
            UInt64(curvePoints.count &* 977) &+ 0xA5A5_A5A5_A5A5_A5A5
        )

        // Use a slightly denser tile for erosion so a meaningful fraction of the body
        // is actually removed (the mockup has a large “grain” region, not just a thin outline).
        // Keep outer dust sparse so it stays airy and widget-safe.
        let dustNoise = fuzzNoiseImage(preferred: .sparse)
        let erodeNoise = fuzzNoiseImage(preferred: .normal)

        if cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.0001 {
            let solidInset = computeSolidCoreInset(
                bandHalfWidth: bandHalfWidth,
                heights: heights,
                displayScale: ds,
                configuration: cfg
            )

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
                solidInset: solidInset,
                tier: tier,
                configuration: cfg,
                seed: RainSurfacePRNG.combine(baseSeed, 0xBEE1_BEE1_BEE1_BEE1)
            )
        }

        var allowOuterDust = cfg.fuzzOuterDustEnabled && (!isExtension || cfg.fuzzOuterDustEnabledInAppExtension)
        if isExtension {
            if tier == .widgetHeavy {
                allowOuterDust = false
            } else {
                let coverageCutoff: Double = 0.55
                let areaCutoff: Double = 420_000.0
                if wetCoverage >= coverageCutoff || pixelArea >= areaCutoff {
                    allowOuterDust = false
                }
            }
        }

        if allowOuterDust {
            let desiredPassCount = isExtension ? cfg.fuzzOuterDustPassCountInAppExtension : cfg.fuzzOuterDustPassCount
            let passCount = isExtension ? min(desiredPassCount, 1) : desiredPassCount
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
        solidInset: CGFloat,
        tier: FuzzBudgetTier,
        configuration cfg: RainForecastSurfaceConfiguration,
        seed: UInt64
    ) {
        let strength = clamp01(cfg.fuzzErodeStrength)
        guard strength > 0.0001 else { return }
        guard bandHalfWidth > 0.0001 else { return }

        let narrowMul = max(0.10, cfg.fuzzErodeStrokeWidthFactor)

        // By default the erosion reaches well into the slope (broad grain region),
        // but when `fuzzSolidCoreEnabled` is set, the inset is used to cap how far erosion can reach
        // into the body. This keeps the centre solid without needing to re-fill an inset core.
        var wideMul = max(narrowMul * 4.50, narrowMul + 2.00)

        if solidInset > 0.0001 {
            let maxInsideMul = max(Double(narrowMul), Double(solidInset / max(0.0001, bandHalfWidth)))
            wideMul = min(wideMul, maxInsideMul)
        }

        let startPoint = CGPoint(x: rect.minX, y: rect.midY)
        let endPoint = CGPoint(x: rect.maxX, y: rect.midY)

        // Multiple overlapping stroke widths approximate a smooth falloff without blur.
        // This avoids “terrace” bands that happen with only one wide + one narrow pass.
        let layerCount: Int = {
            switch tier {
            case .app:
                return 6
            case .widget:
                return 4
            case .widgetHeavy:
                return 3
            }
        }()

        let edgePower = max(0.05, cfg.fuzzErodeEdgePower)

        // Bias weights so the narrow layers dominate (strong near the contour, weak deeper inside).
        let weightPower: Double = max(0.25, 1.60 + (edgePower - 1.0) * 0.45)

        var widths: [Double] = []
        widths.reserveCapacity(layerCount)

        var weights: [Double] = []
        weights.reserveCapacity(layerCount)

        if layerCount == 1 {
            widths.append(Double(wideMul))
            weights.append(1.0)
        } else {
            for i in 0..<layerCount {
                let t = Double(i) / Double(layerCount - 1) // 0 = narrow, 1 = wide

                let shapedT = pow(t, edgePower)
                let wMul = lerp(Double(narrowMul), Double(wideMul), shapedT)
                widths.append(wMul)

                let u = 1.0 - t
                let w = pow(0.18 + 0.82 * max(0.0, u), weightPower)
                weights.append(w)
            }

            let sum = max(0.000001, weights.reduce(0.0, +))
            weights = weights.map { $0 / sum }
        }

        // Calibrated for the alpha distribution of `RainFuzzNoise*` (median alpha ~0.28).
        // Widget tiers clamp this slightly lower to reduce worst-case subtraction work.
        let baseAlpha: Double = {
            switch tier {
            case .app:
                return 2.45
            case .widget:
                return 2.25
            case .widgetHeavy:
                return 1.95
            }
        }()

        context.blendMode = .destinationOut
        context.drawLayer { layer in
            layer.clip(to: Path(clipRect))
            layer.clip(to: corePath)

            // `drawLayer` inherits the parent blend mode. When the parent is `.destinationOut`,
            // drawing into the layer with the inherited mode would erase from an empty layer.
            // The layer is drawn normally, then composited back with `.destinationOut`.
            layer.blendMode = .normal

            for i in 0..<widths.count {
                let wMul = widths[i]
                let aMul = baseAlpha * weights[i] * strength
                if aMul <= 0.00001 { continue }

                let stroke = curvePath.strokedPath(
                    StrokeStyle(
                        lineWidth: bandHalfWidth * 2.0 * CGFloat(wMul),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )

                let g = scaledGradient(maskGradient, alphaMultiplier: aMul)
                layer.fill(stroke, with: .linearGradient(g, startPoint: startPoint, endPoint: endPoint))
            }

            guard let noiseImage else { return }

            var prng = RainSurfacePRNG(seed: seed)

            // Larger jitter prevents the tile from “locking” to the chart edges.
            let jitterBase = max(64.0, min(256.0, Double(max(rect.width, rect.height))))
            let ox = CGFloat(prng.nextSignedFloat() * jitterBase)
            let oy = CGFloat(prng.nextSignedFloat() * jitterBase)

            // A small deterministic scale variation reduces visible repetition without adding passes.
            let scaleJitter = 0.92 + 0.16 * CGFloat(prng.nextFloat01())
            let s = max(0.05, noiseTileScale * scaleJitter)

            let origin = CGPoint(x: rect.minX + ox, y: rect.minY + oy)
            let shading = GraphicsContext.Shading.tiledImage(
                noiseImage,
                origin: origin,
                sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
                scale: s
            )

            layer.blendMode = .destinationIn
            layer.fill(Path(clipRect), with: shading)
            layer.blendMode = .normal
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
                layer.fill(Path(clipRect), with: shading)
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

// MARK: - Work region (keeps offscreen layers bounded)

extension RainForecastSurfaceRenderer {
    static func computeDissipationClipRect(
        rect: CGRect,
        baselineY: CGFloat,
        heights: [CGFloat],
        strength: [Double],
        bandHalfWidth: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> CGRect {
        let n = min(heights.count, strength.count)
        guard n > 0 else {
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0.0, baselineY - rect.minY))
        }

        let activeEps: Double = 0.002
        var firstActive: Int = n
        var lastActive: Int = -1
        var maxActiveH: CGFloat = 0.0

        for i in 0..<n where strength[i] > activeEps {
            firstActive = min(firstActive, i)
            lastActive = max(lastActive, i)
            maxActiveH = max(maxActiveH, heights[i])
        }

        if lastActive < firstActive {
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0.0, baselineY - rect.minY))
        }

        let denom = CGFloat(max(1, n - 1))
        func xAt(_ idx: Int) -> CGFloat {
            rect.minX + (CGFloat(idx) / denom) * rect.width
        }

        let narrowMul = max(0.10, cfg.fuzzErodeStrokeWidthFactor)
        let wideMul = max(narrowMul * 4.50, narrowMul + 2.00)
        let maxBandMul = max(Double(wideMul), cfg.fuzzTextureOuterBandMultiplier)

        let pad = bandHalfWidth * CGFloat(maxBandMul) * 1.25

        let minX = max(rect.minX, min(xAt(firstActive), xAt(lastActive)) - pad)
        let maxX = min(rect.maxX, max(xAt(firstActive), xAt(lastActive)) + pad)

        let yPad = pad * 0.95
        let minY = max(rect.minY, baselineY - maxActiveH - yPad)
        let maxY = baselineY

        let w = max(0.0, maxX - minX)
        let h = max(0.0, maxY - minY)
        if w <= 0.0 || h <= 0.0 {
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0.0, baselineY - rect.minY))
        }

        return CGRect(x: minX, y: minY, width: w, height: h)
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
