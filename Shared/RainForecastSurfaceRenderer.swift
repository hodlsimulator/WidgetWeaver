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

        let onePx: CGFloat = 1.0 / max(1.0, ds)
        let wetThresholdPt: CGFloat = onePx * 0.85
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

                Self.drawDissipationFuzz(
                    in: &context,
                    rect: rect,
                    baselineY: baselineY,
                    // Tile shading should reach the actual surface contour.
                    // Passing an inset “solid core” path leaves an untextured band that reads like
                    // a second, flat surface layer.
                    corePath: corePath,
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

        // Peak highlight/glint (drawn after all segments so it stays on top).
        if cfg.glossEnabled || cfg.glintEnabled {
            if let peak = Self.peakPoint(segments: segments, baselineY: baselineY) {
                Self.drawPeakHighlights(in: &context, peak: peak, baselineY: baselineY, displayScale: ds, cfg: cfg)
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
        //
        // IMPORTANT:
        // When there are multiple wet runs separated by short dry gaps, tapering both runs by the full
        // available gap width causes the two segments to overlap. That overlap is drawn twice and reads
        // as an internal “crease” (like a second surface) inside the body.
        //
        // Fix: allocate at most half of the inter-run gap to each side.
        let targetTaperPt = max(12.0, min(rect.width * 0.08, 48.0))

        var leftExtendForRun = [CGFloat](repeating: 0.0, count: runs.count)
        var rightExtendForRun = [CGFloat](repeating: 0.0, count: runs.count)

        for r in 0..<runs.count {
            let run = runs[r]

            // Leading dry region (before first run) can take the full taper.
            if r == 0 {
                let dryCount = max(0, run.start)
                leftExtendForRun[r] = min(targetTaperPt, CGFloat(dryCount) * stepX)
            } else {
                let prev = runs[r - 1]
                let gapCount = max(0, run.start - prev.end - 1)
                leftExtendForRun[r] = min(targetTaperPt, CGFloat(gapCount) * stepX * 0.5)
            }

            // Trailing dry region (after last run) can take the full taper.
            if r == runs.count - 1 {
                let dryCount = max(0, (n - 1) - run.end)
                rightExtendForRun[r] = min(targetTaperPt, CGFloat(dryCount) * stepX)
            } else {
                let next = runs[r + 1]
                let gapCount = max(0, next.start - run.end - 1)
                rightExtendForRun[r] = min(targetTaperPt, CGFloat(gapCount) * stepX * 0.5)
            }
        }

        var segments: [SurfaceSegment] = []
        segments.reserveCapacity(runs.count)

        for r in 0..<runs.count {
            let run = runs[r]

            let leftExtendPt = leftExtendForRun[r]
            let rightExtendPt = rightExtendForRun[r]

            let startIdx = max(0, run.start)
            let endIdx = min(n - 1, run.end)

            let minX = rect.minX + CGFloat(startIdx) * stepX - leftExtendPt
            let maxX = rect.minX + CGFloat(endIdx + 1) * stepX + rightExtendPt

            // Build sample points with baseline anchors at both ends.
            var pts: [CGPoint] = []
            var hs: [CGFloat] = []
            var cs: [CGFloat] = []

            pts.reserveCapacity((endIdx - startIdx + 1) + 4)
            hs.reserveCapacity(pts.capacity)
            cs.reserveCapacity(pts.capacity)

            let c0 = certainties01[startIdx]
            let c1 = certainties01[endIdx]

            // Baseline start.
            pts.append(CGPoint(x: minX, y: baselineY))
            hs.append(0.0)
            cs.append(c0)

            // Left taper (baseline -> first height).
            let firstX = xMid(startIdx)
            let firstH = heights[startIdx]
            if leftExtendPt > 0.5, firstX > minX + 0.5 {
                let span = max(0.0, firstX - minX)
                if span > 0.5 {
                    // Smooth “cap” so segment starts/ends do not read as cut-off cliffs.
                    let taper: [(CGFloat, CGFloat)] = [
                        (0.22, 0.08),
                        (0.48, 0.28),
                        (0.72, 0.58),
                        (0.88, 0.84),
                    ]

                    for (xf, hf) in taper {
                        let x = minX + span * xf
                        if x <= minX + 0.25 { continue }

                        pts.append(CGPoint(x: x, y: baselineY - firstH * hf))
                        hs.append(firstH * hf)
                        cs.append(c0)
                    }
                }
            }

            // Main samples.
            for i in startIdx...endIdx {
                pts.append(CGPoint(x: xMid(i), y: baselineY - heights[i]))
                hs.append(heights[i])
                cs.append(certainties01[i])
            }

            // Right taper (last height -> baseline).
            let endSampleX = xMid(endIdx)
            let lastH = heights[endIdx]
            if rightExtendPt > 0.5, maxX > endSampleX + 0.5 {
                let span = max(0.0, maxX - endSampleX)
                if span > 0.5 {
                    let taper: [(CGFloat, CGFloat)] = [
                        (0.14, 0.88),
                        (0.38, 0.62),
                        (0.63, 0.30),
                        (0.85, 0.10),
                    ]

                    for (xf, hf) in taper {
                        let x = endSampleX + span * xf
                        if x >= maxX - 0.25 { continue }

                        pts.append(CGPoint(x: x, y: baselineY - lastH * hf))
                        hs.append(lastH * hf)
                        cs.append(c1)
                    }
                }
            }

            // Baseline end.
            pts.append(CGPoint(x: maxX, y: baselineY))
            hs.append(0.0)
            cs.append(c1)

            segments.append(SurfaceSegment(
                curvePoints: pts,
                heights: hs,
                certainties01: cs,
                gradientStartX: minX,
                gradientEndX: maxX
            ))
        }

        return segments
    }

    static func peakPoint(segments: [SurfaceSegment], baselineY: CGFloat) -> CGPoint? {
        var best: CGPoint? = nil

        for seg in segments {
            if seg.curvePoints.count <= 2 { continue }

            // Skip baseline anchors (first/last).
            for i in 1..<(seg.curvePoints.count - 1) {
                let p = seg.curvePoints[i]
                if p.y >= baselineY { continue }
                if best == nil || p.y < (best?.y ?? .greatestFiniteMagnitude) {
                    best = p
                }
            }
        }

        return best
    }

    // MARK: - Sampling density / widths

    static func denseSampleCount(sourceCount: Int, rectWidthPoints: CGFloat, displayScale: CGFloat, maxDense: Int) -> Int {
        let ds = max(1.0, displayScale)
        let px = rectWidthPoints * ds
        let target = Int(px * 1.15)
        let n = max(sourceCount, min(maxDense, target))
        return max(12, n)
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

        // Convert Hermite form to Bezier segments.
        var p = Path()
        p.move(to: pts[0])

        for i in 0..<(n - 1) {
            let p0 = pts[i]
            let p1 = pts[i + 1]
            let dx = p1.x - p0.x

            let c0 = CGPoint(x: p0.x + dx / 3, y: p0.y + tangents[i] * dx / 3)
            let c1 = CGPoint(x: p1.x - dx / 3, y: p1.y - tangents[i + 1] * dx / 3)

            p.addCurve(to: p1, control1: c0, control2: c1)
        }

        return p
    }

    static func drawCore(in context: inout GraphicsContext, corePath: Path, curvePoints: [CGPoint], baselineY: CGFloat, cfg: RainForecastSurfaceConfiguration) {
        let topY = curvePoints.map { $0.y }.min() ?? (baselineY - 120.0)
        let midX = ((curvePoints.first?.x ?? 0.0) + (curvePoints.last?.x ?? 0.0)) * 0.5

        let topMix = max(0.0, min(1.0, cfg.coreTopMix))
        let fadeFrac = max(0.0, min(1.0, cfg.coreFadeFraction))

        let grad = Gradient(stops: [
            .init(color: cfg.coreTopColor.opacity(topMix), location: 0.0),
            .init(color: cfg.coreBodyColor.opacity(1.0), location: max(0.0, 1.0 - fadeFrac))
        ])

        // Vertical gradient:
        // - top uses `coreTopColor`
        // - bottom uses `coreBodyColor`
        //
        // A per-segment diagonal gradient makes segment overlaps far more visible, so keep the vector
        // purely vertical.
        let shading = GraphicsContext.Shading.linearGradient(
            grad,
            startPoint: CGPoint(x: midX, y: topY),
            endPoint: CGPoint(x: midX, y: baselineY)
        )

        context.fill(corePath, with: shading)
    }

    static func drawPeakHighlights(in context: inout GraphicsContext, peak: CGPoint, baselineY: CGFloat, displayScale ds: CGFloat, cfg: RainForecastSurfaceConfiguration) {
        let ds = max(1.0, ds)
        let onePx = 1.0 / ds

        let height = max(0.0, baselineY - peak.y)
        if height <= 0.5 { return }

        let prevBlend = context.blendMode
        let prevOpacity = context.opacity
        context.blendMode = .plusLighter
        context.opacity = 1.0

        // Soft glow (cyan/blue) around the peak.
        if cfg.glossEnabled, cfg.glossMaxOpacity > 0.0001 {
            let a = clamp01(cfg.glossMaxOpacity)
            let r0 = max(10.0 * onePx, min(height * 0.22, 90.0 * onePx))
            let r1 = max(r0, r0 * 1.35)

            let glowGradient = Gradient(stops: [
                .init(color: cfg.coreTopColor.opacity(a * 0.10), location: 0.0),
                .init(color: cfg.coreTopColor.opacity(a * 0.22), location: 0.30),
                .init(color: Color.white.opacity(a * 0.20), location: 0.42),
                .init(color: cfg.coreTopColor.opacity(a * 0.10), location: 0.62),
                .init(color: Color.white.opacity(0.0), location: 1.0)
            ])

            let shading = GraphicsContext.Shading.radialGradient(
                glowGradient,
                center: CGPoint(x: peak.x, y: peak.y - r0 * 0.05),
                startRadius: 0.0,
                endRadius: r1
            )

            context.fill(
                Path(ellipseIn: CGRect(x: peak.x - r1, y: peak.y - r1, width: r1 * 2, height: r1 * 2)),
                with: shading
            )
        }

        // Glint (tight white highlight).
        if cfg.glintEnabled, cfg.glintMaxOpacity > 0.0001 {
            let a = clamp01(cfg.glintMaxOpacity)
            let minR = max(onePx, CGFloat(cfg.glintRadiusPixels.lowerBound) / ds)
            let maxR = max(minR, CGFloat(cfg.glintRadiusPixels.upperBound) / ds)
            let r = maxR

            let glintGradient = Gradient(stops: [
                .init(color: Color.white.opacity(a), location: 0.0),
                .init(color: Color.white.opacity(a * 0.85), location: 0.18),
                .init(color: cfg.coreTopColor.opacity(a * 0.40), location: 0.42),
                .init(color: Color.white.opacity(0.0), location: 1.0)
            ])

            let q = CGPoint(x: peak.x, y: peak.y - r * 0.18)
            let shading = GraphicsContext.Shading.radialGradient(
                glintGradient,
                center: q,
                startRadius: 0.0,
                endRadius: r
            )

            context.fill(
                Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: r * 2, height: r * 2)),
                with: shading
            )
        }

        context.blendMode = prevBlend
        context.opacity = prevOpacity
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
