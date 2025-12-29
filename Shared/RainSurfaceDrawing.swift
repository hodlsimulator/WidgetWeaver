//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum RainSurfaceDrawing {

    static func drawSurface(
        in context: inout GraphicsContext,
        geometry: RainSurfaceGeometry,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let chartRect = geometry.chartRect
        guard geometry.sampleCount > 1 else { return }

        // If the surface is effectively absent, skip heavy styling work.
        let scale = max(1.0, displayScale)
        let maxHeightPt = geometry.heights.max() ?? 0.0
        let maxHeightPx = maxHeightPt * scale
        guard maxHeightPx >= 0.18 else { return }

        // Band sizing is needed for several cheap welding layers.
        let bandWidthPx = fuzzBandWidthPixels(chartRect: chartRect, cfg: cfg, displayScale: displayScale)

        // Per-point styling strength (0..1), derived from probability + height semantics.
        let perPointStrength = computeFuzzStrengthPerPoint(
            geometry: geometry,
            cfg: cfg,
            bandWidthPx: bandWidthPx
        )
        let maxStrength = perPointStrength.max() ?? 0.0

        // Surface points + outward normals.
        let surfacePoints: [CGPoint] = (0..<geometry.sampleCount).map { geometry.surfacePointAt($0) }
        let normals = computeOutwardNormals(points: surfacePoints)
        let perSeg = segmentStrengths(from: perPointStrength)

        let fuzzAllowed = cfg.canEnableFuzz
            && cfg.fuzzEnabled
            && (cfg.fuzzMaxOpacity > 0.000_1)
            && (maxStrength > 0.015)

        // Slightly inset the solid core so fuzz owns the boundary.
        let insetPt = max(0.0, cfg.fuzzErodeRimInsetPixels) / scale
        var insetTopPoints: [CGPoint] = surfacePoints
        if fuzzAllowed, insetPt > 0.000_1, insetTopPoints.count == geometry.sampleCount {
            for i in 0..<insetTopPoints.count {
                var p = insetTopPoints[i]
                p.y += insetPt
                if p.y > geometry.baselineY { p.y = geometry.baselineY }
                insetTopPoints[i] = p
            }
        }

        let corePath = geometry.filledPath(usingInsetTopPoints: insetTopPoints)
        if corePath.isEmpty { return }

        let surfacePath = geometry.surfacePolylinePath()

        // ---- Core fill -------------------------------------------------------------------------
        context.fill(corePath, with: .color(cfg.coreBodyColor))

        // Subtle internal lift (clipped), keeping background black.
        drawCoreTopLift(
            in: &context,
            corePath: corePath,
            chartRect: chartRect,
            baselineY: geometry.baselineY,
            cfg: cfg,
            displayScale: displayScale,
            maxStrength: maxStrength
        )

        // Extra top-edge fade inside the core to help fuzz weld to the boundary.
        drawCoreEdgeFade(
            in: &context,
            corePath: corePath,
            surfacePath: surfacePath,
            cfg: cfg,
            bandWidthPx: bandWidthPx,
            displayScale: displayScale,
            maxStrength: maxStrength
        )

        // ---- Fuzz (outside-heavy particulate band + inside weld) --------------------------------
        if fuzzAllowed, cfg.fuzzHazeStrength > 0.000_1, maxStrength > 0.02 {
            drawFuzzHaze(
                in: &context,
                chartRect: chartRect,
                corePath: corePath,
                surfacePoints: surfacePoints,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                displayScale: displayScale,
                maxStrength: maxStrength
            )
        }

        if fuzzAllowed, cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.000_1, maxStrength > 0.02 {
            drawCoreErosion(
                in: &context,
                corePath: corePath,
                surfacePoints: surfacePoints,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                displayScale: displayScale,
                maxStrength: maxStrength
            )
        }

        if fuzzAllowed, cfg.fuzzSpeckStrength > 0.000_1, cfg.fuzzSpeckleBudget > 0, maxStrength > 0.03 {
            drawFuzzSpeckles(
                in: &context,
                chartRect: chartRect,
                corePath: corePath,
                surfacePoints: surfacePoints,
                normals: normals,
                perSegmentStrength: perSeg,
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                displayScale: displayScale,
                maxStrength: maxStrength
            )
        }

        // Faint under-grain near baseline (clipped to the core).
        drawBaselineGrain(
            in: &context,
            chartRect: chartRect,
            corePath: corePath,
            baselineY: geometry.baselineY,
            cfg: cfg,
            displayScale: displayScale,
            maxStrength: maxStrength
        )

        // ---- Gloss (optional) ------------------------------------------------------------------
        if cfg.glossEnabled, cfg.glossMaxOpacity > 0.000_1 {
            drawGloss(
                in: &context,
                corePath: corePath,
                surfacePath: surfacePath,
                chartRect: chartRect,
                cfg: cfg,
                displayScale: displayScale
            )
        }

        // ---- Glints (optional) -----------------------------------------------------------------
        if cfg.glintEnabled, cfg.glintMaxOpacity > 0.000_1, cfg.glintCount > 0 {
            drawGlints(
                in: &context,
                surfacePoints: surfacePoints,
                cfg: cfg,
                displayScale: displayScale
            )
        }

        // ---- Rim (crisp edge) ------------------------------------------------------------------
        if cfg.rimEnabled, maxHeightPx > 0.24 {
            drawRim(
                in: &context,
                surfacePath: surfacePath,
                cfg: cfg,
                displayScale: displayScale
            )
        }
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard cfg.baselineEnabled else { return }

        let scale = max(1.0, displayScale)
        let y = RainSurfaceMath.alignToPixelCenter(
            baselineY + (cfg.baselineOffsetPixels / scale),
            displayScale: displayScale
        )
        let w = max(1.0, cfg.baselineWidthPixels / scale)

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: y))
        p.addLine(to: CGPoint(x: chartRect.maxX, y: y))

        let fade = max(0.0, min(0.49, cfg.baselineEndFadeFraction))
        let leftA = fade
        let rightA = 1.0 - fade

        let color = cfg.baselineColor.opacity(cfg.baselineLineOpacity)
        let grad = Gradient(stops: [
            .init(color: color.opacity(0.0), location: 0.0),
            .init(color: color, location: leftA),
            .init(color: color, location: rightA),
            .init(color: color.opacity(0.0), location: 1.0)
        ])

        context.stroke(
            p,
            with: .linearGradient(
                grad,
                startPoint: CGPoint(x: chartRect.minX, y: y),
                endPoint: CGPoint(x: chartRect.maxX, y: y)
            ),
            lineWidth: w
        )
    }
}

