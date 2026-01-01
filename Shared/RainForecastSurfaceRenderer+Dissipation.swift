//
//  RainForecastSurfaceRenderer+Dissipation.swift
//  WidgetWeaver
//
//  Created by . . on 12/31/25.
//
//  Texture-based dissipation:
//  - seamless tiling (no band seams)
//  - additive interior grain + surface mist
//  - widget-safe path stays constant-cost to avoid placeholder timeouts
//

import Foundation
import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

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

        let maxAlpha = clamp01(cfg.fuzzMaxOpacity)

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

        let topY = min(curvePoints.map { $0.y }.min() ?? baselineY, baselineY)
        let yStart = max(rect.minY, topY - outerBand * 0.55)
        let yEnd = min(baselineY + outerBand * 0.35, rect.maxY)

        let xMaskGradient = makeAlphaGradient(
            baseColor: .white,
            strength: strength,
            minAlpha: 0.28,
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

        let tilePixels = max(24, min(cfg.fuzzTextureTilePixels, 1024))

        let baseSeed = cfg.noiseSeed ^ stableSeed(from: curvePoints, displayScale: ds)

        let fineShading = tiledNoiseShading(
            image: fineNoise,
            bounds: clipRect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 1.0,
            seed: baseSeed,
            jitterFraction: 0.22
        )

        let fineDetailShading = tiledNoiseShading(
            image: fineNoise,
            bounds: clipRect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 0.62,
            seed: baseSeed &+ 0x9E37_79B9_7F4A_7C15,
            jitterFraction: 0.18
        )

        let coarseShading = tiledNoiseShading(
            image: coarseNoise,
            bounds: clipRect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 1.28,
            seed: (cfg.noiseSeed &+ 0xBF58_476D_1CE4_E5B9) ^ stableSeed(from: Array(curvePoints.reversed()), displayScale: ds),
            jitterFraction: 0.28
        )

        let coarseDetailShading = tiledNoiseShading(
            image: coarseNoise,
            bounds: clipRect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 0.86,
            seed: baseSeed &+ 0x94D0_49BB_1331_11EB,
            jitterFraction: 0.24
        )

        let depthFullBody = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(1.0), location: 0.0),
                .init(color: .white.opacity(0.92), location: 0.18),
                .init(color: .white.opacity(0.52), location: 0.70),
                .init(color: .white.opacity(0.40), location: 1.0),
            ]),
            startPoint: CGPoint(x: clipRect.midX, y: yStart),
            endPoint: CGPoint(x: clipRect.midX, y: yEnd)
        )

        // Above-surface fade: strongest just above the contour, vanishes upwards and below.
        let aboveTopY = max(rect.minY, yStart - outerBand * 1.35)
        let aboveBottomY = min(rect.maxY, yStart + outerBand * 0.55)
        let aboveFade = GraphicsContext.Shading.linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0.0), location: 0.0),
                .init(color: .white.opacity(1.0), location: 0.62),
                .init(color: .white.opacity(0.0), location: 1.0),
            ]),
            startPoint: CGPoint(x: clipRect.midX, y: aboveTopY),
            endPoint: CGPoint(x: clipRect.midX, y: aboveBottomY)
        )

        // Widget-safe path:
        // - constant number of draw operations
        // - 2 offscreen layers total (interior + exterior)
        // - no per-speckle loops
        if isExtension {
            let innerMulA = clamp01(cfg.fuzzTextureInnerOpacityMultiplier)
            let outerMulA = clamp01(cfg.fuzzTextureOuterOpacityMultiplier)

            let bodyA0 = min(1.0, maxAlpha * innerMulA * 0.86)
            let bodyA1 = min(1.0, maxAlpha * innerMulA * 0.44)
            let edgeA0 = min(1.0, maxAlpha * innerMulA * 0.78)
            let edgeA1 = min(1.0, maxAlpha * innerMulA * 0.42)

            context.drawLayer { layer in
                layer.clip(to: Path(clipRect))
                layer.clip(to: corePath)

                layer.blendMode = .plusLighter
                layer.opacity = bodyA0
                layer.fill(Path(clipRect), with: fineShading)

                layer.opacity = bodyA1
                layer.fill(Path(clipRect), with: fineDetailShading)

                layer.opacity = edgeA0
                layer.fill(innerBandPath, with: coarseShading)

                layer.opacity = edgeA0 * 0.55
                layer.fill(innerBandPath, with: coarseDetailShading)

                layer.opacity = edgeA1
                layer.fill(innerBandPath, with: fineDetailShading)

                layer.blendMode = .destinationIn
                layer.opacity = 1.0
                layer.fill(Path(clipRect), with: depthFullBody)
                layer.fill(Path(clipRect), with: xMaskShading)
            }

            let allowOuter = cfg.fuzzOuterDustEnabled && cfg.fuzzOuterDustEnabledInAppExtension
            if allowOuter {
                var outside = Path()
                outside.addRect(clipRect)
                outside.addPath(corePath)

                let blueA = min(1.0, maxAlpha * outerMulA * 0.62)
                let whiteA = min(1.0, maxAlpha * outerMulA * 0.28)

                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    layer.clip(to: outerBandPath)
                    layer.clip(to: outside, style: FillStyle(eoFill: true, antialiased: true))

                    layer.blendMode = .normal
                    layer.opacity = 1.0
                    layer.fill(Path(clipRect), with: .color(cfg.fuzzColor.opacity(blueA)))

                    layer.blendMode = .plusLighter
                    layer.opacity = 1.0
                    layer.fill(Path(clipRect), with: .color(Color.white.opacity(whiteA)))

                    // Fine speckles to break up tiled shapes (masked by the same noise/fade below).
                    let speckA = min(1.0, maxAlpha * outerMulA * 0.10)
                    layer.opacity = speckA
                    layer.fill(Path(clipRect), with: fineDetailShading)

                    layer.blendMode = .destinationIn
                    layer.opacity = 1.0
                    layer.fill(Path(clipRect), with: coarseDetailShading)
                    layer.fill(Path(clipRect), with: aboveFade)
                    layer.fill(Path(clipRect), with: xMaskShading)
                }
            }

            return
        }

        // App path (richer layering; outside WidgetKit watchdog limits).

        // Body grain (everywhere under the surface).
        do {
            let a0 = maxAlpha * clamp01(cfg.fuzzTextureInnerOpacityMultiplier) * 0.44
            let a1 = maxAlpha * clamp01(cfg.fuzzTextureInnerOpacityMultiplier) * 0.22
            if (a0 + a1) > 0.0001 {
                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    layer.clip(to: corePath)

                    layer.blendMode = .plusLighter
                    layer.opacity = a0
                    layer.fill(Path(clipRect), with: fineShading)

                    layer.opacity = a1
                    layer.fill(Path(clipRect), with: fineDetailShading)

                    layer.blendMode = .destinationIn
                    layer.opacity = 1.0
                    layer.fill(Path(clipRect), with: depthFullBody)
                    layer.fill(Path(clipRect), with: xMaskShading)
                }
            }
        }

        // Near-surface mist band (inside).
        do {
            let a = maxAlpha * clamp01(cfg.fuzzTextureInnerOpacityMultiplier) * 0.92
            if a > 0.0001 {
                context.drawLayer { layer in
                    layer.clip(to: Path(clipRect))
                    layer.clip(to: corePath)
                    layer.clip(to: innerBandPath)

                    layer.blendMode = .plusLighter
                    layer.opacity = a
                    layer.fill(Path(clipRect), with: coarseShading)

                    layer.opacity = a * 0.55
                    layer.fill(Path(clipRect), with: coarseDetailShading)

                    layer.blendMode = .destinationIn
                    layer.opacity = 1.0
                    layer.fill(Path(clipRect), with: xMaskShading)
                }
            }
        }

        // Above-surface mist (white + blue), masked by seamless noise.
        do {
            let allowOuter = cfg.fuzzOuterDustEnabled
            if allowOuter {
                var outside = Path()
                outside.addRect(clipRect)
                outside.addPath(corePath)

                let blueA = maxAlpha * clamp01(cfg.fuzzTextureOuterOpacityMultiplier) * 0.70
                let whiteA = maxAlpha * clamp01(cfg.fuzzTextureOuterOpacityMultiplier) * 0.32

                if (blueA + whiteA) > 0.0001 {
                    context.drawLayer { layer in
                        layer.clip(to: Path(clipRect))
                        layer.clip(to: outerBandPath)
                        layer.clip(to: outside, style: FillStyle(eoFill: true, antialiased: true))

                        layer.blendMode = .normal
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: .color(cfg.fuzzColor.opacity(blueA)))

                        layer.blendMode = .plusLighter
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: .color(Color.white.opacity(whiteA)))

                        // Fine speckles to break up tiled shapes (masked by the same noise/fade below).
                        let speckA = maxAlpha * clamp01(cfg.fuzzTextureOuterOpacityMultiplier) * 0.10
                        layer.opacity = speckA
                        layer.fill(Path(clipRect), with: fineDetailShading)

                        layer.blendMode = .destinationIn
                        layer.opacity = 1.0
                        layer.fill(Path(clipRect), with: coarseDetailShading)
                        layer.fill(Path(clipRect), with: aboveFade)
                        layer.fill(Path(clipRect), with: xMaskShading)
                    }
                }
            }
        }

        // Subtle edge erosion (only within the contour band).
        if cfg.fuzzErodeEnabled && cfg.fuzzErodeStrength > 0.0001 {
            let k = max(0.0, cfg.fuzzErodeStrength)
            let a = maxAlpha * min(0.45, 0.22 * k)

            if a > 0.0001 {
                for pass in 0..<2 {
                    let passSeed = cfg.noiseSeed &+ UInt64(pass) &* 0xBF58476D1CE4E5B9

                    let passShading = tiledNoiseShading(
                        image: coarseNoise,
                        bounds: clipRect,
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

        let authored = CGFloat(RainSurfaceSeamlessNoiseTile.tileSizePixels)
        let desiredPt = CGFloat(max(16, desiredTilePixels)) / ds
        let baseScale = desiredPt / max(1.0, authored)

        let scale = max(0.10, min(6.0, baseScale * max(0.05, scaleMultiplier)))

        var prng = RainSurfacePRNG(seed: seed)
        let j = max(0.0, min(1.0, jitterFraction))
        let jitter = desiredPt * j

        let ox = (CGFloat(prng.nextFloat01()) - 0.5) * 2.0 * jitter
        let oy = (CGFloat(prng.nextFloat01()) - 0.5) * 2.0 * jitter

        let baseOx = desiredPt * 0.371
        let baseOy = desiredPt * 0.173
        let origin = CGPoint(x: bounds.minX + baseOx + ox, y: bounds.minY + baseOy + oy)

        return GraphicsContext.Shading.tiledImage(
            image,
            origin: origin,
            sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            scale: scale
        )
    }

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

    static func makeAlphaGradient(baseColor: Color, strength: [Double], minAlpha: Double, maxAlpha: Double, stops: Int) -> Gradient {
        let n = max(1, strength.count)
        let stopCount = max(2, stops)

        var out: [Gradient.Stop] = []
        out.reserveCapacity(stopCount)

        for i in 0..<stopCount {
            let t = Double(i) / Double(stopCount - 1)
            let idx = min(n - 1, max(0, Int(round(t * Double(n - 1)))))
            let s0 = clamp01(strength[idx])
            let minA = clamp01(minAlpha)
            let maxA = clamp01(maxAlpha)
            let a = clamp01(minA + (maxA - minA) * s0)
            out.append(Gradient.Stop(color: baseColor.opacity(a), location: t))
        }

        return Gradient(stops: out)
    }

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

        for i in 0..<n {
            if strength[i] > activeEps && Double(heights[i]) > 0.0001 {
                firstActive = min(firstActive, i)
                lastActive = max(lastActive, i)
                maxActiveH = max(maxActiveH, heights[i])
            }
        }

        if firstActive > lastActive {
            return CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: max(0.0, baselineY - rect.minY))
        }

        let stepX = rect.width / CGFloat(max(1, n))
        let xAt: (Int) -> CGFloat = { i in
            rect.minX + (CGFloat(i) + 0.5) * stepX
        }

        let padMul = max(cfg.fuzzTextureOuterBandMultiplier, cfg.fuzzTextureInnerBandMultiplier)
        let pad = max(2.0, bandHalfWidth * CGFloat(max(1.0, padMul)) * 1.25)

        let x0 = max(rect.minX, xAt(firstActive) - pad)
        let x1 = min(rect.maxX, xAt(lastActive) + pad)

        let top = max(rect.minY, baselineY - maxActiveH - pad)
        let bottom = min(rect.maxY, baselineY + pad)

        return CGRect(x: x0, y: top, width: max(1.0, x1 - x0), height: max(1.0, bottom - top))
    }
}
