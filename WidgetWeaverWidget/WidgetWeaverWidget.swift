//
//  WidgetWeaverWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/17/25.
//

import Foundation
import WidgetKit
import SwiftUI
import AppIntents

struct WidgetWeaverEntry: TimelineEntry {
    let date: Date
    let spec: WidgetSpec
}

// MARK: - AppEntity for widget configuration

enum WidgetWeaverSpecEntityIDs {
    static let appDefault = "app_default"
}

struct WidgetWeaverSpecEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Widget Design")
    }

    static var defaultQuery: WidgetWeaverSpecEntityQuery {
        WidgetWeaverSpecEntityQuery()
    }

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct WidgetWeaverSpecEntityQuery: EntityQuery {
    func entities(for identifiers: [WidgetWeaverSpecEntity.ID]) async throws -> [WidgetWeaverSpecEntity] {
        let store = WidgetSpecStore.shared
        var out: [WidgetWeaverSpecEntity] = []

        for ident in identifiers {
            if ident == WidgetWeaverSpecEntityIDs.appDefault {
                out.append(WidgetWeaverSpecEntity(id: WidgetWeaverSpecEntityIDs.appDefault, name: "Default (App)"))
                continue
            }

            if let uuid = UUID(uuidString: ident),
               let spec = store.load(id: uuid) {
                out.append(WidgetWeaverSpecEntity(id: spec.id.uuidString, name: spec.name))
            }
        }

        return out
    }

    func suggestedEntities() async throws -> [WidgetWeaverSpecEntity] {
        let defaultEntity = WidgetWeaverSpecEntity(id: WidgetWeaverSpecEntityIDs.appDefault, name: "Default (App)")
        let saved = WidgetSpecStore.shared
            .loadAll()
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { WidgetWeaverSpecEntity(id: $0.id.uuidString, name: $0.name) }

        return [defaultEntity] + saved
    }

    func defaultResult() async -> WidgetWeaverSpecEntity? {
        WidgetWeaverSpecEntity(id: WidgetWeaverSpecEntityIDs.appDefault, name: "Default (App)")
    }
}

// MARK: - Widget configuration intent

struct WidgetWeaverConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "WidgetWeaver Design"
    static let description = IntentDescription("Select which saved design this widget should use.")

    @Parameter(title: "Design") var spec: WidgetWeaverSpecEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$spec)")
    }
}

// MARK: - Timeline provider

struct WidgetWeaverProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverEntry
    typealias Intent = WidgetWeaverConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), spec: .defaultSpec())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let spec = loadSpec(for: configuration)

        if needsWeatherUpdate(for: spec) {
            _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded()
        }

        return Entry(date: Date(), spec: spec)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let spec = loadSpec(for: configuration)
        let needsWeather = needsWeatherUpdate(for: spec)

        if needsWeather {
            _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded()
        }

        var refreshSeconds: TimeInterval = 60 * 15

        if needsWeather {
            refreshSeconds = WidgetWeaverWeatherStore.shared.recommendedRefreshIntervalSeconds()
            if WidgetWeaverWeatherStore.shared.loadSnapshot() == nil {
                refreshSeconds = min(refreshSeconds, 60 * 2)
            }
        }

        if spec.usesTimeDependentRendering() {
            refreshSeconds = min(refreshSeconds, 60 * 5)
        }

        let entry = Entry(date: Date(), spec: spec)
        let next = Date().addingTimeInterval(refreshSeconds)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadSpec(for configuration: Intent) -> WidgetSpec {
        let store = WidgetSpecStore.shared

        if let selected = configuration.spec {
            if selected.id == WidgetWeaverSpecEntityIDs.appDefault {
                return store.loadDefault()
            }
            if let uuid = UUID(uuidString: selected.id),
               let spec = store.load(id: uuid) {
                return spec
            }
        }

        return store.loadDefault()
    }

    private func needsWeatherUpdate(for spec: WidgetSpec) -> Bool {
        spec.usesWeatherRendering()
    }
}

// MARK: - Widget view

