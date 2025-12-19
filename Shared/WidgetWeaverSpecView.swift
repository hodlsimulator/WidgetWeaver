//
//  WidgetWeaverSpecView.swift
//  WidgetWeaver
//
//  Created by Conor on 12/17/25.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit

public enum WidgetWeaverRenderContext: String, Codable, Sendable {
    case widget
    case preview
    case simulator
}

// MARK: - Weather Template

private struct WeatherTemplateView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext
    let style: StyleSpec
    let accent: Color
    let snapshot: WidgetWeaverWeatherSnapshot?
    let unit: UnitTemperature
    let attributionURL: URL?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let snapshot {
                WeatherFilledStateView(
                    spec: spec,
                    family: family,
                    snapshot: snapshot,
                    unit: unit,
                    accent: accent,
                    attributionURL: attributionURL
                )
            } else {
                WeatherEmptyStateView(
                    spec: spec,
                    family: family,
                    accent: accent,
                    attributionURL: attributionURL
                )
            }
        }
    }
}

private struct WeatherFilledStateView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let snapshot: WidgetWeaverWeatherSnapshot
    let unit: UnitTemperature
    let accent: Color
    let attributionURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            headerRow

            HStack(alignment: .top, spacing: 14) {
                temperatureBlock
                    .frame(maxWidth: .infinity, alignment: .leading)

                conditionBlock
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            statsRow

            if family != .systemSmall {
                HourlyForecastStrip(
                    points: Array(snapshot.hourly.prefix(family == .systemMedium ? 5 : 6)),
                    unit: unit,
                    accent: accent
                )

                TemperatureSparklineView(
                    points: Array(snapshot.hourly.prefix(family == .systemMedium ? 5 : 6)),
                    unit: unit,
                    accent: accent
                )
                .frame(height: family == .systemMedium ? 28 : 34)
            }

            if family == .systemLarge {
                DailyForecastListView(
                    points: Array(snapshot.daily.prefix(5)),
                    unit: unit,
                    accent: accent
                )
            }

            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottomTrailing) {
            if let url = attributionURL {
                Link(destination: url) {
                    Text("Weather")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }

    private var verticalSpacing: CGFloat {
        switch family {
        case .systemSmall: return 10
        case .systemMedium: return 12
        case .systemLarge: return 12
        default: return 12
        }
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(spec.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Spacer(minLength: 8)

            Text(updatedLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var updatedLabel: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let rel = formatter.localizedString(for: snapshot.fetchedAt, relativeTo: Date())
        return "Updated \(rel)"
    }

    private var temperatureBlock: some View {
        let temp = roundedTemperature(snapshot.temperatureC, unit: unit)
        let feels = snapshot.apparentTemperatureC.map { roundedTemperature($0, unit: unit) }

        let title = spec.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = spec.secondaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(temp)
                    .font(temperatureFont)
                    .monospacedDigit()
                    .foregroundStyle(.primary)

                Text("°")
                    .font(degreeFont)
                    .foregroundStyle(.primary)
            }

            if !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemSmall ? 1 : 2)
            } else {
                Text(snapshot.conditionDescription)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemSmall ? 1 : 2)
            }

            if let feels, family != .systemSmall {
                Text("Feels \(feels)°")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var conditionBlock: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Image(systemName: snapshot.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(conditionIconFont)
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)

            Text(snapshot.conditionDescription)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            if let hi = snapshot.highTemperatureC, let lo = snapshot.lowTemperatureC {
                WeatherStatPill(
                    title: "H/L",
                    icon: "arrow.up.arrow.down",
                    value: "\(roundedTemperature(hi, unit: unit))° / \(roundedTemperature(lo, unit: unit))°"
                )
            }

            if let p = snapshot.precipitationChance01 {
                let pct = Int(round(p * 100))
                WeatherStatPill(
                    title: "Precip",
                    icon: "drop.fill",
                    value: "\(pct)%"
                )
            }

            if let h = snapshot.humidity01 {
                let pct = Int(round(h * 100))
                WeatherStatPill(
                    title: "Humidity",
                    icon: "humidity.fill",
                    value: "\(pct)%"
                )
            }
        }
    }

    private var temperatureFont: Font {
        switch family {
        case .systemSmall:
            return .system(size: 52, weight: .heavy, design: .rounded)
        case .systemMedium:
            return .system(size: 62, weight: .heavy, design: .rounded)
        case .systemLarge:
            return .system(size: 64, weight: .heavy, design: .rounded)
        default:
            return .system(size: 62, weight: .heavy, design: .rounded)
        }
    }

    private var degreeFont: Font {
        switch family {
        case .systemSmall:
            return .system(size: 26, weight: .bold, design: .rounded)
        case .systemMedium:
            return .system(size: 30, weight: .bold, design: .rounded)
        case .systemLarge:
            return .system(size: 30, weight: .bold, design: .rounded)
        default:
            return .system(size: 30, weight: .bold, design: .rounded)
        }
    }

    private var conditionIconFont: Font {
        switch family {
        case .systemSmall:
            return .system(size: 34, weight: .regular)
        case .systemMedium:
            return .system(size: 40, weight: .regular)
        case .systemLarge:
            return .system(size: 46, weight: .regular)
        default:
            return .system(size: 40, weight: .regular)
        }
    }

    private func roundedTemperature(_ celsius: Double, unit: UnitTemperature) -> String {
        let v = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value
        return String(Int(round(v)))
    }
}

