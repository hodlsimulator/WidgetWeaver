//
//  WidgetWeaverWeatherTemplateView.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

@inline(__always)
private func wwTempString(_ celsius: Double, unit: UnitTemperature) -> String {
    let m = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit)
    return String(Int(round(m.value)))
}

@inline(__always)
private func wwHourString(_ date: Date) -> String {
    let hour = Calendar.current.component(.hour, from: date)
    return String(format: "%02d", hour)
}

@inline(__always)
private func wwShortTimeString(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
}

// MARK: - Weather Template

/// The weather template is opinionated and rain-first:
/// - Next hour precipitation is the primary focus (Dark Sky style).
/// - Temperature is secondary.
/// - Everything else is de-emphasised.
struct WeatherTemplateView: View {
    let spec: WidgetSpec

    #if canImport(WidgetKit)
    let family: WidgetFamily
    #else
    let family: Int
    #endif

    let context: WidgetWeaverRenderContext
    let accent: Color

    init(
        spec: WidgetSpec,
        family: WidgetFamily,
        context: WidgetWeaverRenderContext,
        accent: Color
    ) {
        self.spec = spec
        self.family = family
        self.context = context
        self.accent = accent
    }

    var body: some View {
        let store = WidgetWeaverWeatherStore.shared
        let snapshot = store.snapshotForRender(context: context)
        let location = store.loadLocation()
        let unit = store.resolvedUnitTemperature()

        let metrics = WeatherMetrics(
            family: family,
            style: spec.style,
            layout: spec.layout
        )

        Group {
            if context == .widget || context == .simulator {
                TimelineView(.periodic(from: Date(), by: 60)) { timeline in
                    WeatherTemplateContent(
                        snapshot: snapshot,
                        location: location,
                        unit: unit,
                        now: timeline.date,
                        family: family,
                        metrics: metrics,
                        accent: accent
                    )
                }
            } else {
                WeatherTemplateContent(
                    snapshot: snapshot,
                    location: location,
                    unit: unit,
                    now: Date(),
                    family: family,
                    metrics: metrics,
                    accent: accent
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel(snapshot: snapshot, location: location, unit: unit, now: Date()))
    }

    private func accessibilityLabel(
        snapshot: WidgetWeaverWeatherSnapshot?,
        location: WidgetWeaverWeatherLocation?,
        unit: UnitTemperature,
        now: Date
    ) -> String {
        guard let snapshot else {
            if location == nil {
                return "Weather. No location selected."
            }
            return "Weather. Updating."
        }

        let temp = wwTempString(snapshot.temperatureC, unit: unit)
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)
        let headline = nowcast.primaryText
        return "Weather. \(snapshot.locationName). \(headline). Temperature \(temp)."
    }
}

private struct WeatherTemplateContent: View {
    let snapshot: WidgetWeaverWeatherSnapshot?
    let location: WidgetWeaverWeatherLocation?
    let unit: UnitTemperature
    let now: Date
    let family: WidgetFamily
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let snapshot {
                WeatherBackdropView(
                    palette: WeatherPalette.forSnapshot(snapshot, now: now, accent: accent),
                    family: family
                )
            } else {
                WeatherBackdropView(
                    palette: WeatherPalette.fallback(accent: accent),
                    family: family
                )
            }

