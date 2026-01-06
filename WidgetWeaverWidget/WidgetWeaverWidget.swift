//
//  WidgetWeaverWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 1/2/26.
//

import Foundation
import SwiftUI
import WidgetKit
import AppIntents
import UIKit

public struct WidgetWeaverEntry: TimelineEntry {
    public let date: Date
    public let family: WidgetFamily
    public let spec: WidgetSpec
    public let isWidgetKitPreview: Bool

    public init(date: Date, family: WidgetFamily, spec: WidgetSpec, isWidgetKitPreview: Bool) {
        self.date = date
        self.family = family
        self.spec = spec
        self.isWidgetKitPreview = isWidgetKitPreview
    }
}

// MARK: - App Intent / Design Selection

public struct WidgetWeaverDesignSelectionIntent: AppIntent {
    public static var title: LocalizedStringResource = "Design"
    public static var description = IntentDescription("Choose a saved WidgetWeaver design for this widget.")

    @Parameter(title: "Design")
    public var design: WidgetWeaverDesignChoice?

    public init() {}
}

public struct WidgetWeaverDesignChoice: AppEntity, Identifiable, Hashable, Sendable {
    public let id: String // UUID string
    public let name: String

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Design")
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    public static var defaultQuery: Query { Query() }

    public struct Query: EntityQuery, Sendable {
        public init() {}

        public func suggestedEntities() async throws -> [WidgetWeaverDesignChoice] {
            makeChoices()
        }

        public func entities(for identifiers: [String]) async throws -> [WidgetWeaverDesignChoice] {
            let set = Set(identifiers)
            return makeChoices().filter { set.contains($0.id) }
        }

        public func defaultResult() async -> WidgetWeaverDesignChoice? {
            nil
        }

        private func makeChoices() -> [WidgetWeaverDesignChoice] {
            let store = WidgetSpecStore.shared
            let all = store.loadAll()
            let sorted = all.sorted { a, b in
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                return a.name < b.name
            }
            return sorted.map { WidgetWeaverDesignChoice(id: $0.id.uuidString, name: $0.name) }
        }
    }
}

// MARK: - Main Widget Provider

