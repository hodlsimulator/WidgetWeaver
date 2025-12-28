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

        // ---- Fuzz strength per point (0..1) ---------------------------------
        let bandWidthPx = fuzzBandWidthPixels(chartRect: chartRect, cfg: cfg, displayScale: displayScale)
        let bandWidthPt = bandWidthPx / max(1.0, displayScale)

        let perPointStrength = computeFuzzStrengthPerPoint(
            geometry: geometry,
            cfg: cfg,
            bandWidthPx: bandWidthPx
        )

        // ---- Build normals along the surface --------------------------------
        let surfacePoints = (0..<geometry.sampleCount).map { geometry.surfacePointAt($0) }
        let normals = computeOutwardNormals(points: surfacePoints)

        // ---- Core top inset (THIS is the “surface becomes fuzz” move) --------
        // Pull the solid fill down/inward so it never meets the true surface.
        // The fuzz band sits where the surface is.
        let baseInset = bandWidthPt * CGFloat(max(0.10, min(1.25, cfg.fuzzInsideWidthFactor))) * 0.55

        var insetTopPoints: [CGPoint] = []
        insetTopPoints.reserveCapacity(surfacePoints.count)

        for i in 0..<surfacePoints.count {
            let s = CGFloat(max(0.0, min(1.0, perPointStrength[i])))
            let inset = baseInset * (0.35 + 0.65 * s)

            let n = normals[i]
            let inward = CGVector(dx: -n.dx, dy: -n.dy)
            var p = CGPoint(
                x: surfacePoints[i].x + inward.dx * inset,
                y: surfacePoints[i].y + inward.dy * inset
            )

            // Prevent the inset from crossing below baseline (keeps dry segments clean).
            if p.y > geometry.baselineY { p.y = geometry.baselineY }
            insetTopPoints.append(p)
        }

        let corePath = geometry.filledPath(usingInsetTopPoints: insetTopPoints)
        let surfacePath = geometry.surfacePolylinePath()

        // ---- Core fill -------------------------------------------------------
        context.fill(corePath, with: .color(cfg.coreBodyColor))

        if cfg.coreTopMix > 0.001 {
            // Subtle top tint overlay, clipped to core.
            let mix = max(0.0, min(1.0, cfg.coreTopMix))
            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.fill(corePath, with: .color(cfg.coreTopColor.opacity(Double(mix))))
            }
        }

        // Extra fade-out at the top of the core (helps the hard edge disappear).
        if cfg.coreFadeFraction > 0.0001 {
            let fadeH = max(1.0, chartRect.height * cfg.coreFadeFraction)
            let y0 = chartRect.minY
            let y1 = min(chartRect.maxY, chartRect.minY + fadeH)

            var fadeRect = Path()
            fadeRect.addRect(CGRect(x: chartRect.minX, y: y0, width: chartRect.width, height: y1 - y0))

            // destinationOut removes alpha; a vertical gradient removes more near the top.
            let stops = Gradient(stops: [
                .init(color: Color.white.opacity(1.0), location: 0.0),
                .init(color: Color.white.opacity(0.0), location: 1.0)
            ])

            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .destinationOut
                layer.fill(
                    fadeRect,
                    with: .linearGradient(stops, startPoint: CGPoint(x: chartRect.midX, y: y0), endPoint: CGPoint(x: chartRect.midX, y: y1))
                )
            }
        }

        // ---- Fuzz: haze + speckles + erosion --------------------------------
        let fuzzAllowed = cfg.canEnableFuzz && cfg.fuzzEnabled
        if fuzzAllowed {
            // 1) Erode the core edge even more (removes any remaining “solid outline” feel).
            if cfg.fuzzErodeEnabled {
                drawCoreErosion(
                    in: &context,
                    corePath: corePath,
                    surfacePoints: surfacePoints,
                    perSegmentStrength: segmentStrengths(from: perPointStrength),
                    cfg: cfg,
                    bandWidthPx: bandWidthPx
                )
            }

            // 2) Outside haze (glow).
            drawFuzzHaze(
                in: &context,
                chartRect: chartRect,
                clipOutsideCore: corePath,
                surfacePoints: surfacePoints,
                perSegmentStrength: segmentStrengths(from: perPointStrength),
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                inside: false
            )

            // 3) Inside haze (glow within the fill near the edge).
            drawFuzzHaze(
                in: &context,
                chartRect: chartRect,
                clipInsideCore: corePath,
                surfacePoints: surfacePoints,
                perSegmentStrength: segmentStrengths(from: perPointStrength),
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                inside: true
            )

            // 4) Speckles (outside + a smaller portion inside).
            drawFuzzSpeckles(
                in: &context,
                chartRect: chartRect,
                corePath: corePath,
                surfacePoints: surfacePoints,
                normals: normals,
                perSegmentStrength: segmentStrengths(from: perPointStrength),
                cfg: cfg,
                bandWidthPx: bandWidthPx,
                displayScale: displayScale
            )
        }

        // ---- Gloss (optional) ------------------------------------------------
        if cfg.glossEnabled, cfg.glossMaxOpacity > 0.0001 {
            let depth = max(1.0, cfg.glossDepthPixels / max(1.0, displayScale))
            let blur = max(0.0, cfg.glossBlurPixels / max(1.0, displayScale))
            let offset = chartRect.height * cfg.glossVerticalOffsetFraction

            context.drawLayer { layer in
                layer.clip(to: corePath)
                layer.blendMode = .plusLighter
                if blur > 0.001 { layer.addFilter(.blur(radius: blur)) }

                // A soft band just below the surface.
                var glossPath = Path()
                for i in 0..<surfacePoints.count {
                    let p = surfacePoints[i]
                    glossPath.addEllipse(in: CGRect(x: p.x - depth, y: p.y + offset - depth, width: depth * 2, height: depth * 2))
                }

                layer.fill(glossPath, with: .color(cfg.coreTopColor.opacity(cfg.glossMaxOpacity)))
            }
        }

        // ---- Glints (optional) ----------------------------------------------
        if cfg.glintEnabled, cfg.glintCount > 0, cfg.glintMaxOpacity > 0.0001 {
            drawGlints(
                in: &context,
                surfacePoints: surfacePoints,
                cfg: cfg,
                displayScale: displayScale
            )
        }

        // ---- Rim (kept subtle; fuzz should “be” the edge) --------------------
        if cfg.rimEnabled {
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

        let y = RainSurfaceMath.alignToPixelCenter(baselineY + (cfg.baselineOffsetPixels / max(1.0, displayScale)), displayScale: displayScale)
        let w = max(1.0, cfg.baselineWidthPixels / max(1.0, displayScale))

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
            .init(color: color.opacity(0.0), location: 1.0),
        ])

        context.stroke(
            p,
            with: .linearGradient(grad, startPoint: CGPoint(x: chartRect.minX, y: y), endPoint: CGPoint(x: chartRect.maxX, y: y)),
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

    static func computeFuzzStrengthPerPoint(
        geometry: RainSurfaceGeometry,
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat
    ) -> [Double] {
        let n = geometry.sampleCount
        guard n > 0 else { return [] }

        let dxPt = geometry.dx
        let dxPx = dxPt * max(1.0, geometry.displayScale)

        // Wet mask should be driven by actual surface height.
        // Otherwise (when chance is non-zero everywhere) fuzz can collapse into a flat baseline band.
        let onePixelPt: CGFloat = 1.0 / max(1.0, geometry.displayScale)
        let epsilon: CGFloat = max(onePixelPt * 0.75, 0.20)

        var wet: [Bool] = Array(repeating: false, count: n)
        for i in 0..<n {
            wet[i] = geometry.heights[i] > epsilon
        }

        // No wet height => no fuzz band.
        if !wet.contains(true) {
            return Array(repeating: 0.0, count: n)
        }

        // Distance in samples to nearest wet.
        var dist = Array(repeating: Int.max / 4, count: n)
        var lastWet = -1
        for i in 0..<n {
            if wet[i] { lastWet = i }
            if lastWet >= 0 { dist[i] = i - lastWet }
        }
        lastWet = -1
        for i in stride(from: n - 1, through: 0, by: -1) {
            if wet[i] { lastWet = i }
            if lastWet >= 0 { dist[i] = min(dist[i], lastWet - i) }
        }

        // Fade distance: fuzz should stop shortly after wet ends.
        let fadeDistancePx = max(bandWidthPx * 1.8, 18.0)
        func wetFade(_ dSamples: Int) -> Double {
            let dPx = Double(CGFloat(dSamples) * dxPx)
            let t = RainSurfaceMath.smoothstep(0.0, Double(fadeDistancePx), dPx)
            return max(0.0, 1.0 - t)
        }

        // Chance -> fuzz (lower chance => more fuzz).
        let thr = cfg.fuzzChanceThreshold
        let trans = max(0.000_1, cfg.fuzzChanceTransition)
        let floorS = max(0.0, min(1.0, cfg.fuzzChanceFloor))
        let expn = max(0.10, cfg.fuzzChanceExponent)

        // Height boost.
        let baselineDist = max(1.0, geometry.baselineY - geometry.chartRect.minY)

        var strength: [Double] = []
        strength.reserveCapacity(n)

        for i in 0..<n {
            let chance = geometry.certaintyAt(i)

            // chance below threshold => positive => stronger fuzz
            let u = max(0.0, (thr - chance) / trans)
            var s = min(1.0, u)
            s = pow(s, expn)

            let h01 = Double(max(0.0, min(1.0, geometry.heights[i] / baselineDist)))

            // Gate low-height reinforcement so fully-dry samples do not create a baseline fog field.
            let wetGate = RainSurfaceMath.smoothstep01(RainSurfaceMath.clamp01(h01 / 0.10))

            // Keep a small floor for high-certainty plateaus, but attenuate it at near-zero height.
            s = max(s, floorS * (0.15 + 0.85 * wetGate))

            let lowBoostBase = pow(max(0.0, 1.0 - h01), max(0.10, cfg.fuzzLowHeightPower)) * max(0.0, cfg.fuzzLowHeightBoost)
            let lowBoost = lowBoostBase * wetGate

            var out = s + (1.0 - s) * lowBoost
            out *= wetFade(dist[i])

            out = max(0.0, min(1.0, out))
            strength.append(out)
        }

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
            let t = norm(CGVector(dx: p1.x - p0.x, dy: p1.y - p0.y))

            // Outward normal for a left->right polyline: (dy, -dx)
            var nrm = CGVector(dx: t.dy, dy: -t.dx)

            // Ensure it generally points “out” (upward for the top curve).
            if nrm.dy > 0 {
                nrm = CGVector(dx: -nrm.dx, dy: -nrm.dy)
            }
            normals[i] = norm(nrm)
        }
        return normals
    }

    static func boostedFuzzColor(_ color: Color) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)

        let rr = max(0, min(1, r * 0.78))
        let gg = max(0, min(1, g * 0.88))
        let bb = max(0, min(1, b * 1.18 + 0.04))
        return Color(red: rr, green: gg, blue: bb).opacity(Double(a))
        #else
        return color
        #endif
    }

    static func drawCoreErosion(
        in context: inout GraphicsContext,
        corePath: Path,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat
    ) {
        let widthPt = (bandWidthPx / max(1.0, context.environment.displayScale)) * CGFloat(max(0.20, min(1.5, cfg.fuzzInsideWidthFactor))) * 1.05
        let blurPt = max(0.0, widthPt * 0.35)

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .destinationOut
            if blurPt > 0.001 { layer.addFilter(.blur(radius: blurPt)) }

            for i in 0..<(surfacePoints.count - 1) {
                let s = pow(max(0.0, min(1.0, perSegmentStrength[i])), max(0.10, cfg.fuzzErodeEdgePower))
                let op = cfg.fuzzErodeStrength * s
                if op <= 0.0001 { continue }

                var seg = Path()
                seg.move(to: surfacePoints[i])
                seg.addLine(to: surfacePoints[i + 1])

                layer.stroke(seg, with: .color(Color.white.opacity(op)), lineWidth: widthPt)
            }
        }
    }

    static func drawFuzzHaze(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        clipOutsideCore corePathOutside: Path? = nil,
        clipInsideCore corePathInside: Path? = nil,
        surfacePoints: [CGPoint],
        perSegmentStrength: [Double],
        cfg: RainForecastSurfaceConfiguration,
        bandWidthPx: CGFloat,
        inside: Bool
    ) {
        let scale = max(1.0, context.environment.displayScale)
        let bandPt = bandWidthPx / scale

        let blur1 = max(0.0, bandPt * CGFloat(max(0.05, cfg.fuzzHazeBlurFractionOfBand)) * 1.05)
        let blur2 = max(0.0, bandPt * 0.16)

        let strokeFactor = inside ? cfg.fuzzInsideHazeStrokeWidthFactor : cfg.fuzzHazeStrokeWidthFactor
        let w1 = bandPt * CGFloat(max(0.25, strokeFactor))
        let w2 = bandPt * 0.70

        let baseColor = boostedFuzzColor(cfg.fuzzColor)
        let hazeAlphaBase = cfg.fuzzMaxOpacity * cfg.fuzzHazeStrength

        let opMul = inside ? cfg.fuzzInsideOpacityFactor : 1.0

        func clipLayer(_ layer: inout GraphicsContext) {
            if inside {
                if let corePathInside {
                    layer.clip(to: corePathInside)
                }
            } else {
                if let corePathOutside {
                    var outside = Path()
                    outside.addRect(chartRect)
                    outside.addPath(corePathOutside)
                    layer.clip(to: outside, style: FillStyle(eoFill: true))
                }
            }
        }

        // Two-pass haze to get a brighter “edge glow” with a softer outer bloom.
        context.drawLayer { layer in
            clipLayer(&layer)
            layer.blendMode = .plusLighter
            if blur1 > 0.001 { layer.addFilter(.blur(radius: blur1)) }

            for i in 0..<(surfacePoints.count - 1) {
                let s = max(0.0, min(1.0, perSegmentStrength[i]))
                let op = hazeAlphaBase * 0.72 * s * opMul
                if op <= 0.0001 { continue }

                var seg = Path()
                seg.move(to: surfacePoints[i])
                seg.addLine(to: surfacePoints[i + 1])
                layer.stroke(seg, with: .color(baseColor.opacity(op)), lineWidth: w1)
            }
        }

        context.drawLayer { layer in
            clipLayer(&layer)
            layer.blendMode = .plusLighter
            if blur2 > 0.001 { layer.addFilter(.blur(radius: blur2)) }

            for i in 0..<(surfacePoints.count - 1) {
                let s = max(0.0, min(1.0, perSegmentStrength[i]))
                let op = hazeAlphaBase * 0.38 * s * opMul
                if op <= 0.0001 { continue }

                var seg = Path()
                seg.move(to: surfacePoints[i])
                seg.addLine(to: surfacePoints[i + 1])
                layer.stroke(seg, with: .color(cfg.fuzzColor.opacity(op)), lineWidth: w2)
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
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let bandPt = bandWidthPx / scale

        let insideWidth = bandPt * CGFloat(max(0.05, min(2.0, cfg.fuzzInsideWidthFactor)))
        let outsideWidth = bandPt

        // Segment weights (more speckles where fuzz is strong).
        var weights: [Double] = []
        weights.reserveCapacity(perSegmentStrength.count)
        var totalW: Double = 0
        for s in perSegmentStrength {
            let w = max(0.000_01, s)
            weights.append(w)
            totalW += w
        }
        if totalW <= 0.000_001 { return }

        var prefix: [Double] = Array(repeating: 0, count: weights.count)
        var acc: Double = 0
        for i in 0..<weights.count {
            acc += weights[i]
            prefix[i] = acc
        }

        func pickSegment(_ r: Double) -> Int {
            let x = r * acc
            var lo = 0
            var hi = prefix.count - 1
            while lo < hi {
                let mid = (lo + hi) >> 1
                if x <= prefix[mid] { hi = mid } else { lo = mid + 1 }
            }
            return lo
        }

        let glowColor = boostedFuzzColor(cfg.fuzzColor)
        let baseSpeckAlpha = cfg.fuzzMaxOpacity * cfg.fuzzSpeckStrength

        // Radii in points.
        let r0 = cfg.fuzzSpeckleRadiusPixels.lowerBound / scale
        let r1 = cfg.fuzzSpeckleRadiusPixels.upperBound / scale

        let count = max(0, cfg.fuzzSpeckleBudget)
        if count == 0 { return }

        // Binned paths for performance.
        let bins = 5
        var outsideBins: [Path] = Array(repeating: Path(), count: bins)
        var insideBins: [Path] = Array(repeating: Path(), count: bins)

        var prng = RainSurfacePRNG(seed: RainSurfacePRNG.combine(cfg.noiseSeed, 0xC0FFEE_BAAD_F00D))

        for _ in 0..<count {
            let segIdx = pickSegment(prng.nextFloat01())
            let sSeg = max(0.0, min(1.0, perSegmentStrength[segIdx]))
            if sSeg <= 0.000_1 { continue }

            let p0 = surfacePoints[segIdx]
            let p1 = surfacePoints[segIdx + 1]
            let n0 = normals[segIdx]
            let n1 = normals[segIdx + 1]

            let t = CGFloat(prng.nextFloat01())
            let px = p0.x + (p1.x - p0.x) * t
            let py = p0.y + (p1.y - p0.y) * t

            // Interpolate normal and compute tangent.
            let nx = n0.dx + (n1.dx - n0.dx) * t
            let ny = n0.dy + (n1.dy - n0.dy) * t
            let nrmLen = sqrt(nx * nx + ny * ny)
            let nn = nrmLen > 0.000_001 ? CGVector(dx: nx / nrmLen, dy: ny / nrmLen) : CGVector(dx: 0, dy: -1)
            let tan = CGVector(dx: -nn.dy, dy: nn.dx)

            // Decide inside/outside.
            let insidePick = prng.nextFloat01() < max(0.0, min(1.0, cfg.fuzzInsideSpeckleFraction))

            let powOutside = max(0.10, cfg.fuzzDistancePowerOutside)
            let powInside = max(0.10, cfg.fuzzDistancePowerInside)

            let u = prng.nextFloat01()
            let d01 = pow(u, insidePick ? powInside : powOutside)

            let dist = CGFloat(d01) * (insidePick ? insideWidth : outsideWidth)
            let signedDist = insidePick ? -dist : dist

            let jitter = CGFloat(prng.nextSignedFloat()) * CGFloat(max(0.0, cfg.fuzzAlongTangentJitter)) * bandPt * 0.55

            let cx = px + nn.dx * signedDist + tan.dx * jitter
            let cy = py + nn.dy * signedDist + tan.dy * jitter

            // Keep within chart.
            if cx < chartRect.minX - bandPt || cx > chartRect.maxX + bandPt { continue }
            if cy < chartRect.minY - bandPt * 2 || cy > chartRect.maxY + bandPt { continue }

            // Radius and alpha bin.
            let rr = r0 + (r1 - r0) * CGFloat(prng.nextFloat01())

            let distWeight: Double = {
                let denom = Double(insidePick ? insideWidth : outsideWidth)
                if denom <= 0.000_001 { return 1.0 }
                let a = min(1.0, max(0.0, 1.0 - Double(abs(signedDist)) / denom))
                let pp = insidePick ? cfg.fuzzDistancePowerInside : cfg.fuzzDistancePowerOutside
                return pow(a, max(0.10, pp))
            }()

            var alpha = baseSpeckAlpha * (0.25 + 0.75 * sSeg) * distWeight
            if insidePick { alpha *= cfg.fuzzInsideOpacityFactor }

            alpha = max(0.0, min(1.0, alpha))

            // Bin by alpha.
            let bin = min(bins - 1, max(0, Int(floor(alpha * Double(bins)))))
            let rect = CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)

            if insidePick {
                insideBins[bin].addEllipse(in: rect)
            } else {
                outsideBins[bin].addEllipse(in: rect)
            }
        }

        // Draw: outside first (plusLighter), then inside (clipped).
        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            for b in 0..<bins {
                let op = (Double(b + 1) / Double(bins)) * cfg.fuzzMaxOpacity * 0.95
                if op <= 0.0001 { continue }
                layer.fill(outsideBins[b], with: .color(glowColor.opacity(op)))
            }
        }

        context.drawLayer { layer in
            layer.clip(to: corePath)
            layer.blendMode = .plusLighter
            for b in 0..<bins {
                let op = (Double(b + 1) / Double(bins)) * cfg.fuzzMaxOpacity * cfg.fuzzInsideOpacityFactor * 0.80
                if op <= 0.0001 { continue }
                layer.fill(insideBins[b], with: .color(cfg.fuzzColor.opacity(op)))
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

        let innerW = max(0.5, cfg.rimInnerWidthPixels / scale)
        let outerW = max(innerW, cfg.rimOuterWidthPixels / scale)

        if cfg.rimOuterOpacity > 0.0001 {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.addFilter(.blur(radius: max(0.0, outerW * 0.35)))
                layer.stroke(surfacePath, with: .color(cfg.rimColor.opacity(cfg.rimOuterOpacity)), lineWidth: outerW)
            }
        }

        if cfg.rimInnerOpacity > 0.0001 {
            context.stroke(surfacePath, with: .color(cfg.rimColor.opacity(cfg.rimInnerOpacity)), lineWidth: innerW)
        }
    }

    static func drawGlints(
        in context: inout GraphicsContext,
        surfacePoints: [CGPoint],
        cfg: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let sigma = max(0.5, cfg.glintSigmaPixels / scale)
        let offsetY = cfg.glintVerticalOffsetPixels / scale

        let seed = RainSurfacePRNG.combine(cfg.noiseSeed, 0xA11CE5A10DDC0FFE)
        var prng = RainSurfacePRNG(seed: seed)

        let n = max(1, cfg.glintCount)
        guard !surfacePoints.isEmpty else { return }

        for _ in 0..<n {
            let i = Int(prng.nextFloat01() * Double(max(1, surfacePoints.count - 1)))
            let p = surfacePoints[max(0, min(surfacePoints.count - 1, i))]

            let dx = CGFloat(prng.nextSignedFloat()) * sigma * 1.25
            let dy = CGFloat(prng.nextSignedFloat()) * sigma * 0.65

            let rect = CGRect(
                x: p.x + dx - sigma,
                y: p.y + dy + offsetY - sigma,
                width: sigma * 2,
                height: sigma * 2
            )

            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.addFilter(.blur(radius: sigma * 0.65))
                var circle = Path()
                circle.addEllipse(in: rect)
                layer.fill(circle, with: .color(Color.white.opacity(cfg.glintMaxOpacity)))
            }
        }
    }
}
