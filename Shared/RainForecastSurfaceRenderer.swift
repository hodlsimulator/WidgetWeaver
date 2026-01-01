//
//  RainForecastSurfaceRenderer.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Draws the nowcast “rain surface” into a SwiftUI Canvas.
//  Core shape is a filled ribbon with optional rim + fuzz layers.
//

import Foundation
import SwiftUI
import CoreGraphics

struct RainForecastSurfaceRenderer {

    private let intensitiesMMPerHour: [Double]
    private let certainties01: [Double]
    private let cfg: RainForecastSurfaceConfiguration

    init(intensities: [Double], certainties: [Double], configuration: RainForecastSurfaceConfiguration) {
        self.intensitiesMMPerHour = intensities
        self.certainties01 = certainties.map { Self.clamp01($0) }
        self.cfg = configuration
    }

    init(intensities: [Double], certainties: [Double?], configuration: RainForecastSurfaceConfiguration) {
        self.intensitiesMMPerHour = intensities
        self.certainties01 = certainties.map { Self.clamp01($0 ?? 0.0) }
        self.cfg = configuration
    }

    func render(in context: inout GraphicsContext, rect: CGRect, displayScale ds: CGFloat) {
        guard rect.width > 1, rect.height > 1 else { return }

        let n0 = max(1, cfg.sourceMinuteCount)
        let sourceCount = max(1, min(n0, intensitiesMMPerHour.count))

        let raw = Array(intensitiesMMPerHour.prefix(sourceCount)).map { max(0.0, $0.isFinite ? $0 : 0.0) }
        let certs = Array(certainties01.prefix(sourceCount)).map { Self.clamp01($0) }

        let referenceMax = Self.robustReferenceMaxMMPerHour(
            values: raw,
            defaultMax: max(0.1, cfg.intensityReferenceMaxMMPerHour),
            percentile: cfg.robustMaxPercentile
        )

        let scaled = raw.map { v -> CGFloat in
            guard referenceMax > 0 else { return 0 }
            let x = max(0.0, min(1.0, v / referenceMax))
            let g = max(0.05, cfg.intensityGamma)
            let y = pow(x, g)
            return CGFloat(y)
        }

        let denseCount = Self.denseSampleCount(
            sourceCount: sourceCount,
            rectWidthPoints: rect.width,
            displayScale: ds,
            maxDense: cfg.maxDenseSamples
        )

        let denseHeights01 = Self.resampleDense(values01: scaled, denseCount: denseCount)
        let denseCerts01 = Self.resampleDense(values01: certs.map { CGFloat($0) }, denseCount: denseCount)

        let baselineY = rect.minY + rect.height * CGFloat(cfg.baselineFractionFromTop)
        let topHeadroom = rect.height * CGFloat(max(0.0, cfg.topHeadroomFraction))

        // Normalise heights into points.
        let maxHeightPt = max(1.0, baselineY - (rect.minY + topHeadroom))
        let heights: [CGFloat] = denseHeights01.map { h01 in
            max(0.0, min(maxHeightPt, h01 * maxHeightPt))
        }

        let wetThresholdPt: CGFloat = 0.25
        let segments = Self.buildWetSegments(
            rect: rect,
            baselineY: baselineY,
            heights: heights,
            certainties01: denseCerts01,
            wetThreshold: wetThresholdPt
        )

        if segments.isEmpty {
            if cfg.baselineEnabled {
                Self.drawBaseline(in: &context, rect: rect, baselineY: baselineY, displayScale: ds, cfg: cfg)
            }
            return
        }

        for seg in segments {
            let curvePoints = seg.curvePoints
            let heights = seg.heights
            let certainties01 = seg.certainties01

            let corePath = Self.buildCoreFillPath(curvePoints: curvePoints)

            Self.drawCore(in: &context, corePath: corePath, curvePoints: curvePoints, baselineY: baselineY, cfg: cfg)

            if cfg.fuzzEnabled && cfg.canEnableFuzz && cfg.fuzzTextureEnabled {
                let bandHalfWidth = Self.computeBandHalfWidth(rect: rect, displayScale: ds, cfg: cfg)

                var effectiveCorePath = corePath
                if cfg.fuzzSolidCoreEnabled {
                    let inset = Self.computeSolidCoreInset(
                        bandHalfWidth: bandHalfWidth,
                        heights: heights,
                        displayScale: ds,
                        configuration: cfg
                    )
                    if inset > 0.0 {
                        effectiveCorePath = Self.buildSolidCoreFillPath(
                            curvePoints: curvePoints,
                            baselineY: baselineY,
                            inset: inset
                        )
                    }
                }

                Self.drawDissipationFuzz(
                    in: &context,
                    rect: rect,
                    baselineY: baselineY,
                    corePath: effectiveCorePath,
                    curvePoints: curvePoints,
                    heights: heights,
                    certainties01: certainties01,
                    bandHalfWidth: bandHalfWidth,
                    displayScale: ds,
                    configuration: cfg
                )
            }

            if cfg.rimEnabled {
                Self.drawRim(in: &context, curvePoints: curvePoints, baselineY: baselineY, displayScale: ds, cfg: cfg)
            }
        }

        if cfg.baselineEnabled {
            Self.drawBaseline(in: &context, rect: rect, baselineY: baselineY, displayScale: ds, cfg: cfg)
        }
    }

