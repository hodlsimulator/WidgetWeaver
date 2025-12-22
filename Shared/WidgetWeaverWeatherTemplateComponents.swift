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

// MARK: - Chart

struct WeatherNowcastChart: View {
    let buckets: [WeatherNowcastBucket]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = buckets.count
            let spacing: CGFloat = (count > 24) ? 1 : 2
            let totalSpacing = spacing * CGFloat(max(0, count - 1))
            let barWidth = (count > 0) ? max(1, (w - totalSpacing) / CGFloat(count)) : 0

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.ultraThinMaterial)

                if count == 0 {
                    Text("—")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(buckets) { b in
                            let intensity = max(0.0, b.intensityMMPerHour)
                            let chance = max(0.0, min(1.0, b.chance01))
                            let isWet = WeatherNowcast.isWet(intensityMMPerHour: intensity)

                            let frac: CGFloat = (maxIntensityMMPerHour > 0)
                                ? CGFloat(intensity / maxIntensityMMPerHour)
                                : 0

                            let barHeight: CGFloat = isWet ? max(1, h * frac) : 0
                            let rainUncertainty = max(0.0, min(1.0, b.rainUncertainty01))

                            ZStack(alignment: .bottom) {
                                if isWet {
                                    // Static uncertainty “envelope” (Dark Sky-ish):
                                    // thickness/opacity grows with rainUncertainty.
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .stroke(accent, lineWidth: 0.6 + 3.2 * rainUncertainty)
                                        .opacity(0.06 + 0.18 * rainUncertainty)
                                        .blur(radius: 0.2 + 1.2 * rainUncertainty)
                                        .frame(width: barWidth, height: barHeight)

                                    // Bar:
                                    // Opacity is still influenced by chance, but the presence of a bar is driven
                                    // only by intensity via `isWet` (prevents false “dry” for mist/drizzle).
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(accent)
                                        .opacity(0.08 + 0.92 * chance)
                                        .frame(width: barWidth, height: barHeight)
                                }
                            }
                            .frame(width: barWidth, height: h, alignment: .bottom)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }

                if showAxisLabels {
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
        }
    }
}

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
        case .systemSmall:
            familyMultiplier = 0.85
        case .systemMedium:
            familyMultiplier = 0.90
        default:
            familyMultiplier = 1.00
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
