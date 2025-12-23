//
//  WidgetWeaverWeatherTemplateComponents.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//
//  UI components for the weather template.
//
//  NOTE ABOUT MINUTE-BY-MINUTE CONSISTENCY
//  --------------------------------------
//  The chart must not invent “wet” pixels when the nowcast model says it is dry.
//  Rendering must be driven by `WeatherNowcast.isWet(...)` to keep the chart aligned
//  with the headline text as the widget ticks every minute.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Render context environment

private struct WidgetWeaverRenderContextEnvironmentKey: EnvironmentKey {
    static let defaultValue: WidgetWeaverRenderContext = .preview
}

extension EnvironmentValues {
    var wwRenderContext: WidgetWeaverRenderContext {
        get { self[WidgetWeaverRenderContextEnvironmentKey.self] }
        set { self[WidgetWeaverRenderContextEnvironmentKey.self] = newValue }
    }
}

// MARK: - Widget-safe “glass” background
//
// WidgetKit can render Material as black on the Home Screen (especially after snapshotting).
// This view uses a stable translucent fill for `.widget` and keeps Material for previews.

private struct WeatherGlassBackground: View {
    let cornerRadius: CGFloat

    @Environment(\.wwRenderContext) private var renderContext
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        switch renderContext {
        case .widget:
            shape.fill(fallbackFill)
        case .preview, .simulator:
            shape.fill(.ultraThinMaterial)
        }
    }

    private var fallbackFill: Color {
        // Light mode: a little dark tint.
        // Dark mode: a little light tint.
        if colorScheme == .dark {
            return Color.white.opacity(0.11)
        } else {
            return Color.black.opacity(0.07)
        }
    }
}

// MARK: - Chart

struct WeatherNowcastChart: View {
    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool

    var body: some View {
        GeometryReader { _ in
            let plotInset: CGFloat = 10

            ZStack(alignment: .bottomLeading) {
                WeatherGlassBackground(cornerRadius: 10)

                if points.isEmpty {
                    Text("—")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    WeatherNowcastBandPlot(
                        samples: WeatherNowcastBandPlot.samples(from: points, targetMinutes: 60),
                        maxIntensityMMPerHour: maxIntensityMMPerHour,
                        accent: accent
                    )
                    .padding(.horizontal, plotInset)
                    .padding(.vertical, plotInset)
                }

                if showAxisLabels {
                    WeatherNowcastAxisLabels()
                }
            }
        }
    }
}

private struct WeatherNowcastAxisLabels: View {
    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack {
                Text("Now")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("60m")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}

private struct WeatherNowcastBandPlot: View {
    /// One sample per minute (target: 60). Wet/dry is driven only by intensity via `WeatherNowcast.isWet`.
    ///
    /// One-sided “Core + Halo” ribbon:
    /// - Baseline = dry reference (always present)
    /// - Core ribbon = expected intensity (height + saturation/brightness)
    /// - Halo = uncertainty envelope (extra height + grey drift + blur)
    ///
    /// Rendering must never imply “below zero” rain. The ribbon only extends upward from the baseline.
    struct Sample: Hashable {
        var intensityMMPerHour: Double
        var chance01: Double
    }

    let samples: [Sample] // exactly 60 samples, padded
    let maxIntensityMMPerHour: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let n = max(1, samples.count)
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)

            // Place the baseline low so the ribbon reads as “above zero”.
            let baselineY = h * 0.82
            let stepX = w / CGFloat(n)

            let wetMask: [Bool] = samples.map { WeatherNowcast.isWet(intensityMMPerHour: $0.intensityMMPerHour) }
            let wetRanges = wetRanges(from: wetMask)
            let hasAnyWet = !wetRanges.isEmpty

            let coreHeights = coreHeights(
                plotSize: geo.size,
                baselineY: baselineY,
                wetMask: wetMask
            )

            let haloHeights = haloHeights(
                plotSize: geo.size,
                baselineY: baselineY,
                wetMask: wetMask,
                coreHeights: coreHeights
            )

            let coreStops = gradientStops(
                wetMask: wetMask,
                colourForIndex: { i in
                    let s = samples[i]
                    return coreColour(
                        accent: accent,
                        intensityFraction01: intensityFraction(for: s),
                        chance01: s.chance01,
                        uncertainty01: uncertainty01(forChance: s.chance01)
                    )
                }
            )

