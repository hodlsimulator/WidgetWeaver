//
//  RainForecastSurfaceRenderer+Dissipation.swift
//  WidgetWeaver
//
//  Created by . . on 12/31/25.
//
//  Dissipation fuzz rendering.
//  Tiling is confined to low-certainty slopes and to the body under the surface.
//  Fix: ensure tapered ends show texture by (1) taper-edge boost and (2) height-dependent body cut.
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

        // Tiling strength:
        // - Uses uncertainty where available.
        // - Adds a taper-edge boost so geometric tails still show texture.
        // - Pins baseline anchors to avoid X-mask gradient artefacts at taper endpoints.
        let tilingStrength = computeTilingStrengthPerPoint(
            heights: heights,
            certainties01: certainties01.map { Double($0) },
            configuration: cfg
        )

        if (tilingStrength.max() ?? 0.0) <= 0.001 {
            return
        }

        let slopeStrength = computeSlopeStrengthPerPoint(heights: heights)

        // Surface tiling: emphasise slopes, avoid flat peaks.
        let surfaceStrength: [Double] = zip(tilingStrength, slopeStrength).map { u, s in
            clamp01Local(u * (0.10 + 0.90 * s))
        }

        // Body tiling: mostly uncertainty/taper-driven, lightly slope-weighted.
        let bodyStrength: [Double] = zip(tilingStrength, slopeStrength).map { u, s in
            clamp01Local(u * (0.35 + 0.65 * s))
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

        // Body region: a lowered version of the core fill, so tiling starts underneath the surface.
        // Height-dependent cut allows the body region to rise towards the surface on taper ends.
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

        // X-masks: more stops reduces visible vertical banding when texture is strong.
        let maxStops = isExtension ? 140 : 260
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

        // Tile shadings (two-phase draw reduces any residual repeat emphasis).
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

        // PASS 1 — Surface tiling, slopes only.
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

                    // Subtle on the surface; the body pass carries most of the texture.
                    layer.opacity = base * 0.18 * 0.5
                    layer.fill(clipRectPath, with: coarseA)
                    layer.fill(clipRectPath, with: coarseB)

                    layer.opacity = base * 0.10 * 0.5
                    layer.fill(clipRectPath, with: coarseDetailA)
                    layer.fill(clipRectPath, with: coarseDetailB)

                    layer.opacity = base * 0.06 * 0.5
                    layer.fill(clipRectPath, with: fineA)
                    layer.fill(clipRectPath, with: fineB)

                    layer.opacity = base * 0.04 * 0.5
                    layer.fill(clipRectPath, with: fineDetailA)
                    layer.fill(clipRectPath, with: fineDetailB)

                    layer.blendMode = .destinationIn
                    layer.opacity = 1.0
                    layer.fill(clipRectPath, with: surfaceMaskShading)
                }
            }
        }

        // PASS 2 — Body tiling underneath the surface.
        do {
            let bodyMax = bodyStrength.max() ?? 0.0
            if bodyMax > 0.002 {
                let mulA = clamp01Local(cfg.fuzzTextureInnerOpacityMultiplier)
                let base = maxAlpha * mulA

                context.drawLayer { layer in
                    layer.clip(to: clipRectPath)
                    layer.clip(to: bodyPath)

                    layer.blendMode = .plusLighter

                    layer.opacity = base * 0.42 * 0.5
                    layer.fill(clipRectPath, with: coarseA)
                    layer.fill(clipRectPath, with: coarseB)

                    layer.opacity = base * 0.24 * 0.5
                    layer.fill(clipRectPath, with: coarseDetailA)
                    layer.fill(clipRectPath, with: coarseDetailB)

                    layer.opacity = base * 0.13 * 0.5
                    layer.fill(clipRectPath, with: fineA)
                    layer.fill(clipRectPath, with: fineB)

                    layer.opacity = base * 0.09 * 0.5
                    layer.fill(clipRectPath, with: fineDetailA)
                    layer.fill(clipRectPath, with: fineDetailB)

                    layer.blendMode = .destinationIn
                    layer.opacity = 1.0
                    layer.fill(clipRectPath, with: bodyMaskShading)
                }
            }
        }

        // Optional outer dust, masked to the surface uncertainty region.
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

        // Optional erosion: apply to the body region, not the surface band.
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

    // MARK: - Tiling strength

    private static func computeTilingStrengthPerPoint(
        heights: [CGFloat],
        certainties01: [Double],
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> [Double] {
        let n = min(heights.count, certainties01.count)
        guard n > 0 else { return [] }

        var out = [Double](repeating: 0.0, count: n)

        let chanceThresh = clamp01Local(cfg.fuzzChanceThreshold)
        let chanceTrans = max(0.0001, clamp01Local(cfg.fuzzChanceTransition))
        let chanceExp = max(0.05, cfg.fuzzChanceExponent)

        let maxH = max(0.0, heights.prefix(n).max() ?? 0.0)

        for i in 0..<n {
            let h = max(0.0, heights[i])
            if h <= 0.0001 {
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

            if maxH > 0.0001 {
                let frac = Double(h / maxH)
                let lowPow = max(0.05, cfg.fuzzLowHeightPower)
                let lowBoost = max(0.0, cfg.fuzzLowHeightBoost)
                let low = pow(max(0.0, min(1.0, 1.0 - frac)), lowPow)
                u *= (1.0 + lowBoost * low)
            }

            out[i] = clamp01Local(u)
        }

        // Add texture on tapered ends even when certainty is high.
        applyTaperEdgeBoost(&out, heights: heights)

        // Avoid X-mask gradients on baseline anchors (taper endpoints).
        pinStrengthAtZeroHeightEndpoints(&out, heights: heights)

        return out
    }

    private static func applyTaperEdgeBoost(_ strength: inout [Double], heights: [CGFloat]) {
        let n = min(strength.count, heights.count)
        guard n >= 3 else { return }

        let eps: CGFloat = 0.0001

        var firstNonZero: Int? = nil
        for i in 0..<n {
            if heights[i] > eps {
                firstNonZero = i
                break
            }
        }

        var lastNonZero: Int? = nil
        for i in stride(from: n - 1, through: 0, by: -1) {
            if heights[i] > eps {
                lastNonZero = i
                break
            }
        }

        guard let f = firstNonZero, let l = lastNonZero, l > f else { return }

        let span = l - f + 1
        let edgeWindow = max(6, min(46, Int(Double(span) * 0.22)))

        let maxH = Double(max(0.0, heights[f...l].max() ?? 0.0))
        if maxH <= 0.0001 { return }

        // Gain is deliberately < 1 so uncertainty can still dominate where present.
        let gain: Double = 0.90

        for i in f...l {
            let h = Double(max(0.0, heights[i]))
            if h <= 0.0001 { continue }

            let d = min(i - f, l - i)

            var edge = 1.0 - (Double(d) / Double(edgeWindow))
            edge = clamp01Local(edge)
            edge = smoothstepLocal(edge)
            edge = pow(edge, 1.25)

            let hr = h / maxH
            var low = (0.62 - hr) / 0.62
            low = clamp01Local(low)
            low = smoothstepLocal(low)
            low = pow(low, 1.10)

            let taper = edge * low
            let boosted = clamp01Local(taper * gain)

            strength[i] = max(strength[i], boosted)
        }
    }

    private static func pinStrengthAtZeroHeightEndpoints(_ strength: inout [Double], heights: [CGFloat]) {
        let n = min(strength.count, heights.count)
        guard n >= 2 else { return }

        let eps: CGFloat = 0.0001

        var firstNonZero: Int? = nil
        for i in 0..<n {
            if heights[i] > eps {
                firstNonZero = i
                break
            }
        }

        var lastNonZero: Int? = nil
        for i in stride(from: n - 1, through: 0, by: -1) {
            if heights[i] > eps {
                lastNonZero = i
                break
            }
        }

        if let f = firstNonZero {
            let v = strength[f]
            if f > 0 {
                for i in 0..<f {
                    strength[i] = v
                }
            }
        }

        if let l = lastNonZero {
            let v = strength[l]
            if l < n - 1 {
                for i in (l + 1)..<n {
                    strength[i] = v
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

        let hinted = max(2, stopsHint)
        let auto = max(24, min(maxStops, max(48, n / 2)))
        let count = max(hinted, auto)

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
        // - Small heights (tapers): cut very little so the body region reaches up towards the surface.
        // - Large heights (peaks): cut more so the body region stays deeper.
        let cutMin: Double = 0.10
        let cutMax: Double = 0.72
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

        // Quantise to whole device pixels.
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