private struct WeatherEmptyStateView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let accent: Color
    let attributionURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(spec.name.isEmpty ? "Weather" : spec.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let url = attributionURL {
                    Link(destination: url) {
                        Text("Weather")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "location.slash")
                    .font(.system(size: family == .systemSmall ? 28 : 34, weight: .semibold))
                    .foregroundStyle(accent)

                Text("Set a location in Weather settings")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text("Menu → Weather")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer(minLength: 0)
        }
    }
}

private struct WeatherStatPill: View {
    let title: String
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HourlyForecastStrip: View {
    let points: [WidgetWeaverWeatherHourlyPoint]
    let unit: UnitTemperature
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            ForEach(points.prefix(6)) { p in
                VStack(spacing: 6) {
                    Text(hourLabel(p.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Image(systemName: p.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14, weight: .regular))

                    Text("\(roundedTemp(p.temperatureC))°")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func roundedTemp(_ celsius: Double) -> Int {
        let v = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value
        return Int(round(v))
    }

    private func hourLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("ha")
        return f.string(from: date)
    }
}

private struct TemperatureSparklineView: View {
    let points: [WidgetWeaverWeatherHourlyPoint]
    let unit: UnitTemperature
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let temps = points.map { tempValue($0.temperatureC) }
            let minV = temps.min() ?? 0
            let maxV = temps.max() ?? 1
            let range = max(maxV - minV, 1)

            let w = geo.size.width
            let h = geo.size.height
            let stepX = w / CGFloat(max(temps.count - 1, 1))
            let padY: CGFloat = 4

            let pointsCG: [CGPoint] = temps.enumerated().map { i, v in
                let x = CGFloat(i) * stepX
                let y = (1 - CGFloat((v - minV) / range)) * (h - padY * 2) + padY
                return CGPoint(x: x, y: y)
            }

            ZStack {
                if pointsCG.count >= 2 {
                    Path { p in
                        p.move(to: pointsCG[0])
                        for pt in pointsCG.dropFirst() {
                            p.addLine(to: pt)
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.95), Color.white.opacity(0.55)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    Path { p in
                        p.move(to: CGPoint(x: pointsCG[0].x, y: h))
                        p.addLine(to: pointsCG[0])
                        for pt in pointsCG.dropFirst() {
                            p.addLine(to: pt)
                        }
                        p.addLine(to: CGPoint(x: pointsCG.last!.x, y: h))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.20), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }

                ForEach(Array(pointsCG.enumerated()), id: \.offset) { idx, pt in
                    Circle()
                        .fill(Color.white.opacity(idx == pointsCG.count - 1 ? 0.95 : 0.55))
                        .frame(width: idx == pointsCG.count - 1 ? 5 : 4, height: idx == pointsCG.count - 1 ? 5 : 4)
                        .position(pt)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tempValue(_ celsius: Double) -> Double {
        Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value
    }
}

private struct DailyForecastListView: View {
    let points: [WidgetWeaverWeatherDailyPoint]
    let unit: UnitTemperature
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            ForEach(points.prefix(5)) { d in
                HStack(spacing: 10) {
                    Text(weekday(d.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, alignment: .leading)

                    Image(systemName: d.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))

                    Spacer(minLength: 8)

                    if let hi = d.highTemperatureC {
                        Text("\(rounded(hi))°")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                    }

                    if let lo = d.lowTemperatureC {
                        Text("\(rounded(lo))°")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date)
    }

    private func rounded(_ celsius: Double) -> Int {
        let v = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit).value
        return Int(round(v))
    }
}

private struct WeatherBackdropView: View {
    let snapshot: WidgetWeaverWeatherSnapshot?
    let accent: Color
    let fallbackToken: BackgroundToken

    var body: some View {
        if let snapshot {
            let palette = WeatherPalette.make(from: snapshot, accent: accent)

            ZStack {
                LinearGradient(colors: palette.baseGradient, startPoint: .topLeading, endPoint: .bottomTrailing)

                Circle()
                    .fill(palette.glow1)
                    .frame(width: 320, height: 320)
                    .blur(radius: 60)
                    .offset(x: -110, y: -120)

                Circle()
                    .fill(palette.glow2)
                    .frame(width: 380, height: 380)
                    .blur(radius: 75)
                    .offset(x: 140, y: 160)

                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .blendMode(.overlay)
            }
        } else {
            Rectangle()
                .fill(fallbackToken.shapeStyle(accent: accent))
        }
    }
}

private struct WeatherPalette {
    var baseGradient: [Color]
    var glow1: Color
    var glow2: Color

    static func make(from snapshot: WidgetWeaverWeatherSnapshot, accent: Color) -> WeatherPalette {
        let kind = WeatherVisualKind.from(symbolName: snapshot.symbolName)
        let isDay = snapshot.isDaylight

        switch (kind, isDay) {
        case (.clear, true):
            return WeatherPalette(
                baseGradient: [
                    Color.blue.opacity(0.95),
                    Color.cyan.opacity(0.80),
                    accent.opacity(0.38)
                ],
                glow1: Color.yellow.opacity(0.35),
                glow2: accent.opacity(0.30)
            )

        case (.clear, false):
            return WeatherPalette(
                baseGradient: [
                    Color.indigo.opacity(0.95),
                    Color.black.opacity(0.90),
                    accent.opacity(0.24)
                ],
                glow1: Color.purple.opacity(0.30),
                glow2: accent.opacity(0.26)
            )

        case (.cloudy, true):
            return WeatherPalette(
                baseGradient: [
                    Color.blue.opacity(0.55),
                    Color.gray.opacity(0.55),
                    accent.opacity(0.22)
                ],
                glow1: Color.white.opacity(0.18),
                glow2: accent.opacity(0.22)
            )

        case (.cloudy, false):
            return WeatherPalette(
                baseGradient: [
                    Color.gray.opacity(0.55),
                    Color.black.opacity(0.90),
                    accent.opacity(0.18)
                ],
                glow1: Color.white.opacity(0.12),
                glow2: accent.opacity(0.18)
            )

        case (.rain, true):
            return WeatherPalette(
                baseGradient: [
                    Color.blue.opacity(0.70),
                    Color.indigo.opacity(0.62),
                    accent.opacity(0.20)
                ],
                glow1: Color.white.opacity(0.16),
                glow2: accent.opacity(0.22)
            )

        case (.rain, false):
            return WeatherPalette(
                baseGradient: [
                    Color.indigo.opacity(0.78),
                    Color.black.opacity(0.92),
                    accent.opacity(0.18)
                ],
                glow1: Color.white.opacity(0.10),
                glow2: accent.opacity(0.18)
            )

        case (.storm, _):
            return WeatherPalette(
                baseGradient: [
                    Color.purple.opacity(0.78),
                    Color.black.opacity(0.94),
                    accent.opacity(0.18)
                ],
                glow1: Color.white.opacity(0.12),
                glow2: accent.opacity(0.22)
            )

        case (.snow, true):
            return WeatherPalette(
                baseGradient: [
                    Color.white.opacity(0.85),
                    Color.cyan.opacity(0.35),
                    accent.opacity(0.22)
                ],
                glow1: Color.white.opacity(0.22),
                glow2: accent.opacity(0.18)
            )

        case (.snow, false):
            return WeatherPalette(
                baseGradient: [
                    Color.gray.opacity(0.62),
                    Color.black.opacity(0.92),
                    accent.opacity(0.14)
                ],
                glow1: Color.white.opacity(0.12),
                glow2: accent.opacity(0.16)
            )

        case (.fog, _):
            return WeatherPalette(
                baseGradient: [
                    Color.gray.opacity(0.58),
                    Color.gray.opacity(0.42),
                    accent.opacity(0.16)
                ],
                glow1: Color.white.opacity(0.12),
                glow2: accent.opacity(0.16)
            )

        case (.windy, _):
            return WeatherPalette(
                baseGradient: [
                    Color.teal.opacity(0.55),
                    Color.blue.opacity(0.50),
                    accent.opacity(0.18)
                ],
                glow1: Color.white.opacity(0.14),
                glow2: accent.opacity(0.18)
            )

        case (.mixed, _):
            return WeatherPalette(
                baseGradient: [
                    Color.blue.opacity(0.70),
                    Color.indigo.opacity(0.65),
                    accent.opacity(0.24)
                ],
                glow1: Color.white.opacity(0.14),
                glow2: accent.opacity(0.20)
            )
        }
    }

    private enum WeatherVisualKind {
        case clear
        case cloudy
        case rain
        case storm
        case snow
        case fog
        case windy
        case mixed

        static func from(symbolName: String) -> WeatherVisualKind {
            let s = symbolName.lowercased()

            if s.contains("bolt") || s.contains("thunder") {
                return .storm
            }

            if s.contains("snow") || s.contains("sleet") || s.contains("hail") {
                return .snow
            }

            if s.contains("rain") || s.contains("drizzle") || s.contains("showers") {
                return .rain
            }

            if s.contains("fog") || s.contains("haze") || s.contains("smoke") {
                return .fog
            }

            if s.contains("wind") || s.contains("tornado") {
                return .windy
            }

            if s.contains("cloud") {
                return .cloudy
            }

            if s.contains("sun") || s.contains("moon") || s.contains("clear") {
                return .clear
            }

            return .mixed
        }
    }
}

public struct WidgetWeaverSpecView: View {
    public let spec: WidgetSpec
    public let family: WidgetFamily
    public let context: WidgetWeaverRenderContext

    @AppStorage(WidgetWeaverWeatherStore.Keys.snapshotData, store: AppGroup.userDefaults)
    private var weatherSnapshotData: Data = Data()

    @AppStorage(WidgetWeaverWeatherStore.Keys.attributionData, store: AppGroup.userDefaults)
    private var weatherAttributionData: Data = Data()

    public init(spec: WidgetSpec, family: WidgetFamily, context: WidgetWeaverRenderContext) {
        self.spec = spec
        self.family = family
        self.context = context
    }

    public var body: some View {
        let _ = weatherSnapshotData
        let _ = weatherAttributionData

        let resolved = spec.resolved(for: family).resolvingVariables()
        let style = resolved.style
        let layout = resolved.layout
        let accent = style.accent.swiftUIColor

        ZStack {
            backgroundView(spec: resolved, layout: layout, style: style, accent: accent)

            VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
                switch layout.template {
                case .classic:
                    classicTemplate(spec: resolved, layout: layout, style: style, accent: accent)
                case .hero:
                    heroTemplate(spec: resolved, layout: layout, style: style, accent: accent)
                case .poster:
                    posterTemplate(spec: resolved, layout: layout, style: style, accent: accent)
                case .weather:
                    weatherTemplate(spec: resolved, layout: layout, style: style, accent: accent)
                }
            }
            .padding(layout.template == .poster ? 0 : style.padding)
        }
        .modifier(
            WidgetWeaverBackgroundModifier(
                cornerRadius: layout.template == .poster ? 0 : style.cornerRadius,
                family: family,
                context: context
            )
        )
    }

    // MARK: - Templates

    private func classicTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            headerRow(spec: spec, style: style, accent: accent)

            contentStackClassic(spec: spec, layout: layout, style: style)

            if let symbol = spec.symbol {
                imageRowClassic(symbol: symbol, style: style, accent: accent)
            }

            if layout.showsAccentBar {
                accentBar(accent: accent, style: style)
            }
        }
    }

    private func heroTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            headerRow(spec: spec, style: style, accent: accent)

            HStack(alignment: .top, spacing: layout.spacing) {
                VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
                    contentStackHero(spec: spec, layout: layout, style: style)

                    if layout.showsAccentBar {
                        accentBar(accent: accent, style: style)
                    }
                }

                if let symbol = spec.symbol {
                    Image(systemName: symbol.name)
                        .font(.system(size: style.symbolSize))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .opacity(0.85)
                }
            }
        }
        .padding(style.padding)
    }

