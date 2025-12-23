//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Forecast surface renderer (WidgetKit-safe):
//  - One filled ribbon above a subtle baseline
//  - Uncertainty shown as inward diffusion near the top edge (no outline, no second band)
//  - Stronger left start-ease + right end-fade applied ONLY to diffusion/glow (not geometry)
//  - Intensity gating to suppress fuzz in near-drizzle without crushing the effect
//  - Deterministic micro-jitter (optional) to break contour banding without flicker
//

import Foundation
import SwiftUI

// MARK: - Configuration

struct RainForecastSurfaceConfiguration: Hashable {
    // Background
    var backgroundColor: Color = .clear
    var backgroundOpacity: Double = 0.0

    // Data mapping
    var intensityCap: Double = 1.0
    var wetThreshold: Double = 0.0
    var intensityEasingPower: Double = 0.75
    var minVisibleHeightFraction: CGFloat = 0.03

    // Layout
    var baselineYFraction: CGFloat = 0.82
    var edgeInsetFraction: CGFloat = 0.0

    // Baseline (felt, not seen)
    var baselineColor: Color = .white
    var baselineOpacity: Double = 0.10
    var baselineLineWidth: CGFloat = 1.0
    var baselineInsetPoints: CGFloat = 6.0
    var baselineSoftWidthMultiplier: CGFloat = 2.6
    var baselineSoftOpacityMultiplier: Double = 0.30

    // Core ribbon fill
    var fillBottomColor: Color = .blue
    var fillTopColor: Color = .blue
    var fillBottomOpacity: Double = 0.18
    var fillTopOpacity: Double = 0.92

    // Boundary modifiers (rendering only)
    var startEaseMinutes: Int = 6
    var endFadeMinutes: Int = 10
    var endFadeFloor: Double = 0.0

    // Diffusion behaviour (top soft zone)
    var diffusionLayers: Int = 24
    var diffusionFalloffPower: Double = 2.2

    // Uncertainty -> diffusion radius
    var diffusionMinRadiusPoints: CGFloat = 1.5
    var diffusionMaxRadiusPoints: CGFloat = 16.0
    var diffusionMinRadiusFractionOfHeight: CGFloat = 0.03
    var diffusionMaxRadiusFractionOfHeight: CGFloat = 0.34
    var diffusionRadiusUncertaintyPower: Double = 1.35

    // Uncertainty -> diffusion strength
    // The max multiplier is treated as baseDiffusionAlpha (recommended ~0.52).
    var diffusionStrengthMaxMultiplier: Double = 0.52
    var diffusionStrengthMinMultiplier: Double = 0.30
    var diffusionStrengthUncertaintyPower: Double = 1.15

    // Intensity gating (keeps light rain calm)
    var diffusionDrizzleThreshold: Double = 0.10
    var diffusionLowIntensityGateMin: Double = 0.55

    // Light-rain restraint (summary intensity)
    var diffusionLightRainMeanThreshold: Double = 0.18
    var diffusionLightRainMaxRadiusScale: Double = 0.80
    var diffusionLightRainStrengthScale: Double = 0.85

    // Anti-banding
    // - stride reduces per-minute stop changes (helps vertical striping)
    // - jitter breaks contour edge alignment (keep tiny; deterministic)
    var diffusionStopStride: Int = 2
    var diffusionJitterAmplitudePoints: Double = 0.35   // ±0.175 px max

    // Glow (optional; inward concentration, never a stroke)
    var glowEnabled: Bool = true
    var glowColor: Color = .blue
    var glowLayers: Int = 6
    var glowMaxAlpha: Double = 0.18
    var glowFalloffPower: Double = 1.75
    var glowCertaintyPower: Double = 1.6
    var glowMaxRadiusPoints: CGFloat = 3.2
    var glowMaxRadiusFractionOfHeight: CGFloat = 0.075
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

            // Background
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

            // Boundary modifiers (rendering only)
            let edgeFactors = Self.edgeFactors(
                sampleCount: n,
                startEaseMinutes: configuration.startEaseMinutes,
                endFadeMinutes: configuration.endFadeMinutes,
                endFadeFloor: configuration.endFadeFloor
            )

            // Base arrays
            var wetMask = [Bool](repeating: false, count: n)
            var heights = [CGFloat](repeating: 0, count: n)
            var intensityNorm = [Double](repeating: 0, count: n)