struct WidgetWeaverProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverEntry
    typealias Intent = WidgetWeaverDesignSelectionIntent

    func placeholder(in context: Context) -> Entry {
        let spec = WidgetSpecStore.shared.loadDefault()
        return Entry(date: Date(), family: context.family, spec: spec, isWidgetKitPreview: true)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let spec = resolveSpec(for: configuration)

        // WidgetKit snapshots are often produced under strict time/memory budgets even when
        // `context.isPreview` is false. Treat all snapshots as low-budget.
        return Entry(date: Date(), family: context.family, spec: spec, isWidgetKitPreview: true)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let spec = resolveSpec(for: configuration)

        if context.isPreview {
            let now = Date()
            let entries: [Entry] = [
                Entry(date: now, family: context.family, spec: spec, isWidgetKitPreview: true),
                Entry(date: now.addingTimeInterval(60), family: context.family, spec: spec, isWidgetKitPreview: true)
            ]
            return Timeline(entries: entries, policy: .atEnd)
        }

        let usesWeather = spec.usesWeatherRendering()
        let usesTime = spec.usesTimeDependentRendering()
        let usesCalendar = (spec.layout.template == LayoutTemplateToken.nextUpCalendar)
        let usesSteps = spec.usesStepsRendering()
        let usesActivity = spec.usesActivityRendering()

        if usesWeather {
            let hasLocation = (WidgetWeaverWeatherStore.shared.loadLocation() != nil)
            if hasLocation {
                Task.detached(priority: .utility) {
                    _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded(force: false)
                }
            }
        }
        if usesCalendar {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: false)
            }
        }
        if usesSteps {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: false)
                _ = await WidgetWeaverStepsEngine.shared.updateHistoryFromBeginningIfNeeded(force: false)
            }
        }
        if usesActivity {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverActivityEngine.shared.updateIfNeeded(force: false)
            }
        }

        let now = Date()

        let familySpec = spec.resolved(for: context.family)
        let shuffleSchedule = SmartPhotoShuffleSchedule.load(for: familySpec, now: now)

        // Poster-only shuffle: schedule entries exactly at rotation boundaries.
        if let shuffleSchedule,
           !usesWeather,
           !usesTime,
           !usesCalendar,
           !usesSteps,
           !usesActivity
        {
            let maxEntries: Int = 240
            let desiredHorizon: TimeInterval = 60 * 60 * 6
            let horizon = max(desiredHorizon, shuffleSchedule.nextChangeDate.timeIntervalSince(now) + (shuffleSchedule.intervalSeconds * 4))

            var entries: [Entry] = []
            entries.reserveCapacity(min(maxEntries, 32))

            entries.append(Entry(date: now, family: context.family, spec: spec, isWidgetKitPreview: false))

            var d = shuffleSchedule.nextChangeDate
            while entries.count < maxEntries && d > now && d <= now.addingTimeInterval(horizon) {
                entries.append(Entry(date: d, family: context.family, spec: spec, isWidgetKitPreview: false))
                d = d.addingTimeInterval(shuffleSchedule.intervalSeconds)
            }

            if entries.count == 1 {
                entries.append(Entry(date: shuffleSchedule.nextChangeDate, family: context.family, spec: spec, isWidgetKitPreview: false))
            }

            return Timeline(entries: entries, policy: .atEnd)
        }

        var refreshSeconds: TimeInterval = usesTime ? 60 : (60 * 60)
        if let shuffleSchedule {
            refreshSeconds = min(refreshSeconds, shuffleSchedule.intervalSeconds)
        }

        // Weather (template or variables) should tick every minute for live nowcast text.
        if usesWeather { refreshSeconds = 60 }
        if usesCalendar { refreshSeconds = min(refreshSeconds, 60) }

        if usesSteps && !usesTime {
            refreshSeconds = min(refreshSeconds, max(60, WidgetWeaverStepsStore.shared.recommendedRefreshIntervalSeconds()))
        }

        if usesActivity && !usesTime {
            refreshSeconds = min(refreshSeconds, max(60, WidgetWeaverActivityStore.shared.recommendedRefreshIntervalSeconds()))
        }

        // Important: use `now` as the base so a timeline reload inside the same minute
        // produces a new entry date and forces a redraw on the Home Screen.
        let base: Date = now

        // Buffer enough future entries so the widget doesn't "run out" if WidgetKit delays reloads.
        let maxEntries: Int = 240
        let desiredHorizon: TimeInterval = 60 * 60 * 6
        let horizon: TimeInterval = min(desiredHorizon, refreshSeconds * Double(maxEntries - 1))
        let count = max(2, Int(horizon / refreshSeconds) + 1)

        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for i in 0..<count {
            let d = base.addingTimeInterval(TimeInterval(i) * refreshSeconds)
            entries.append(Entry(date: d, family: context.family, spec: spec, isWidgetKitPreview: false))
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    private func resolveSpec(for configuration: Intent) -> WidgetSpec {
        if let idString = configuration.design?.id,
           let id = UUID(uuidString: idString),
           let loaded = WidgetSpecStore.shared.load(id: id)
        {
            return loaded
        }
        return WidgetSpecStore.shared.loadDefault()
    }
}

private struct SmartPhotoShuffleSchedule: Sendable {
    var intervalSeconds: TimeInterval
    var nextChangeDate: Date

    static func load(for spec: WidgetSpec, now: Date) -> SmartPhotoShuffleSchedule? {
        guard let fileName = spec.image?.smartPhoto?.shuffleManifestFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !fileName.isEmpty
        else {
            return nil
        }

        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: fileName) else { return nil }
        guard manifest.rotationIntervalMinutes > 0 else { return nil }

        // Don't bother scheduling rotations until something is actually prepared.
        guard manifest.entries.contains(where: { $0.isPrepared }) else { return nil }

        guard let next = manifest.nextChangeDateFrom(now: now) else { return nil }

        let intervalSeconds = TimeInterval(manifest.rotationIntervalMinutes) * 60.0
        return SmartPhotoShuffleSchedule(intervalSeconds: intervalSeconds, nextChangeDate: next)
    }
}

// MARK: - Main Design Widget

