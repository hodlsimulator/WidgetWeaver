//
//  RainSurfaceDrawing.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Rendering helpers for the forecast surface.
//

import Foundation
import SwiftUI
import CoreGraphics
#if canImport(UIKit)
import UIKit
#endif

enum RainSurfaceDrawing {
    // MARK: - Surface (core + fuzz band + rim + optional glints)

    static func drawSurface(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        certainties: [Double],
        corePath: Path,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard chartRect.width > 1, chartRect.height > 1 else { return }
        guard !heights.isEmpty else { return }

        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)
        let maxHeight = max(heights.max() ?? 0, onePixel)

        drawCore(
            in: &context,
            topEdgePath: topEdgePath,
            corePath: corePath,
            configuration: configuration,
            displayScale: displayScale
        )

        if configuration.fuzzEnabled && configuration.fuzzMaxOpacity > 0.001 && configuration.fuzzSpeckleBudget > 0 {
            drawFuzzBand(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                certainties: certainties,
                maxHeight: maxHeight,
                corePath: corePath,
                topEdgePath: topEdgePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        if configuration.rimEnabled {
            drawRim(
                in: &context,
                topEdgePath: topEdgePath,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }

        if configuration.glintEnabled {
            drawGlints(
                in: &context,
                chartRect: chartRect,
                baselineY: baselineY,
                stepX: stepX,
                heights: heights,
                maxHeight: maxHeight,
                corePath: corePath,
                configuration: configuration,
                displayScale: displayScale
            )
        }
    }

    // MARK: - Fuzz band (surface-bound: outside + inside)

    private static func drawFuzzBand(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        certainties: [Double],
        maxHeight: CGFloat,
        corePath: Path,
        topEdgePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard chartRect.width > 2, chartRect.height > 2 else { return }

        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let desiredPx = Double(chartRect.height * configuration.fuzzWidthFraction * scale)
        let clampedPx = RainSurfaceMath.clamp(
            desiredPx,
            min: configuration.fuzzWidthPixelsClamp.lowerBound,
            max: configuration.fuzzWidthPixelsClamp.upperBound
        )
        let bandW = CGFloat(clampedPx / scale)
        if bandW <= onePixel { return }

        let insideWidthFactor = RainSurfaceMath.clamp(configuration.fuzzInsideWidthFactor, min: 0.10, max: 1.00)
        let insideBandW = max(onePixel, bandW * CGFloat(insideWidthFactor))

        let insideOpacityFactor = RainSurfaceMath.clamp(configuration.fuzzInsideOpacityFactor, min: 0.0, max: 1.0)
        let insideSpeckleFrac = RainSurfaceMath.clamp(configuration.fuzzInsideSpeckleFraction, min: 0.0, max: 0.85)

        let uncertaintyFloor = RainSurfaceMath.clamp(configuration.fuzzUncertaintyFloor, min: 0.0, max: 0.90)
        let uncertaintyExp = RainSurfaceMath.clamp(configuration.fuzzUncertaintyExponent, min: 0.35, max: 6.0)

        let lowHeightPower = max(0.8, configuration.fuzzLowHeightPower)
        let lowHeightBoost = RainSurfaceMath.clamp(configuration.fuzzLowHeightBoost, min: 0.0, max: 1.0)

        let maxOpacity = RainSurfaceMath.clamp(configuration.fuzzMaxOpacity, min: 0.02, max: 0.55)
        let hazeStrength = RainSurfaceMath.clamp(configuration.fuzzHazeStrength, min: 0.0, max: 1.5)
        let speckStrength = RainSurfaceMath.clamp(configuration.fuzzSpeckStrength, min: 0.0, max: 1.5)

        let distPowOut = RainSurfaceMath.clamp(configuration.fuzzDistancePowerOutside, min: 1.05, max: 4.0)
        let distPowIn = RainSurfaceMath.clamp(configuration.fuzzDistancePowerInside, min: 1.05, max: 4.0)
        let tangentJitterFrac = RainSurfaceMath.clamp(configuration.fuzzAlongTangentJitterFraction, min: 0.0, max: 2.0)

        let n = heights.count
        if n == 0 { return }

        // Per-column strength and slope.
        var strengthByI = [Double](repeating: 0.0, count: n)
        var slopeByI = [CGFloat](repeating: 0.0, count: n)

        let maxHeightSafe = max(maxHeight, onePixel)
        var sumStrength = 0.0

        for i in 0..<n {
            let cRaw: Double = {
                if certainties.isEmpty { return 1.0 }
                if i < certainties.count { return certainties[i] }
                return certainties.last ?? 1.0
            }()
            let certainty = RainSurfaceMath.clamp01(cRaw)

            let u = RainSurfaceMath.clamp01(uncertaintyFloor + (1.0 - uncertaintyFloor) * (1.0 - certainty))
            let uncertainty = pow(u, uncertaintyExp)

            let hNorm = RainSurfaceMath.clamp01(Double(heights[i] / maxHeightSafe))
            let lowH = pow(max(0.0, 1.0 - hNorm), lowHeightPower)

            let s = RainSurfaceMath.clamp01(max(uncertainty, lowH * lowHeightBoost))
            strengthByI[i] = s
            sumStrength += s

            let ip = max(0, i - 1)
            let inx = min(n - 1, i + 1)
            let y0 = baselineY - heights[ip]
            let y1 = baselineY - heights[inx]
            let dx = CGFloat(max(1, inx - ip)) * stepX
            slopeByI[i] = (dx > onePixel) ? ((y1 - y0) / dx) : 0.0
        }

        let avgStrength = sumStrength / Double(max(1, n))

        // Clip fuzz strictly to above-baseline chart area.
        let clipRect = CGRect(
            x: chartRect.minX,
            y: chartRect.minY,
            width: chartRect.width,
            height: max(0, baselineY - chartRect.minY)
        )
        let clipPath = Path(clipRect)

        // Haze is a bounded, continuous envelope around the edge (outside + inside).
        let blurFrac = RainSurfaceMath.clamp(configuration.fuzzHazeBlurFractionOfBand, min: 0.0, max: 1.0)
        let hazeBlurOut = CGFloat(Double(bandW) * blurFrac)
        let hazeBlurIn = CGFloat(Double(insideBandW) * blurFrac * 0.90)

        let hazeWidthOut = max(onePixel, bandW * CGFloat(RainSurfaceMath.clamp(configuration.fuzzHazeStrokeWidthFactor, min: 0.25, max: 3.0)))
        let hazeWidthIn = max(onePixel, insideBandW * CGFloat(RainSurfaceMath.clamp(configuration.fuzzInsideHazeStrokeWidthFactor, min: 0.25, max: 3.0)))

        let hazeAOut = maxOpacity * hazeStrength * (0.10 + 0.40 * avgStrength)
        let hazeAIn = hazeAOut * insideOpacityFactor * 0.85

        // Speckle budget (scaled by baseDensity).
        let density01 = RainSurfaceMath.clamp01(configuration.fuzzBaseDensity)
        let totalBudget = max(0, Int(Double(max(0, configuration.fuzzSpeckleBudget)) * density01))
        if totalBudget <= 0 { return }

        // Column downsampling.
        let maxColumns = max(24, configuration.fuzzMaxColumns)
        let stride = max(1, n / maxColumns)

        var indices: [Int] = []
        indices.reserveCapacity(min(n, maxColumns + 2))

        var i = 0
        while i < n {
            indices.append(i)
            i += stride
        }
        if indices.last != (n - 1) { indices.append(n - 1) }

        // Weighted allocation so tapered ends always get speckles.
        var weights: [Double] = []
        weights.reserveCapacity(indices.count)

        var sumW = 0.0
        for idx in indices {
            let s = strengthByI[idx]
            let w = 0.10 + 0.90 * pow(max(0.0, s), 0.80)
            weights.append(w)
            sumW += w
        }
        if sumW <= 1e-9 { return }

        var counts: [Int] = Array(repeating: 0, count: indices.count)
        var carry = 0.0
        var allocated = 0

        for k in 0..<indices.count {
            let frac = weights[k] / sumW
            carry += frac * Double(totalBudget)
            let target = Int(floor(carry))
            let c = max(0, target - allocated)
            counts[k] = c
            allocated = target
        }

        let leftover = totalBudget - allocated
        if leftover > 0, let last = counts.indices.last {
            counts[last] += leftover
        }

        let rMinPx = max(0.15, configuration.fuzzSpeckleRadiusPixels.lowerBound)
        let rMaxPx = max(rMinPx, configuration.fuzzSpeckleRadiusPixels.upperBound)

        context.drawLayer { layer in
            layer.blendMode = .plusLighter
            layer.clip(to: clipPath)

            // Outside haze: clip to (clipRect - corePath) using even-odd fill.
            if hazeAOut > 0.0001, hazeWidthOut > onePixel {
                layer.drawLayer { l2 in
                    let outsideMask = RainSurfaceGeometry.makeOutsideMaskPath(clipRect: clipRect, corePath: corePath)
                    l2.clip(to: outsideMask, style: FillStyle(eoFill: true))

                    if hazeBlurOut > 0.01 {
                        l2.addFilter(.blur(radius: hazeBlurOut))
                    }

                    l2.stroke(
                        topEdgePath,
                        with: .color(configuration.fuzzColor.opacity(hazeAOut)),
                        style: StrokeStyle(lineWidth: hazeWidthOut, lineCap: .round, lineJoin: .round)
                    )
                }
            }

            // Inside haze: clip to corePath.
            if hazeAIn > 0.0001, hazeWidthIn > onePixel {
                layer.drawLayer { l2 in
                    l2.clip(to: corePath)

                    if hazeBlurIn > 0.01 {
                        l2.addFilter(.blur(radius: hazeBlurIn))
                    }

                    l2.stroke(
                        topEdgePath,
                        with: .color(configuration.fuzzColor.opacity(hazeAIn)),
                        style: StrokeStyle(lineWidth: hazeWidthIn, lineCap: .round, lineJoin: .round)
                    )
                }
            }

            // Speckles: spawned along edge normal (outside + inside), bounded by band widths.
            for k in 0..<indices.count {
                let idx = indices[k]
                let count = counts[k]
                if count <= 0 { continue }

                let s = strengthByI[idx]
                let sCurve = 0.25 + 0.75 * pow(max(0.0, s), 1.15)

                let xC = chartRect.minX + (CGFloat(idx) + 0.5) * stepX
                let yC = baselineY - heights[idx]

                if yC <= chartRect.minY + onePixel { continue }
                if yC >= baselineY - onePixel { continue }

                let slope = slopeByI[idx]

                // Outside normal for region below the curve: (slope, -1), normalised.
                var nx: CGFloat = slope
                var ny: CGFloat = -1.0
                let nLen = max(onePixel, sqrt(nx * nx + ny * ny))
                nx /= nLen
                ny /= nLen

                // Tangent: (1, slope), normalised.
                var tx: CGFloat = 1.0
                var ty: CGFloat = slope
                let tLen = max(onePixel, sqrt(tx * tx + ty * ty))
                tx /= tLen
                ty /= tLen

                // Inside is the opposite direction.
                let inNx = -nx
                let inNy = -ny

                let insideCount = Int(round(Double(count) * insideSpeckleFrac))
                let outsideCount = max(0, count - insideCount)

                let seedA = RainSurfacePRNG.combine(configuration.noiseSeed, UInt64(bitPattern: Int64(idx)) &* 0x9E3779B97F4A7C15)
                let seedB = RainSurfacePRNG.combine(seedA, 0xD1B54A32D192ED03)
                var rng = RainSurfacePRNG(seed: seedB)

                // Outside speckles.
                if outsideCount > 0 && speckStrength > 0.0001 {
                    for _ in 0..<outsideCount {
                        let r0 = rng.nextDouble01()
                        let r1 = rng.nextDouble01()
                        let r2 = rng.nextDouble01()

                        let along = (CGFloat(r0) - 0.5) * stepX * CGFloat(0.85 * tangentJitterFrac)

                        let dist = bandW * CGFloat(pow(r1, distPowOut))
                        let edge = pow(max(0.0, 1.0 - Double(dist / max(onePixel, bandW))), 1.35)

                        let px = xC + along * tx + dist * nx
                        let py = yC + along * ty + dist * ny

                        if px < chartRect.minX || px > chartRect.maxX { continue }
                        if py < chartRect.minY || py > baselineY { continue }

                        let rrT = r2 * r2
                        let rPx = rMinPx + (rMaxPx - rMinPx) * rrT
                        let rPt = CGFloat(rPx / Double(scale))

                        var a = maxOpacity
                            * speckStrength
                            * sCurve
                            * (0.20 + 0.80 * edge)
                            * (0.25 + 0.75 * (0.35 + 0.65 * rng.nextDouble01()))

                        a = min(a, maxOpacity)

                        if a <= 0.0005 { continue }

                        let rect = CGRect(x: px - rPt, y: py - rPt, width: rPt * 2, height: rPt * 2)
                        layer.fill(Path(ellipseIn: rect), with: .color(configuration.fuzzColor.opacity(a)))
                    }
                }

                // Inside speckles.
                if insideCount > 0 && speckStrength > 0.0001 && insideOpacityFactor > 0.0001 {
                    for _ in 0..<insideCount {
                        let r0 = rng.nextDouble01()
                        let r1 = rng.nextDouble01()
                        let r2 = rng.nextDouble01()

                        let along = (CGFloat(r0) - 0.5) * stepX * CGFloat(0.75 * tangentJitterFrac)

                        let dist = insideBandW * CGFloat(pow(r1, distPowIn))
                        let edge = pow(max(0.0, 1.0 - Double(dist / max(onePixel, insideBandW))), 1.45)

                        let px = xC + along * tx + dist * inNx
                        let py = yC + along * ty + dist * inNy

                        if px < chartRect.minX || px > chartRect.maxX { continue }
                        if py < chartRect.minY || py > baselineY { continue }

                        let rrT = r2 * r2
                        let rPx = rMinPx + (rMaxPx - rMinPx) * rrT
                        let rPt = CGFloat(rPx / Double(scale))

                        var a = maxOpacity
                            * speckStrength
                            * insideOpacityFactor
                            * (0.18 + 0.82 * edge)
                            * (0.18 + 0.82 * sCurve)
                            * (0.22 + 0.78 * (0.35 + 0.65 * rng.nextDouble01()))

                        a = min(a, maxOpacity * insideOpacityFactor)

                        if a <= 0.0005 { continue }

                        let rect = CGRect(x: px - rPt, y: py - rPt, width: rPt * 2, height: rPt * 2)
                        layer.fill(Path(ellipseIn: rect), with: .color(configuration.fuzzColor.opacity(a)))
                    }
                }
            }
        }
    }

    // MARK: - Core (opaque volume + optional inside-only gloss)

    private static func drawCore(
        in context: inout GraphicsContext,
        topEdgePath: Path,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        context.fill(corePath, with: .color(configuration.coreBodyColor.opacity(1.0)))

        if configuration.glossEnabled && configuration.glossMaxOpacity > 0.0001 {
            let depthPx = RainSurfaceMath.clamp(
                (configuration.glossDepthPixels.lowerBound + configuration.glossDepthPixels.upperBound) * 0.5,
                min: configuration.glossDepthPixels.lowerBound,
                max: configuration.glossDepthPixels.upperBound
            )
            let depth = CGFloat(depthPx / scale)
            let opacity = configuration.glossMaxOpacity

            let shiftY = max(onePixel, depth * 0.33)
            let bandPath = topEdgePath.applying(CGAffineTransform(translationX: 0, y: shiftY))
            let bandPath2 = topEdgePath.applying(CGAffineTransform(translationX: 0, y: shiftY + max(onePixel, depth * 0.32)))

            context.drawLayer { layer in
                layer.blendMode = .screen

                layer.stroke(
                    bandPath2,
                    with: .color(configuration.coreTopColor.opacity(opacity * 0.50)),
                    style: StrokeStyle(lineWidth: max(onePixel, depth * 2.35), lineCap: .round, lineJoin: .round)
                )

                layer.stroke(
                    bandPath,
                    with: .color(configuration.coreTopColor.opacity(opacity)),
                    style: StrokeStyle(lineWidth: max(onePixel, depth * 1.45), lineCap: .round, lineJoin: .round)
                )

                layer.blendMode = .destinationIn
                layer.fill(corePath, with: .color(.white))
            }
        }
    }

    // MARK: - Rim (thin smooth edge + subtle outer halo)

    private static func drawRim(
        in context: inout GraphicsContext,
        topEdgePath: Path,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let innerW = max(onePixel, CGFloat(configuration.rimInnerWidthPixels / scale))
        let outerW = max(innerW, CGFloat(configuration.rimOuterWidthPixels / scale))

        let innerA = RainSurfaceMath.clamp(configuration.rimInnerOpacity, min: 0.0, max: 1.0)
        let outerA = RainSurfaceMath.clamp(configuration.rimOuterOpacity, min: 0.0, max: 1.0)

        if outerA > 0.0001 && outerW > onePixel {
            context.drawLayer { layer in
                layer.blendMode = .plusLighter
                layer.stroke(
                    topEdgePath,
                    with: .color(configuration.rimColor.opacity(outerA)),
                    style: StrokeStyle(lineWidth: outerW, lineCap: .round, lineJoin: .round)
                )

                layer.blendMode = .destinationOut
                layer.fill(corePath, with: .color(.white))
            }
        }

        if innerA > 0.0001 {
            context.drawLayer { layer in
                layer.blendMode = .screen
                layer.stroke(
                    topEdgePath,
                    with: .color(configuration.rimColor.opacity(innerA)),
                    style: StrokeStyle(lineWidth: innerW, lineCap: .round, lineJoin: .round)
                )

                layer.blendMode = .destinationIn
                layer.fill(corePath, with: .color(.white))
            }
        }
    }

    // MARK: - Glints (tiny, local maxima only)

    private static func drawGlints(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        stepX: CGFloat,
        heights: [CGFloat],
        maxHeight: CGFloat,
        corePath: Path,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let minFrac = RainSurfaceMath.clamp(configuration.glintMinHeightFraction, min: 0.35, max: 0.90)
        let minH = maxHeight * CGFloat(minFrac)

        let peakIndices = localMaximaIndices(
            heights: heights,
            minHeight: minH,
            maxCount: max(0, configuration.glintMaxCount),
            minSeparationPoints: max(onePixel * 10, chartRect.width * 0.08),
            stepX: stepX
        )
        guard !peakIndices.isEmpty else { return }

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            for idx in peakIndices {
                let h = heights[idx]
                let x = chartRect.minX + (CGFloat(idx) + 0.5) * stepX
                let y = baselineY - h

                let w0 = max(onePixel * 7.0, onePixel * 9.0)
                let h0 = max(onePixel * 1.2, onePixel * 1.6)
                let rect0 = CGRect(x: x - w0 * 0.5, y: y - h0 * 0.6, width: w0, height: h0)
                layer.fill(
                    Path(roundedRect: rect0, cornerRadius: h0 * 0.5),
                    with: .color(configuration.glintColor.opacity(configuration.glintMaxOpacity * 0.52))
                )

                let w1 = max(onePixel * 4.0, onePixel * 5.5)
                let h1 = max(onePixel * 0.9, onePixel * 1.2)
                let rect1 = CGRect(x: x - w1 * 0.5, y: y - h1 * 0.6, width: w1, height: h1)
                layer.fill(
                    Path(roundedRect: rect1, cornerRadius: h1 * 0.5),
                    with: .color(configuration.glintColor.opacity(configuration.glintMaxOpacity))
                )
            }

            layer.blendMode = .destinationIn
            layer.fill(corePath, with: .color(.white))
        }
    }

    private static func localMaximaIndices(
        heights: [CGFloat],
        minHeight: CGFloat,
        maxCount: Int,
        minSeparationPoints: CGFloat,
        stepX: CGFloat
    ) -> [Int] {
        guard heights.count >= 3, maxCount > 0 else { return [] }

        var peaks: [(idx: Int, h: CGFloat)] = []
        peaks.reserveCapacity(8)

        for i in 1..<(heights.count - 1) {
            let a = heights[i - 1]
            let b = heights[i]
            let c = heights[i + 1]
            if b >= minHeight && b > a && b >= c {
                peaks.append((i, b))
            }
        }

        guard !peaks.isEmpty else { return [] }
        peaks.sort { $0.h > $1.h }

        var chosen: [Int] = []
        chosen.reserveCapacity(min(maxCount, peaks.count))

        for p in peaks {
            if chosen.count >= maxCount { break }
            let xP = CGFloat(p.idx) * stepX
            let tooClose = chosen.contains { j in abs(CGFloat(j) * stepX - xP) < minSeparationPoints }
            if !tooClose { chosen.append(p.idx) }
        }

        return chosen
    }

    // MARK: - Baseline (drawn last)

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration: RainForecastSurfaceConfiguration,
        displayScale: CGFloat
    ) {
        guard chartRect.width > 1 else { return }

        let scale = max(1.0, displayScale)
        let onePixel = CGFloat(1.0 / scale)

        let x0 = chartRect.minX
        let x1 = chartRect.maxX

        let fadeFrac = RainSurfaceMath.clamp(configuration.baselineEndFadeFraction, min: 0.03, max: 0.08)
        let fadeW = max(onePixel, chartRect.width * fadeFrac)

        let leftStop = min(1.0, Double(fadeW / chartRect.width))
        let rightStop = max(0.0, 1.0 - Double(fadeW / chartRect.width))

        let gradient = Gradient(stops: [
            .init(color: .white.opacity(0.0), location: 0.0),
            .init(color: .white.opacity(1.0), location: leftStop),
            .init(color: .white.opacity(1.0), location: rightStop),
            .init(color: .white.opacity(0.0), location: 1.0)
        ])

        let alphaMask = GraphicsContext.Shading.linearGradient(
            gradient,
            startPoint: CGPoint(x: x0, y: baselineY),
            endPoint: CGPoint(x: x1, y: baselineY)
        )

        var line = Path()
        line.move(to: CGPoint(x: x0, y: baselineY))
        line.addLine(to: CGPoint(x: x1, y: baselineY))

        context.drawLayer { layer in
            layer.blendMode = .plusLighter

            let base = RainSurfaceMath.clamp(configuration.baselineLineOpacity, min: 0.05, max: 0.60)

            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.08)),
                style: StrokeStyle(lineWidth: onePixel * 6.0, lineCap: .round)
            )
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base * 0.16)),
                style: StrokeStyle(lineWidth: onePixel * 3.2, lineCap: .round)
            )
            layer.stroke(
                line,
                with: .color(configuration.baselineColor.opacity(base)),
                style: StrokeStyle(lineWidth: onePixel * 0.85, lineCap: .butt)
            )

            layer.blendMode = .destinationIn
            var fadeRect = Path()
            fadeRect.addRect(chartRect)
            layer.fill(fadeRect, with: alphaMask)
        }
    }
}
