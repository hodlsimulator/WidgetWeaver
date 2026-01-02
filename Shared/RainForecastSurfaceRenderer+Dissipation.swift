//
//  RainForecastSurfaceRenderer+Dissipation.swift
//  WidgetWeaver
//
//  Created by . . on 12/31/25.
//
//  Dissipation fuzz rendering using tiledImage.
//  Seam fix:
//  - Use a wrap-padded tile image.
//  - Tile only the interior via sourceRect.
//  - Snap pattern origin to the device pixel grid.
//

import Foundation
import SwiftUI
import CoreGraphics

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
        guard cfg.fuzzEnabled, cfg.canEnableFuzz else { return }
        guard cfg.fuzzTextureEnabled else { return }
        guard cfg.fuzzMaxOpacity > 0.0001 else { return }

        let isExtension = WidgetWeaverRuntime.isRunningInAppExtension

        let n = min(heights.count, certainties01.count)
        guard n >= 3 else { return }
        guard curvePoints.count == heights.count, heights.count == certainties01.count else { return }

        // Slight boost makes seams easier to spot while verifying.
        let maxAlpha = clamp01(cfg.fuzzMaxOpacity * 1.35)

        let strength = computeFuzzStrengthPerPoint(
            heights: heights,
            certainties01: certainties01.map { Double($0) },
            configuration: cfg
        )

        if (strength.max() ?? 0.0) <= 0.001 {
            return
        }

        let clipRect = computeDissipationClipRect(
            rect: rect,
            baselineY: baselineY,
            curvePoints: curvePoints,
            heights: heights,
            strength: strength,
            bandHalfWidth: bandHalfWidth,
            configuration: cfg
        )

        guard clipRect.width > 1.0, clipRect.height > 1.0 else { return }

        let contour = contourPath(from: curvePoints)

        let innerMul = max(0.05, cfg.fuzzTextureInnerBandMultiplier)
        let outerMul = max(innerMul, cfg.fuzzTextureOuterBandMultiplier)

        let innerBand = max(0.25, bandHalfWidth * CGFloat(innerMul))
        let outerBand = max(innerBand, bandHalfWidth * CGFloat(outerMul))

        let innerBandPath = contour.strokedPath(
            StrokeStyle(lineWidth: innerBand * 2.0, lineCap: .round, lineJoin: .round)
        )

        let outerBandPath = contour.strokedPath(
            StrokeStyle(lineWidth: outerBand * 2.0, lineCap: .round, lineJoin: .round)
        )

        let xMaskGradient = makeAlphaGradient(
            baseColor: .white,
            strength: strength,
            minAlpha: 0.08,
            maxAlpha: 1.0,
            stops: cfg.fuzzTextureGradientStops
        )
        let xMaskShading = GraphicsContext.Shading.linearGradient(
            xMaskGradient,
            startPoint: CGPoint(x: clipRect.minX, y: clipRect.midY),
            endPoint: CGPoint(x: clipRect.maxX, y: clipRect.midY)
        )

        let fineNoise = RainSurfaceSeamlessNoiseTile.image(.fine)
        let coarseNoise = RainSurfaceSeamlessNoiseTile.image(.coarse)

        let widthDriven = Int((rect.width * ds) * (isExtension ? 0.55 : 0.45))
        let tilePixels = max(24, min(max(cfg.fuzzTextureTilePixels, widthDriven), 1024))

        let baseSeed = cfg.noiseSeed ^ stableSeed(from: curvePoints, displayScale: ds)

        let fineShading = tiledNoiseShading(
            image: fineNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 1.0,
            seed: baseSeed,
            jitterFraction: 0.22
        )

        let fineDetailShading = tiledNoiseShading(
            image: fineNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 0.62,
            seed: baseSeed &+ 0x9E37_79B9_7F4A_7C15,
            jitterFraction: 0.18
        )

        let coarseShading = tiledNoiseShading(
            image: coarseNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 1.28,
            seed: (cfg.noiseSeed &+ 0xBF58_476D_1CE4_E5B9) ^ stableSeed(from: Array(curvePoints.reversed()), displayScale: ds),
            jitterFraction: 0.28
        )

        let coarseDetailShading = tiledNoiseShading(
            image: coarseNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 2.55,
            seed: (cfg.noiseSeed &+ 0x94D0_49BB_1331_11EB) ^ stableSeed(from: curvePoints, displayScale: ds),
            jitterFraction: 0.30
        )

        // WidgetKit-safe: constant number of draws.
        if isExtension {
            let innerMulA = clamp01(cfg.fuzzTextureInnerOpacityMultiplier)

            let a0 = min(1.0, maxAlpha * innerMulA * 0.70)
            let a1 = min(1.0, maxAlpha * innerMulA * 0.38)
            let a2 = min(1.0, maxAlpha * innerMulA * 0.18)
            let a3 = min(1.0, maxAlpha * innerMulA * 0.12)

            if (a0 + a1 + a2 + a3) > 0.0001 {
                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    layer.clip(to: corePath)
                    layer.clip(to: innerBandPath)

                    layer.blendMode = .plusLighter

                    layer.opacity = a0
                    layer.fill(Path(clipRect), with: coarseShading)

                    layer.opacity = a1
                    layer.fill(Path(clipRect), with: coarseDetailShading)

                    layer.opacity = a2
                    layer.fill(Path(clipRect), with: fineShading)

                    layer.opacity = a3
                    layer.fill(Path(clipRect), with: fineDetailShading)

                    layer.blendMode = .destinationIn
                    layer.opacity = 1.0
                    layer.fill(Path(clipRect), with: xMaskShading)
                }
            }

            let allowOuter = cfg.fuzzOuterDustEnabled && cfg.fuzzOuterDustEnabledInAppExtension
            if allowOuter {
                var outside = Path()
                outside.addRect(clipRect)
                outside.addPath(corePath)

                let outerMulA = clamp01(cfg.fuzzTextureOuterOpacityMultiplier)
                let tintA = min(1.0, maxAlpha * outerMulA * 0.55)

                if tintA > 0.0001 {
                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))
                        layer.clip(to: outerBandPath)
                        layer.clip(to: outside, style: FillStyle(eoFill: true, antialiased: true))

                        layer.blendMode = .plusLighter
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: coarseDetailShading)

                        layer.opacity = 0.60
                        layer.fill(Path(clipRect), with: fineShading)

                        layer.opacity = 0.45
                        layer.fill(Path(clipRect), with: fineDetailShading)

                        layer.opacity = 0.32
                        layer.fill(Path(clipRect), with: coarseShading)

                        layer.blendMode = .sourceIn
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: .color(cfg.fuzzColor.opacity(tintA)))

                        layer.blendMode = .destinationIn
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: xMaskShading)
                    }
                }
            }

            return
        }

        // App path (same structure, richer).
        do {
            let innerMulA = clamp01(cfg.fuzzTextureInnerOpacityMultiplier)

            let a0 = min(1.0, maxAlpha * innerMulA * 0.70)
            let a1 = min(1.0, maxAlpha * innerMulA * 0.38)
            let a2 = min(1.0, maxAlpha * innerMulA * 0.18)
            let a3 = min(1.0, maxAlpha * innerMulA * 0.12)

            if (a0 + a1 + a2 + a3) > 0.0001 {
                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    layer.clip(to: corePath)
                    layer.clip(to: innerBandPath)

                    layer.blendMode = .plusLighter

                    layer.opacity = a0
                    layer.fill(Path(clipRect), with: coarseShading)

                    layer.opacity = a1
                    layer.fill(Path(clipRect), with: coarseDetailShading)

                    layer.opacity = a2
                    layer.fill(Path(clipRect), with: fineShading)

                    layer.opacity = a3
                    layer.fill(Path(clipRect), with: fineDetailShading)

                    layer.blendMode = .destinationIn
                    layer.opacity = 1.0
                    layer.fill(Path(clipRect), with: xMaskShading)
                }
            }
        }

        do {
            let allowOuter = cfg.fuzzOuterDustEnabled
            if allowOuter {
                var outside = Path()
                outside.addRect(clipRect)
                outside.addPath(corePath)

                let outerMulA = clamp01(cfg.fuzzTextureOuterOpacityMultiplier)
                let tintA = min(1.0, maxAlpha * outerMulA * 0.55)

                if tintA > 0.0001 {
                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))
                        layer.clip(to: outerBandPath)
                        layer.clip(to: outside, style: FillStyle(eoFill: true, antialiased: true))

                        layer.blendMode = .plusLighter
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: coarseDetailShading)

                        layer.opacity = 0.60
                        layer.fill(Path(clipRect), with: fineShading)

                        layer.opacity = 0.45
                        layer.fill(Path(clipRect), with: fineDetailShading)

                        layer.opacity = 0.32
                        layer.fill(Path(clipRect), with: coarseShading)

                        layer.blendMode = .sourceIn
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: .color(cfg.fuzzColor.opacity(tintA)))

                        layer.blendMode = .destinationIn
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: xMaskShading)
                    }
                }
            }
        }

        if cfg.fuzzErodeEnabled && cfg.fuzzErodeStrength > 0.0001 {
            let k = max(0.0, cfg.fuzzErodeStrength)
            let a = maxAlpha * min(0.45, 0.22 * k)

            if a > 0.0001 {
                for pass in 0..<2 {
                    let passSeed = cfg.noiseSeed &+ UInt64(pass) &* 0xBF58476D1CE4E5B9

                    let passShading = tiledNoiseShading(
                        image: coarseNoise,
                        bounds: rect,
                        displayScale: ds,
                        desiredTilePixels: tilePixels,
                        scaleMultiplier: 1.55 + CGFloat(pass) * 0.22,
                        seed: passSeed ^ stableSeed(from: curvePoints, displayScale: ds),
                        jitterFraction: 0.32
                    )

                    let prevBlend = context.blendMode
                    let prevOpacity = context.opacity
                    context.blendMode = .destinationOut
                    context.opacity = a

                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))
                        layer.clip(to: corePath)
                        layer.clip(to: outerBandPath)

                        layer.blendMode = .normal
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: passShading)

                        layer.blendMode = .destinationIn
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: xMaskShading)
                    }

                    context.blendMode = prevBlend
                    context.opacity = prevOpacity
                }
            }
        }
    }

    // MARK: - Helpers

    private static func contourPath(from points: [CGPoint]) -> Path {
        Self.buildCurveStrokePath(curvePoints: points)
    }

    private static func stableSeed(from points: [CGPoint], displayScale: CGFloat) -> UInt64 {
        let ds = max(1.0, displayScale)
        var h: UInt64 = 0xD1B54A32D192ED03

        let take = min(10, points.count)
        for i in 0..<take {
            let p = points[(i * max(1, points.count - 1)) / max(1, take - 1)]
            let xi = Int64((p.x * ds).rounded())
            let yi = Int64((p.y * ds).rounded())
            let a = UInt64(bitPattern: xi)
            let b = UInt64(bitPattern: yi)
            h = h ^ (a &* 0x9E3779B97F4A7C15) ^ (b &* 0xBF58476D1CE4E5B9)
            h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
            h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
            h = h ^ (h >> 31)
        }

        return h
    }

    private static func tiledNoiseShading(
        image: Image,
        bounds: CGRect,
        displayScale: CGFloat,
        desiredTilePixels: Int,
        scaleMultiplier: CGFloat,
        seed: UInt64,
        jitterFraction: CGFloat
    ) -> GraphicsContext.Shading {
        let ds = max(1.0, displayScale)

        // Tile repeat size is the interior (padding is excluded via sourceRect).
        let authoredRepeatPt = CGFloat(RainSurfaceSeamlessNoiseTile.tileInteriorPixels)
        let sourceRect = RainSurfaceSeamlessNoiseTile.unitSourceRect

        // Quantise the final tile period to whole device pixels.
        let basePx = CGFloat(max(16, desiredTilePixels))
        let mul = max(0.05, scaleMultiplier)

        let targetPx = max(12.0, min(2048.0, (basePx * mul).rounded(.toNearestOrAwayFromZero)))
        let targetPt = targetPx / ds

        var prng = RainSurfacePRNG(seed: seed)

        let j = max(0.0, min(1.0, jitterFraction))
        let jitterPx = targetPx * j

        let oxPx = (CGFloat(prng.nextFloat01()) - 0.5) * 2.0 * jitterPx
        let oyPx = (CGFloat(prng.nextFloat01()) - 0.5) * 2.0 * jitterPx

        let baseOxPx = targetPx * 0.37
        let baseOyPx = targetPx * 0.21

        // Snap origin to the device pixel grid.
        let originPxX = (bounds.minX * ds + baseOxPx + oxPx).rounded(.toNearestOrAwayFromZero)
        let originPxY = (bounds.minY * ds + baseOyPx + oyPx).rounded(.toNearestOrAwayFromZero)
        let origin = CGPoint(x: originPxX / ds, y: originPxY / ds)

        // Scale such that the interior repeat maps to targetPt.
        let scale = max(0.10, min(6.0, targetPt / max(1.0, authoredRepeatPt)))

        return GraphicsContext.Shading.tiledImage(
            image,
            origin: origin,
            sourceRect: sourceRect,
            scale: scale
        )
    }

    // MARK: - Strength

    static func computeFuzzStrengthPerPoint(
        heights: [CGFloat],
        certainties01: [Double],
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> [Double] {
        let n = min(heights.count, certainties01.count)
        guard n > 0 else { return [] }

        var out = [Double](repeating: 0.0, count: n)

        let chanceThresh = clamp01(cfg.fuzzChanceThreshold)
        let chanceTrans = max(0.0001, clamp01(cfg.fuzzChanceTransition))
        let chanceExp = max(0.05, cfg.fuzzChanceExponent)

        let floorStrength = clamp01(cfg.fuzzChanceFloor)
        let minStrength = clamp01(cfg.fuzzChanceMinStrength)

        let maxH = max(0.0, heights.prefix(n).max() ?? 0.0)

        for i in 0..<n {
            let h = max(0.0, heights[i])
            if h <= 0.0001 {
                out[i] = 0.0
                continue
            }

            let c = clamp01(certainties01[i])
            var u = 1.0 - c

            if c >= chanceThresh {
                u = 0.0
            } else {
                let t = (chanceThresh - c) / chanceTrans
                u = clamp01(t)
            }

            u = pow(u, chanceExp)
            u = max(minStrength, u)

            if maxH > 0.0001 {
                let frac = Double(h / maxH)
                let lowPow = max(0.05, cfg.fuzzLowHeightPower)
                let lowBoost = max(0.0, cfg.fuzzLowHeightBoost)
                let low = pow(max(0.0, min(1.0, 1.0 - frac)), lowPow)
                u *= (1.0 + lowBoost * low)
            }

            u = max(floorStrength, u)
            out[i] = clamp01(u)
        }

        if cfg.fuzzTailMinutes > 0.0001 {
            let tail = max(0.0, cfg.fuzzTailMinutes)
            let tailCount = max(1, Int(tail.rounded()))

            if tailCount >= 2, out.count >= 2 {
                let sm = out
                for i in 0..<out.count {
                    var acc = 0.0
                    var wsum = 0.0
                    for k in 0..<tailCount {
                        let j = min(out.count - 1, i + k)
                        let w = 1.0 - (Double(k) / Double(max(1, tailCount - 1)))
                        acc += sm[j] * w
                        wsum += w
                    }
                    out[i] = (wsum > 0.0001) ? (acc / wsum) : out[i]
                }
            }
        }

        return out
    }

    // MARK: - Mask gradient

    static func makeAlphaGradient(
        baseColor: Color,
        strength: [Double],
        minAlpha: Double,
        maxAlpha: Double,
        stops: Int
    ) -> Gradient {
        let n = strength.count
        guard n > 0 else {
            return Gradient(stops: [
                .init(color: baseColor.opacity(minAlpha), location: 0.0),
                .init(color: baseColor.opacity(minAlpha), location: 1.0)
            ])
        }

        let sMin = minAlpha
        let sMax = maxAlpha

        let count = max(2, stops)
        var out: [Gradient.Stop] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let idx = Int((t * Double(n - 1)).rounded())
            let v = clamp01(strength[min(n - 1, max(0, idx))])

            let a = sMin + (sMax - sMin) * v
            out.append(.init(color: baseColor.opacity(a), location: t))
        }

        return Gradient(stops: out)
    }

    // MARK: - Clip rect

    static func computeDissipationClipRect(
        rect: CGRect,
        baselineY: CGFloat,
        curvePoints: [CGPoint],
        heights: [CGFloat],
        strength: [Double],
        bandHalfWidth: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> CGRect {
        let n = min(heights.count, strength.count, curvePoints.count)
        guard n > 0 else {
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0.0, baselineY - rect.minY))
        }

        var minXCurve = CGFloat.greatestFiniteMagnitude
        var maxXCurve: CGFloat = -CGFloat.greatestFiniteMagnitude
        for i in 0..<n {
            let x = curvePoints[i].x
            minXCurve = min(minXCurve, x)
            maxXCurve = max(maxXCurve, x)
        }
        if !minXCurve.isFinite || !maxXCurve.isFinite || maxXCurve <= minXCurve {
            minXCurve = rect.minX
            maxXCurve = rect.maxX
        }

        let activeEps: Double = 0.002
        var maxActiveH: CGFloat = 0.0
        for i in 0..<n {
            if strength[i] > activeEps && Double(heights[i]) > 0.0001 {
                maxActiveH = max(maxActiveH, heights[i])
            }
        }
        if maxActiveH <= 0.0001 {
            maxActiveH = max(0.0, heights.prefix(n).max() ?? 0.0)
        }

        let maxBandMul = max(cfg.fuzzTextureOuterBandMultiplier, cfg.fuzzTextureInnerBandMultiplier)
        let outerBand = bandHalfWidth * CGFloat(maxBandMul)

        let padX = max(outerBand * 1.25, 18.0)
        let padYTop = max(outerBand * 1.85, 24.0)
        let padYBottom = max(outerBand * 0.35, 8.0)

        let minX = max(rect.minX, minXCurve - padX)
        let maxX = min(rect.maxX, maxXCurve + padX)

        let minY = max(rect.minY, baselineY - maxActiveH - padYTop)
        let maxY = min(rect.maxY, baselineY + padYBottom)

        let w = max(0.0, maxX - minX)
        let h = max(0.0, maxY - minY)
        if w <= 0.0 || h <= 0.0 {
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0.0, baselineY - rect.minY))
        }

        return CGRect(x: minX, y: minY, width: w, height: h)
    }
}