    // MARK: - Segment building

    struct SurfaceSegment: Hashable {
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

        // Find contiguous wet runs.
        var runs: [(start: Int, end: Int)] = []
        runs.reserveCapacity(4)

        var runStart: Int? = nil
        for i in 0..<n {
            if isWet(i) {
                if runStart == nil { runStart = i }
            } else if let start = runStart {
                runs.append((start: start, end: i - 1))
                runStart = nil
            }
        }

        if let start = runStart {
            runs.append((start: start, end: n - 1))
        }

        guard !runs.isEmpty else { return [] }

        // Per-segment tapering avoids the “cliff” at rain start/end without affecting true
        // rain-now / rain-at-60m scenarios.
        let targetTaperPt = max(10.0, min(rect.width * 0.05, 26.0))

        var segments: [SurfaceSegment] = []
        segments.reserveCapacity(runs.count)

        for r in 0..<runs.count {
            let run = runs[r]

            let leftDryCount: Int
            if r == 0 {
                leftDryCount = run.start
            } else {
                leftDryCount = max(0, run.start - (runs[r - 1].end + 1))
            }

            let rightDryCount: Int
            if r == runs.count - 1 {
                rightDryCount = max(0, (n - 1) - run.end)
            } else {
                rightDryCount = max(0, runs[r + 1].start - (run.end + 1))
            }

            let leftExtendPt = min(targetTaperPt, CGFloat(leftDryCount) * stepX)
            let rightExtendPt = min(targetTaperPt, CGFloat(rightDryCount) * stepX)

            if let seg = makeSegment(
                rect: rect,
                baselineY: baselineY,
                start: run.start,
                end: run.end,
                stepX: stepX,
                xMid: xMid,
                heights: heights,
                certainties01: certainties01,
                leftExtendPt: leftExtendPt,
                rightExtendPt: rightExtendPt
            ) {
                segments.append(seg)
            }
        }

        return segments
    }

