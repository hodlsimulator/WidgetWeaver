//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Programmatic “forecast surface” renderer:
//  - Single filled ribbon above a subtle baseline
//  - Uncertainty shown as an inward, soft diffusion at the top edge
//  - Deterministic (no randomness / no animation)
//

import Foundation
import SwiftUI

// MARK: - Configuration

struct RainForecastSurfaceConfiguration: Hashable {
    // Background
    var backgroundColor: Color
    var backgroundOpacity: Double

    // Data mapping
    var intensityCap: Double
    var wetThreshold: Double
    var intensityEasingPower: Double
    var minVisibleHeightFraction: CGFloat

    // Layout
    var baselineYFraction: CGFloat
    var edgeInsetFraction: CGFloat

    // Baseline (felt, not seen)
    var baselineColor: Color
    var baselineOpacity: Double
    var baselineLineWidth: CGFloat
    var baselineInsetPoints: CGFloat
    var baselineSoftWidthMultiplier: CGFloat
    var baselineSoftOpacityMultiplier: Double

    // Core ribbon fill
    var fillBottomColor: Color
    var fillTopColor: Color
    var fillBottomOpacity: Double
    var fillTopOpacity: Double

    // Boundary modifiers (rendering only)
    var startEaseMinutes: Int
    var endFadeMinutes: Int
    var endFadeFloor: Double

    // Top-edge diffusion (inward)
    //
    // Rendering is split into:
    // - Body fill: baseline -> (top contour + diffusionRadius)
    // - Diffusion cap: top contour -> body contour, built from stacked bands
    //
    // The cap band opacity is controlled as:
    // finalMultiplier = 1 - (1 - baseBandMultiplier) * diffusionEffect
    //
    // where baseBandMultiplier ramps from diffusionEdgeAlphaFloor -> diffusionMaxAlpha.
    // diffusionEffect varies by uncertainty and boundary fades (startEase/endFade).
    var diffusionMinRadiusPoints: CGFloat
    var diffusionMaxRadiusPoints: CGFloat
    var diffusionMinRadiusFractionOfHeight: CGFloat
    var diffusionMaxRadiusFractionOfHeight: CGFloat
    var diffusionLayers: Int
    var diffusionMaxAlpha: Double
    var diffusionBandFalloffPower: Double
    var diffusionEdgeAlphaFloor: Double

    // Uncertainty mapping
    var diffusionRadiusUncertaintyPower: Double       // e.g. 1.4
    var diffusionStrengthUncertaintyPower: Double     // e.g. 1.2
    var diffusionStrengthMinMultiplier: Double        // e.g. 0.25
    var diffusionStrengthMaxMultiplier: Double        // e.g. 1.0

    // Optional tight glow (inward, never a stroke)
    var glowEnabled: Bool
    var glowColor: Color
    var glowMaxRadiusPoints: CGFloat
    var glowMaxRadiusFractionOfHeight: CGFloat
    var glowLayers: Int
    var glowMaxAlpha: Double
    var glowFalloffPower: Double
    var glowCertaintyPower: Double
}

// MARK: - View

struct RainForecastSurfaceView: View {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration

    @Environment(\.displayScale) private var displayScale

    init(
        intensities: [Double],
        certainties: [Double],
        configuration: RainForecastSurfaceConfiguration
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
    }

