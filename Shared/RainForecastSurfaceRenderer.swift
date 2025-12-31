//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI
import CoreGraphics

#if canImport(UIKit)
import UIKit
#endif

struct RainForecastSurfaceRenderer {
    private let intensities: [Double]
    private let certainties01: [Double]
    private let configuration: RainForecastSurfaceConfiguration

    init(
        intensities: [Double],
        certainties: [Double] = [],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties01 = certainties.map { Self.clamp01($0) }
        self.configuration = configuration
    }

    init(
        intensities: [Double],
        certainties: [Double?],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties01 = certainties.map { Self.clamp01($0 ?? 0.0) }
        self.configuration = configuration
    }

    func render(in context: inout GraphicsContext, rect: CGRect, displayScale: CGFloat) {
        guard rect.width > 1.0, rect.height > 1.0 else { return }

        var cfg = configuration
        cfg.sourceMinuteCount = intensities.count

        let isExtension = WidgetWeaverRuntime.isRunningInAppExtension

        let ds: CGFloat = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0
        let onePx: CGFloat = 1.0 / max(1.0, ds)

        if isExtension {
            cfg.glossEnabled = false
            cfg.glintEnabled = false
            cfg.fuzzHazeBlurFractionOfBand = 0.0
        }

        cfg.maxDenseSamples = max(120, min(cfg.maxDenseSamples, isExtension ? 620 : 900))

        let chartRect = rect
        let baselineY = chartRect.minY
        + chartRect.height * CGFloat(Self.clamp01(cfg.baselineFractionFromTop))
        + CGFloat(cfg.baselineOffsetPixels) / max(1.0, ds)

        guard !intensities.isEmpty else {
            Self.drawBaseline(in: &context, chartRect: chartRect, baselineY: baselineY, configuration: cfg, displayScale: ds)
            return
        }

        let filledIntensities = Self.fillMissingLinearHoldEnds(intensities)

        let referenceMax = Self.robustReferenceMaxMMPerHour(
            values: filledIntensities,
            defaultMax: cfg.intensityReferenceMaxMMPerHour,
            percentile: cfg.robustMaxPercentile
        )

        let topY = chartRect.minY + chartRect.height * CGFloat(Self.clamp01(cfg.topHeadroomFraction))
        let usableHeight = max(1.0, baselineY - topY)
        let peakHeight = usableHeight * CGFloat(Self.clamp01(cfg.typicalPeakFraction))

        var minuteHeights: [CGFloat] = filledIntensities.map { v in
            let x = max(0.0, v.isFinite ? v : 0.0)
            let n = Self.clamp01(x / max(0.001, referenceMax))
            let g = pow(n, max(0.01, cfg.intensityGamma))
            return CGFloat(g) * peakHeight
        }

        if cfg.edgeEasingFraction > 0.0001 {
            minuteHeights = Self.applyEdgeEasing(
                values: minuteHeights,
                fraction: cfg.edgeEasingFraction,
                power: cfg.edgeEasingPower
            )
        }

        let minuteCertainties = Self.makeMinuteCertainties(
            sourceCount: minuteHeights.count,
            certainties01: certainties01
        )

        let denseCount = Self.denseSampleCount(
            sourceCount: minuteHeights.count,
            rectWidthPoints: Double(chartRect.width),
            displayScale: Double(ds),
            maxDense: cfg.maxDenseSamples
        )

        let denseHeights = Self.resampleLinear(minuteHeights, toCount: denseCount)
        let denseCertainties = Self.resampleLinear(minuteCertainties, toCount: denseCount)

        // Segment rendering avoids long baseline strokes through dry gaps, and creates tapered
        // ends for each distinct rain burst.
        let wetThreshold = onePx * 0.85
        let segments = Self.buildWetSegments(
            rect: chartRect,
            baselineY: baselineY,
            heights: denseHeights,
            certainties01: denseCertainties,
            wetThreshold: wetThreshold
        )

        let shouldDrawFuzz = cfg.fuzzEnabled && cfg.canEnableFuzz && cfg.fuzzTextureEnabled
        let bandHalfWidth = shouldDrawFuzz
        ? Self.computeBandHalfWidthPoints(rect: chartRect, displayScale: ds, configuration: cfg)
        : 0.0

        for seg in segments {
            let corePath = Self.buildCoreFillPath(baselineY: baselineY, curvePoints: seg.curvePoints)

            // Outer body first, then erosion/dust, then a solid inner core to preserve data
            // legibility while still allowing a strong dissipation band.
            Self.drawCore(
                in: &context,
                corePath: corePath,
                curvePoints: seg.curvePoints,
                baselineY: baselineY,
                configuration: cfg
            )

            if shouldDrawFuzz, bandHalfWidth > onePx * 0.5 {
                Self.drawDissipationFuzz(
                    in: &context,
                    rect: chartRect,
                    baselineY: baselineY,
                    corePath: corePath,
                    curvePoints: seg.curvePoints,
                    heights: seg.heights,
                    certainties01: seg.certainties01,
                    bandHalfWidth: bandHalfWidth,
                    displayScale: ds,
                    configuration: cfg
                )

                if cfg.fuzzErodeEnabled, cfg.fuzzErodeStrength > 0.0001 {
                    let inset = Self.computeSolidCoreInset(
                        bandHalfWidth: bandHalfWidth,
                        heights: seg.heights
                    )

                    if inset > onePx * 0.75 {
                        let innerCurvePoints = Self.makeInsetCurvePoints(
                            curvePoints: seg.curvePoints,
                            baselineY: baselineY,
                            heights: seg.heights,
                            inset: inset
                        )
                        let innerCorePath = Self.buildCoreFillPath(baselineY: baselineY, curvePoints: innerCurvePoints)

                        Self.drawCore(
                            in: &context,
                            corePath: innerCorePath,
                            curvePoints: innerCurvePoints,
                            baselineY: baselineY,
                            configuration: cfg
                        )
                    }
                }
            }

            Self.drawRim(
                in: &context,
                curvePoints: seg.curvePoints,
                configuration: cfg,
                displayScale: ds
            )
        }

        Self.drawBaseline(in: &context, chartRect: chartRect, baselineY: baselineY, configuration: cfg, displayScale: ds)
    }
}