            var certaintyRaw = [Double](repeating: 0, count: n)
            for i in 0..<n {
                certaintyRaw[i] = Self.clamp01(certainties[i])
            }

            // Smooth certainty for diffusion/glow ONLY (reduces vertical striping).
            let certaintySmooth = Self.smooth1D(values: certaintyRaw, passes: 2)

            for i in 0..<n {
                let intensity = max(0.0, intensities[i])
                let isWet = intensity >= configuration.wetThreshold
                wetMask[i] = isWet

                guard isWet else {
                    heights[i] = 0
                    intensityNorm[i] = 0
                    continue
                }

                let frac = min(intensity / intensityCap, 1.0)
                let eased = pow(frac, configuration.intensityEasingPower)
                intensityNorm[i] = eased

                var h = CGFloat(eased) * maxHeight
                h = max(h, minVisibleHeight)
                heights[i] = h
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

            // Light-rain restraint (summary intensity)
            let meanIntensityNorm: Double = intensityNorm.reduce(0.0, +) / Double(max(1, n))
            let lightRainRadiusScale: Double = (meanIntensityNorm < configuration.diffusionLightRainMeanThreshold) ? configuration.diffusionLightRainMaxRadiusScale : 1.0
            let lightRainStrengthScale: Double = (meanIntensityNorm < configuration.diffusionLightRainMeanThreshold) ? configuration.diffusionLightRainStrengthScale : 1.0

            // Diffusion radius bounds (scaled with size, clamped)
            let minRadius = max(configuration.diffusionMinRadiusPoints, rect.height * configuration.diffusionMinRadiusFractionOfHeight)
            let maxRadiusUnscaled = min(configuration.diffusionMaxRadiusPoints, rect.height * configuration.diffusionMaxRadiusFractionOfHeight)
            let maxRadius = max(minRadius, maxRadiusUnscaled * CGFloat(lightRainRadiusScale))

            // Per-sample diffusion + glow strengths (rendering only)
            var diffusionRadius = [CGFloat](repeating: 0, count: n)
            var diffusionStrength = [Double](repeating: 0, count: n)
            var glowStrength = [Double](repeating: 0, count: n)

            for i in 0..<n {
                guard wetMask[i] else {
                    diffusionRadius[i] = 0
                    diffusionStrength[i] = 0
                    glowStrength[i] = 0
                    continue
                }

                let c = certaintySmooth[i]
                let u = 1.0 - c
                let iNorm = max(0.0, min(1.0, intensityNorm[i]))

                // Intensity gate (do not crush fuzz to near-zero)
                let drizzleT = max(0.000_001, configuration.diffusionDrizzleThreshold)
                let diffusionGate: Double
                if iNorm <= drizzleT {
                    let g = iNorm / drizzleT
                    diffusionGate = Self.lerp(configuration.diffusionLowIntensityGateMin, 1.0, g)
                } else {
                    diffusionGate = 1.0
                }

                // Radius: lerp(min,max,pow(u,1.35)), then intensity gate
                let uR = pow(u, configuration.diffusionRadiusUncertaintyPower)
                var r = minRadius + (maxRadius - minRadius) * CGFloat(uR)
                r = r * CGFloat(diffusionGate)

                // Clamp diffusion inside ribbon
                r = min(r, heights[i] * 0.85)
                diffusionRadius[i] = max(0, r)

                // Strength: baseDiffusionAlpha * lerp(0.30,1,pow(u,1.15))
                let baseAlpha = max(0.0, min(1.0, configuration.diffusionStrengthMaxMultiplier * lightRainStrengthScale))
                let uS = pow(u, configuration.diffusionStrengthUncertaintyPower)
                let sTerm = Self.lerp(configuration.diffusionStrengthMinMultiplier, 1.0, uS)

                // Apply gating + boundary modifiers ONLY to diffusion/glow
                let boundary = edgeFactors[i]
                let s = baseAlpha * sTerm * diffusionGate * boundary
                diffusionStrength[i] = max(0.0, min(1.0, s))

                // Glow: glowBase * pow(c,1.6), then boundary modifiers
                if configuration.glowEnabled {
                    let gBase = max(0.0, min(1.0, configuration.glowMaxAlpha))
                    let gTerm = pow(max(0.0, min(1.0, c)), configuration.glowCertaintyPower)

                    // Keep glow calmer in drizzle without killing it
                    let glowGate = Self.lerp(0.65, 1.0, min(1.0, iNorm / drizzleT))
                    let g = gBase * gTerm * glowGate * boundary
                    glowStrength[i] = max(0.0, min(1.0, g))
                } else {
                    glowStrength[i] = 0
                }
            }

            // Additional smoothing for diffusionStrength ONLY (reduces column-like striping)
            diffusionStrength = Self.smooth1D(values: diffusionStrength, passes: 1, preserveZerosUsing: wetMask)

            // Core ribbon shading (matte vertical gradient)
            let bodyGradient = Gradient(stops: [
                .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
                .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0),
            ])
            let bodyShading = GraphicsContext.Shading.linearGradient(
                bodyGradient,
                startPoint: CGPoint(x: plotRect.midX, y: baselineY),
                endPoint: CGPoint(x: plotRect.midX, y: rect.minY)
            )