// MARK: - Internals

private extension RainSurfaceDrawing {

    static func fuzzBandWidthPixels(chartRect: CGRect, cfg: RainForecastSurfaceConfiguration, displayScale: CGFloat) -> CGFloat {
        let pxFromFraction = chartRect.height * cfg.fuzzWidthFraction * max(1.0, displayScale)
        let clamped = min(max(pxFromFraction, cfg.fuzzWidthPixelsClamp.lowerBound), cfg.fuzzWidthPixelsClamp.upperBound)
        return max(6.0, clamped)
    }

    // NOTE: geometry.certaintyAt(i) is treated as a probability/chance (0..1).
    // Height always comes from intensity; chance affects styling only.
    static func computeFuzzStrengthPerPoint(
        geometry: RainSurfaceGeometry,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat
    ) -> [Double] {
        let n = geometry.sampleCount
        guard n > 0 else { return [] }

        let scale = max(1.0, geometry.displayScale)
        let dxPx = geometry.dx * scale
        let onePx = 1.0 / max(1.0, scale)

        // "Wet" is height-driven only.
        let wetByHeight: [Bool] = geometry.heights.map { $0 > (onePx * 0.5) }

        // Distance in samples to nearest wet point (for tails).
        var distToWet = Array(repeating: Int.max / 4, count: n)
        var last = -1
        for i in 0..<n {
            if wetByHeight[i] { last = i }
            if last >= 0 { distToWet[i] = i - last }
        }
        last = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if wetByHeight[i] { last = i }
            if last >= 0 { distToWet[i] = min(distToWet[i], last - i) }
        }

        // Tail distance in pixels: short, readable, and capped by the band width.
        let tailDistancePx: CGFloat = max(min(bandWidthPx * 2.1, 180.0), 28.0)
        let safeDxPx = max(0.000_001, dxPx)

        func tailPresence(_ dSamples: Int) -> Double {
            let dPx = Double(CGFloat(dSamples)) * Double(safeDxPx)
            let t = RainSurfaceMath.smoothstep(0.0, Double(tailDistancePx), dPx)
            return max(0.0, 1.0 - t)
        }

        // Chance -> strength mapping.
        let thr = RainSurfaceMath.clamp01(cfg.fuzzChanceThreshold)
        let trans = max(0.000_1, cfg.fuzzChanceTransition)
        let floorS = RainSurfaceMath.clamp01(cfg.fuzzChanceFloor)
        let expn = max(0.10, cfg.fuzzChanceExponent)
        let tailMin = RainSurfaceMath.clamp01(cfg.fuzzChanceMinStrength)

        // Low-height + slope boosts emphasise tails/shoulders.
        let baselineDist = max(1.0, geometry.baselineY - geometry.chartRect.minY)
        let lowPower = max(0.10, cfg.fuzzLowHeightPower)
        let lowBoostMax = max(0.0, cfg.fuzzLowHeightBoost)

        let bandPt = bandWidthPx / scale
        let slopeDenom = max(0.08, bandPt * 0.65)
        let slopeBoostMax = max(0.0, min(0.82, 0.22 + 0.58 * lowBoostMax))