// MARK: - Segments

extension RainForecastSurfaceRenderer {
    struct SurfaceSegment {
        var curvePoints: [CGPoint]
        var heights: [CGFloat]
        var certainties01: [CGFloat]
        var gradientStartX: CGFloat
        var gradientEndX: CGFloat
    }

    static func buildWetSegments(
        rect: CGRect,
        baselineY: CGFloat,
        heights: [CGFloat],
        certainties01: [CGFloat],
        wetThreshold: CGFloat
    ) -> [SurfaceSegment] {
        guard heights.count >= 1 else { return [] }

        let n = min(heights.count, certainties01.count)
        guard n >= 1 else { return [] }

        let stepX = rect.width / CGFloat(max(1, n))
        let xMid: (Int) -> CGFloat = { i in
            rect.minX + (CGFloat(i) + 0.5) * stepX
        }

        let isWet: (Int) -> Bool = { i in
            heights[i] > wetThreshold
        }

        var segments: [SurfaceSegment] = []
        segments.reserveCapacity(4)

        var runStart: Int? = nil
        for i in 0..<n {
            if isWet(i) {
                if runStart == nil { runStart = i }
            } else if let start = runStart {
                let end = i - 1
                if let seg = makeSegment(rect: rect, baselineY: baselineY, start: start, end: end, stepX: stepX, xMid: xMid, heights: heights, certainties01: certainties01) {
                    segments.append(seg)
                }
                runStart = nil
            }
        }

        if let start = runStart {
            let end = n - 1
            if let seg = makeSegment(rect: rect, baselineY: baselineY, start: start, end: end, stepX: stepX, xMid: xMid, heights: heights, certainties01: certainties01) {
                segments.append(seg)
            }
        }

        return segments
    }