    var body: some View {
        Canvas { context, size in
            let n = min(intensities.count, certainties.count)
            guard n > 0 else { return }

            let rect = CGRect(origin: .zero, size: size)

            // Layer 0: Background
            if configuration.backgroundOpacity > 0 {
                var bg = Path()
                bg.addRect(rect)
                context.fill(bg, with: .color(configuration.backgroundColor.opacity(configuration.backgroundOpacity)))
            }

            let insetX = max(0, rect.width * configuration.edgeInsetFraction)
            let plotRect = rect.insetBy(dx: insetX, dy: 0)

            guard plotRect.width > 0, plotRect.height > 0 else { return }

            var baselineY = rect.minY + rect.height * configuration.baselineYFraction
            baselineY = Self.alignToPixelCenter(baselineY, displayScale: displayScale)

            let maxHeight = max(0, baselineY - rect.minY)
            let minVisibleHeight = max(0, maxHeight * configuration.minVisibleHeightFraction)

            let intensityCap = max(configuration.intensityCap, 0.000_001)
            let stepX = plotRect.width / CGFloat(n)

            // Boundary fades (rendering only)
            let edgeFactors = Self.edgeFactors(
                sampleCount: n,
                startEaseMinutes: configuration.startEaseMinutes,
                endFadeMinutes: configuration.endFadeMinutes,
                endFadeFloor: configuration.endFadeFloor
            )

            // Diffusion radius range (points), scaled by size but clamped.
            let minRadius = max(configuration.diffusionMinRadiusPoints, rect.height * configuration.diffusionMinRadiusFractionOfHeight)
            let maxRadius = min(configuration.diffusionMaxRadiusPoints, rect.height * configuration.diffusionMaxRadiusFractionOfHeight)

            var wetMask = [Bool](repeating: false, count: n)
            var heights = [CGFloat](repeating: 0, count: n)
            var radii = [CGFloat](repeating: 0, count: n)
            var certainty01 = [Double](repeating: 0, count: n)

            for i in 0..<n {
                let intensity = max(0.0, intensities[i])
                let c = Self.clamp01(certainties[i])
                certainty01[i] = c

                let isWet = intensity >= configuration.wetThreshold
                wetMask[i] = isWet

                guard isWet else {
                    heights[i] = 0
                    radii[i] = 0
                    continue
                }

                let frac = min(intensity / intensityCap, 1.0)
                let eased = pow(frac, configuration.intensityEasingPower)

                var h = CGFloat(eased) * maxHeight
                h = max(h, minVisibleHeight)
                heights[i] = h

                // Radius mapping: pow(u, 1.4)
                let u = 1.0 - c
                let uRadius = pow(u, configuration.diffusionRadiusUncertaintyPower)
                var r = minRadius + (maxRadius - minRadius) * CGFloat(uRadius)

                r = min(r, h * 0.85)
                radii[i] = max(0, r)
            }

            let wetRanges = Self.wetRanges(from: wetMask)
            guard !wetRanges.isEmpty else {
                Self.drawBaseline(
                    in: &context,
                    plotRect: plotRect,
                    baselineY: baselineY,
                    configuration: configuration
                )
                return
            }

            // Light smoothing (keeps shape calm; deterministic)
            do {
                var smoothedHeights = heights
                var smoothedRadii = radii

                for range in wetRanges {
                    guard range.count >= 2 else { continue }

                    for i in range {
                        let i0 = max(range.lowerBound, i - 1)
                        let i1 = i
                        let i2 = min(range.upperBound - 1, i + 1)

                        let h0 = heights[i0]
                        let h1 = heights[i1]
                        let h2 = heights[i2]
                        smoothedHeights[i] = h0 * 0.25 + h1 * 0.50 + h2 * 0.25

                        let r0 = radii[i0]
                        let r1 = radii[i1]
                        let r2 = radii[i2]
                        smoothedRadii[i] = r0 * 0.25 + r1 * 0.50 + r2 * 0.25
                    }
                }

                heights = smoothedHeights
                radii = smoothedRadii

                for i in 0..<n {
                    radii[i] = min(radii[i], heights[i] * 0.85)
                }
            }

            // Vertical base gradient used by body + cap
            func baseFillShading() -> GraphicsContext.Shading {
                let g = Gradient(stops: [
                    .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
                    .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0),
                ])
                return .linearGradient(
                    g,
                    startPoint: CGPoint(x: plotRect.midX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.midX, y: rect.minY)
                )
            }

            let bodyShading = baseFillShading()

            for range in wetRanges {
                let segment = Self.buildSegmentTopPoints(
                    range: range,
                    sampleCount: n,
                    plotRect: plotRect,
                    baselineY: baselineY,
                    stepX: stepX,
                    heights: heights,
                    radii: radii
                )

                let topPoints = segment.topPoints
                let perPointRadius = segment.radii
                let sampleIndexForPoint = segment.sampleIndexForPoint
                let segmentMaxRadius = segment.maxRadius

                guard topPoints.count >= 2 else { continue }

                // BODY: top pushed downward by diffusion radius
                var bodyTopPoints = topPoints
                if segmentMaxRadius > 0 {
                    for j in 0..<bodyTopPoints.count {
                        let p = topPoints[j]
                        let r = perPointRadius[j]
                        bodyTopPoints[j] = CGPoint(x: p.x, y: min(baselineY, p.y + r))
                    }
                }

                // Layer 2: Body fill
                do {
                    var bodyPath = Path()
                    Self.addSmoothQuadSegments(&bodyPath, points: bodyTopPoints, moveToFirst: true)
                    bodyPath.addLine(to: bodyTopPoints.first ?? CGPoint(x: plotRect.minX, y: baselineY))
                    bodyPath.closeSubpath()
                    context.fill(bodyPath, with: bodyShading)
                }

                // Layer 3: Diffusion cap (stacked bands, per-x fade only affects diffusion)
                if segmentMaxRadius > 0, configuration.diffusionLayers > 0 {
                    let layers = max(1, configuration.diffusionLayers)

                    // Edge alpha floor at the top-most edge (u-driven strength modulates how much of this transparency is applied).
                    let edgeFloor = max(0.0, min(1.0, configuration.diffusionEdgeAlphaFloor))

                    // Inner boundary alpha should be 1.0 to avoid a seam against the body.
                    // diffusionMaxAlpha is still honoured, but clamped to [0,1].
                    let maxA = max(0.0, min(1.0, configuration.diffusionMaxAlpha))

                    for k in 0..<layers {
                        let t0 = CGFloat(k) / CGFloat(layers)
                        let t1 = CGFloat(k + 1) / CGFloat(layers)
                        let tMid = (t0 + t1) * 0.5

                        // 0..1 ramp from top edge to inner boundary
                        let ramp = pow(Double(tMid), configuration.diffusionBandFalloffPower)
                        let baseBand = edgeFloor + (maxA - edgeFloor) * ramp

                        var contourA: [CGPoint] = []
                        var contourB: [CGPoint] = []
                        contourA.reserveCapacity(topPoints.count)
                        contourB.reserveCapacity(topPoints.count)

                        for j in 0..<topPoints.count {
                            let p = topPoints[j]
                            let r = perPointRadius[j]
                            contourA.append(CGPoint(x: p.x, y: min(baselineY, p.y + r * t0)))
                            contourB.append(CGPoint(x: p.x, y: min(baselineY, p.y + r * t1)))
                        }

                        var strip = Path()
                        Self.addSmoothQuadSegments(&strip, points: contourA, moveToFirst: true)
                        strip.addLine(to: contourB.last ?? contourA.last ?? CGPoint(x: plotRect.maxX, y: baselineY))
                        Self.addSmoothQuadSegments(&strip, points: contourB.reversed(), moveToFirst: false)
                        strip.closeSubpath()

                        // Per-x diffusion effect based on uncertainty + boundary modifiers:
                        // diffusionEffect = lerp(0.25, 1.0, pow(u, 1.2)) * startEase * endFade
                        var maskStops: [Gradient.Stop] = []
                        maskStops.reserveCapacity(topPoints.count)

                        for j in 0..<topPoints.count {
                            let p = topPoints[j]
                            let loc = Self.safeLocation01(x: p.x, minX: plotRect.minX, maxX: plotRect.maxX)

                            let si = sampleIndexForPoint[j]
                            let c = certainty01[si]
                            let u = 1.0 - c

                            let uStrength = pow(u, configuration.diffusionStrengthUncertaintyPower)
                            let strength = Self.lerp(
                                configuration.diffusionStrengthMinMultiplier,
                                configuration.diffusionStrengthMaxMultiplier,
                                uStrength
                            )

                            let edge = edgeFactors[si]
                            let diffusionEffect = max(0.0, min(1.0, strength * edge))

                            // Rendering-only fade: reduces the amount of transparency, not the geometry.
                            // finalMultiplier approaches 1.0 as diffusionEffect -> 0.
                            let finalMultiplier = 1.0 - (1.0 - baseBand) * diffusionEffect

                            maskStops.append(.init(color: Color.white.opacity(finalMultiplier), location: loc))
                        }

                        let maskGradient = Gradient(stops: maskStops)
                        let maskShading = GraphicsContext.Shading.linearGradient(
                            maskGradient,
                            startPoint: CGPoint(x: plotRect.minX, y: 0),
                            endPoint: CGPoint(x: plotRect.maxX, y: 0)
                        )

                        // Preserve the vertical shading while applying per-x alpha via destinationIn.
                        context.drawLayer { layer in
                            layer.fill(strip, with: bodyShading)
                            layer.blendMode = .destinationIn
                            layer.fill(strip, with: maskShading)
                        }
                    }
                }

                // Layer 4: Tight inward glow (per-x fades applied)
                if configuration.glowEnabled, configuration.glowMaxAlpha > 0 {
                    let glowRadiusMax = min(configuration.glowMaxRadiusPoints, rect.height * configuration.glowMaxRadiusFractionOfHeight)
                    let glowLayers = max(1, configuration.glowLayers)

                    for k in 0..<glowLayers {
                        let t0 = CGFloat(k) / CGFloat(glowLayers)
                        let t1 = CGFloat(k + 1) / CGFloat(glowLayers)
                        let tMid = (t0 + t1) * 0.5

                        let falloff = pow(1.0 - Double(tMid), configuration.glowFalloffPower)
                        let alphaBase = configuration.glowMaxAlpha * falloff

                        var contourA: [CGPoint] = []
                        var contourB: [CGPoint] = []
                        contourA.reserveCapacity(topPoints.count)
                        contourB.reserveCapacity(topPoints.count)

                        for j in 0..<topPoints.count {
                            let p = topPoints[j]
                            let si = sampleIndexForPoint[j]

                            let c = certainty01[si]
                            let certaintyBoost = pow(max(0.0, min(1.0, c)), configuration.glowCertaintyPower)

                            let h = heights[si]
                            let rMaxByHeight = min(glowRadiusMax, h * 0.75)
                            let r = max(0, rMaxByHeight * CGFloat(certaintyBoost))

                            contourA.append(CGPoint(x: p.x, y: min(baselineY, p.y + r * t0)))
                            contourB.append(CGPoint(x: p.x, y: min(baselineY, p.y + r * t1)))
                        }

                        var strip = Path()
                        Self.addSmoothQuadSegments(&strip, points: contourA, moveToFirst: true)
                        strip.addLine(to: contourB.last ?? contourA.last ?? CGPoint(x: plotRect.maxX, y: baselineY))
                        Self.addSmoothQuadSegments(&strip, points: contourB.reversed(), moveToFirst: false)
                        strip.closeSubpath()

                        var stops: [Gradient.Stop] = []
                        stops.reserveCapacity(topPoints.count)

                        for j in 0..<topPoints.count {
                            let p = topPoints[j]
                            let loc = Self.safeLocation01(x: p.x, minX: plotRect.minX, maxX: plotRect.maxX)

                            let si = sampleIndexForPoint[j]
                            let c = certainty01[si]
                            let certaintyBoost = pow(max(0.0, min(1.0, c)), configuration.glowCertaintyPower)

                            // Boundary modifiers (rendering only)
                            let edge = edgeFactors[si]

                            let a = max(0, min(1.0, alphaBase * certaintyBoost * edge))
                            stops.append(.init(color: configuration.glowColor.opacity(a), location: loc))
                        }

                        let grad = Gradient(stops: stops)
                        let shading = GraphicsContext.Shading.linearGradient(
                            grad,
                            startPoint: CGPoint(x: plotRect.minX, y: 0),
                            endPoint: CGPoint(x: plotRect.maxX, y: 0)
                        )

                        context.fill(strip, with: shading)
                    }
                }
            }

            // Layer 1: Baseline (on top)
            Self.drawBaseline(
                in: &context,
                plotRect: plotRect,
                baselineY: baselineY,
                configuration: configuration
            )
        }
    }
}