    static func makeSegment(
        rect: CGRect,
        baselineY: CGFloat,
        start: Int,
        end: Int,
        stepX: CGFloat,
        xMid: (Int) -> CGFloat,
        heights: [CGFloat],
        certainties01: [CGFloat],
        leftExtendPt: CGFloat,
        rightExtendPt: CGFloat
    ) -> SurfaceSegment? {
        guard start >= 0, end >= start else { return nil }
        guard end < heights.count, end < certainties01.count else { return nil }

        let runLeftX = rect.minX + CGFloat(start) * stepX
        let runRightX = rect.minX + CGFloat(end + 1) * stepX

        let minX = max(rect.minX, min(runLeftX - max(0.0, leftExtendPt), rect.maxX))
        let maxX = min(rect.maxX, max(runRightX + max(0.0, rightExtendPt), rect.minX))

        if maxX <= minX + 0.0001 {
            return nil
        }

        let c0 = certainties01[start]
        let c1 = certainties01[end]

        let firstH = max(0.0, heights[start])
        let lastH = max(0.0, heights[end])

        let startSampleX = xMid(start)
        let endSampleX = xMid(end)

        var pts: [CGPoint] = []
        var hs: [CGFloat] = []
        var cs: [CGFloat] = []

        // Baseline start.
        pts.append(CGPoint(x: minX, y: baselineY))
        hs.append(0.0)
        cs.append(c0)

        // Left taper (baseline -> first height).
        if leftExtendPt > 0.5, startSampleX > minX + 0.5 {
            let span = max(0.0, startSampleX - minX)
            if span > 0.5 {
                pts.append(CGPoint(x: minX + span * 0.35, y: baselineY - firstH * 0.22))
                hs.append(firstH * 0.22)
                cs.append(c0)

                pts.append(CGPoint(x: minX + span * 0.70, y: baselineY - firstH * 0.68))
                hs.append(firstH * 0.68)
                cs.append(c0)
            }
        }

        // Sample points.
        for i in start...end {
            pts.append(CGPoint(x: xMid(i), y: baselineY - heights[i]))
            hs.append(heights[i])
            cs.append(certainties01[i])
        }

        // Right taper (last height -> baseline).
        if rightExtendPt > 0.5, maxX > endSampleX + 0.5 {
            let span = max(0.0, maxX - endSampleX)
            if span > 0.5 {
                pts.append(CGPoint(x: endSampleX + span * 0.30, y: baselineY - lastH * 0.70))
                hs.append(lastH * 0.70)
                cs.append(c1)

                pts.append(CGPoint(x: endSampleX + span * 0.65, y: baselineY - lastH * 0.24))
                hs.append(lastH * 0.24)
                cs.append(c1)
            }
        }

        // Baseline end.
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

    static func computeSolidCoreInset(
        bandHalfWidth: CGFloat,
        heights: [CGFloat],
        displayScale ds: CGFloat,
        configuration cfg: RainForecastSurfaceConfiguration
    ) -> CGFloat {
        guard cfg.fuzzSolidCoreEnabled else { return 0.0 }

        let hMax = max(0.0, heights.max() ?? 0.0)
        if hMax <= 0.001 { return 0.0 }

        let mul = max(0.0, cfg.fuzzSolidCoreInsetBandMultiplier)
        let minInset = max(0.0, cfg.fuzzSolidCoreMinInsetPixels) / max(1.0, ds)

        let peakFrac = max(0.0, min(1.0, cfg.fuzzSolidCoreInsetPeakFraction))
        let peakInset = hMax * CGFloat(peakFrac)

        let bandInset = bandHalfWidth * CGFloat(mul)

        return max(minInset, min(peakInset, bandInset))
    }

    static func buildSolidCoreFillPath(curvePoints: [CGPoint], baselineY: CGFloat, inset: CGFloat) -> Path {
        guard curvePoints.count >= 2 else { return Path() }

        // Keep endpoints anchored to the baseline.
        var pts = curvePoints
        pts[0].y = baselineY
        pts[pts.count - 1].y = baselineY

        for i in 1..<(pts.count - 1) {
            let y = pts[i].y
            let clamped = min(baselineY, y + inset)
            pts[i].y = clamped
        }

        return buildCoreFillPath(curvePoints: pts)
    }

    // MARK: - Core + strokes

    static func buildCoreFillPath(curvePoints: [CGPoint]) -> Path {
        var p = buildCurveStrokePath(curvePoints: curvePoints)
        p.closeSubpath()
        return p
    }

    static func buildCurveStrokePath(curvePoints: [CGPoint]) -> Path {
        guard curvePoints.count >= 2 else { return Path() }

        let pts = curvePoints
        let n = pts.count

        // Monotone cubic interpolation in x (gives “Weather app” smoothness without overshoot).
        // Compute slopes (dy/dx) at each point.
        var dx = [CGFloat](repeating: 0.0, count: n - 1)
        var dy = [CGFloat](repeating: 0.0, count: n - 1)
        var m = [CGFloat](repeating: 0.0, count: n - 1)

        for i in 0..<(n - 1) {
            dx[i] = pts[i + 1].x - pts[i].x
            dy[i] = pts[i + 1].y - pts[i].y
            m[i] = (dx[i] != 0.0) ? (dy[i] / dx[i]) : 0.0
        }

        var tangents = [CGFloat](repeating: 0.0, count: n)
        tangents[0] = m[0]
        tangents[n - 1] = m[n - 2]

        if n > 2 {
            for i in 1..<(n - 1) {
                if m[i - 1] * m[i] <= 0 {
                    tangents[i] = 0
                } else {
                    let w1 = 2 * dx[i] + dx[i - 1]
                    let w2 = dx[i] + 2 * dx[i - 1]
                    tangents[i] = (w1 + w2) / (w1 / m[i - 1] + w2 / m[i])
                }
            }
        }

        // Clamp to avoid overshoot.
        for i in 0..<(n - 1) {
            if m[i] == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
            } else {
                let a = tangents[i] / m[i]
                let b = tangents[i + 1] / m[i]
                let s = a * a + b * b
                if s > 9 {
                    let t = 3 / sqrt(s)
                    tangents[i] = t * a * m[i]
                    tangents[i + 1] = t * b * m[i]
                }
            }
        }

        var path = Path()
        path.move(to: pts[0])

        for i in 0..<(n - 1) {
            let p0 = pts[i]
            let p1 = pts[i + 1]
            let h = dx[i] / 3

            let c1 = CGPoint(x: p0.x + h, y: p0.y + tangents[i] * h)
            let c2 = CGPoint(x: p1.x - h, y: p1.y - tangents[i + 1] * h)

            path.addCurve(to: p1, control1: c1, control2: c2)
        }

        return path
    }