    private static func makeSegment(
        rect: CGRect,
        baselineY: CGFloat,
        start: Int,
        end: Int,
        stepX: CGFloat,
        xMid: (Int) -> CGFloat,
        heights: [CGFloat],
        certainties01: [CGFloat]
    ) -> SurfaceSegment? {
        guard start >= 0, end >= start else { return nil }
        guard end < heights.count, end < certainties01.count else { return nil }

        let leftX = rect.minX + CGFloat(start) * stepX
        let rightX = rect.minX + CGFloat(end + 1) * stepX

        let clampedLeftX = max(rect.minX, min(leftX, rect.maxX))
        let clampedRightX = max(rect.minX, min(rightX, rect.maxX))
        let minX = min(clampedLeftX, clampedRightX)
        let maxX = max(clampedLeftX, clampedRightX)

        var pts: [CGPoint] = []
        var hs: [CGFloat] = []
        var cs: [CGFloat] = []

        let count = (end - start + 1)
        pts.reserveCapacity(count + 2)
        hs.reserveCapacity(count + 2)
        cs.reserveCapacity(count + 2)

        let c0 = certainties01[start]
        let c1 = certainties01[end]

        pts.append(CGPoint(x: minX, y: baselineY))
        hs.append(0.0)
        cs.append(c0)

        for i in start...end {
            pts.append(CGPoint(x: xMid(i), y: baselineY - heights[i]))
            hs.append(heights[i])
            cs.append(certainties01[i])
        }

        pts.append(CGPoint(x: maxX, y: baselineY))
        hs.append(0.0)
        cs.append(c1)

        return SurfaceSegment(
            curvePoints: pts,
            heights: hs,
            certainties01: cs,
            gradientStartX: minX,
            gradientEndX: maxX
        )
    }

    static func computeSolidCoreInset(bandHalfWidth: CGFloat, heights: [CGFloat]) -> CGFloat {
        let maxH = heights.max() ?? 0.0
        if maxH <= 0.0001 { return 0.0 }

        let byBand = bandHalfWidth * 0.55
        let byPeak = maxH * 0.12
        return max(0.0, min(byBand, byPeak))
    }

    static func makeInsetCurvePoints(
        curvePoints: [CGPoint],
        baselineY: CGFloat,
        heights: [CGFloat],
        inset: CGFloat
    ) -> [CGPoint] {
        let n = min(curvePoints.count, heights.count)
        guard n > 0 else { return curvePoints }

        var pts: [CGPoint] = []
        pts.reserveCapacity(n)

        for i in 0..<n {
            let h = max(0.0, heights[i] - inset)
            pts.append(CGPoint(x: curvePoints[i].x, y: baselineY - h))
        }

        return pts
    }
}

// MARK: - Core / Rim / Baseline

extension RainForecastSurfaceRenderer {
    static func drawCore(
        in context: inout GraphicsContext,
        corePath: Path,
        curvePoints: [CGPoint],
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) {
        guard !curvePoints.isEmpty else { return }

        let topY = curvePoints.map(\.y).min() ?? baselineY
        let startPoint = CGPoint(x: curvePoints.first?.x ?? 0.0, y: topY)
        let endPoint = CGPoint(x: curvePoints.first?.x ?? 0.0, y: baselineY)

        let top = cfg.coreTopColor
        let body = cfg.coreBodyColor
        let mid = Color.blend(body, top, t: cfg.coreTopMix)

        let fade = clamp01(cfg.coreFadeFraction)
        let midStop = 0.42

        let gradient: Gradient
        if fade <= 0.0001 {
            gradient = Gradient(stops: [
                Gradient.Stop(color: top, location: 0.0),
                Gradient.Stop(color: mid, location: midStop),
                Gradient.Stop(color: body, location: 1.0),
            ])
        } else {
            let fadeStart = max(midStop, 1.0 - fade)
            gradient = Gradient(stops: [
                Gradient.Stop(color: top, location: 0.0),
                Gradient.Stop(color: mid, location: midStop),
                Gradient.Stop(color: body, location: fadeStart),
                Gradient.Stop(color: body.opacity(0.0), location: 1.0),
            ])
        }

        context.fill(corePath, with: .linearGradient(gradient, startPoint: startPoint, endPoint: endPoint))
    }