            let haloStops = gradientStops(
                wetMask: wetMask,
                colourForIndex: { i in
                    let s = samples[i]
                    return haloColour(
                        accent: accent,
                        intensityFraction01: intensityFraction(for: s),
                        chance01: s.chance01,
                        uncertainty01: uncertainty01(forChance: s.chance01)
                    )
                }
            )

            let coreGradient = LinearGradient(
                gradient: Gradient(stops: coreStops),
                startPoint: .leading,
                endPoint: .trailing
            )

            let haloGradient = LinearGradient(
                gradient: Gradient(stops: haloStops),
                startPoint: .leading,
                endPoint: .trailing
            )

            ZStack(alignment: .topLeading) {
                if hasAnyWet {
                    // Halo: uncertainty envelope (grey drift + blur).
                    ForEach(wetRanges, id: \.self) { r in
                        let x0 = CGFloat(r.lowerBound) * stepX
                        let x1 = CGFloat(r.upperBound) * stepX

                        Rectangle()
                            .fill(haloGradient)
                            .mask(
                                ribbonPath(
                                    size: geo.size,
                                    baselineY: baselineY,
                                    heights: haloHeights,
                                    range: r
                                )
                                .fill(Color.white)
                            )
                            .opacity(0.55)
                            .blur(radius: 6.5)
                            .mask(rangeMask(x0: x0, x1: x1, baselineY: baselineY))
                    }

                    // Core: expected intensity.
                    ForEach(wetRanges, id: \.self) { r in
                        let x0 = CGFloat(r.lowerBound) * stepX
                        let x1 = CGFloat(r.upperBound) * stepX

                        Rectangle()
                            .fill(coreGradient)
                            .mask(
                                ribbonPath(
                                    size: geo.size,
                                    baselineY: baselineY,
                                    heights: coreHeights,
                                    range: r
                                )
                                .fill(Color.white)
                            )
                            .opacity(0.95)
                            .blur(radius: 0.8)
                            .mask(rangeMask(x0: x0, x1: x1, baselineY: baselineY))
                    }

                    // Subtle top-edge highlight to keep it readable at a glance.
                    ForEach(wetRanges, id: \.self) { r in
                        let x0 = CGFloat(r.lowerBound) * stepX
                        let x1 = CGFloat(r.upperBound) * stepX

                        topEdgePath(
                            size: geo.size,
                            baselineY: baselineY,
                            heights: coreHeights,
                            range: r
                        )
                        .stroke(
                            Color.white.opacity(0.08),
                            style: StrokeStyle(
                                lineWidth: 1,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                        .mask(rangeMask(x0: x0, x1: x1, baselineY: baselineY))
                    }
                }

                // Baseline “dry” guide (always present).
                Path { p in
                    p.move(to: CGPoint(x: 0, y: baselineY))
                    p.addLine(to: CGPoint(x: w, y: baselineY))
                }
                .stroke(Color.white.opacity(0.12), lineWidth: 1)

                // “Now” marker (subtle, left edge).
                Path { p in
                    let lineTop = max(0, baselineY - (h * 0.72))
                    p.move(to: CGPoint(x: 0.5, y: lineTop))
                    p.addLine(to: CGPoint(x: 0.5, y: baselineY))
                }
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
            }
            .compositingGroup()
        }
    }

    private func rangeMask(x0: CGFloat, x1: CGFloat, baselineY: CGFloat) -> some View {
        Rectangle()
            .frame(width: max(0, x1 - x0), height: max(0, baselineY))
            .offset(x: x0, y: 0)
    }

    // MARK: - Data shaping

    static func samples(from points: [WidgetWeaverWeatherMinutePoint], targetMinutes: Int) -> [Sample] {
        let clipped = Array(points.prefix(targetMinutes))

        var out: [Sample] = []
        out.reserveCapacity(targetMinutes)

        for p in clipped {
            out.append(
                Sample(
                    intensityMMPerHour: max(0.0, p.precipitationIntensityMMPerHour ?? 0.0),
                    chance01: clamp01(p.precipitationChance01 ?? 0.0)
                )
            )
        }

        if out.count < targetMinutes {
            let missing = targetMinutes - out.count
            for _ in 0..<missing {
                out.append(Sample(intensityMMPerHour: 0.0, chance01: 0.0))
            }
        }

        return out
    }