            if let snapshot {
                WeatherFilledStateView(
                    snapshot: snapshot,
                    unit: unit,
                    now: now,
                    family: family,
                    metrics: metrics,
                    accent: accent
                )
            } else {
                WeatherEmptyStateView(
                    location: location,
                    metrics: metrics,
                    accent: accent
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Layouts

private struct WeatherFilledStateView: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let unit: UnitTemperature
    let now: Date
    let family: WidgetFamily
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        WeatherGlassContainer(metrics: metrics) {
            switch family {
            case .systemSmall:
                WeatherSmallRainLayout(
                    snapshot: snapshot,
                    unit: unit,
                    now: now,
                    family: family,
                    metrics: metrics,
                    accent: accent
                )

            case .systemMedium:
                WeatherMediumRainLayout(
                    snapshot: snapshot,
                    unit: unit,
                    now: now,
                    family: family,
                    metrics: metrics,
                    accent: accent
                )

            default:
                WeatherLargeRainLayout(
                    snapshot: snapshot,
                    unit: unit,
                    now: now,
                    metrics: metrics,
                    accent: accent
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if family == .systemSmall {
                WeatherAttributionLink(accent: accent)
                    .padding(metrics.contentPadding)
            }
        }
    }
}

private struct WeatherSmallRainLayout: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let unit: UnitTemperature
    let now: Date
    let family: WidgetFamily
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)

        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.locationName)
                        .font(.system(size: metrics.locationFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(nowcast.primaryText)
                        .font(.system(size: metrics.nowcastPrimaryFontSizeSmall, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }

            WeatherNowcastChart(
                buckets: nowcast.buckets(for: family),
                maxIntensityMMPerHour: nowcast.peakIntensityMMPerHour,
                accent: accent,
                showAxisLabels: false
            )
            .frame(height: metrics.nowcastChartHeightSmall)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(wwTempString(snapshot.temperatureC, unit: unit))
                    .font(.system(size: metrics.temperatureFontSizeSmall, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if let hi = snapshot.highTemperatureC, let lo = snapshot.lowTemperatureC {
                    Text("H \(wwTempString(hi, unit: unit))  L \(wwTempString(lo, unit: unit))")
                        .font(.system(size: metrics.detailsFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

private struct WeatherMediumRainLayout: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let unit: UnitTemperature
    let now: Date
    let family: WidgetFamily
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)
        let later = WeatherLaterToday(snapshot: snapshot, now: now)

        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.locationName)
                        .font(.system(size: metrics.locationFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(nowcast.primaryText)
                        .font(.system(size: metrics.nowcastPrimaryFontSizeMedium, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if let secondary = nowcast.secondaryText {
                        Text(secondary)
                            .font(.system(size: metrics.detailsFontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 0)

                Text(wwTempString(snapshot.temperatureC, unit: unit))
                    .font(.system(size: metrics.temperatureFontSizeMedium, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            WeatherNowcastChart(
                buckets: nowcast.buckets(for: family),
                maxIntensityMMPerHour: nowcast.peakIntensityMMPerHour,
                accent: accent,
                showAxisLabels: true
            )
            .frame(height: metrics.nowcastChartHeightMedium)

            if !later.hourlyPoints.isEmpty {
                WeatherHourlyRainStrip(
                    points: later.hourlyPoints,
                    unit: unit,
                    accent: accent,
                    fontSize: metrics.hourlyStripFontSize
                )
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WeatherAttributionLink(accent: accent)

                Spacer(minLength: 0)

                Text("Updated \(wwShortTimeString(snapshot.fetchedAt))")
                    .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

private struct WeatherLargeRainLayout: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let unit: UnitTemperature
    let now: Date
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)
        let later = WeatherLaterToday(snapshot: snapshot, now: now)
        let tomorrow = WeatherTomorrow(snapshot: snapshot, now: now)

        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.locationName)
                        .font(.system(size: metrics.locationFontSizeLarge, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(nowcast.primaryText)
                        .font(.system(size: metrics.nowcastPrimaryFontSizeLarge, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    if let secondary = nowcast.secondaryText {
                        Text(secondary)
                            .font(.system(size: metrics.detailsFontSizeLarge, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                    }
                }

                Spacer(minLength: 0)

                Text(wwTempString(snapshot.temperatureC, unit: unit))
                    .font(.system(size: metrics.temperatureFontSizeLarge, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            WeatherSectionCard(metrics: metrics) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("Next hour")
                            .font(.system(size: metrics.sectionTitleFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        if let start = nowcast.startTimeText {
                            Text(start)
                                .font(.system(size: metrics.sectionTitleFontSize, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    WeatherNowcastChart(
                        buckets: nowcast.buckets(for: .systemLarge),
                        maxIntensityMMPerHour: nowcast.peakIntensityMMPerHour,
                        accent: accent,
                        showAxisLabels: true
                    )
                    .frame(height: metrics.nowcastChartHeightLarge)

                    WeatherNowcastDetailsRow(nowcast: nowcast, metrics: metrics)
                }
            }

            if !later.hourlyPoints.isEmpty {
                WeatherSectionCard(metrics: metrics) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Later today")
                            .font(.system(size: metrics.sectionTitleFontSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)

                        WeatherHourlyRainStrip(
                            points: later.hourlyPoints,
                            unit: unit,
                            accent: accent,
                            fontSize: metrics.hourlyStripFontSizeLarge
                        )
                    }
                }
            }

            if let tomorrow {
                WeatherSectionCard(metrics: metrics) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tomorrow")
                                .font(.system(size: metrics.sectionTitleFontSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)

                            Text(tomorrow.summaryText)
                                .font(.system(size: metrics.detailsFontSizeLarge, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }

                        Spacer(minLength: 0)

                        if let hiLo = tomorrow.hiLoText(unit: unit) {
                            Text(hiLo)
                                .font(.system(size: metrics.detailsFontSizeLarge, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WeatherAttributionLink(accent: accent)

                Spacer(minLength: 0)

                Text("Updated \(wwShortTimeString(snapshot.fetchedAt))")
                    .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }
}

// MARK: - Empty State

private struct WeatherEmptyStateView: View {
    let location: WidgetWeaverWeatherLocation?
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        WeatherGlassContainer(metrics: metrics) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rain")
                    .font(.system(size: metrics.nowcastPrimaryFontSizeMedium, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if location == nil {
                    Text("Set a location in the app.")
                        .font(.system(size: metrics.detailsFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("Tap to open settings")
                        .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(accent)
                } else {
                    Text("Updating weather…")
                        .font(.system(size: metrics.detailsFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("Tap to refresh")
                        .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(accent)
                }

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    WeatherAttributionLink(accent: accent)

                    Spacer(minLength: 0)

                    Text("WidgetWeaver")
                        .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Nowcast Model

private struct WeatherNowcastBucket: Identifiable, Hashable {
    var id: Int
    var intensityMMPerHour: Double
    var chance01: Double
}

private struct WeatherNowcast: Hashable {
    let points: [WidgetWeaverWeatherMinutePoint]

    let startOffsetMinutes: Int?
    let endOffsetMinutes: Int?

    let peakIntensityMMPerHour: Double
    let peakChance01: Double

    let primaryText: String
    let secondaryText: String?

    let startTimeText: String?

    init(snapshot: WidgetWeaverWeatherSnapshot, now: Date) {
        let raw = snapshot.minute ?? []
        let filtered = raw
            .filter { $0.date >= now.addingTimeInterval(-30) }
            .sorted(by: { $0.date < $1.date })

        // Take a forward-looking hour from 'now'.
        let forward = filtered.filter { $0.date >= now }.prefix(60)
        self.points = Array(forward)

        let analysis = WeatherNowcast.analyse(points: self.points, now: now)

        self.startOffsetMinutes = analysis.startOffsetMinutes
        self.endOffsetMinutes = analysis.endOffsetMinutes
        self.peakIntensityMMPerHour = analysis.peakIntensityMMPerHour
        self.peakChance01 = analysis.peakChance01
        self.primaryText = analysis.primaryText
        self.secondaryText = analysis.secondaryText
        self.startTimeText = analysis.startTimeText
    }

    func buckets(for family: WidgetFamily) -> [WeatherNowcastBucket] {
        guard !points.isEmpty else {
            return []
        }

        let bucketSize: Int
        switch family {
        case .systemSmall:
            bucketSize = 5
        case .systemMedium:
            bucketSize = 3
        default:
            bucketSize = 1
        }

        let intensities = points.map { max(0.0, $0.precipitationIntensityMMPerHour ?? 0.0) }
        let chances = points.map { WeatherNowcast.clamp01($0.precipitationChance01 ?? 0.0) }

        var out: [WeatherNowcastBucket] = []
        out.reserveCapacity(Int((Double(points.count) / Double(bucketSize)).rounded(.up)))

        var idx = 0
        var bucketId = 0
        while idx < points.count {
            let end = min(points.count, idx + bucketSize)
            let sliceI = intensities[idx..<end]
            let sliceC = chances[idx..<end]

            let maxIntensity = sliceI.max() ?? 0.0
            let maxChance = sliceC.max() ?? 0.0

            out.append(.init(id: bucketId, intensityMMPerHour: maxIntensity, chance01: maxChance))

            bucketId += 1
            idx += bucketSize
        }

        return out
    }

    var startMinutesText: String? {
        guard let startOffsetMinutes else { return nil }
        if startOffsetMinutes <= 0 { return "Now" }
        return "In \(startOffsetMinutes)m"
    }

    var endMinutesText: String? {
        guard let endOffsetMinutes else { return nil }
        if endOffsetMinutes <= 0 { return "Now" }
        return "In \(endOffsetMinutes)m"
    }

    // MARK: Analysis

    private struct Analysis: Hashable {
        var startOffsetMinutes: Int?
        var endOffsetMinutes: Int?
        var peakIntensityMMPerHour: Double
        var peakChance01: Double
        var primaryText: String
        var secondaryText: String?
        var startTimeText: String?
    }

    private static func analyse(points: [WidgetWeaverWeatherMinutePoint], now: Date) -> Analysis {
        guard !points.isEmpty else {
            return Analysis(
                startOffsetMinutes: nil,
                endOffsetMinutes: nil,
                peakIntensityMMPerHour: 0,
                peakChance01: 0,
                primaryText: "No rain next hour",
                secondaryText: nil,
                startTimeText: nil
            )
        }

        struct Sample {
            var offsetM: Int
            var intensity: Double
            var chance: Double
        }

        let samples: [Sample] = points.map {
            let intensity = max(0.0, $0.precipitationIntensityMMPerHour ?? 0.0)
            let chance = clamp01($0.precipitationChance01 ?? 0.0)
            let offsetM = max(0, Int($0.date.timeIntervalSince(now) / 60.0))
            return Sample(offsetM: offsetM, intensity: intensity, chance: chance)
        }

        // Use expected intensity to decide if it's meaningfully wet.
        let wetThreshold: Double = 0.08

        let wetIdx: [Int] = samples.enumerated().compactMap { (i, s) in
            let expected = s.intensity * s.chance
            return expected >= wetThreshold ? i : nil
        }

        if wetIdx.isEmpty {
            let peakChance = samples.map { $0.chance }.max() ?? 0
            let secondary: String? = peakChance > 0.15 ? "Low chance showers" : nil
            return Analysis(
                startOffsetMinutes: nil,
                endOffsetMinutes: nil,
                peakIntensityMMPerHour: 0,
                peakChance01: peakChance,
                primaryText: "No rain next hour",
                secondaryText: secondary,
                startTimeText: nil
            )
        }

        let startIndex = wetIdx.first ?? 0
        let endIndex = wetIdx.last ?? startIndex

        let startOffset = samples[startIndex].offsetM
        let endOffset = samples[endIndex].offsetM

        let peakIntensity = wetIdx.map { samples[$0].intensity }.max() ?? 0
        let peakChance = wetIdx.map { samples[$0].chance }.max() ?? 0

        let descriptor = intensityDescriptor(peakIntensity)

        let startTimeText: String?
        if startOffset <= 0 {
            startTimeText = "Now"
        } else {
            startTimeText = "Starts in \(startOffset)m"
        }

        if startOffset <= 0 {
            // Raining now.
            let primary = "\(descriptor) rain now"
            let secondary: String?
            if endOffset < 55 {
                secondary = "Stopping in \(endOffset)m"
            } else {
                secondary = "For at least an hour"
            }
            return Analysis(
                startOffsetMinutes: 0,
                endOffsetMinutes: endOffset,
                peakIntensityMMPerHour: peakIntensity,
                peakChance01: peakChance,
                primaryText: primary,
                secondaryText: secondary,
                startTimeText: startTimeText
            )
        } else {
            // Starts later.
            let primary = "\(descriptor) rain in \(startOffset)m"
            let secondary: String?
            if endOffset > startOffset {
                let dur = endOffset - startOffset
                if dur >= 5 && dur <= 55 {
                    secondary = "Lasting ~\(dur)m"
                } else {
                    secondary = nil
                }
            } else {
                secondary = nil
            }
            return Analysis(
                startOffsetMinutes: startOffset,
                endOffsetMinutes: endOffset,
                peakIntensityMMPerHour: peakIntensity,
                peakChance01: peakChance,
                primaryText: primary,
                secondaryText: secondary,
                startTimeText: startTimeText
            )
        }
    }

    private static func intensityDescriptor(_ mmPerHour: Double) -> String {
        if mmPerHour < 0.4 { return "Light" }
        if mmPerHour < 2.5 { return "Moderate" }
        return "Heavy"
    }

    private static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }
}

private struct WeatherNowcastDetailsRow: View {
    let nowcast: WeatherNowcast
    let metrics: WeatherMetrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            WeatherDetailPill(
                title: "Peak",
                value: nowcast.peakIntensityMMPerHour > 0 ? String(format: "%.1f mm/h", nowcast.peakIntensityMMPerHour) : "—",
                metrics: metrics
            )

            WeatherDetailPill(
                title: "Chance",
                value: percentText(nowcast.peakChance01),
                metrics: metrics
            )

            if let start = nowcast.startMinutesText {
                WeatherDetailPill(
                    title: "Start",
                    value: start,
                    metrics: metrics
                )
            }

            Spacer(minLength: 0)

            if let end = nowcast.endMinutesText {
                Text("End \(end)")
                    .font(.system(size: metrics.detailsFontSizeLarge, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func percentText(_ chance01: Double) -> String {
        let pct = Int((chance01 * 100.0).rounded())
        return "\(pct)%"
    }
}

private struct WeatherDetailPill: View {
    let title: String
    let value: String
    let metrics: WeatherMetrics

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: metrics.pillTitleFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(size: metrics.pillValueFontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Later Today Model

private struct WeatherLaterToday: Hashable {
    let hourlyPoints: [WidgetWeaverWeatherHourlyPoint]

    init(snapshot: WidgetWeaverWeatherSnapshot, now: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(60 * 60 * 24)

        let remaining = snapshot.hourly
            .filter { $0.date >= now && $0.date < endOfToday }
            .prefix(8)

        self.hourlyPoints = Array(remaining)
    }
}

private struct WeatherTomorrow: Hashable {
    let day: WidgetWeaverWeatherDailyPoint

    var summaryText: String {
        if let chance = day.precipitationChance01 {
            let pct = Int((chance * 100).rounded())
            if pct <= 10 { return "Mostly dry" }
            return "\(pct)% chance of rain"
        }
        return "—"
    }

    func hiLoText(unit: UnitTemperature) -> String? {
        guard let hi = day.highTemperatureC, let lo = day.lowTemperatureC else { return nil }
        let hiText = wwTempString(hi, unit: unit)
        let loText = wwTempString(lo, unit: unit)
        return "H \(hiText)  L \(loText)"
    }

    init?(snapshot: WidgetWeaverWeatherSnapshot, now: Date) {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(60 * 60 * 24)

        if let match = snapshot.daily.first(where: { cal.isDate($0.date, inSameDayAs: tomorrow) }) {
            self.day = match
        } else if snapshot.daily.count >= 2 {
            self.day = snapshot.daily[1]
        } else {
            return nil
        }
    }
}

// MARK: - Chart

private struct WeatherNowcastChart: View {
    let buckets: [WeatherNowcastBucket]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let count = buckets.count
            let spacing: CGFloat = count > 24 ? 1 : 2
            let totalSpacing = spacing * CGFloat(max(0, count - 1))
            let barWidth = count > 0 ? max(1, (w - totalSpacing) / CGFloat(count)) : 0

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

                            let frac: CGFloat = (maxIntensityMMPerHour > 0) ? CGFloat(intensity / maxIntensityMMPerHour) : 0
                            let barHeight = max(1, h * frac)

                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(accent)
                                .opacity(0.25 + 0.75 * chance)
                                .frame(width: barWidth, height: barHeight)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)

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
}

private struct WeatherHourlyRainStrip: View {
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

private struct WeatherGlassContainer<Content: View>: View {
    let metrics: WeatherMetrics
    @ViewBuilder let content: () -> Content

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

private struct WeatherSectionCard<Content: View>: View {
    let metrics: WeatherMetrics
    @ViewBuilder let content: () -> Content

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

private struct WeatherAttributionLink: View {
    let accent: Color

    var body: some View {
        let store = WidgetWeaverWeatherStore.shared
        if let url = store.attributionLegalURL() {
            Link(destination: url) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(6)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Weather attribution")
        } else {
            EmptyView()
        }
    }
}

// MARK: - Metrics

private struct WeatherMetrics {
    let family: WidgetFamily
    let style: StyleSpec
    let layout: LayoutSpec

    var scale: CGFloat {
        max(0.85, min(1.35, CGFloat(style.weatherScale)))
    }

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

    var containerCornerRadius: CGFloat {
        max(14, min(26, CGFloat(style.cornerRadius)))
    }

    var sectionCornerRadius: CGFloat {
        max(12, min(22, CGFloat(style.cornerRadius) - 4))
    }

    var sectionPadding: CGFloat {
        max(10, min(16, CGFloat(style.padding) * 0.75)) * scale
    }

    var sectionSpacing: CGFloat {
        max(8, min(14, CGFloat(layout.spacing))) * scale
    }

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

    var pillTitleFontSize: CGFloat { 11 * scale }
    var pillValueFontSize: CGFloat { 12 * scale }

    // Chart heights
    var nowcastChartHeightSmall: CGFloat { 54 * scale }
    var nowcastChartHeightMedium: CGFloat { 62 * scale }
    var nowcastChartHeightLarge: CGFloat { 92 * scale }

    // Hourly strip
    var hourlyStripFontSize: CGFloat { 11 * scale }
    var hourlyStripFontSizeLarge: CGFloat { 12 * scale }
}

// MARK: - Background

private struct WeatherPalette: Hashable {
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
        let hasRain = nowcast.peakIntensityMMPerHour > 0.05 || (nowcast.startOffsetMinutes ?? 999) <= 60

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

private struct WeatherBackdropView: View {
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
        case .systemSmall:
            return 110
        case .systemMedium:
            return 150
        default:
            return 220
        }
    }

    private var glowBlur: CGFloat {
        switch family {
        case .systemSmall:
            return 28
        case .systemMedium:
            return 34
        default:
            return 44
        }
    }

    private var glowOffsetX: CGFloat {
        switch family {
        case .systemSmall:
            return 45
        case .systemMedium:
            return 85
        default:
            return 110
        }
    }

    private var glowOffsetY: CGFloat {
        switch family {
        case .systemSmall:
            return -35
        case .systemMedium:
            return -40
        default:
            return -55
        }
    }
}