    static func drawRim(
        in context: inout GraphicsContext,
        curvePoints: [CGPoint],
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale ds: CGFloat
    ) {
        guard cfg.rimEnabled, !curvePoints.isEmpty else { return }

        let path = buildCurveStrokePath(curvePoints: curvePoints)
        let px = max(1.0, ds)

        if cfg.rimInnerOpacity > 0.0001, cfg.rimInnerWidthPixels > 0.0001 {
            context.stroke(
                path,
                with: .color(cfg.rimColor.opacity(clamp01(cfg.rimInnerOpacity))),
                lineWidth: CGFloat(cfg.rimInnerWidthPixels) / px
            )
        }

        if cfg.rimOpacity > 0.0001, cfg.rimWidthPixels > 0.0001 {
            context.stroke(
                path,
                with: .color(cfg.rimColor.opacity(clamp01(cfg.rimOpacity))),
                lineWidth: CGFloat(cfg.rimWidthPixels) / px
            )
        }

        if cfg.rimOuterOpacity > 0.0001, cfg.rimOuterWidthPixels > 0.0001 {
            context.stroke(
                path,
                with: .color(cfg.rimColor.opacity(clamp01(cfg.rimOuterOpacity))),
                lineWidth: CGFloat(cfg.rimOuterWidthPixels) / px
            )
        }
    }

    static func drawBaseline(
        in context: inout GraphicsContext,
        chartRect: CGRect,
        baselineY: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration,
        displayScale ds: CGFloat
    ) {
        guard cfg.baselineEnabled else { return }
        guard cfg.baselineWidthPixels > 0.0001, cfg.baselineLineOpacity > 0.0001 else { return }

        var p = Path()
        p.move(to: CGPoint(x: chartRect.minX, y: baselineY))
        p.addLine(to: CGPoint(x: chartRect.maxX, y: baselineY))

        let fade = clamp01(cfg.baselineEndFadeFraction)
        let base = cfg.baselineColor.opacity(clamp01(cfg.baselineLineOpacity))

        let gradient = Gradient(stops: [
            Gradient.Stop(color: base.opacity(0.0), location: 0.0),
            Gradient.Stop(color: base, location: fade),
            Gradient.Stop(color: base, location: 1.0 - fade),
            Gradient.Stop(color: base.opacity(0.0), location: 1.0),
        ])

        context.stroke(
            p,
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: chartRect.minX, y: baselineY),
                endPoint: CGPoint(x: chartRect.maxX, y: baselineY)
            ),
            lineWidth: CGFloat(cfg.baselineWidthPixels) / max(1.0, ds)
        )
    }
}

// MARK: - Geometry helpers