    // MARK: - Geometry / scaling

    private func intensityFraction(for sample: Sample) -> Double {
        guard maxIntensityMMPerHour > 0 else { return 0.0 }
        return clamp01(sample.intensityMMPerHour / maxIntensityMMPerHour)
    }

    private func coreHeights(plotSize: CGSize, baselineY: CGFloat, wetMask: [Bool]) -> [CGFloat] {
        let h = max(1, plotSize.height)
        let available = max(1, baselineY - 2)

        // Tuning knobs:
        let minH = max(1, h * 0.065)             // drizzle visibility floor
        let maxH = min(available, h * 0.62)      // intensity ceiling

        return samples.enumerated().map { (i, s) in
            guard wetMask[i] else { return 0 }
            let frac = CGFloat(intensityFraction(for: s))
            let core = minH + frac * (maxH - minH)
            return min(core, available)
        }
    }

    private func haloHeights(
        plotSize: CGSize,
        baselineY: CGFloat,
        wetMask: [Bool],
        coreHeights: [CGFloat]
    ) -> [CGFloat] {
        let h = max(1, plotSize.height)
        let available = max(1, baselineY - 2)

        // Tuning knobs:
        let maxExtra = min(available * 0.35, h * 0.26)

        return coreHeights.indices.map { i in
            guard wetMask[i] else { return 0 }
            let u = CGFloat(uncertainty01(forChance: samples[i].chance01))
            let extra = u * maxExtra
            return min(coreHeights[i] + extra, available)
        }
    }

    private func wetRanges(from wetMask: [Bool]) -> [Range<Int>] {
        guard !wetMask.isEmpty else { return [] }

        var ranges: [Range<Int>] = []
        var currentStart: Int? = nil

        for i in wetMask.indices {
            if wetMask[i] {
                if currentStart == nil { currentStart = i }
            } else {
                if let s = currentStart {
                    ranges.append(s..<i)
                    currentStart = nil
                }
            }
        }

        if let s = currentStart {
            ranges.append(s..<wetMask.endIndex)
        }

        return ranges.filter { !$0.isEmpty }
    }

    // MARK: - Colour encoding

    private func uncertainty01(forChance chance01: Double) -> Double {
        // Interpret “confidence” as chance, and “uncertainty” as the inverse.
        // Used only for halo/grey drift; wet/dry is still driven by intensity alone.
        clamp01(1.0 - chance01)
    }

    private func coreColour(
        accent: Color,
        intensityFraction01: Double,
        chance01: Double,
        uncertainty01: Double
    ) -> Color {
        // Intensity: darker → brighter
        // Uncertainty: drift towards grey
        // Chance: influences alpha only (does not create/erase wet pixels)

        let i = clamp01(intensityFraction01)
        let u = clamp01(uncertainty01)
        let c = clamp01(chance01)

        let darken = CGFloat(0.65 * (1.0 - i))
        let desaturate = CGFloat(0.18 * (1.0 - i))
        let driftGrey = CGFloat(0.55 * u)
        let lighten = CGFloat(0.12 * i)

        var colour = accent
            .wwBlended(with: .black, amount: darken)
            .wwBlended(with: .gray, amount: desaturate)
            .wwBlended(with: .gray, amount: driftGrey)
            .wwBlended(with: .white, amount: lighten)

        let alpha = 0.22 + 0.78 * c
        colour = colour.opacity(alpha)

        return colour
    }

    private func haloColour(
        accent: Color,
        intensityFraction01: Double,
        chance01: Double,
        uncertainty01: Double
    ) -> Color {
        let i = clamp01(intensityFraction01)
        let u = clamp01(uncertainty01)
        let c = clamp01(chance01)

        let darken = CGFloat(0.75 * (1.0 - i))
        let driftGrey = CGFloat(0.75 * u)
        let lighten = CGFloat(0.08 * i)

        var colour = accent
            .wwBlended(with: .black, amount: darken)
            .wwBlended(with: .gray, amount: driftGrey)
            .wwBlended(with: .white, amount: lighten)

        let alpha = (0.10 + 0.35 * c) * (0.35 + 0.65 * (1.0 - u))
        colour = colour.opacity(alpha)

        return colour
    }