struct WidgetWeaverWidgetView: View {
    let entry: WidgetWeaverProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetWeaverSpecView(spec: entry.spec, family: family, context: .widget)
    }
}

// MARK: - Widget

struct WidgetWeaverWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetWeaverWidgetKinds.main,
            intent: WidgetWeaverConfigurationIntent.self,
            provider: WidgetWeaverProvider()
        ) { entry in
            WidgetWeaverWidgetView(entry: entry)
        }
        .configurationDisplayName("Design")
        .description("A WidgetWeaver design.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    WidgetWeaverWidget()
} timeline: {
    WidgetWeaverEntry(date: Date(), spec: .defaultSpec())
}


// MARK: - Lock Screen Weather Widget (AppIntent-based to avoid 'sending' closure errors)

struct WidgetWeaverLockScreenWeatherEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetWeaverWeatherSnapshot?
}

struct WidgetWeaverLockScreenWeatherIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Lock Screen Weather"
    static let description = IntentDescription("Next-hour rain with a static uncertainty cue.")

    static var parameterSummary: some ParameterSummary {
        Summary("Weather")
    }
}

struct WidgetWeaverLockScreenWeatherProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverLockScreenWeatherEntry
    typealias Intent = WidgetWeaverLockScreenWeatherIntent

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), snapshot: .sampleSunny())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let store = WidgetWeaverWeatherStore.shared

        if store.loadSnapshot() == nil {
            _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded()
        }

        let snap = store.loadSnapshot()
        if context.isPreview && snap == nil {
            return Entry(date: Date(), snapshot: .sampleSunny())
        }

        return Entry(date: Date(), snapshot: snap)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let store = WidgetWeaverWeatherStore.shared

        _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded()

        let snap = store.loadSnapshot()

        var refreshSeconds = store.recommendedRefreshIntervalSeconds()
        if snap == nil {
            refreshSeconds = min(refreshSeconds, 60 * 2)
        }

        let entry = Entry(date: Date(), snapshot: snap)
        let next = Date().addingTimeInterval(refreshSeconds)
        return Timeline(entries: [entry], policy: .after(next))
    }
}