    static func drawCore(in context: inout GraphicsContext, corePath: Path, curvePoints: [CGPoint], baselineY: CGFloat, cfg: RainForecastSurfaceConfiguration) {
        let startX = curvePoints.first?.x ?? 0
        let endX = curvePoints.last?.x ?? 1

        let topMix = max(0.0, min(1.0, cfg.coreTopMix))
        let fadeFrac = max(0.0, min(1.0, cfg.coreFadeFraction))

        let grad = Gradient(stops: [
            .init(color: cfg.coreTopColor.opacity(topMix), location: 0.0),
            .init(color: cfg.coreBodyColor.opacity(1.0), location: max(0.0, 1.0 - fadeFrac))
        ])

        let shading = GraphicsContext.Shading.linearGradient(
            grad,
            startPoint: CGPoint(x: startX, y: baselineY),
            endPoint: CGPoint(x: endX, y: baselineY - 500)
        )

        context.fill(corePath, with: shading)
    }

    static func drawRim(in context: inout GraphicsContext, curvePoints: [CGPoint], baselineY: CGFloat, displayScale ds: CGFloat, cfg: RainForecastSurfaceConfiguration) {
        let w = max(0.5, cfg.rimWidthPixels) / max(1.0, ds)
        let p = buildCurveStrokePath(curvePoints: curvePoints)

        context.stroke(
            p,
            with: .color(cfg.rimColor.opacity(cfg.rimOpacity)),
            style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round)
        )
    }

    static func drawBaseline(in context: inout GraphicsContext, rect: CGRect, baselineY: CGFloat, displayScale ds: CGFloat, cfg: RainForecastSurfaceConfiguration) {
        let w = max(0.5, cfg.baselineWidthPixels) / max(1.0, ds)
        let y = baselineY + (cfg.baselineOffsetPixels / max(1.0, ds))

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: y))
        p.addLine(to: CGPoint(x: rect.maxX, y: y))

        context.stroke(p, with: .color(cfg.baselineColor.opacity(cfg.baselineLineOpacity)), style: StrokeStyle(lineWidth: w))
    }

    // MARK: - Utilities

    static func computeBandHalfWidth(rect: CGRect, displayScale ds: CGFloat, cfg: RainForecastSurfaceConfiguration) -> CGFloat {
        let frac = max(0.0, cfg.fuzzWidthFraction)
        let w0 = rect.height * CGFloat(frac)

        let minPx = cfg.fuzzWidthPixelsClamp.lowerBound / max(1.0, ds)
        let maxPx = cfg.fuzzWidthPixelsClamp.upperBound / max(1.0, ds)

        return max(CGFloat(minPx), min(CGFloat(maxPx), w0))
    }

    static func resampleDense(values01: [CGFloat], denseCount: Int) -> [CGFloat] {
        let n = values01.count
        guard n > 0 else { return [] }
        guard denseCount > 0 else { return [] }
        if denseCount == n { return values01 }

        var out = [CGFloat](repeating: 0.0, count: denseCount)

        if n == 1 {
            out = [CGFloat](repeating: values01[0], count: denseCount)
            return out
        }

        for i in 0..<denseCount {
            let t = CGFloat(i) / CGFloat(denseCount - 1)
            let x = t * CGFloat(n - 1)
            let x0 = Int(floor(x))
            let x1 = min(n - 1, x0 + 1)
            let frac = x - CGFloat(x0)
            let v0 = values01[x0]
            let v1 = values01[x1]
            out[i] = v0 + (v1 - v0) * frac
        }

        return out
    }

    static func clamp01(_ x: Double) -> Double {
        max(0.0, min(1.0, x.isFinite ? x : 0.0))
    }
}