        let density = max(0.0, min(2.0, cfg.fuzzDensity))

        var strength: [Double] = Array(repeating: 0.0, count: n)

        for i in 0..<n {
            let chance = geometry.certaintyAt(i)

            let presence: Double = wetByHeight[i] ? 1.0 : tailPresence(distToWet[i])
            if presence <= 0.000_01 {
                strength[i] = 0.0
                continue
            }

            let x = RainSurfaceMath.clamp01((chance - thr) / trans)
            let mapped = floorS + (1.0 - floorS) * pow(x, expn)

            // Tail readability even if chance falls quickly after wet ends.
            let tailOverride = tailMin * presence
            var s = max(mapped, tailOverride) * presence

            // Low height boost near baseline.
            let h = geometry.heights[i]
            let h01 = Double(max(0.0, min(1.0, h / baselineDist)))
            let low = pow(1.0 - h01, lowPower)
            s *= (1.0 + lowBoostMax * low)

            // Shoulder boost based on local slope.
            let hPrev = geometry.heights[max(0, i - 1)]
            let hNext = geometry.heights[min(n - 1, i + 1)]
            let slope = Double(abs(hNext - hPrev)) / Double(slopeDenom)
            let slopeT = min(1.0, max(0.0, slope))
            s *= (1.0 + slopeBoostMax * pow(slopeT, 0.85))

            // Density scaling keeps budgets stable; mainly adjusts perceived strength.
            s *= (0.70 + 0.30 * density)

            strength[i] = RainSurfaceMath.clamp01(s)
        }

        // Small smoothing reduces seam artefacts.
        strength = RainSurfaceMath.smooth(strength, windowRadius: 2, passes: 1)
            .map { RainSurfaceMath.clamp01($0) }

