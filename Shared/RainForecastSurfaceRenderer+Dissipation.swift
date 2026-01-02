//
//  RainForecastSurfaceRenderer+Dissipation.swift
//  WidgetWeaver
//
//  Created by . . on 12/31/25.
//
//  Dissipation fuzz rendering.
//  Tiling layer placement matches the mockup:
//  - Texture belongs on tapered edges (near the sides/ends of each non-zero “island”)
//  - Texture is absent under the smooth interior core
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

        let n = min(heights.count, certainties01.count, curvePoints.count)
        guard n >= 3 else { return }
        guard curvePoints.count == heights.count, heights.count == certainties01.count else { return }

        let maxAlpha = clamp01Local(cfg.fuzzMaxOpacity)

        // Core change:
        // tilingStrength is now “edge/taper domain” first (per rain island),
        // then uncertainty/height modulates within that domain.
        let tilingStrength = computeTilingStrengthPerPoint(
            heights: heights,
            certainties01: certainties01.map { Double($0) },
            configuration: cfg
        )

        if (tilingStrength.max() ?? 0.0) <= 0.001 {
            return
        }

        let slopeStrength = computeSlopeStrengthPerPoint(heights: heights)

        // Surface tiling: keep it on sloped edges.
        let surfaceStrength: [Double] = zip(tilingStrength, slopeStrength).map { u, s in
            clamp01Local(u * (0.12 + 0.88 * s))
        }

        // Body tiling: still edge domain, slightly less slope-gated.
        let bodyStrength: [Double] = zip(tilingStrength, slopeStrength).map { u, s in
            clamp01Local(u * (0.30 + 0.70 * s))
        }

        let clipRect = computeDissipationClipRect(
            rect: rect,
            baselineY: baselineY,
            curvePoints: curvePoints,
            heights: heights,
            strength: tilingStrength,
            bandHalfWidth: bandHalfWidth,
            configuration: cfg
        )

        guard clipRect.width > 1.0, clipRect.height > 1.0 else { return }

        let contour = contourPath(from: curvePoints)

        let innerMul = max(0.05, cfg.fuzzTextureInnerBandMultiplier)
        let outerMul = max(innerMul, cfg.fuzzTextureOuterBandMultiplier)

        let surfaceBand = max(0.25, bandHalfWidth * CGFloat(innerMul))
        let outerBand = max(surfaceBand, bandHalfWidth * CGFloat(outerMul))

        let surfaceBandPath = contour.strokedPath(
            StrokeStyle(lineWidth: surfaceBand * 2.0, lineCap: .round, lineJoin: .round)
        )

        let outerBandPath = contour.strokedPath(
            StrokeStyle(lineWidth: outerBand * 2.0, lineCap: .round, lineJoin: .round)
        )

        // Body region starts below the surface, but rises towards the surface on low heights.
        let minY = curvePoints.map { $0.y }.min() ?? baselineY
        let peakHeight = max(0.0, baselineY - minY)

        let minInset = max(12.0, outerBand * 0.85)
        let maxInset = max(minInset, peakHeight * 0.55)
        let bodyInset = min(maxInset, max(minInset, peakHeight * 0.30))

        let bodyPath = loweredCoreFillPath(
            curvePoints: curvePoints,
            baselineY: baselineY,
            inset: bodyInset
        )

        // X-masks: use one stop per sample to avoid smearing texture into the smooth core.
        let maxStops = isExtension ? 256 : 512

        let surfaceMaskGradient = makeAlphaGradient(
            baseColor: .white,
            strength: surfaceStrength,
            minAlpha: 0.0,
            maxAlpha: 1.0,
            stopsHint: cfg.fuzzTextureGradientStops,
            maxStops: maxStops
        )

        let bodyMaskGradient = makeAlphaGradient(
            baseColor: .white,
            strength: bodyStrength,
            minAlpha: 0.0,
            maxAlpha: 1.0,
            stopsHint: cfg.fuzzTextureGradientStops,
            maxStops: maxStops
        )

        let surfaceMaskShading = GraphicsContext.Shading.linearGradient(
            surfaceMaskGradient,
            startPoint: CGPoint(x: clipRect.minX, y: clipRect.midY),
            endPoint: CGPoint(x: clipRect.maxX, y: clipRect.midY)
        )

        let bodyMaskShading = GraphicsContext.Shading.linearGradient(
            bodyMaskGradient,
            startPoint: CGPoint(x: clipRect.minX, y: clipRect.midY),
            endPoint: CGPoint(x: clipRect.maxX, y: clipRect.midY)
        )

        let fineNoise = RainSurfaceSeamlessNoiseTile.image(.fine)
        let coarseNoise = RainSurfaceSeamlessNoiseTile.image(.coarse)

        let widthDriven = Int((rect.width * ds) * (isExtension ? 0.55 : 0.45))
        let tilePixels = max(24, min(max(cfg.fuzzTextureTilePixels, widthDriven), 1024))

        let baseSeed = cfg.noiseSeed ^ stableSeed(from: curvePoints, displayScale: ds)

        let coarseA = tiledNoiseShading(
            image: coarseNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 1.25,
            seed: baseSeed &+ 0x0000_0000_0000_0001,
            jitterFraction: 0.22
        )
        let coarseB = tiledNoiseShading(
            image: coarseNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 1.25,
            seed: baseSeed &+ 0x9E37_79B9_7F4A_7C15,
            jitterFraction: 0.22
        )

        let coarseDetailA = tiledNoiseShading(
            image: coarseNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 2.35,
            seed: baseSeed &+ 0xBF58_476D_1CE4_E5B9,
            jitterFraction: 0.26
        )
        let coarseDetailB = tiledNoiseShading(
            image: coarseNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 2.35,
            seed: baseSeed &+ 0x94D0_49BB_1331_11EB,
            jitterFraction: 0.26
        )

        let fineA = tiledNoiseShading(
            image: fineNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 0.95,
            seed: baseSeed ^ 0xD1B5_4A32_D192_ED03,
            jitterFraction: 0.18
        )
        let fineB = tiledNoiseShading(
            image: fineNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 0.95,
            seed: baseSeed ^ 0x8CB9_2BA7_2F3D_8DD7,
            jitterFraction: 0.18
        )

        let fineDetailA = tiledNoiseShading(
            image: fineNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 0.62,
            seed: baseSeed ^ 0x4F1B_CDC7_14E5_A3B7,
            jitterFraction: 0.16
        )
        let fineDetailB = tiledNoiseShading(
            image: fineNoise,
            bounds: rect,
            displayScale: ds,
            desiredTilePixels: tilePixels,
            scaleMultiplier: 0.62,
            seed: baseSeed ^ 0x27D4_EB2F_1656_67C5,
            jitterFraction: 0.16
        )

        let clipRectPath = Path(clipRect)

        // PASS 1 — Surface tiling on tapered edges only.
        do {
            let surfaceMax = surfaceStrength.max() ?? 0.0
            if surfaceMax > 0.002 {
                let mulA = clamp01Local(cfg.fuzzTextureInnerOpacityMultiplier)
                let base = maxAlpha * mulA

                context.drawLayer { layer in
                    layer.clip(to: clipRectPath)
                    layer.clip(to: corePath)
                    layer.clip(to: surfaceBandPath)

                    layer.blendMode = .plusLighter

                    layer.opacity = base * 0.22 * 0.5
                    layer.fill(clipRectPath, with: coarseA)
                    layer.fill(clipRectPath, with: coarseB)

                    layer.opacity = base * 0.12 * 0.5
                    layer.fill(clipRectPath, with: coarseDetailA)
                    layer.fill(clipRectPath, with: coarseDetailB)

                    layer.opacity = base * 0.07 * 0.5
                    layer.fill(clipRectPath, with: fineA)
                    layer.fill(clipRectPath, with: fineB)

                    layer.opacity = base * 0.05 * 0.5
                    layer.fill(clipRectPath, with: fineDetailA)
                    layer.fill(clipRectPath, with: fineDetailB)

                    layer.blendMode = .destinationIn
                    layer.opacity = 1.0
                    layer.fill(clipRectPath, with: surfaceMaskShading)
                }
            }
        }

        // PASS 2 — Body tiling underneath tapered edges.
        do {
            let bodyMax = bodyStrength.max() ?? 0.0
            if bodyMax > 0.002 {
                let mulA = clamp01Local(cfg.fuzzTextureInnerOpacityMultiplier)
                let base = maxAlpha * mulA

                context.drawLayer { layer in
                    layer.clip(to: clipRectPath)
                    layer.clip(to: bodyPath)

                    layer.blendMode = .plusLighter

                    layer.opacity = base * 0.46 * 0.5
                    layer.fill(clipRectPath, with: coarseA)
                    layer.fill(clipRectPath, with: coarseB)

                    layer.opacity = base * 0.27 * 0.5
                    layer.fill(clipRectPath, with: coarseDetailA)
                    layer.fill(clipRectPath, with: coarseDetailB)

                    layer.opacity = base * 0.15 * 0.5
                    layer.fill(clipRectPath, with: fineA)
                    layer.fill(clipRectPath, with: fineB)

                    layer.opacity = base * 0.10 * 0.5
                    layer.fill(clipRectPath, with: fineDetailA)
                    layer.fill(clipRectPath, with: fineDetailB)

                    layer.blendMode = .destinationIn
                    layer.opacity = 1.0
                    layer.fill(clipRectPath, with: bodyMaskShading)
                }
            }
        }

        // Optional outer dust is still surface-masked.
        do {
            let allowOuter: Bool
            if isExtension {
                allowOuter = cfg.fuzzOuterDustEnabled && cfg.fuzzOuterDustEnabledInAppExtension
            } else {
                allowOuter = cfg.fuzzOuterDustEnabled
            }

            if allowOuter {
                var outside = Path()
                outside.addRect(clipRect)
                outside.addPath(corePath)

                let outerMulA = clamp01Local(cfg.fuzzTextureOuterOpacityMultiplier)
                let tintA = maxAlpha * outerMulA * 0.55

                if tintA > 0.0001 {
                    context.drawLayer { layer in
                        layer.clip(to: clipRectPath)
                        layer.clip(to: outerBandPath)
                        layer.clip(to: outside, style: FillStyle(eoFill: true, antialiased: true))

                        layer.blendMode = .plusLighter

                        layer.opacity = 0.55
                        layer.fill(clipRectPath, with: coarseDetailA)
                        layer.fill(clipRectPath, with: coarseDetailB)

                        layer.opacity = 0.35
                        layer.fill(clipRectPath, with: fineA)
                        layer.fill(clipRectPath, with: fineB)

                        layer.blendMode = .sourceIn
                        layer.opacity = 1.0
                        layer.fill(clipRectPath, with: .color(cfg.fuzzColor.opacity(tintA)))

                        layer.blendMode = .destinationIn
                        layer.opacity = 1.0
                        layer.fill(clipRectPath, with: surfaceMaskShading)
                    }
                }
            }
        }

        // Optional erosion stays on the body region.
        if !isExtension, cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.0001 {
            let k = max(0.0, cfg.fuzzErodeStrength)
            let a = maxAlpha * min(0.40, 0.20 * k)

            if a > 0.0001 {
                for pass in 0..<2 {
                    let passSeed = baseSeed &+ UInt64(pass) &* 0xBF58476D1CE4E5B9

                    let passShading = tiledNoiseShading(
                        image: coarseNoise,
                        bounds: rect,
                        displayScale: ds,
                        desiredTilePixels: tilePixels,
                        scaleMultiplier: 1.55 + CGFloat(pass) * 0.22,
                        seed: passSeed ^ 0x94D0_49BB_1331_11EB,
                        jitterFraction: 0.30
                    )

                    let prevBlend = context.blendMode
                    let prevOpacity = context.opacity
                    context.blendMode = .destinationOut
                    context.opacity = a

                    context.drawLayer { layer in
                        layer.clip(to: clipRectPath)
                        layer.clip(to: bodyPath)

                        layer.blendMode = .normal
                        layer.opacity = 1.0
                        layer.fill(clipRectPath, with: passShading)

                        layer.blendMode = .destinationIn
                        layer.opacity = 1.0
                        layer.fill(clipRectPath, with: bodyMaskShading)
                    }

                    context.blendMode = prevBlend
                    context.opacity = prevOpacity
                }
            }
        }
    }

    // MARK: - Tiling strength (placement)

    private static func computeTilingStrengthPerPoint(
        heights: [CGFloat],
        certainties01: [Double],
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> [Double] {
        let n = min(heights.count, certainties01.count)
        guard n > 0 else { return [] }

        let eps: CGFloat = 0.0001
        let maxH = max(0.0, heights.prefix(n).max() ?? 0.0)

        // 1) Domain mask: 1 at tapered edges of each non-zero segment, 0 at interior core.
        let edgeMask = computeEdgeStrengthPerPoint(heights: Array(heights.prefix(n)))

        // 2) Height shaping: stronger towards low heights (taper/bottom), softer higher up.
        let lowHeightMask = computeLowHeightStrengthPerPoint(
            heights: Array(heights.prefix(n)),
            maxHeight: maxH
        )

        // 3) Uncertainty shaping (still useful within the edge domain).
        let chanceThresh = clamp01Local(cfg.fuzzChanceThreshold)
        let chanceTrans = max(0.0001, clamp01Local(cfg.fuzzChanceTransition))
        let chanceExp = max(0.05, cfg.fuzzChanceExponent)

        // Floor for tails so textured tapers still read when certainty is high.
        let tailFloor: Double = 0.62

        var out = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let h = max(0.0, heights[i])

            // Outside the rain shape, nothing is needed.
            if h <= eps {
                out[i] = 0.0
                continue
            }

            let c = clamp01Local(certainties01[i])

            var u: Double
            if c >= chanceThresh {
                u = 0.0
            } else {
                let t = (chanceThresh - c) / chanceTrans
                u = clamp01Local(t)
            }
            u = pow(u, chanceExp)

            let low = lowHeightMask[i]
            let base = max(u, tailFloor * low)

            // Final placement: edge/taper domain decides where tiling can exist.
            var s = base * edgeMask[i]

            // Soft roll-off makes the interior core stay clean.
            s = pow(clamp01Local(s), 1.10)

            out[i] = s
        }

        // Keep baseline anchor samples adjacent to a segment from forcing an X-mask fade
        // right at the geometric taper endpoints.
        pinStrengthAtSegmentAnchors(&out, heights: Array(heights.prefix(n)))

        return out
    }

    private static func computeEdgeStrengthPerPoint(heights: [CGFloat]) -> [Double] {
        let n = heights.count
        guard n > 0 else { return [] }

        let eps: CGFloat = 0.0001
        var out = [Double](repeating: 0.0, count: n)

        var i = 0
        while i < n {
            while i < n && heights[i] <= eps { i += 1 }
            if i >= n { break }

            let start = i
            while i < n && heights[i] > eps { i += 1 }
            let end = i - 1

            let length = end - start + 1
            if length <= 0 { continue }

            // Controls how far the edge domain reaches into the segment.
            // Capped so the interior core can reach zero even on shorter segments.
            let edgeFraction: Double = 0.35
            var edgeWidth = Int((Double(length) * edgeFraction).rounded(.toNearestOrAwayFromZero))
            edgeWidth = max(4, min(56, edgeWidth))

            let dMax = max(1, length / 2)
            edgeWidth = min(edgeWidth, dMax)

            let denom = Double(max(1, edgeWidth))

            for j in start...end {
                let d = min(j - start, end - j)

                var t = 1.0 - (Double(d) / denom)
                t = clamp01Local(t)

                // Smooth edge falloff.
                var e = smoothstepLocal(t)
                e = pow(e, 1.15)

                out[j] = e
            }
        }

        return out
    }

    private static func computeLowHeightStrengthPerPoint(heights: [CGFloat], maxHeight: CGFloat) -> [Double] {
        let n = heights.count
        guard n > 0 else { return [] }

        let maxH = Double(max(0.0, maxHeight))
        if maxH <= 0.0001 {
            return [Double](repeating: 0.0, count: n)
        }

        // Low-height weighting:
        // - near the bottom/tapers: ~1
        // - towards the top: ~0
        let startFrac: Double = 0.90
        let widthFrac: Double = 0.42

        var out = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let h = Double(max(0.0, heights[i]))
            let frac = clamp01Local(h / maxH)

            var t = (startFrac - frac) / widthFrac
            t = clamp01Local(t)
            t = smoothstepLocal(t)
            t = pow(t, 1.05)

            out[i] = t
        }

        return out
    }

    private static func pinStrengthAtSegmentAnchors(_ strength: inout [Double], heights: [CGFloat]) {
        let n = min(strength.count, heights.count)
        guard n >= 2 else { return }

        let eps: CGFloat = 0.0001

        var i = 0
        while i < n {
            while i < n && heights[i] <= eps { i += 1 }
            if i >= n { break }

            let start = i
            while i < n && heights[i] > eps { i += 1 }
            let end = i - 1

            if start >= 0 && start < n {
                let v = strength[start]
                if start - 1 >= 0 {
                    strength[start - 1] = max(strength[start - 1], v)
                }
            }

            if end >= 0 && end < n {
                let v = strength[end]
                if end + 1 < n {
                    strength[end + 1] = max(strength[end + 1], v)
                }
            }
        }
    }

    private static func computeSlopeStrengthPerPoint(heights: [CGFloat]) -> [Double] {
        let n = heights.count
        guard n > 0 else { return [] }

        let maxH = Double(max(0.0, heights.max() ?? 0.0))
        if maxH <= 0.0001 {
            return [Double](repeating: 0.0, count: n)
        }

        var out = [Double](repeating: 0.0, count: n)

        for i in 0..<n {
            let a = Double(heights[max(0, i - 1)])
            let b = Double(heights[min(n - 1, i + 1)])
            let dh = abs(b - a)

            var s = (dh / maxH) / 0.08
            s = clamp01Local(s)
            s = smoothstepLocal(s)
            out[i] = s
        }

        return out
    }

    // MARK: - Masks

    private static func makeAlphaGradient(
        baseColor: Color,
        strength: [Double],
        minAlpha: Double,
        maxAlpha: Double,
        stopsHint: Int,
        maxStops: Int
    ) -> Gradient {
        let n = strength.count
        guard n > 0 else {
            return Gradient(stops: [
                .init(color: baseColor.opacity(minAlpha), location: 0.0),
                .init(color: baseColor.opacity(minAlpha), location: 1.0)
            ])
        }

        // One stop per sample gives a mask that matches placement precisely.
        let count = min(maxStops, max(2, n))

        var out: [Gradient.Stop] = []
        out.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let idx = Int((t * Double(n - 1)).rounded())
            let v = clamp01Local(strength[min(n - 1, max(0, idx))])

            let a = minAlpha + (maxAlpha - minAlpha) * v
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

        let activeEps: Double = 0.001
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

    // MARK: - Paths

    private static func contourPath(from points: [CGPoint]) -> Path {
        Self.buildCurveStrokePath(curvePoints: points)
    }

    private static func loweredCoreFillPath(
        curvePoints: [CGPoint],
        baselineY: CGFloat,
        inset: CGFloat
    ) -> Path {
        guard curvePoints.count >= 2 else { return Path() }

        let inset = max(0.0, inset)
        let eps: CGFloat = 0.0001

        let minY = curvePoints.map { $0.y }.min() ?? baselineY
        let peakHeight = max(0.0, baselineY - minY)
        let peakH = max(eps, peakHeight)

        // Cut fraction rises with height:
        // - low heights: minimal cut, body reaches close to surface
        // - high heights: deeper cut, body starts well below surface
        let cutMin: Double = 0.08
        let cutMax: Double = 0.76
        let cutExp: Double = 1.15

        var pts = curvePoints
        for i in 0..<pts.count {
            if abs(pts[i].y - baselineY) < eps {
                continue
            }

            let h = max(0.0, baselineY - pts[i].y)
            if h <= eps { continue }

            let k = clamp01Local(Double(h / peakH))
            let cutFrac = cutMin + (cutMax - cutMin) * pow(k, cutExp)

            let localInsetByFrac = h * CGFloat(cutFrac)
            let localInset = min(inset, localInsetByFrac)

            pts[i].y = min(baselineY, pts[i].y + localInset)
        }

        var p = Self.buildCurveStrokePath(curvePoints: pts)
        p.closeSubpath()
        return p
    }

    // MARK: - Tiled shading

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

        let authoredPt = CGFloat(RainSurfaceSeamlessNoiseTile.tileSizePixels)

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

        let originPxX = (bounds.minX * ds + baseOxPx + oxPx).rounded(.toNearestOrAwayFromZero)
        let originPxY = (bounds.minY * ds + baseOyPx + oyPx).rounded(.toNearestOrAwayFromZero)
        let origin = CGPoint(x: originPxX / ds, y: originPxY / ds)

        let scale = max(0.10, min(6.0, targetPt / max(1.0, authoredPt)))

        return GraphicsContext.Shading.tiledImage(
            image,
            origin: origin,
            sourceRect: CGRect(x: 0, y: 0, width: 1, height: 1),
            scale: scale
        )
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

    // MARK: - Small math

    private static func clamp01Local(_ x: Double) -> Double {
        max(0.0, min(1.0, x.isFinite ? x : 0.0))
    }

    private static func smoothstepLocal(_ t: Double) -> Double {
        let x = clamp01Local(t)
        return x * x * (3.0 - 2.0 * x)
    }
}