            // Draw segments
            for range in wetRanges {
                let segment = Self.buildSegmentPoints(
                    range: range,
                    plotRect: plotRect,
                    baselineY: baselineY,
                    stepX: stepX,
                    heights: heights
                )

                let topPoints = segment.topPoints
                let sampleIndexForPoint = segment.sampleIndexForPoint

                // Core ribbon (geometry)
                do {
                    var ribbon = Path()
                    Self.addSmoothQuadSegments(&ribbon, points: topPoints, moveToFirst: true)
                    ribbon.addLine(to: topPoints.first ?? CGPoint(x: plotRect.minX, y: baselineY))
                    ribbon.closeSubpath()
                    context.fill(ribbon, with: bodyShading)
                }

                // Diffusion (soft top zone): stacked contour strips inside the ribbon
                let K = max(14, configuration.diffusionLayers)
                if K >= 2 {
                    let pExp = max(1.2, configuration.diffusionFalloffPower)
                    let jitterAmp = max(0.0, configuration.diffusionJitterAmplitudePoints)

                    for k in 0..<(K - 1) {
                        let t0 = Double(k) / Double(K - 1)
                        let t1 = Double(k + 1) / Double(K - 1)
                        let tMid = 0.5 * (t0 + t1)

                        // Falloff strongest near the edge; soften immediate edge to avoid a hard "line"
                        // This keeps fuzz present but avoids reading as a stroke.
                        let edgeSoftIn = Self.smoothstep01(min(1.0, tMid / 0.10))
                        let falloff = pow(1.0 - tMid, pExp) * edgeSoftIn

                        var contourA: [CGPoint] = []
                        var contourB: [CGPoint] = []
                        contourA.reserveCapacity(topPoints.count)
                        contourB.reserveCapacity(topPoints.count)

                        for j in 0..<topPoints.count {
                            let p = topPoints[j]
                            let si = sampleIndexForPoint[j]
                            let r = Double(diffusionRadius[si])

                            if r <= 0.0 {
                                contourA.append(p)
                                contourB.append(p)
                                continue
                            }

                            let j0 = (Self.hash01(si * 131 + k * 911) - 0.5) * jitterAmp
                            let j1 = (Self.hash01(si * 131 + (k + 1) * 911) - 0.5) * jitterAmp

                            var o0 = r * t0 + j0
                            var o1 = r * t1 + j1
                            if o1 < o0 { o1 = o0 }

                            contourA.append(CGPoint(x: p.x, y: min(baselineY, p.y + o0)))
                            contourB.append(CGPoint(x: p.x, y: min(baselineY, p.y + o1)))
                        }

                        var strip = Path()
                        Self.addSmoothQuadSegments(&strip, points: contourA, moveToFirst: true)
                        strip.addLine(to: contourB.last ?? contourA.last ?? CGPoint(x: plotRect.maxX, y: baselineY))
                        Self.addSmoothQuadSegments(&strip, points: contourB.reversed(), moveToFirst: false)
                        strip.closeSubpath()

                        // Horizontal alpha variation (downsampled to reduce striping)
                        let stops = Self.buildStops(
                            points: topPoints,
                            sampleIndexForPoint: sampleIndexForPoint,
                            plotMinX: plotRect.minX,
                            plotMaxX: plotRect.maxX,
                            stride: max(1, configuration.diffusionStopStride)
                        ) { si in
                            let a = diffusionStrength[si] * falloff
                            return configuration.fillTopColor.opacity(max(0.0, min(1.0, a)))
                        }

                        if stops.count >= 2 {
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

                // Glow: tight inward concentration clipped inside the ribbon
                if configuration.glowEnabled, configuration.glowMaxAlpha > 0 {
                    let glowLayers = max(3, configuration.glowLayers)

                    let glowRadiusMaxUnscaled = min(configuration.glowMaxRadiusPoints, rect.height * configuration.glowMaxRadiusFractionOfHeight)
                    let glowRadiusMax = max(0.0, glowRadiusMaxUnscaled)

                    for k in 0..<(glowLayers - 1) {
                        let t0 = Double(k) / Double(glowLayers - 1)
                        let t1 = Double(k + 1) / Double(glowLayers - 1)
                        let tMid = 0.5 * (t0 + t1)

                        let falloff = pow(1.0 - tMid, max(1.0, configuration.glowFalloffPower))

                        var contourA: [CGPoint] = []
                        var contourB: [CGPoint] = []
                        contourA.reserveCapacity(topPoints.count)
                        contourB.reserveCapacity(topPoints.count)

                        for j in 0..<topPoints.count {
                            let p = topPoints[j]
                            let si = sampleIndexForPoint[j]
                            let h = Double(heights[si])

                            if h <= 0.0 {
                                contourA.append(p)
                                contourB.append(p)
                                continue
                            }

                            // Tight radius, clipped inside ribbon
                            let rMax = min(Double(glowRadiusMax), h * 0.75)
                            let r = max(0.0, rMax)

                            contourA.append(CGPoint(x: p.x, y: min(baselineY, p.y + r * t0)))
                            contourB.append(CGPoint(x: p.x, y: min(baselineY, p.y + r * t1)))
                        }

                        var strip = Path()
                        Self.addSmoothQuadSegments(&strip, points: contourA, moveToFirst: true)
                        strip.addLine(to: contourB.last ?? contourA.last ?? CGPoint(x: plotRect.maxX, y: baselineY))
                        Self.addSmoothQuadSegments(&strip, points: contourB.reversed(), moveToFirst: false)
                        strip.closeSubpath()

                        let stops = Self.buildStops(
                            points: topPoints,
                            sampleIndexForPoint: sampleIndexForPoint,
                            plotMinX: plotRect.minX,
                            plotMaxX: plotRect.maxX,
                            stride: 2
                        ) { si in
                            let a = glowStrength[si] * falloff
                            return configuration.glowColor.opacity(max(0.0, min(1.0, a)))
                        }

                        if stops.count >= 2 {
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
            }

            // Baseline on top
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
        var sampleIndexForPoint: [Int]
    }

    static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }

    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let tt = max(0.0, min(1.0, t))
        return a + (b - a) * tt
    }

    static func smoothstep01(_ u: Double) -> Double {
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
                startEase = smoothstep01(u)
            }

            let endFade: Double
            if endFadeMinutes <= 0 {
                endFade = 1.0
            } else if t <= endT0 {
                endFade = 1.0
            } else {
                let u = (t - endT0) / max(0.000_001, (1.0 - endT0))
                let s = smoothstep01(u)
                endFade = 1.0 - s
            }

            out.append(startEase * max(endFade, floorClamped))
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

    static func buildSegmentPoints(
        range: Range<Int>,
        plotRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat]
    ) -> SegmentPoints {
        let startEdgeX = plotRect.minX + CGFloat(range.lowerBound) * stepX
        let endEdgeX = plotRect.minX + CGFloat(range.upperBound) * stepX

        var points: [CGPoint] = []
        var sampleMap: [Int] = []

        points.reserveCapacity(range.count + 2)
        sampleMap.reserveCapacity(range.count + 2)

        // baseline cap
        points.append(CGPoint(x: startEdgeX, y: baselineY))
        sampleMap.append(range.lowerBound)

        for i in range {
            let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
            let y = baselineY - heights[i]
            points.append(CGPoint(x: x, y: y))
            sampleMap.append(i)
        }

        // baseline cap
        points.append(CGPoint(x: endEdgeX, y: baselineY))
        sampleMap.append(max(range.lowerBound, range.upperBound - 1))

        return SegmentPoints(topPoints: points, sampleIndexForPoint: sampleMap)
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

        // soft pass
        if configuration.baselineSoftOpacityMultiplier > 0, configuration.baselineSoftWidthMultiplier > 1 {
            let softWidth = max(configuration.baselineLineWidth, configuration.baselineLineWidth * configuration.baselineSoftWidthMultiplier)
            let softOpacity = max(0.0, min(1.0, configuration.baselineOpacity * configuration.baselineSoftOpacityMultiplier))
            let softStyle = StrokeStyle(lineWidth: softWidth, lineCap: .round)
            context.stroke(base, with: .color(configuration.baselineColor.opacity(softOpacity)), style: softStyle)
        }

        // crisp pass
        let stroke = StrokeStyle(lineWidth: configuration.baselineLineWidth, lineCap: .round)
        context.stroke(base, with: .color(configuration.baselineColor.opacity(configuration.baselineOpacity)), style: stroke)
    }

    static func alignToPixelCenter(_ value: CGFloat, displayScale: CGFloat) -> CGFloat {
        guard displayScale > 0 else { return value }
        return (floor(value * displayScale) + 0.5) / displayScale
    }

    static func safeLocation01(x: CGFloat, minX: CGFloat, maxX: CGFloat) -> Double {
        let denom = max(0.000_001, maxX - minX)
        let t = (x - minX) / denom
        return Double(max(0, min(1, t)))
    }

    static func buildStops(
        points: [CGPoint],
        sampleIndexForPoint: [Int],
        plotMinX: CGFloat,
        plotMaxX: CGFloat,
        stride: Int,
        colorForSample: (Int) -> Color
    ) -> [Gradient.Stop] {
        guard points.count == sampleIndexForPoint.count, points.count >= 2 else { return [] }

        let s = max(1, stride)
        let firstSample = sampleIndexForPoint.first ?? 0
        let lastSample = sampleIndexForPoint.last ?? firstSample

        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(points.count / s + 2)

        var lastIncludedSample: Int? = nil

        for j in 0..<points.count {
            let si = sampleIndexForPoint[j]
            let p = points[j]

            let isFirst = (j == 0)
            let isLast = (j == points.count - 1)

            let includeByStride: Bool
            if si == firstSample || si == lastSample {
                includeByStride = true
            } else {
                includeByStride = ((si - firstSample) % s == 0)
            }

            if isFirst || isLast || (includeByStride && lastIncludedSample != si) {
                let loc = safeLocation01(x: p.x, minX: plotMinX, maxX: plotMaxX)
                stops.append(.init(color: colorForSample(si), location: loc))
                lastIncludedSample = si
            }
        }

        // Ensure at least two stops
        if stops.count < 2 {
            let loc0 = safeLocation01(x: points.first!.x, minX: plotMinX, maxX: plotMaxX)
            let loc1 = safeLocation01(x: points.last!.x, minX: plotMinX, maxX: plotMaxX)
            stops = [
                .init(color: colorForSample(firstSample), location: loc0),
                .init(color: colorForSample(lastSample), location: loc1),
            ]
        }

        return stops
    }

    static func smooth1D(values: [Double], passes: Int, preserveZerosUsing mask: [Bool]? = nil) -> [Double] {
        guard values.count >= 3, passes > 0 else { return values }

        var out = values
        for _ in 0..<passes {
            var next = out
            for i in 0..<out.count {
                if let m = mask, i < m.count, m[i] == false {
                    next[i] = 0.0
                    continue
                }

                let i0 = max(0, i - 1)
                let i1 = i
                let i2 = min(out.count - 1, i + 1)

                let v = out[i0] * 0.25 + out[i1] * 0.50 + out[i2] * 0.25
                next[i] = v
            }
            out = next
        }
        return out
    }

    // Deterministic hash 0...1 (stable; no randomness)
    static func hash01(_ x: Int) -> Double {
        var z = UInt64(bitPattern: Int64(x))
        z &+= 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        let m = Double(UInt32.max)
        return Double(UInt32(truncatingIfNeeded: z)) / m
    }
}
