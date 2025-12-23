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

    // Baseline
    var baselineColor: Color
    var baselineOpacity: Double
    var baselineLineWidth: CGFloat

    // Core ribbon fill
    var fillBottomColor: Color
    var fillTopColor: Color
    var fillBottomOpacity: Double
    var fillTopOpacity: Double

    // Top-edge diffusion (inward)
    //
    // Rendering is split into:
    // - Body fill: baseline -> (top contour + diffusionRadius)
    // - Diffusion cap: top contour -> body contour, built from stacked alpha bands
    //
    // diffusionMaxAlpha:
    // - Alpha multiplier at the inner boundary of the cap (typically 1.0)
    //
    // diffusionUncertaintyAlphaFloor:
    // - Alpha multiplier at the very top edge of the cap.
    //   Lower values make the edge more “misty”; higher values make it more “present”.
    var diffusionMinRadiusPoints: CGFloat
    var diffusionMaxRadiusPoints: CGFloat
    var diffusionMinRadiusFractionOfHeight: CGFloat
    var diffusionMaxRadiusFractionOfHeight: CGFloat
    var diffusionLayers: Int
    var diffusionMaxAlpha: Double
    var diffusionFalloffPower: Double
    var diffusionUncertaintyAlphaFloor: Double

    // Optional tight glow (inward, subtle; never a stroke)
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
                context.fill(
                    bg,
                    with: .color(configuration.backgroundColor.opacity(configuration.backgroundOpacity))
                )
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

                let u = 1.0 - c
                var r = minRadius + (maxRadius - minRadius) * CGFloat(u)

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

            // Light smoothing inside each wet segment to remove hard “walls” at dry->wet boundaries.
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

            // Vertical base gradient used by body and cap.
            func scaledFillShading(multiplier: Double) -> GraphicsContext.Shading {
                let m = max(0.0, multiplier)
                let g = Gradient(stops: [
                    .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity * m), location: 0.0),
                    .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity * m), location: 1.0),
                ])
                return .linearGradient(
                    g,
                    startPoint: CGPoint(x: plotRect.midX, y: baselineY),
                    endPoint: CGPoint(x: plotRect.midX, y: rect.minY)
                )
            }

            let bodyShading = scaledFillShading(multiplier: 1.0)

            for range in wetRanges {
                let segment = Self.buildSegmentTopPoints(
                    range: range,
                    plotRect: plotRect,
                    baselineY: baselineY,
                    stepX: stepX,
                    heights: heights,
                    radii: radii
                )

                let topPoints = segment.topPoints
                let perPointRadius = segment.radii
                let segmentMaxRadius = segment.maxRadius

                guard topPoints.count >= 2 else { continue }

                // Body contour (top pushed downward by diffusion radius).
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

                // Layer 3: Diffusion cap (stacked alpha bands)
                if segmentMaxRadius > 0, configuration.diffusionLayers > 0, configuration.diffusionMaxAlpha > 0 {
                    let layers = max(1, configuration.diffusionLayers)

                    let edgeFloor = max(0.0, min(configuration.diffusionUncertaintyAlphaFloor, configuration.diffusionMaxAlpha))
                    let maxA = max(edgeFloor, configuration.diffusionMaxAlpha)

                    for k in 0..<layers {
                        let t0 = CGFloat(k) / CGFloat(layers)
                        let t1 = CGFloat(k + 1) / CGFloat(layers)
                        let tMid = (t0 + t1) * 0.5

                        // Alpha ramps from edgeFloor at the top edge (t=0)
                        // to maxA at the inner boundary (t=1).
                        let ramp = pow(Double(tMid), configuration.diffusionFalloffPower)
                        let bandMultiplier = edgeFloor + (maxA - edgeFloor) * ramp

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

                        context.fill(strip, with: scaledFillShading(multiplier: bandMultiplier))
                    }
                }

                // Layer 4: Tight inward glow near ridge (optional; never a stroke)
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

                            let sampleIndex: Int
                            if j <= segment.firstSamplePointIndex {
                                sampleIndex = range.lowerBound
                            } else if j >= segment.lastSamplePointIndex {
                                sampleIndex = max(range.lowerBound, range.upperBound - 1)
                            } else {
                                let candidate = range.lowerBound + (j - (segment.firstSamplePointIndex + 1))
                                sampleIndex = max(range.lowerBound, min(range.upperBound - 1, candidate))
                            }

                            let c = certainty01[sampleIndex]
                            let certaintyBoost = pow(max(0.0, min(1.0, c)), configuration.glowCertaintyPower)

                            let h = heights[sampleIndex]
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

                            let sampleIndex: Int
                            if j <= segment.firstSamplePointIndex {
                                sampleIndex = range.lowerBound
                            } else if j >= segment.lastSamplePointIndex {
                                sampleIndex = max(range.lowerBound, range.upperBound - 1)
                            } else {
                                let candidate = range.lowerBound + (j - (segment.firstSamplePointIndex + 1))
                                sampleIndex = max(range.lowerBound, min(range.upperBound - 1, candidate))
                            }

                            let c = certainty01[sampleIndex]
                            let certaintyBoost = pow(max(0.0, min(1.0, c)), configuration.glowCertaintyPower)
                            let a = max(0, min(1.0, alphaBase * certaintyBoost))

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

        // Indices in the points array used to map back to samples for glow modulation.
        // These are conservative and deliberately simple.
        var firstSamplePointIndex: Int
        var lastSamplePointIndex: Int
    }

    static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
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
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        radii: [CGFloat]
    ) -> SegmentPoints {
        let first = range.lowerBound
        let last = max(first, range.upperBound - 1)

        let startEdgeX = plotRect.minX + CGFloat(first) * stepX
        let endEdgeX = plotRect.minX + CGFloat(last + 1) * stepX

        let firstSampleX = plotRect.minX + (CGFloat(first) + 0.5) * stepX
        let lastSampleX = plotRect.minX + (CGFloat(last) + 0.5) * stepX

        let firstH = heights[first]
        let lastH = heights[last]
        let firstR = radii[first]
        let lastR = radii[last]

        // Boundary easing reduces vertical “walls” at dry->wet boundaries.
        let rampXFrac: CGFloat = 0.28
        let rampHFrac: CGFloat = 0.35
        let rampRFrac: CGFloat = 0.40

        let rampInX = min(firstSampleX, startEdgeX + stepX * rampXFrac)
        let rampOutX = max(lastSampleX, endEdgeX - stepX * rampXFrac)

        let rampInY = baselineY - firstH * rampHFrac
        let rampOutY = baselineY - lastH * rampHFrac

        var points: [CGPoint] = []
        var perPointRadius: [CGFloat] = []
        points.reserveCapacity(range.count + 4)
        perPointRadius.reserveCapacity(range.count + 4)

        // Start baseline cap
        points.append(CGPoint(x: startEdgeX, y: baselineY))
        perPointRadius.append(0)

        // Start ramp (only if there is room)
        if rampInX > startEdgeX + 0.5 {
            points.append(CGPoint(x: rampInX, y: rampInY))
            perPointRadius.append(firstR * rampRFrac)
        }

        // Samples
        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            points.append(CGPoint(x: x, y: y))
            perPointRadius.append(radii[i])
        }

        // End ramp (only if there is room)
        if endEdgeX > rampOutX + 0.5 {
            points.append(CGPoint(x: rampOutX, y: rampOutY))
            perPointRadius.append(lastR * rampRFrac)
        }

        // End baseline cap
        points.append(CGPoint(x: endEdgeX, y: baselineY))
        perPointRadius.append(0)

        let maxR = perPointRadius.max() ?? 0

        // Sample point indices in the points array:
        // points layout:
        // 0 = baseline cap
        // 1 = optional ramp
        // next = samples...
        // last-1 = optional ramp
        // last = baseline cap
        //
        // first sample index:
        let firstSamplePointIndex = (points.count >= (range.count + 2)) ? (points.count - (range.count + 1)) : 1
        let lastSamplePointIndex = max(firstSamplePointIndex, firstSamplePointIndex + range.count - 1)

        return SegmentPoints(
            topPoints: points,
            radii: perPointRadius,
            maxRadius: maxR,
            firstSamplePointIndex: firstSamplePointIndex,
            lastSamplePointIndex: lastSamplePointIndex
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
        var base = Path()
        base.move(to: CGPoint(x: plotRect.minX, y: baselineY))
        base.addLine(to: CGPoint(x: plotRect.maxX, y: baselineY))

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