private struct WidgetWeaverLockScreenWeatherView: View {
    let entry: WidgetWeaverLockScreenWeatherEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryCircular:
            circularView
        default:
            rectangularView
        }
    }

    private var inlineText: String {
        guard let s = entry.snapshot else { return "Weather —" }
        let sum = nowcastSummary(snapshot: s, now: entry.date)
        if let pct = sum.peakChancePercentText {
            return "\(sum.primaryText) \(pct)"
        }
        return sum.primaryText
    }

    private var rectangularView: some View {
        let store = WidgetWeaverWeatherStore.shared
        let unit = store.resolvedUnitTemperature()

        return VStack(alignment: .leading, spacing: 2) {
            if let s = entry.snapshot {
                let sum = nowcastSummary(snapshot: s, now: entry.date)

                Text(s.locationName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(sum.primaryText)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .widgetAccentable()

                HStack(spacing: 6) {
                    Text("\(temperatureString(s.temperatureC, unit: unit))°")

                    if let pct = sum.peakChancePercentText {
                        Text(pct)
                    }

                    if let hi = s.highTemperatureC, let lo = s.lowTemperatureC {
                        Text("H \(temperatureString(hi, unit: unit))° L \(temperatureString(lo, unit: unit))°")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("Weather")
                    .font(.headline)
                    .widgetAccentable()

                Text("Open the app to set a location.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var circularView: some View {
        let store = WidgetWeaverWeatherStore.shared
        let unit = store.resolvedUnitTemperature()

        return ZStack {
            if let s = entry.snapshot {
                let sum = nowcastSummary(snapshot: s, now: entry.date)

                VStack(spacing: 2) {
                    Image(systemName: symbolName(for: s, summary: sum))
                        .font(.system(size: 16, weight: .semibold))
                        .widgetAccentable()

                    if let pct = sum.peakChancePercentText {
                        Text(pct)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    } else {
                        Text("\(temperatureString(s.temperatureC, unit: unit))°")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .lineLimit(1)
                    }
                }
            } else {
                Image(systemName: "cloud")
                    .font(.system(size: 16, weight: .semibold))
                    .widgetAccentable()
            }
        }
    }

    private struct NowcastSummary: Hashable {
        var primaryText: String
        var peakChance01: Double
        var peakIntensityMMPerHour: Double

        var peakChancePercentText: String? {
            let pct = Int(round(peakChance01 * 100.0))
            if pct <= 0 { return nil }
            return "\(pct)%"
        }
    }

    private func nowcastSummary(snapshot: WidgetWeaverWeatherSnapshot, now: Date) -> NowcastSummary {
        let points = (snapshot.minute ?? [])
            .filter { $0.date >= now && $0.date < now.addingTimeInterval(60 * 60) }
            .sorted(by: { $0.date < $1.date })
            .prefix(60)

        let arr = Array(points)

        if arr.isEmpty {
            let chance = snapshot.precipitationChance01 ?? (snapshot.hourly.first?.precipitationChance01 ?? 0.0)
            let text = chance > 0.25 ? "Possible rain" : "Dry next hour"
            return NowcastSummary(primaryText: text, peakChance01: chance, peakIntensityMMPerHour: 0.0)
        }

        struct Sample {
            var offsetM: Int
            var intensity: Double
            var chance: Double
        }

        @inline(__always)
        func clamp01(_ v: Double) -> Double { max(0.0, min(1.0, v)) }

        let samples: [Sample] = arr.map { p in
            let intensity = max(0.0, p.precipitationIntensityMMPerHour ?? 0.0)
            let chance = clamp01(p.precipitationChance01 ?? 0.0)
            let offsetM = max(0, Int(p.date.timeIntervalSince(now) / 60.0))
            return Sample(offsetM: offsetM, intensity: intensity, chance: chance)
        }

        let peakChance = samples.map { $0.chance }.max() ?? 0.0
        let peakIntensity = samples.map { $0.intensity }.max() ?? 0.0

        // Expected intensity is used to decide if it's meaningfully wet.
        let wetThreshold: Double = 0.08

        let wetIndices: [Int] = samples.enumerated().compactMap { (i, s) in
            let expected = s.intensity * s.chance
            return expected >= wetThreshold ? i : nil
        }

        if wetIndices.isEmpty {
            let text = peakChance > 0.25 ? "Low chance showers" : "No rain next hour"
            return NowcastSummary(primaryText: text, peakChance01: peakChance, peakIntensityMMPerHour: peakIntensity)
        }

        let startIndex = wetIndices.first ?? 0
        let startOffset = samples[startIndex].offsetM

        if startOffset <= 0 {
            return NowcastSummary(primaryText: "Rain now", peakChance01: peakChance, peakIntensityMMPerHour: peakIntensity)
        }

        return NowcastSummary(primaryText: "Rain in \(startOffset)m", peakChance01: peakChance, peakIntensityMMPerHour: peakIntensity)
    }

    private func temperatureString(_ celsius: Double, unit: UnitTemperature) -> String {
        let m = Measurement(value: celsius, unit: UnitTemperature.celsius).converted(to: unit)
        return String(Int(round(m.value)))
    }

    private func symbolName(for snapshot: WidgetWeaverWeatherSnapshot, summary: NowcastSummary) -> String {
        if summary.peakChance01 >= 0.35 {
            return "cloud.rain.fill"
        }
        let name = snapshot.symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "cloud" : name
    }
}

struct WidgetWeaverLockScreenWeatherWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetWeaverWidgetKinds.lockScreenWeather,
            intent: WidgetWeaverLockScreenWeatherIntent.self,
            provider: WidgetWeaverLockScreenWeatherProvider()
        ) { entry in
            WidgetWeaverLockScreenWeatherView(entry: entry)
        }
        .configurationDisplayName("Weather")
        .description("Next-hour rain with a static uncertainty cue.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

#Preview(as: .accessoryRectangular) {
    WidgetWeaverLockScreenWeatherWidget()
} timeline: {
    WidgetWeaverLockScreenWeatherEntry(date: Date(), snapshot: .sampleSunny())
}