// MARK: - Helpers

private extension RainForecastSurfaceView {

    struct SegmentPoints {
        var topPoints: [CGPoint]
        var radii: [CGFloat]
        var maxRadius: CGFloat
        var sampleIndexForPoint: [Int]
    }

    static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let tt = max(0.0, min(1.0, t))
        return a + (b - a) * tt
    }

    static func smoothstep(_ u: Double) -> Double {
        let x = max(0.0, min(1.0, u))
        return x * x * (3.0 - 2.0 * x)
    }

    static func edgeFactors(sampleCount: Int, startEaseMinutes: Int, endFadeMinutes: Int, endFadeFloor: Double) -> [Double] {
        guard sampleCount > 0 else { return [] }
        if sampleCount == 1 { return [1.0] }

        let n = sampleCount
        let denom = Double(n - 1)

        let floorClamped = max(0.0, min(1.0, endFadeFloor))

        let startT1: Double
        if startEaseMinutes <= 1 {
            startT1 = 0.0
        } else {
            startT1 = Double(startEaseMinutes - 1) / denom
        }

        let fadeStartIndex = max(0, n - max(0, endFadeMinutes))
        let endT0 = Double(fadeStartIndex) / denom

        var out: [Double] = []
        out.reserveCapacity(n)

        for i in 0..<n {
            let t = Double(i) / denom

            let startEase: Double
            if startEaseMinutes <= 1 {
                startEase = 1.0
            } else if t >= startT1 {
                startEase = 1.0
            } else {
                let u = t / max(0.000_001, startT1)
                startEase = smoothstep(u)
            }

            let endFade: Double
            if endFadeMinutes <= 0 {
                endFade = 1.0
            } else if t <= endT0 {
                endFade = 1.0
            } else {
                let u = (t - endT0) / max(0.000_001, (1.0 - endT0))
                let s = smoothstep(u)
                endFade = 1.0 - s
            }

            let endF = max(endFade, floorClamped)
            out.append(startEase * endF)
        }

        return out
    }

    static func wetRanges(from mask: [Bool]) -> [Range<Int>] {
        guard !mask.isEmpty else { return [] }
        var ranges: [Range<Int>] = []
        ranges.reserveCapacity(4)

        var start: Int? = nil
        for i in 0..<mask.count {
            if mask[i] {
                if start == nil { start = i }
            } else if let s = start {
                ranges.append(s..<i)
                start = nil
            }
        }
        if let s = start {
            ranges.append(s..<mask.count)
        }
        return ranges
    }

    static func buildSegmentTopPoints(
        range: Range<Int>,
        sampleCount: Int,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        radii: [CGFloat]
    ) -> SegmentPoints {
        let first = range.lowerBound
        let last = max(first, range.upperBound - 1)

        let touchesLeftEdge = (first == 0)
        let touchesRightEdge = (range.upperBound == sampleCount)

        let startEdgeX = plotRect.minX + CGFloat(first) * stepX
        let endEdgeX = plotRect.minX + CGFloat(last + 1) * stepX

        // Interior-only easing at wet/dry boundaries (not applied at Now or 60m edges)
        let rampXFrac: CGFloat = 0.28
        let rampHFrac: CGFloat = 0.35
        let rampRFrac: CGFloat = 0.40

        let firstSampleX = plotRect.minX + (CGFloat(first) + 0.5) * stepX
        let lastSampleX = plotRect.minX + (CGFloat(last) + 0.5) * stepX

        let firstH = heights[first]
        let lastH = heights[last]
        let firstR = radii[first]
        let lastR = radii[last]

        let rampInX = min(firstSampleX, startEdgeX + stepX * rampXFrac)
        let rampOutX = max(lastSampleX, endEdgeX - stepX * rampXFrac)

        let rampInY = baselineY - firstH * rampHFrac
        let rampOutY = baselineY - lastH * rampHFrac

        var points: [CGPoint] = []
        var perPointRadius: [CGFloat] = []
        var sampleMap: [Int] = []

        points.reserveCapacity(range.count + 4)
        perPointRadius.reserveCapacity(range.count + 4)
        sampleMap.reserveCapacity(range.count + 4)

        // Start baseline cap
        points.append(CGPoint(x: startEdgeX, y: baselineY))
        perPointRadius.append(0)
        sampleMap.append(first)

        // Start interior ramp (only if not at Now edge)
        if !touchesLeftEdge, rampInX > startEdgeX + 0.5 {
            points.append(CGPoint(x: rampInX, y: rampInY))
            perPointRadius.append(firstR * rampRFrac)
            sampleMap.append(first)
        }

        // Samples
        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            points.append(CGPoint(x: x, y: y))
            perPointRadius.append(radii[i])
            sampleMap.append(i)
        }

        // End interior ramp (only if not at 60m edge)
        if !touchesRightEdge, endEdgeX > rampOutX + 0.5 {
            points.append(CGPoint(x: rampOutX, y: rampOutY))
            perPointRadius.append(lastR * rampRFrac)
            sampleMap.append(last)
        }

        // End baseline cap
        points.append(CGPoint(x: endEdgeX, y: baselineY))
        perPointRadius.append(0)
        sampleMap.append(last)

        let maxR = perPointRadius.max() ?? 0

        return SegmentPoints(
            topPoints: points,
            radii: perPointRadius,
            maxRadius: maxR,
            sampleIndexForPoint: sampleMap
        )
    }

    static func safeLocation01(x: CGFloat, minX: CGFloat, maxX: CGFloat) -> Double {
        let denom = max(0.000_001, maxX - minX)
        let t = (x - minX) / denom
        return Double(max(0, min(1, t)))
    }

    static func addSmoothQuadSegments(_ path: inout Path, points: [CGPoint], moveToFirst: Bool) {
        guard points.count >= 2 else { return }

        if moveToFirst {
            path.move(to: points[0])
        }

        if points.count == 2 {
            path.addLine(to: points[1])
            return
        }

        for i in 1..<(points.count - 1) {
            let current = points[i]
            let next = points[i + 1]
            let mid = CGPoint(x: (current.x + next.x) * 0.5, y: (current.y + next.y) * 0.5)
            path.addQuadCurve(to: mid, control: current)
        }

        path.addQuadCurve(to: points[points.count - 1], control: points[points.count - 2])
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        plotRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration
    ) {
        let inset = max(0, configuration.baselineInsetPoints)

        let x0 = plotRect.minX + inset
        let x1 = plotRect.maxX - inset
        guard x1 > x0 else { return }

        var base = Path()
        base.move(to: CGPoint(x: x0, y: baselineY))
        base.addLine(to: CGPoint(x: x1, y: baselineY))

        // Soft pass (atmospheric)
        if configuration.baselineSoftOpacityMultiplier > 0, configuration.baselineSoftWidthMultiplier > 1 {
            let softWidth = max(configuration.baselineLineWidth, configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier)
            let softOpacity = max(0.0, min(1.0, configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier))
            let softStyle = StrokeStyle(lineWidth: softWidth, lineCap: .round)
            context.stroke(
                base,
                with: .color(configuration.baselineColor.opacity(softOpacity)),
                style: softStyle
            )
        }

        // Crisp 1px pass
        let stroke = StrokeStyle(lineWidth: configuration.baselineLineWidth, lineCap: .round)
        context.stroke(
            base,
            with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)),
            style: stroke
        )
    }

    static func alignToPixelCenter(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        guard displayScale > 0 else { return value }
        return (floor(value * displayScale) + 0.5) / displayScale
    }
}