        return strength
    }

    static func segmentStrengths(from perPoint: [Double]) -> [Double] {
        guard perPoint.count >= 2 else { return [] }
        var s: [Double] = []
        s.reserveCapacity(perPoint.count - 1)
        for i in 0..<(perPoint.count - 1) {
            s.append(0.5 * (perPoint[i] + perPoint[i + 1]))
        }
        return s
    }

    static func computeOutwardNormals(points: [CGPoint]) -> [CGVector] {
        let n = points.count
        guard n >= 2 else { return Array(repeating: CGVector(dx: 0, dy: -1), count: n) }

        func norm(_ v: CGVector) -> CGVector {
            let len = sqrt(v.dx * v.dx + v.dy * v.dy)
            if len < 0.000_001 { return CGVector(dx: 0, dy: -1) }
            return CGVector(dx: v.dx / len, dy: v.dy / len)
        }

        var normals: [CGVector] = Array(repeating: CGVector(dx: 0, dy: -1), count: n)

        for i in 0..<n {
            let p0 = points[max(0, i - 1)]
            let p1 = points[min(n - 1, i + 1)]
            let t = CGVector(dx: p1.x - p0.x, dy: p1.y - p0.y)

            // Right-hand normal: (dy, -dx)
            var nn = norm(CGVector(dx: t.dy, dy: -t.dx))

            // Ensure it generally points outward (upward) for the top curve.
            if nn.dy > 0 {
                nn = CGVector(dx: -nn.dx, dy: -nn.dy)
            }
            normals[i] = nn
        }

        return normals
    }

    static func boostedFuzzColor(_ cfg: RainForecastSurfaceConfiguration) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(cfg.fuzzColor)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            let rr = min(1.0, r * 1.00)
            let gg = min(1.0, g * 1.06)
            let bb = min(1.0, b * 1.18)
            return Color(red: Double(rr), green: Double(gg), blue: Double(bb), opacity: Double(a))
        }
        return cfg.fuzzColor
        #else
        return cfg.fuzzColor
        #endif
    }

    static func buildBinnedSegmentPaths(
        points: [CGPoint],
        perSegmentStrength: [Double],
        bins: Int
    ) -> (paths: [Path], avg: [Double]) {
        let n = points.count
        guard bins >= 2, n >= 2, perSegmentStrength.count == n - 1 else {
            return (Array(repeating: Path(), count: max(2, bins)), Array(repeating: 0.0, count: max(2, bins)))
        }

        var paths = Array(repeating: Path(), count: bins)
        var sum = Array(repeating: 0.0, count: bins)
        var cnt = Array(repeating: 0, count: bins)

        for i in 0..<(n - 1) {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 { continue }

            let b = min(bins - 1, max(0, Int(floor(s * Double(bins)))))
            var seg = Path()
            seg.move(to: points[i])
            seg.addLine(to: points[i + 1])
            paths[b].addPath(seg)

            sum[b] += s
            cnt[b] += 1
        }

        var avg = Array(repeating: 0.0, count: bins)
        for i in 0..<bins {
            if cnt[i] > 0 {
                avg[i] = sum[i] / Double(cnt[i])
            } else {
                avg[i] = 0.0
            }
        }

        return (paths, avg)
    }

    static func drawCoreTopLift(
        in context: inout GraphicsContext,
        corePath: Path,
        chartRect: CGRect,
        baselineY: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let mix = Double(max(0.0, min(1.0, cfg.coreTopMix)))
        guard mix > 0.000_1 else { return }

        let scale = max(1.0, displayScale)
        let h = max(1.0, baselineY - chartRect.minY)

        let topAlpha = min(1.0, max(0.0, (0.18 + 0.10 * maxStrength) * mix))
        let midAlpha = min(1.0, max(0.0, (0.08 + 0.06 * maxStrength) * mix))

        let grad = Gradient(stops: [
            .init(color: cfg.coreTopColor.opacity(topAlpha), location: 0.0),
            .init(color: cfg.coreTopColor.opacity(midAlpha), location: min(0.85, 0.55 + 0.20 * (1.0 / max(1.0, Double(h / 120.0))))),
            .init(color: cfg.coreTopColor.opacity(0.0), location: 1.0)
        ])

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter

            var rect = Path()
            rect.addRect(CGRect(x: chartRect.minX, y: chartRect.minY, width: chartRect.width, height: h))

            layer.fill(
                rect,
                with: .linearGradient(
                    grad,
                    startPoint: CGPoint(x: chartRect.midX, y: chartRect.minY),
                    endPoint: CGPoint(x: chartRect.midX, y: baselineY)
                )
            )

            // A thin inner edge lift helps the rim read crisp without a halo.
            let w = max(0.6, min(6.0, (2.2 * mix) / scale))
            let blur = max(0.0, min(3.0, w * 0.75))
            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            // The stroke target is drawn later (surfacePath), so this lift is handled elsewhere.
        }
    }

    static func drawCoreEdgeFade(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePath: Path,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let f = max(0.0, min(0.40, cfg.coreFadeFraction))
        guard f > 0.000_1 else { return }

        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let w = max(0.65, min(14.0, bandPt * f * 1.25))
        let blur = max(0.0, min(8.0, w * 0.90))

        let baseA = min(0.22, max(0.04, Double(f) * (0.85 + 0.35 * maxStrength)))

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut

            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            layer.stroke(
                surfacePath,
                with: .color(Color.white.opacity(baseA)),
                lineWidth: w
            )
        }
    }

    static func drawBaselineGrain(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        baselineY: CGFloat,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let scale = max(1.0, displayScale)
        let isTightBudget = (cfg.fuzzSpeckleBudget <= 900) || (cfg.maxDenseSamples <= 280)

        let baseCount = isTightBudget ? 180 : 420
        let widthFactor = Double(min(1.0, max(0.15, (chartRect.width * scale) / 360.0)))
        let strengthFactor = 0.45 + 0.55 * maxStrength
        let count = max(0, min(isTightBudget ? 220 : 520, Int(Double(baseCount) * widthFactor * strengthFactor)))
        guard count > 0 else { return }

        let bandH = max(2.0, min(12.0, (6.0 + 6.0 * maxStrength) / scale))
        let r0 = (0.22 / scale)
        let r1 = (0.88 / scale)

        let baseA = min(0.20, max(0.02, (cfg.baselineLineOpacity * 0.10) + (cfg.fuzzMaxOpacity * 0.045)))
        let color = cfg.fuzzColor.opacity(baseA)

        var p = Path()
        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xBADA55_51A5E_0001)
        var prng = RainSurfacePRNG(seed: seed)

        for _ in 0..<count {
            let x = chartRect.minX + CGFloat(prng.nextFloat01()) * chartRect.width
            let t = CGFloat(prng.nextFloat01())
            let y = baselineY - t * bandH
            let rr = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())
            p.addEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
        }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter
            layer.fill(p, with: .color(color))
        }
    }

    static func drawCoreErosion(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let insideWidth = bandPt * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor))
        let w = max(0.65, min(12.0, insideWidth * 0.42))
        let blur = max(0.0, min(8.0, insideWidth * 0.20))

        var baseAlpha = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzErodeStrength))
        baseAlpha *= (0.30 + 0.70 * maxStrength)
        baseAlpha = min(0.24, baseAlpha)

        guard baseAlpha > 0.000_1 else { return }

        let bins = 6
        let binned = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, bins: bins)

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            let edgePow = max(0.10, cfg.fuzzErodeEdgePower)

            for i in 0..<bins {
                let s = binned.avg[i]
                if s <= 0.000_01 { continue }
                let a = baseAlpha * pow(max(0.0, min(1.0, s)), edgePow)
                if a <= 0.000_01 { continue }

                layer.stroke(
                    binned.paths[i],
                    with: .color(Color.white.opacity(a)),
                    lineWidth: w
                )
            }
        }
    }

    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let isTightBudget = (cfg.fuzzSpeckleBudget <= 900) || (cfg.maxDenseSamples <= 280)
        let density = max(0.0, min(2.0, cfg.fuzzDensity))

        let boostedColor = boostedFuzzColor(cfg)

        let outsideWidth = max(0.000_1, bandPt)
        let insideWidth = max(0.0, outsideWidth * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor)))

        let blurFrac = max(0.0, min(0.60, cfg.fuzzHazeBlurFractionOfBand))
        var blur = max(0.0, min(8.0, outsideWidth * CGFloat(blurFrac)))
        var outsideStrokeW = max(0.8, min(120.0, outsideWidth * CGFloat(max(0.10, cfg.fuzzHazeStrokeWidthFactor))))
        var insideStrokeW = max(0.8, min(120.0, outsideStrokeW * CGFloat(max(0.10, cfg.fuzzInsideHazeStrokeWidthFactor))))

        if isTightBudget {
            blur = min(4.5, blur * 0.70)
            outsideStrokeW = outsideStrokeW * 0.70
            insideStrokeW = insideStrokeW * 0.70
        }

        var baseAlpha = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzHazeStrength))
        baseAlpha *= (0.08 + 0.22 * maxStrength)
        baseAlpha *= (0.82 + 0.18 * density)
        baseAlpha = min(0.14, baseAlpha)

        guard baseAlpha > 0.000_1 else { return }

        let bins = 6
        let binned = buildBinnedSegmentPaths(points: surfacePoints, perSegmentStrength: perSegmentStrength, bins: bins)

        // Outside haze (clipped to outside of the core).
        context.drawLayer { layer in
            let bleed = max(0.0, bandPt * 3.0)
            var outside = Path()
            outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
            outside.addPath(corePath)

            layer.clip(to: outside, style: FillStyle(eoFill: true))
            layer.blendMode = .plusLighter

            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            for i in 0..<bins {
                let s = binned.avg[i]
                if s <= 0.000_01 { continue }
                let a = baseAlpha * (0.18 + 0.82 * pow(s, 0.85))
                if a <= 0.000_01 { continue }

                layer.stroke(
                    binned.paths[i],
                    with: .color(boostedColor.opacity(a)),
                    lineWidth: outsideStrokeW
                )
            }
        }

        // Inside weld haze (clipped to the core).
        if insideWidth > 0.000_01, cfg.fuzzInsideOpacityFactor > 0.000_1 {
            let insideOpacity = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
            let blurInside = max(0.0, min(6.0, blur * 0.62))

            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .plusLighter

                if blurInside > 0.001 {
                    layer.addFilter(.blur(radius: blurInside))
                }

                for i in 0..<bins {
                    let s = binned.avg[i]
                    if s <= 0.000_01 { continue }
                    var a = baseAlpha * 0.70 * insideOpacity * (0.20 + 0.80 * pow(s, 0.80))
                    a = min(0.10, a)
                    if a <= 0.000_01 { continue }

                    layer.stroke(
                        binned.paths[i],
                        with: .color(boostedColor.opacity(a)),
                        lineWidth: insideStrokeW
                    )
                }
            }
        }
    }

    static func drawFuzzSpeckles(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        corePath: Path,
        surfacePoints: [CGPoint],
        normals: [CGVector],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        displayScale: CGFloat,
        maxStrength: Double
    ) {
        guard surfacePoints.count >= 2, normals.count == surfacePoints.count else { return }
        if maxStrength <= 0.03 { return }

        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let outsideWidth = max(0.000_1, bandPt)
        let insideWidth = max(0.0, bandPt * CGFloat(max(0.0, cfg.fuzzInsideWidthFactor)))

        let isTightBudget = (cfg.fuzzSpeckleBudget <= 900) || (cfg.maxDenseSamples <= 280)
        let density = max(0.0, min(2.0, cfg.fuzzDensity))
        let boostedColor = boostedFuzzColor(cfg)

        let baseSpeckAlpha = max(0.0, min(1.0, cfg.fuzzMaxOpacity * cfg.fuzzSpeckStrength))

        let rPx0 = max(0.22, min(3.0, cfg.fuzzSpeckleRadiusPixels.lowerBound))
        let rPx1 = max(rPx0, min(6.0, cfg.fuzzSpeckleRadiusPixels.upperBound))

        let r0 = rPx0 / scale
        let r1 = rPx1 / scale

        // Dynamic speckle count: scale by overall strength.
        let baseBudget0 = max(0, min(6500, cfg.fuzzSpeckleBudget))
        let strengthScale = max(0.0, min(1.0, 0.32 + 0.68 * maxStrength))
        let densityScale = max(0.0, min(1.0, 0.78 + 0.22 * density))

        var baseCount = Int((Double(baseBudget0) * strengthScale * densityScale).rounded(.toNearestOrAwayFromZero))
        if isTightBudget {
            baseCount = min(1200, baseCount)
        } else {
            baseCount = min(6500, baseCount)
        }
        if baseCount <= 0 { return }

        // Build segment CDF. A small floor keeps density along slopes without concentrating only at peaks.
        let segCount = perSegmentStrength.count
        var segCDF: [Double] = Array(repeating: 0.0, count: segCount)
        var totalW: Double = 0.0

        for i in 0..<segCount {
            let s = RainSurfaceMath.clamp01(perSegmentStrength[i])
            if s <= 0.000_01 {
                segCDF[i] = totalW
                continue
            }
            let w = (0.18 + 0.82 * pow(s, 0.55))
            totalW += w
            segCDF[i] = totalW
        }

        if totalW <= 0.000_001 { return }

        @inline(__always)
        func pickSegment(u01: Double) -> Int {
            let target = u01 * totalW
            var lo = 0
            var hi = segCDF.count - 1
            while lo < hi {
                let mid = (lo + hi) >> 1
                if segCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
            }
            return max(0, min(segCount - 1, lo))
        }

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xC0FFEE_BAAD_F00D)
        var prng = RainSurfacePRNG(seed: seed)

        let xBleed = bandPt * 1.6
        let yBleedTop = bandPt * 2.9
        let yBleedBottom = bandPt * 1.2

        let bins = 6
        var outsideBins: [Path] = Array(repeating: Path(), count: bins)
        var insideBins: [Path] = Array(repeating: Path(), count: bins)

        let insideFraction = max(0.0, min(1.0, cfg.fuzzInsideSpeckleFraction))
        let powOutside = max(0.10, cfg.fuzzDistancePowerOutside)
        let powInside = max(0.10, cfg.fuzzDistancePowerInside)
        let tangentJitter = max(0.0, cfg.fuzzAlongTangentJitter)

        var macroCount = 0
        let macroCap = isTightBudget ? 36 : 180
        let macroChance = isTightBudget ? 0.022 : 0.055

        // Base speckle field (distributed through the band).
        for _ in 0..<baseCount {
            let si = pickSegment(u01: prng.nextFloat01())
            let sSegRaw = RainSurfaceMath.clamp01(perSegmentStrength[si])
            if sSegRaw <= 0.000_01 { continue }

            // Flatten a bit so slopes retain visible grain.
            let sSeg = 0.22 + 0.78 * pow(sSegRaw, 0.60)

            let p0 = surfacePoints[si]
            let p1 = surfacePoints[si + 1]
            let t = CGFloat(prng.nextFloat01())
            let px = p0.x + (p1.x - p0.x) * t
            let py = p0.y + (p1.y - p0.y) * t

            let n0 = normals[si]
            let n1 = normals[si + 1]
            let nxRaw = n0.dx + (n1.dx - n0.dx) * t
            let nyRaw = n0.dy + (n1.dy - n0.dy) * t
            let nrmLen = sqrt(nxRaw * nxRaw + nyRaw * nyRaw)
            let nn: CGVector = (nrmLen > 0.000_001) ? CGVector(dx: nxRaw / nrmLen, dy: nyRaw / nrmLen) : CGVector(dx: 0, dy: -1)

            let tan = CGVector(dx: -nn.dy, dy: nn.dx)

            let insidePick = (prng.nextFloat01() < insideFraction) && (insideWidth > 0.000_01)

            let u = prng.nextFloat01()
            let d01 = pow(u, insidePick ? powInside : (powOutside * 1.08))
            let dist = CGFloat(d01) * (insidePick ? insideWidth : outsideWidth)
            let signedDist = insidePick ? -dist : dist

            let jitter = CGFloat(prng.nextSignedFloat()) * CGFloat(tangentJitter) * bandPt * 0.55
            let cx = px + nn.dx * signedDist + tan.dx * jitter
            let cy = py + nn.dy * signedDist + tan.dy * jitter

            if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
            if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

            var rr = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())
            var alphaMul: Double = 1.0

            // Occasional macro grains add volume to the outside fuzz (strictly capped).
            if !insidePick, macroCount < macroCap, prng.nextFloat01() < macroChance {
                macroCount += 1
                rr *= isTightBudget ? 2.05 : 2.20
                alphaMul *= 0.55
            }

            let denom = Double(insidePick ? insideWidth : outsideWidth)
            let distWeight: Double = {
                if denom <= 0.000_001 { return 1.0 }
                let a = min(1.0, max(0.0, 1.0 - Double(abs(signedDist)) / denom))
                let pp = insidePick ? powInside : powOutside
                return pow(a, max(0.10, pp))
            }()

            var alpha = baseSpeckAlpha * (0.22 + 0.78 * sSeg) * distWeight * alphaMul
            if insidePick {
                alpha *= max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
            }
            alpha *= (0.80 + 0.20 * density)
            alpha = max(0.0, min(1.0, alpha))

            let bin = min(bins - 1, max(0, Int(floor(alpha * Double(bins)))))
            let rect = CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)

            if insidePick {
                insideBins[bin].addEllipse(in: rect)
            } else {
                outsideBins[bin].addEllipse(in: rect)
            }
        }

        // Dense edge beads (hug the silhouette; cheap way to read ends/slopes).
        if surfacePoints.count >= 3, outsideWidth > 0.000_1 {
            var perPointS: [Double] = Array(repeating: 0.0, count: surfacePoints.count)
            if perSegmentStrength.count >= 1 {
                perPointS[0] = max(0.0, min(1.0, perSegmentStrength[0]))
                for i in 1..<(surfacePoints.count - 1) {
                    let a = max(0.0, min(1.0, perSegmentStrength[i - 1]))
                    let b = max(0.0, min(1.0, perSegmentStrength[min(perSegmentStrength.count - 1, i)]))
                    perPointS[i] = 0.5 * (a + b)
                }
                perPointS[surfacePoints.count - 1] = max(0.0, min(1.0, perSegmentStrength[perSegmentStrength.count - 1]))
            }

            // Point CDF with a small floor to keep beads along slopes.
            var ptCDF: [Double] = Array(repeating: 0.0, count: perPointS.count)
            var totalPt: Double = 0.0
            for i in 0..<perPointS.count {
                let s = RainSurfaceMath.clamp01(perPointS[i])
                if s <= 0.000_01 {
                    ptCDF[i] = totalPt
                    continue
                }
                let w = (0.22 + 0.78 * pow(s, 0.55))
                totalPt += w
                ptCDF[i] = totalPt
            }

            @inline(__always)
            func pickPoint(u01: Double) -> Int {
                if totalPt <= 0.000_001 { return 0 }
                let target = u01 * totalPt
                var lo = 0
                var hi = ptCDF.count - 1
                while lo < hi {
                    let mid = (lo + hi) >> 1
                    if ptCDF[mid] >= target { hi = mid } else { lo = mid + 1 }
                }
                return max(0, min(ptCDF.count - 1, lo))
            }

            let beadCap = isTightBudget ? 1400 : 4200
            let beadBase = Int(
                (Double(surfacePoints.count)
                 * (isTightBudget ? 4.4 : 7.2)
                 * (0.40 + 0.60 * maxStrength)
                 * (0.80 + 0.20 * density))
                    .rounded(.toNearestOrAwayFromZero)
            )
            let beadBudget = min(beadCap, max(0, beadBase))

            if beadBudget > 0 {
                for _ in 0..<beadBudget {
                    let i = pickPoint(u01: prng.nextFloat01())
                    let sRaw = RainSurfaceMath.clamp01(perPointS[i])
                    if sRaw <= 0.000_01 { continue }

                    let s = 0.28 + 0.72 * pow(sRaw, 0.60)

                    let p = surfacePoints[i]
                    let nn = normals[i]
                    let tan = CGVector(dx: -nn.dy, dy: nn.dx)

                    let u = prng.nextFloat01()
                    let d = outsideWidth * 0.60 * CGFloat(pow(u, 2.9))
                    let jitter = CGFloat(prng.nextSignedFloat()) * bandPt * CGFloat(tangentJitter) * 0.18

                    let cx = p.x + nn.dx * d + tan.dx * jitter
                    let cy = p.y + nn.dy * d + tan.dy * jitter

                    if cx < chartRect.minX - xBleed || cx > chartRect.maxX + xBleed { continue }
                    if cy < chartRect.minY - yBleedTop || cy > chartRect.maxY + yBleedBottom { continue }

                    var rr = (r0 * 0.46) + (r1 * 0.62 - r0 * 0.46) * CGFloat(prng.nextFloat01())

                    var a = baseSpeckAlpha * (0.52 + 0.48 * s)

                    let edgeW: Double = {
                        if outsideWidth <= 0.000_001 { return 1.0 }
                        let t = max(0.0, min(1.0, 1.0 - Double(d / max(0.000_1, outsideWidth * 0.60))))
                        return pow(t, 1.70)
                    }()

                    a *= edgeW
                    a *= (0.84 + 0.16 * density)

                    if !isTightBudget, prng.nextFloat01() < 0.07 {
                        rr *= 1.75
                        a *= 0.55
                    }

                    a = max(0.0, min(1.0, a))
                    let bin = min(bins - 1, max(0, Int(floor(a * Double(bins)))))

                    outsideBins[bin].addEllipse(in: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2))
                }
            }
        }

        // Draw: outside first (plusLighter, clipped), then inside (clipped).
        if outsideBins.contains(where: { !$0.isEmpty }) {
            context.drawLayer { layer in
                let bleed = max(0.0, bandPt * 3.0)
                var outside = Path()
                outside.addRect(chartRect.insetBy(dx: -bleed, dy: -bleed))
                outside.addPath(corePath)

                layer.clip(to: outside, style: FillStyle(eoFill: true))
                layer.blendMode = .plusLighter

                let microBlur = isTightBudget ? min(0.55, bandPt * 0.028) : min(1.25, bandPt * 0.050)
                if microBlur > 0.001 {
                    layer.addFilter(.blur(radius: microBlur))
                }

                for b in 0..<bins {
                    if outsideBins[b].isEmpty { continue }
                    let a = Double(b + 1) / Double(bins)
                    let opacity = max(0.0, min(1.0, a))
                    layer.fill(outsideBins[b], with: .color(boostedColor.opacity(opacity)))
                }
            }
        }

        if insideWidth > 0.000_01, insideBins.contains(where: { !$0.isEmpty }) {
            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .plusLighter

                let microBlur = isTightBudget ? min(0.50, bandPt * 0.026) : min(1.10, bandPt * 0.045)
                if microBlur > 0.001 {
                    layer.addFilter(.blur(radius: microBlur))
                }

                let insideOpacity = max(0.0, min(1.0, cfg.fuzzInsideOpacityFactor))
                for b in 0..<bins {
                    if insideBins[b].isEmpty { continue }
                    let a = (Double(b + 1) / Double(bins)) * insideOpacity
                    let opacity = max(0.0, min(1.0, a))
                    layer.fill(insideBins[b], with: .color(boostedColor.opacity(opacity)))
                }
            }
        }
    }

    static func drawRim(
        in context: inout GraphicsContext,
        surfacePath: Path,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)

        // Hard clamp prevents large soft halos in tight widget budgets.
        let outerW = max(0.5, min(8.0, cfg.rimOuterWidthPixels / scale))
        let innerW = max(0.5, min(3.0, cfg.rimInnerWidthPixels / scale))

        if cfg.rimOuterOpacity > 0.000_1 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                let blur = max(0.0, min(3.0, outerW * 0.18))
                if blur > 0.001 {
                    layer.addFilter(.blur(radius: blur))
                }
                layer.stroke(
                    surfacePath,
                    with: .color(cfg.rimColor.opacity(cfg.rimOuterOpacity)),
                    lineWidth: outerW
                )
            }
        }

        if cfg.rimInnerOpacity > 0.000_1 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.stroke(
                    surfacePath,
                    with: .color(cfg.rimColor.opacity(cfg.rimInnerOpacity)),
                    lineWidth: innerW
                )

                // Secondary tight stroke increases perceived crispness without a halo.
                layer.stroke(
                    surfacePath,
                    with: .color(cfg.rimColor.opacity(cfg.rimInnerOpacity * 0.55)),
                    lineWidth: max(0.5, innerW * 0.55)
                )
            }
        }
    }

    static func drawGloss(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePath: Path,
        chartRect: CGRect,
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let depth = max(1.0, cfg.glossDepthPixels / scale)
        let blur = max(0.0, cfg.glossBlurPixels / scale)
        let a0 = max(0.0, min(1.0, cfg.glossMaxOpacity))
        if a0 <= 0.000_1 { return }

        let offset = (chartRect.height * cfg.glossVerticalOffsetFraction).isFinite
            ? (chartRect.height * cfg.glossVerticalOffsetFraction)
            : 0.0

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter
            if blur > 0.001 {
                layer.addFilter(.blur(radius: blur))
            }

            var shifted = surfacePath
            shifted = shifted.offsetBy(dx: 0, dy: offset)

            layer.stroke(
                shifted,
                with: .color(cfg.coreTopColor.opacity(a0)),
                lineWidth: depth
            )
        }
    }

    static func drawGlints(
        in context: inout GraphicsContext,
        surfacePoints: [CGPoint],
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard !surfacePoints.isEmpty else { return }

        let scale = max(1.0, displayScale)
        let sigma = max(0.5, cfg.glintSigmaPixels / scale)
        let offsetY = cfg.glintVerticalOffsetPixels / scale

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xA11CE5A10DDC0FFE)
        var prng = RainSurfacePRNG(seed: seed)

        let n = max(1, cfg.glintCount)
        let a0 = max(0.0, min(1.0, cfg.glintMaxOpacity))
        if a0 <= 0.000_1 { return }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.addFilter(.blur(radius: max(0.0, sigma * 0.60)))

            for _ in 0..<n {
                let idx = Int(floor(prng.nextFloat01() * Double(surfacePoints.count)))
                let i = max(0, min(surfacePoints.count - 1, idx))
                let p = surfacePoints[i]

                let rr = max(0.9, min(18.0, (4.0 + 10.0 * prng.nextFloat01()) / scale))
                let a = a0 * (0.35 + 0.65 * prng.nextFloat01())

                let rect = CGRect(x: p.x - rr, y: (p.y + offsetY) - rr, width: rr * 2, height: rr * 2)
                var path = Path()
                path.addEllipse(in: rect)

                layer.fill(path, with: .color(cfg.rimColor.opacity(a)))
            }
        }
    }
}