extension RainForecastSurfaceRenderer {
    static func computeBandHalfWidthPoints(
        rect: CGRect,
        displayScale ds: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> CGFloat {
        let minDim = min(rect.height * 0.28, rect.width * 0.10)
        let frac = max(0.0, cfg.fuzzWidthFraction)
        var widthPt = minDim * CGFloat(frac)

        let clampPx = cfg.fuzzWidthPixelsClamp
        let loPx = max(0.0, min(clampPx.lowerBound, clampPx.upperBound))
        let hiPx = max(loPx, clampPx.upperBound)

        let minPt = CGFloat(loPx) / max(1.0, ds)
        let maxPt = CGFloat(hiPx) / max(1.0, ds)
        widthPt = max(minPt, min(widthPt, maxPt))

        return widthPt
    }

    static func buildCurveStrokePath(curvePoints: [CGPoint]) -> Path {
        var p = Path()
        guard curvePoints.count >= 2 else { return p }

        let pts = curvePoints
        p.move(to: pts[0])

        if pts.count == 2 {
            p.addLine(to: pts[1])
            return p
        }

        let n = pts.count
        var x: [CGFloat] = []
        var y: [CGFloat] = []
        x.reserveCapacity(n)
        y.reserveCapacity(n)

        for pt in pts {
            x.append(pt.x)
            y.append(pt.y)
        }

        var h = Array(repeating: CGFloat(0.0), count: max(0, n - 1))
        var delta = Array(repeating: CGFloat(0.0), count: max(0, n - 1))

        for i in 0..<(n - 1) {
            let dx = x[i + 1] - x[i]
            let d = (abs(dx) < 0.000001) ? 0.0 : (y[i + 1] - y[i]) / dx
            h[i] = dx
            delta[i] = d
        }

        var m = Array(repeating: CGFloat(0.0), count: n)
        if n >= 2 {
            m[0] = delta[0]
            m[n - 1] = delta[n - 2]
        }

        if n >= 3 {
            for i in 1..<(n - 1) {
                let d0 = delta[i - 1]
                let d1 = delta[i]
                if d0 == 0.0 || d1 == 0.0 || (d0.sign != d1.sign) {
                    m[i] = 0.0
                } else {
                    let w1 = 2.0 * h[i] + h[i - 1]
                    let w2 = h[i] + 2.0 * h[i - 1]
                    m[i] = (w1 + w2) / (w1 / d0 + w2 / d1)
                }
            }

            // Endpoints (Fritsch–Carlson).
            let h0 = h[0]
            let h1 = h[1]
            let d0 = delta[0]
            let d1 = delta[1]

            if (h0 + h1) != 0.0 {
                var m0 = ((2.0 * h0 + h1) * d0 - h0 * d1) / (h0 + h1)
                if m0.sign != d0.sign { m0 = 0.0 }
                if (d0.sign != d1.sign) && abs(m0) > abs(3.0 * d0) { m0 = 3.0 * d0 }
                m[0] = m0
            }

            let hn1 = h[n - 2]
            let hn2 = h[n - 3]
            let dn1 = delta[n - 2]
            let dn2 = delta[n - 3]

            if (hn1 + hn2) != 0.0 {
                var mn = ((2.0 * hn1 + hn2) * dn1 - hn1 * dn2) / (hn1 + hn2)
                if mn.sign != dn1.sign { mn = 0.0 }
                if (dn1.sign != dn2.sign) && abs(mn) > abs(3.0 * dn1) { mn = 3.0 * dn1 }
                m[n - 1] = mn
            }
        }

        for i in 0..<(n - 1) {
            let p0 = pts[i]
            let p1 = pts[i + 1]
            let dx = p1.x - p0.x

            let c1 = CGPoint(x: p0.x + dx / 3.0, y: p0.y + m[i] * dx / 3.0)
            let c2 = CGPoint(x: p1.x - dx / 3.0, y: p1.y - m[i + 1] * dx / 3.0)

            p.addCurve(to: p1, control1: c1, control2: c2)
        }

        return p
    }

    static func buildCoreFillPath(baselineY: CGFloat, curvePoints: [CGPoint]) -> Path {
        // curvePoints are expected to start and end on the baseline.
        var p = buildCurveStrokePath(curvePoints: curvePoints)
        p.closeSubpath()
        return p
    }
}

// MARK: - Maths

extension RainForecastSurfaceRenderer {
    static func clamp01(_ x: Double) -> Double { max(0.0, min(1.0, x)) }
    static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * clamp01(t) }
}

// MARK: - Colour blend helper

private extension Color {
    static func blend(_ a: Color, _ b: Color, t: Double) -> Color {
        #if canImport(UIKit)
        let ta = RainForecastSurfaceRenderer.clamp01(t)
        let ua = UIKit.UIColor(a)
        let ub = UIKit.UIColor(b)

        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0

        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)

        let r = ar + (br - ar) * CGFloat(ta)
        let g = ag + (bg - ag) * CGFloat(ta)
        let bV = ab + (bb - ab) * CGFloat(ta)
        let aOut = aa + (ba - aa) * CGFloat(ta)

        return Color(red: Double(r), green: Double(g), blue: Double(bV)).opacity(Double(aOut))
        #else
        return a
        #endif
    }
}
