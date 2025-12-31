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

        minuteHeights = Self.applyEdgeEasing(
            values: minuteHeights,
            fraction: cfg.edgeEasingFraction,
            power: cfg.edgeEasingPower
        )

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

        var denseHeights = Self.resampleLinear(minuteHeights, toCount: denseCount)
        let denseCertainties = Self.resampleLinear(minuteCertainties, toCount: denseCount)

        denseHeights = Self.smooth(values: denseHeights, radius: max(1, Int(round(Double(ds) * 1.5))))

        let curvePoints = Self.makeCurvePoints(rect: chartRect, baselineY: baselineY, heights: denseHeights)

        let corePath = Self.buildCoreFillPath(
            rect: chartRect,
            baselineY: baselineY,
            curvePoints: curvePoints
        )

        Self.drawCore(
            in: &context,
            corePath: corePath,
            curvePoints: curvePoints,
            baselineY: baselineY,
            configuration: cfg
        )

        Self.drawRim(
            in: &context,
            curvePoints: curvePoints,
            configuration: cfg,
            displayScale: ds
        )

        if cfg.fuzzEnabled, cfg.canEnableFuzz, cfg.fuzzTextureEnabled {
            let bandHalfWidth = Self.computeBandHalfWidthPoints(rect: chartRect, displayScale: ds, configuration: cfg)
            if bandHalfWidth > onePx * 0.5 {
                Self.drawDissipationFuzz(
                    in: &context,
                    rect: chartRect,
                    baselineY: baselineY,
                    corePath: corePath,
                    curvePoints: curvePoints,
                    heights: denseHeights,
                    certainties01: denseCertainties,
                    bandHalfWidth: bandHalfWidth,
                    displayScale: ds,
                    configuration: cfg
                )
            }
        }

        Self.drawBaseline(in: &context, chartRect: chartRect, baselineY: baselineY, configuration: cfg, displayScale: ds)
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

    static func makeCurvePoints(rect: CGRect, baselineY: CGFloat, heights: [CGFloat]) -> [CGPoint] {
        let n = max(2, heights.count)
        let dx = rect.width / CGFloat(max(1, n - 1))

        var pts: [CGPoint] = []
        pts.reserveCapacity(n)

        for i in 0..<n {
            let x = rect.minX + CGFloat(i) * dx
            let y = baselineY - heights[i]
            pts.append(CGPoint(x: x, y: y))
        }

        return pts
    }

    static func buildCurveStrokePath(curvePoints: [CGPoint]) -> Path {
        var p = Path()
        guard let first = curvePoints.first else { return p }
        p.move(to: first)
        for pt in curvePoints.dropFirst() {
            p.addLine(to: pt)
        }
        return p
    }

    static func buildCoreFillPath(rect: CGRect, baselineY: CGFloat, curvePoints: [CGPoint]) -> Path {
        var p = Path()
        guard let first = curvePoints.first, let last = curvePoints.last else { return p }

        p.move(to: CGPoint(x: first.x, y: baselineY))
        p.addLine(to: first)
        for pt in curvePoints.dropFirst() { p.addLine(to: pt) }
        p.addLine(to: CGPoint(x: last.x, y: baselineY))
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
