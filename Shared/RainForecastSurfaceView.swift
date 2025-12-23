//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Programmatic “forecast surface” renderer:
//  - Single filled ribbon above a subtle baseline
//  - Uncertainty shown as an inward, soft diffusion near the top edge (no second band, no stroke)
//  - Deterministic (no randomness / no animation)
//

import Foundation
import SwiftUI

// MARK: - Configuration

struct RainForecastSurfaceConfiguration: Hashable {
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
    var diffusionColor: Color
    var diffusionMinRadiusPoints: CGFloat
    var diffusionMaxRadiusPoints: CGFloat
    var diffusionMinRadiusFractionOfHeight: CGFloat
    var diffusionMaxRadiusFractionOfHeight: CGFloat
    var diffusionLayers: Int
    var diffusionMaxAlpha: Double
    var diffusionFalloffPower: Double
    var diffusionUncertaintyAlphaFloor: Double

    // Optional tight glow (inward, subtle)
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
            let insetX = max(0, rect.width * configuration.edgeInsetFraction)
            let plotRect = rect.insetBy(dx: insetX, dy: 0)

            guard plotRect.width > 0, plotRect.height > 0 else { return }

            let baselineY = rect.minY + rect.height * configuration.baselineYFraction
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

                // Keep diffusion inside the ribbon.
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

            // Core ribbon gradient (vertical).
            let fillGradient = Gradient(stops: [
                .init(color: configuration.fillBottomColor.opacity(configuration.fillBottomOpacity), location: 0.0),
                .init(color: configuration.fillTopColor.opacity(configuration.fillTopOpacity), location: 1.0),
            ])

            let fillShading = GraphicsContext.Shading.linearGradient(
                fillGradient,
                startPoint: CGPoint(x: plotRect.midX, y: baselineY),
                endPoint: CGPoint(x: plotRect.midX, y: rect.minY)
            )

            for range in wetRanges {
                let startEdgeX = plotRect.minX + CGFloat(range.lowerBound) * stepX
                let endEdgeX = plotRect.minX + CGFloat(range.upperBound) * stepX

                var outerPoints: [CGPoint] = []
                outerPoints.reserveCapacity(range.count + 2)

                var perPointRadius: [CGFloat] = []
                perPointRadius.reserveCapacity(range.count + 2)

                // End caps at baseline.
                outerPoints.append(CGPoint(x: startEdgeX, y: baselineY))
                perPointRadius.append(0)

                for i in range {
                    let x = plotRect.minX + (CGFloat(i) + 0.5) * stepX
                    let y = baselineY - heights[i]
                    outerPoints.append(CGPoint(x: x, y: y))
                    perPointRadius.append(radii[i])
                }

                outerPoints.append(CGPoint(x: endEdgeX, y: baselineY))
                perPointRadius.append(0)

                // Core filled ribbon.
                var ribbonPath = Path()
                Self.addSmoothQuadSegments(&ribbonPath, points: outerPoints, moveToFirst: true)
                ribbonPath.addLine(to: outerPoints.first ?? CGPoint(x: startEdgeX, y: baselineY))
                ribbonPath.closeSubpath()
                context.fill(ribbonPath, with: fillShading)

                // Top-edge diffusion: stacked inward strips (no blur filter).
                let diffusionLayers = max(1, configuration.diffusionLayers)
                for k in 0..<diffusionLayers {
                    let t0 = CGFloat(k) / CGFloat(diffusionLayers)
                    let t1 = CGFloat(k + 1) / CGFloat(diffusionLayers)
                    let tMid = (t0 + t1) * 0.5

                    let falloff = pow(1.0 - Double(tMid), configuration.diffusionFalloffPower)
                    let alphaBase = configuration.diffusionMaxAlpha * falloff

                    var contourA: [CGPoint] = []
                    var contourB: [CGPoint] = []
                    contourA.reserveCapacity(outerPoints.count)
                    contourB.reserveCapacity(outerPoints.count)

                    for j in 0..<outerPoints.count {
                        let p = outerPoints[j]
                        let r = perPointRadius[j]
                        let yA = min(baselineY, p.y + r * t0)
                        let yB = min(baselineY, p.y + r * t1)
                        contourA.append(CGPoint(x: p.x, y: yA))
                        contourB.append(CGPoint(x: p.x, y: yB))
                    }

                    var strip = Path()
                    Self.addSmoothQuadSegments(&strip, points: contourA, moveToFirst: true)
                    strip.addLine(to: contourB.last ?? contourA.last ?? CGPoint(x: endEdgeX, y: baselineY))
                    Self.addSmoothQuadSegments(&strip, points: contourB.reversed(), moveToFirst: false)
                    strip.closeSubpath()

                    var stops: [Gradient.Stop] = []
                    stops.reserveCapacity(outerPoints.count)

                    for j in 0..<outerPoints.count {
                        let p = outerPoints[j]
                        let loc = Self.safeLocation01(x: p.x, minX: plotRect.minX, maxX: plotRect.maxX)

                        let sampleIndex: Int
                        if j == 0 {
                            sampleIndex = range.lowerBound
                        } else if j == outerPoints.count - 1 {
                            sampleIndex = max(range.lowerBound, range.upperBound - 1)
                        } else {
                            sampleIndex = range.lowerBound + (j - 1)
                        }

                        let c = certainty01[sampleIndex]
                        let u = 1.0 - c
                        let scale = configuration.diffusionUncertaintyAlphaFloor + (1.0 - configuration.diffusionUncertaintyAlphaFloor) * u
                        let a = max(0, min(1.0, alphaBase * scale))

                        stops.append(.init(color: configuration.diffusionColor.opacity(a), location: loc))
                    }

                    let grad = Gradient(stops: stops)
                    let shading = GraphicsContext.Shading.linearGradient(
                        grad,
                        startPoint: CGPoint(x: plotRect.minX, y: 0),
                        endPoint: CGPoint(x: plotRect.maxX, y: 0)
                    )

                    context.fill(strip, with: shading)
                }

                // Optional tight glow (inward only), strongest where certainty is high.
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
                        contourA.reserveCapacity(outerPoints.count)
                        contourB.reserveCapacity(outerPoints.count)

                        for j in 0..<outerPoints.count {
                            let p = outerPoints[j]
                            let r = min(perPointRadius[j], glowRadiusMax)
                            let yA = min(baselineY, p.y + r * t0)
                            let yB = min(baselineY, p.y + r * t1)
                            contourA.append(CGPoint(x: p.x, y: yA))
                            contourB.append(CGPoint(x: p.x, y: yB))
                        }

                        var strip = Path()
                        Self.addSmoothQuadSegments(&strip, points: contourA, moveToFirst: true)
                        strip.addLine(to: contourB.last ?? contourA.last ?? CGPoint(x: endEdgeX, y: baselineY))
                        Self.addSmoothQuadSegments(&strip, points: contourB.reversed(), moveToFirst: false)
                        strip.closeSubpath()

                        var stops: [Gradient.Stop] = []
                        stops.reserveCapacity(outerPoints.count)

                        for j in 0..<outerPoints.count {
                            let p = outerPoints[j]
                            let loc = Self.safeLocation01(x: p.x, minX: plotRect.minX, maxX: plotRect.maxX)

                            let sampleIndex: Int
                            if j == 0 {
                                sampleIndex = range.lowerBound
                            } else if j == outerPoints.count - 1 {
                                sampleIndex = max(range.lowerBound, range.upperBound - 1)
                            } else {
                                sampleIndex = range.lowerBound + (j - 1)
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

            // Baseline on top.
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
}