struct WidgetWeaverWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.main

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetWeaverWidgetKinds.main,
            intent: WidgetWeaverDesignSelectionIntent.self,
            provider: WidgetWeaverProvider()
        ) { entry in
            WidgetWeaverRenderClock.withNow(entry.date) {
                let liveSpec = WidgetSpecStore.shared.load(id: entry.spec.id) ?? entry.spec
                WidgetWeaverSpecView(spec: liveSpec, family: entry.family, context: .widget)
                    .environment(\.wwLowGraphicsBudget, entry.isWidgetKitPreview)
                    .environment(\.wwThumbnailRenderingEnabled, !entry.isWidgetKitPreview)
            }
            .id(entry.date)
        }
        .configurationDisplayName("WidgetWeaver")
        .description("A widget built from your saved WidgetWeaver designs.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Lock Screen Weather Widget

public struct WidgetWeaverLockScreenWeatherEntry: TimelineEntry {
    public let date: Date
    public let hasLocation: Bool
    public let snapshot: WidgetWeaverWeatherSnapshot?

    public init(date: Date, hasLocation: Bool, snapshot: WidgetWeaverWeatherSnapshot?) {
        self.date = date
        self.hasLocation = hasLocation
        self.snapshot = snapshot
    }
}

struct WidgetWeaverLockScreenWeatherProvider: TimelineProvider {
    typealias Entry = WidgetWeaverLockScreenWeatherEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), hasLocation: true, snapshot: .sampleSunny())
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let store = WidgetWeaverWeatherStore.shared
        let hasLocation = (store.loadLocation() != nil)
        let snap = store.snapshotForRender(context: context.isPreview ? .preview : .widget)
        completion(Entry(date: Date(), hasLocation: hasLocation, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        if !context.isPreview {
            let hasLocation = (WidgetWeaverWeatherStore.shared.loadLocation() != nil)
            if hasLocation {
                Task.detached(priority: .utility) {
                    _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded(force: false)
                }
            }
        }

        let store = WidgetWeaverWeatherStore.shared
        let hasLocation = context.isPreview ? true : (store.loadLocation() != nil)
        let snap = context.isPreview ? store.snapshotForRender(context: .preview) : store.loadSnapshot()

        let now = Date()
        let base = now
        let count = 60

        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for i in 0..<count {
            let d = base.addingTimeInterval(TimeInterval(i) * 60.0)
            entries.append(Entry(date: d, hasLocation: hasLocation, snapshot: snap))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WidgetWeaverLockScreenWeatherView: View {
    let entry: WidgetWeaverLockScreenWeatherEntry

    var body: some View {
        let store = WidgetWeaverWeatherStore.shared

        let hasLocation: Bool = {
            if let _ = store.loadLocation() { return true }
            return entry.hasLocation
        }()

        let snapshot: WidgetWeaverWeatherSnapshot? = entry.snapshot ?? store.loadSnapshot()

        Group {
            if !hasLocation {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weather")
                        .font(.headline)
                    Text("Open the app to set a location.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let snapshot {
                weatherBody(snapshot: snapshot, now: entry.date)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weather")
                        .font(.headline)
                    Text("Updating…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func weatherBody(snapshot: WidgetWeaverWeatherSnapshot, now: Date) -> some View {
        let unit = WidgetWeaverWeatherStore.shared.resolvedUnitTemperature()
        let temp = Measurement(value: snapshot.temperatureC, unit: UnitTemperature.celsius)
            .converted(to: unit)
            .value
        let tempInt = Int(round(temp))

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(tempInt)°")
                .font(.headline)
                .bold()

            Text(snapshot.conditionDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(WeatherNowcast(snapshot: snapshot, now: now).primaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

struct WidgetWeaverLockScreenWeatherWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.lockScreenWeather

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverLockScreenWeatherProvider()) { entry in
            WidgetWeaverLockScreenWeatherView(entry: entry)
                .wwWidgetContainerBackground()
        }
        .configurationDisplayName("Rain (WidgetWeaver)")
        .description("Next hour precipitation, temperature, and nowcast.")
        .supportedFamilies([.accessoryRectangular])
    }
}
