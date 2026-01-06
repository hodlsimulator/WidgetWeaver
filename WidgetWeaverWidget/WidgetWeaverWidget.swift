//
//  WidgetWeaverWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 1/2/26.
//

import SwiftUI
import WidgetKit

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

struct WidgetWeaverDesignChoice: AppEntity, Hashable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Design"

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static var defaultQuery = WidgetWeaverDesignQuery()
}

struct WidgetWeaverDesignQuery: EntityQuery {
    func entities(for identifiers: [WidgetWeaverDesignChoice.ID]) async throws -> [WidgetWeaverDesignChoice] {
        let store = WidgetSpecStore.shared
        let all = store.loadAll()
        let map = Dictionary(uniqueKeysWithValues: all.map { ($0.id.uuidString, $0) })
        return identifiers.compactMap { id in
            guard let spec = map[id] else { return nil }
            return WidgetWeaverDesignChoice(id: spec.id.uuidString, name: spec.name)
        }
    }

    func suggestedEntities() async throws -> [WidgetWeaverDesignChoice] {
        await Task.detached(priority: .utility) {
            let store = WidgetSpecStore.shared
            let all = store.loadAll()
            let sorted = all.sorted { a, b in
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                return a.name < b.name
            }
            return sorted.map { WidgetWeaverDesignChoice(id: $0.id.uuidString, name: $0.name) }
        }.value
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

        // Regression A guardrail:
        // WidgetKit snapshots are often produced under strict time/memory budgets even when
        // `context.isPreview` is false. Treat all snapshots as low-budget so rainy charts
        // can’t blow the budget.
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

        if !context.isPreview {
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
                }
            }
            if usesActivity {
                Task.detached(priority: .utility) {
                    _ = await WidgetWeaverActivityEngine.shared.updateIfNeeded(force: false)
                }
            }
        }

        let now = Date()

        let familySpec = spec.resolved(for: context.family)
        let shuffleSchedule = SmartPhotoShuffleSchedule.load(for: familySpec, now: now)

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
        let intervalSeconds = TimeInterval(manifest.rotationIntervalMinutes) * 60.0

        guard let next = manifest.nextChangeDateFrom(now: now) else { return nil }

        // Don't bother scheduling rotations until something is actually prepared.
        guard manifest.entries.contains(where: { $0.isPrepared }) else { return nil }

        return SmartPhotoShuffleSchedule(intervalSeconds: intervalSeconds, nextChangeDate: next)
    }
}

// MARK: - Main Design Widget

struct WidgetWeaverWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.main

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WidgetWeaverDesignSelectionIntent.self, provider: WidgetWeaverProvider()) { entry in
            let liveSpec = WidgetSpecStore.shared.load(id: entry.spec.id) ?? entry.spec

            WidgetWeaverRenderClock.withNow(entry.date) {
                WidgetWeaverSpecView(spec: liveSpec, widgetFamily: entry.family, isWidgetKitPreview: entry.isWidgetKitPreview)
                    .id(entry.date)
            }
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
        let hasLocation = (WidgetWeaverWeatherStore.shared.loadLocation() != nil)
        if context.isPreview {
            completion(Entry(date: Date(), hasLocation: true, snapshot: .sampleSunny()))
            return
        }
        let snap = WidgetWeaverWeatherStore.shared.loadSnapshot()
        completion(Entry(date: Date(), hasLocation: hasLocation, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let hasLocation = (WidgetWeaverWeatherStore.shared.loadLocation() != nil)
        let snap = WidgetWeaverWeatherStore.shared.loadSnapshot()

        let now = Date()
        let entries: [Entry] = [
            Entry(date: now, hasLocation: hasLocation, snapshot: snap),
            Entry(date: now.addingTimeInterval(60), hasLocation: hasLocation, snapshot: snap)
        ]

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WidgetWeaverLockScreenWeatherWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.lockWeather

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverLockScreenWeatherProvider()) { entry in
            WidgetWeaverLockScreenWeatherView(entry: entry)
        }
        .configurationDisplayName("Weather")
        .description("A lock screen weather widget.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Lock Screen Weather View

struct WidgetWeaverLockScreenWeatherView: View {
    let entry: WidgetWeaverLockScreenWeatherEntry

    var body: some View {
        if let snap = entry.snapshot, entry.hasLocation {
            WidgetWeaverWeatherTemplateView(snapshot: snap)
        } else {
            Text("No weather")
                .font(.caption2)
        }
    }
}

@main
struct WidgetWeaverWidgetBundle: WidgetBundle {
    var body: some Widget {
        WidgetWeaverWidget()
        WidgetWeaverLockScreenWeatherWidget()
    }
}