    private func gradientStops(wetMask: [Bool], colourForIndex: (Int) -> Color) -> [Gradient.Stop] {
        let n = max(1, samples.count)
        if n == 1 {
            return [.init(color: colourForIndex(0), location: 0)]
        }

        return (0..<n).map { i in
            let isWet = wetMask[i]
            let base = colourForIndex(i)
            let colour = isWet ? base : base.opacity(0.0)
            return Gradient.Stop(color: colour, location: Double(i) / Double(n - 1))
        }
    }

    // MARK: - Path (smoothed ribbon)

    private func ribbonPath(size: CGSize, baselineY: CGFloat, heights: [CGFloat], range: Range<Int>) -> Path {
        let n = max(1, heights.count)
        let w = max(1, size.width)
        let stepX = w / CGFloat(n)

        let clampedLower = max(0, min(n - 1, range.lowerBound))
        let clampedUpper = max(clampedLower + 1, min(n, range.upperBound))

        let xStart = CGFloat(clampedLower) * stepX
        let xEnd = CGFloat(clampedUpper) * stepX

        // Curve points: start/end touch the baseline, samples are in the middle of each minute cell.
        var pts: [CGPoint] = []
        pts.reserveCapacity((clampedUpper - clampedLower) + 2)

        pts.append(CGPoint(x: xStart, y: baselineY))

        for i in clampedLower..<clampedUpper {
            let xMid = (CGFloat(i) + 0.5) * stepX
            let y = baselineY - max(0, heights[i])
            pts.append(CGPoint(x: xMid, y: y))
        }

        pts.append(CGPoint(x: xEnd, y: baselineY))

        return ribbonFillPath(from: pts, baselineY: baselineY, xStart: xStart, xEnd: xEnd)
    }

    private func topEdgePath(size: CGSize, baselineY: CGFloat, heights: [CGFloat], range: Range<Int>) -> Path {
        let n = max(1, heights.count)
        let w = max(1, size.width)
        let stepX = w / CGFloat(n)

        let clampedLower = max(0, min(n - 1, range.lowerBound))
        let clampedUpper = max(clampedLower + 1, min(n, range.upperBound))

        let xStart = CGFloat(clampedLower) * stepX
        let xEnd = CGFloat(clampedUpper) * stepX

        var pts: [CGPoint] = []
        pts.reserveCapacity((clampedUpper - clampedLower) + 2)

        pts.append(CGPoint(x: xStart, y: baselineY))

        for i in clampedLower..<clampedUpper {
            let xMid = (CGFloat(i) + 0.5) * stepX
            let y = baselineY - max(0, heights[i])
            pts.append(CGPoint(x: xMid, y: y))
        }

        pts.append(CGPoint(x: xEnd, y: baselineY))

        return Path { p in
            addSmoothedTopEdge(&p, points: pts)
        }
    }

    private func ribbonFillPath(from topPoints: [CGPoint], baselineY: CGFloat, xStart: CGFloat, xEnd: CGFloat) -> Path {
        Path { p in
            guard topPoints.count >= 2 else { return }

            addSmoothedTopEdge(&p, points: topPoints)

            // Bottom edge (baseline back to start).
            p.addLine(to: CGPoint(x: xEnd, y: baselineY))
            p.addLine(to: CGPoint(x: xStart, y: baselineY))
            p.closeSubpath()
        }
    }

    private func addSmoothedTopEdge(_ p: inout Path, points: [CGPoint]) {
        guard points.count >= 2 else { return }

        p.move(to: points[0])

        if points.count == 2 {
            p.addLine(to: points[1])
            return
        }

        // Quadratic smoothing: reads as a flowing band (not bins).
        for i in 1..<(points.count - 1) {
            let current = points[i]
            let next = points[i + 1]
            let mid = CGPoint(
                x: (current.x + next.x) * 0.5,
                y: (current.y + next.y) * 0.5
            )
            p.addQuadCurve(to: mid, control: current)
        }

        p.addQuadCurve(to: points[points.count - 1], control: points[points.count - 2])
    }

