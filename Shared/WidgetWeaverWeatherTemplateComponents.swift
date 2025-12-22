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
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)

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
    /// One sample per minute (target: 60). Wet/dry is still driven only by intensity via `WeatherNowcast.isWet`.
    struct Sample: Hashable {
        var intensityMMPerHour: Double
        var chance01: Double
    }

    let samples: [Sample] // exactly 60 samples, padded
    let maxIntensityMMPerHour: Double
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width)
            let h = max(1, geo.size.height)

            let wetMask: [Bool] = samples.map { WeatherNowcast.isWet(intensityMMPerHour: $0.intensityMMPerHour) }
            let hasAnyWet = wetMask.contains(true)

            let coreHalfHeights = coreHalfHeights(
                plotHeight: h,
                wetMask: wetMask
            )

            let haloHalfHeights = haloHalfHeights(
                plotHeight: h,
                wetMask: wetMask,
                coreHalfHeights: coreHalfHeights
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

            ZStack {
                // Baseline “dry” guide (always present).
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h / 2))
                    p.addLine(to: CGPoint(x: w, y: h / 2))
                }
                .stroke(Color.white.opacity(0.10), lineWidth: 1)

                // “Now” marker (subtle, left edge).
                Path { p in
                    let lineH = h * 0.72
                    let y0 = (h - lineH) / 2
                    p.move(to: CGPoint(x: 0.5, y: y0))
                    p.addLine(to: CGPoint(x: 0.5, y: y0 + lineH))
                }
                .stroke(Color.white.opacity(0.18), lineWidth: 1)

                if hasAnyWet {
                    // Halo: uncertainty envelope (grey drift + blur).
                    bandPath(size: geo.size, halfHeights: haloHalfHeights)
                        .fill(haloGradient)
                        .opacity(0.55)
                        .blur(radius: 6.5)

                    // Core: expected intensity.
                    bandPath(size: geo.size, halfHeights: coreHalfHeights)
                        .fill(coreGradient)
                        .opacity(0.95)
                        .blur(radius: 0.8)

                    // Soft centre highlight to keep it readable at a glance.
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: h / 2))
                        p.addLine(to: CGPoint(x: w, y: h / 2))
                    }
                    .stroke(Color.white.opacity(0.06), lineWidth: 2)
                }
            }
            .compositingGroup()
        }
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

    private func coreHalfHeights(plotHeight: CGFloat, wetMask: [Bool]) -> [CGFloat] {
        let h = max(1, plotHeight)
        let hardCap = (h / 2) - 1

        // Tuning knobs:
        let minHalf = max(1, h * 0.045)     // drizzle visibility floor
        let maxHalf = min(hardCap, h * 0.38) // intensity ceiling

        return samples.enumerated().map { (i, s) in
            guard wetMask[i] else { return 0 }
            let frac = CGFloat(intensityFraction(for: s))
            let core = minHalf + frac * (maxHalf - minHalf)
            return min(core, hardCap)
        }
    }

    private func haloHalfHeights(plotHeight: CGFloat, wetMask: [Bool], coreHalfHeights: [CGFloat]) -> [CGFloat] {
        let h = max(1, plotHeight)
        let hardCap = (h / 2) - 1

        // Tuning knobs:
        let maxExtra = h * 0.18

        return coreHalfHeights.indices.map { i in
            guard wetMask[i] else { return 0 }
            let u = CGFloat(uncertainty01(forChance: samples[i].chance01))
            let extra = u * maxExtra
            return min(coreHalfHeights[i] + extra, hardCap)
        }
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

    // MARK: - Path (step per minute)

    private func bandPath(size: CGSize, halfHeights: [CGFloat]) -> Path {
        Path { p in
            let n = halfHeights.count
            guard n >= 2 else { return }

            let w = max(1, size.width)
            let h = max(1, size.height)
            let midY = h / 2

            // One minute = one step.
            let stepX = w / CGFloat(n)

            // Top edge (step function).
            p.move(to: CGPoint(x: 0, y: midY - halfHeights[0]))

            for i in 0..<n {
                let x1 = CGFloat(i + 1) * stepX
                p.addLine(to: CGPoint(x: x1, y: midY - halfHeights[i]))

                if i + 1 < n {
                    p.addLine(to: CGPoint(x: x1, y: midY - halfHeights[i + 1]))
                }
            }

            // Bottom edge (reverse).
            p.addLine(to: CGPoint(x: w, y: midY + halfHeights[n - 1]))

            for i in stride(from: n - 1, through: 0, by: -1) {
                let x0 = CGFloat(i) * stepX
                p.addLine(to: CGPoint(x: x0, y: midY + halfHeights[i]))

                if i > 0 {
                    p.addLine(to: CGPoint(x: x0, y: midY + halfHeights[i - 1]))
                }
            }

            p.closeSubpath()
        }
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: metrics.containerCornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.containerCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
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