    private func posterTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                if !spec.name.isEmpty {
                    Text(spec.name)
                        .font(style.nameTextStyle.font(fallback: .caption))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }

                if !spec.primaryText.isEmpty {
                    Text(spec.primaryText)
                        .font(style.primaryTextStyle.font(fallback: .title3))
                        .foregroundStyle(.white)
                        .lineLimit(layout.primaryLineLimit)
                }

                if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(style.secondaryTextStyle.font(fallback: .caption2))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(layout.secondaryLineLimit)
                }
            }
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.10),
                        Color.clear
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
    }

    private func weatherTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        let store = WidgetWeaverWeatherStore.shared
        let snapshot = store.snapshotForRender(context: context)
        let unit = store.resolvedUnitTemperature()
        let attributionURL = store.attributionLegalURL()

        return WeatherTemplateView(
            spec: spec,
            family: family,
            context: context,
            style: style,
            accent: accent,
            snapshot: snapshot,
            unit: unit,
            attributionURL: attributionURL
        )
    }

    // MARK: - Building Blocks

    private func headerRow(spec: WidgetSpec, style: StyleSpec, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if !spec.name.isEmpty {
                Text(spec.name)
                    .font(style.nameTextStyle.font(fallback: .caption))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private func contentStackClassic(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: 6) {
            if !spec.primaryText.isEmpty {
                Text(spec.primaryText)
                    .font(style.primaryTextStyle.font(fallback: .title3))
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemSmall ? layout.primaryLineLimitSmall : layout.primaryLineLimit)
            }

            if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(style.secondaryTextStyle.font(fallback: .caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? layout.secondaryLineLimitSmall : layout.secondaryLineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: layout.alignment.alignment, vertical: .top))
    }

    private func contentStackHero(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: 6) {
            if !spec.primaryText.isEmpty {
                Text(spec.primaryText)
                    .font(style.primaryTextStyle.font(fallback: .title3))
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemSmall ? layout.primaryLineLimitSmall : layout.primaryLineLimit)
            }

            if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                Text(secondaryText)
                    .font(style.secondaryTextStyle.font)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? layout.secondaryLineLimitSmall : layout.secondaryLineLimit)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: layout.alignment.alignment, vertical: .top))
    }

    private func imageRowClassic(symbol: WidgetSymbol, style: StyleSpec, accent: Color) -> some View {
        HStack {
            Spacer(minLength: 0)
            Image(systemName: symbol.name)
                .font(.system(size: style.symbolSize))
                .foregroundStyle(accent)
                .opacity(0.85)
        }
    }

    private func accentBar(accent: Color, style: StyleSpec) -> some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(accent)
            .frame(height: 5)
            .opacity(0.9)
    }

    // MARK: - Background

    private func backgroundView(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        ZStack {
            Color(uiColor: .systemBackground)

            if layout.template == .weather {
                WeatherBackdropView(
                    snapshot: WidgetWeaverWeatherStore.shared.snapshotForRender(context: context),
                    accent: accent,
                    fallbackToken: style.background
                )
            } else if layout.template == .poster,
                      let image = spec.image,
                      let uiImage = image.loadUIImageFromAppGroup() {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)
            } else {
                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)

                backgroundEffects(style: style, accent: accent)
            }
        }
    }

    private func backgroundEffects(style: StyleSpec, accent: Color) -> some View {
        ZStack {
            if style.backgroundGlowEnabled {
                Circle()
                    .fill(accent)
                    .blur(radius: 70)
                    .opacity(0.18)
                    .offset(x: -120, y: -120)

                Circle()
                    .fill(accent)
                    .blur(radius: 90)
                    .opacity(0.12)
                    .offset(x: 140, y: 160)
            }
        }
    }
}

// MARK: - Background Modifier

private struct WidgetWeaverBackgroundModifier: ViewModifier {
    let cornerRadius: Double
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext

    func body(content: Content) -> some View {
        switch context {
        case .widget:
            content
                .containerBackground(for: .widget) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.clear)
                }
        case .preview, .simulator:
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