    // MARK: - Utils

    private static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }

    private func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }
}

// MARK: - Hourly strip

struct WeatherHourlyRainStrip: View {
    let points: [WidgetWeaverWeatherHourlyPoint]
    let unit: UnitTemperature
    let accent: Color
    let fontSize: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ForEach(points.prefix(8)) { p in
                VStack(spacing: 4) {
                    Text(wwHourString(p.date))
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(precipText(p.precipitationChance01))
                        .font(.system(size: fontSize + 1, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(wwTempString(p.temperatureC, unit: unit))
                        .font(.system(size: fontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            WeatherGlassBackground(cornerRadius: 14)
        }
    }

    private func precipText(_ chance01: Double?) -> String {
        guard let chance01 else { return "—" }
        let pct = Int((chance01 * 100).rounded())
        return "\(pct)%"
    }
}

// MARK: - Building Blocks

struct WeatherGlassContainer<Content: View>: View {
    let metrics: WeatherMetrics
    let content: () -> Content

    init(metrics: WeatherMetrics, @ViewBuilder content: @escaping () -> Content) {
        self.metrics = metrics
        self.content = content
    }

    var body: some View {
        content()
            .padding(metrics.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                WeatherGlassBackground(cornerRadius: metrics.containerCornerRadius)
            }
            .overlay {
                RoundedRectangle(cornerRadius: metrics.containerCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            .compositingGroup()
    }
}

struct WeatherSectionCard<Content: View>: View {
    let metrics: WeatherMetrics
    let content: () -> Content

    init(metrics: WeatherMetrics, @ViewBuilder content: @escaping () -> Content) {
        self.metrics = metrics
        self.content = content
    }

    var body: some View {
        content()
            .padding(metrics.sectionPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                Color.black.opacity(0.16),
                in: RoundedRectangle(cornerRadius: metrics.sectionCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.sectionCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

struct WeatherAttributionLink: View {
    let accent: Color

    var body: some View {
        let store = WidgetWeaverWeatherStore.shared
        if let url = store.attributionLegalURL() {
            Link(destination: url) {
                // Removes the redundant info icon and stays out of the “Now” axis label area.
                Text("Weather")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.18), in: Capsule())
            }
            .accessibilityLabel("Apple Weather attribution")
        }
    }
}

// MARK: - Metrics

struct WeatherMetrics {
    let family: WidgetFamily
    let style: StyleSpec
    let layout: LayoutSpec

    var scale: CGFloat { max(0.85, min(1.35, CGFloat(style.weatherScale))) }

    var contentPadding: CGFloat {
        let base = CGFloat(style.padding)
        let familyMultiplier: CGFloat
        switch family {
        case .systemSmall: familyMultiplier = 0.85
        case .systemMedium: familyMultiplier = 0.90
        default: familyMultiplier = 1.00
        }
        return max(10, min(18, base * familyMultiplier)) * scale
    }

    var containerCornerRadius: CGFloat { max(14, min(26, CGFloat(style.cornerRadius))) }
    var sectionCornerRadius: CGFloat { max(12, min(22, CGFloat(style.cornerRadius) - 4)) }

    var sectionPadding: CGFloat { max(10, min(16, CGFloat(style.padding) * 0.75)) * scale }
    var sectionSpacing: CGFloat { max(8, min(14, CGFloat(layout.spacing))) * scale }

    // Font sizes
    var locationFontSize: CGFloat { 12 * scale }
    var locationFontSizeLarge: CGFloat { 13 * scale }

    var nowcastPrimaryFontSizeSmall: CGFloat { 16 * scale }
    var nowcastPrimaryFontSizeMedium: CGFloat { 18 * scale }
    var nowcastPrimaryFontSizeLarge: CGFloat { 20 * scale }

    var detailsFontSize: CGFloat { 12 * scale }
    var detailsFontSizeLarge: CGFloat { 13 * scale }

    var updatedFontSize: CGFloat { 11 * scale }

    var temperatureFontSizeSmall: CGFloat { 28 * scale }
    var temperatureFontSizeMedium: CGFloat { 30 * scale }
    var temperatureFontSizeLarge: CGFloat { 34 * scale }

    var sectionTitleFontSize: CGFloat { 12 * scale }

    // Chart heights
    var nowcastChartHeightSmall: CGFloat { 54 * scale }
    var nowcastChartHeightMedium: CGFloat { 62 * scale }
    var nowcastChartHeightLarge: CGFloat { 92 * scale }

    // Hourly strip
    var hourlyStripFontSize: CGFloat { 11 * scale }
    var hourlyStripFontSizeLarge: CGFloat { 12 * scale }
}

// MARK: - Background

struct WeatherPalette: Hashable {
    let top: Color
    let bottom: Color
    let glow: Color
    let rainAccent: Color

    static func fallback(accent: Color) -> WeatherPalette {
        WeatherPalette(
            top: Color.black.opacity(0.55),
            bottom: Color.black.opacity(0.75),
            glow: accent.opacity(0.25),
            rainAccent: accent
        )
    }

    static func forSnapshot(_ snapshot: WidgetWeaverWeatherSnapshot, now: Date, accent: Color) -> WeatherPalette {
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)
        let hasRain = (nowcast.peakIntensityMMPerHour >= WeatherNowcast.wetIntensityThresholdMMPerHour)
            || ((nowcast.startOffsetMinutes ?? 999) <= 60)

        if hasRain {
            return WeatherPalette(
                top: Color.black.opacity(0.40),
                bottom: Color.black.opacity(0.78),
                glow: accent.opacity(0.35),
                rainAccent: accent
            )
        }

        return WeatherPalette(
            top: Color.black.opacity(0.45),
            bottom: Color.black.opacity(0.82),
            glow: Color.white.opacity(0.08),
            rainAccent: accent
        )
    }
}

struct WeatherBackdropView: View {
    let palette: WeatherPalette
    let family: WidgetFamily

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [palette.top, palette.bottom],
                startPoint: .top,
                endPoint: .bottom
            )

            Circle()
                .fill(palette.glow)
                .frame(width: glowSize, height: glowSize)
                .blur(radius: glowBlur)
                .offset(x: glowOffsetX, y: glowOffsetY)
        }
        .ignoresSafeArea()
    }

    private var glowSize: CGFloat {
        switch family {
        case .systemSmall: return 110
        case .systemMedium: return 150
        default: return 220
        }
    }

    private var glowBlur: CGFloat {
        switch family {
        case .systemSmall: return 28
        case .systemMedium: return 34
        default: return 44
        }
    }

    private var glowOffsetX: CGFloat {
        switch family {
        case .systemSmall: return 45
        case .systemMedium: return 85
        default: return 110
        }
    }

    private var glowOffsetY: CGFloat {
        switch family {
        case .systemSmall: return -30
        case .systemMedium: return -46
        default: return -65
        }
    }
}

// MARK: - Colour blending helpers

private extension Color {
    func wwBlended(with other: Color, amount: CGFloat) -> Color {
        let t = max(0, min(1, amount))
        guard t > 0 else { return self }

        guard let a = wwRGBA(), let b = other.wwRGBA() else {
            return self
        }

        let r = a.r + (b.r - a.r) * t
        let g = a.g + (b.g - a.g) * t
        let bl = a.b + (b.b - a.b) * t
        let al = a.a + (b.a - a.a) * t

        return Color(red: Double(r), green: Double(g), blue: Double(bl), opacity: Double(al))
    }

    func wwRGBA() -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)? {
        #if canImport(UIKit)
        let ui = UIColor(self)

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return (r, g, b, a)
        }

        if let cs = CGColorSpace(name: CGColorSpace.sRGB),
           let cg = ui.cgColor.converted(to: cs, intent: .defaultIntent, options: nil),
           let comps = cg.components
        {
            if comps.count >= 4 { return (comps[0], comps[1], comps[2], comps[3]) }
            if comps.count == 2 { return (comps[0], comps[0], comps[0], comps[1]) }
        }

        return nil
        #elseif canImport(AppKit)
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.sRGB) else { return nil }
        return (rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent)
        #else
        return nil
        #endif
    }
}
