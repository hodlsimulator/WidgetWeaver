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
import UIKit

// MARK: - Widget Entry

public struct WidgetWeaverEntry: TimelineEntry {
    public let date: Date
    public let family: WidgetFamily
    public let spec: WidgetSpec

    /// WidgetKit preview/placeholder/snapshot rendering has tighter time and memory budgets.
    /// This flag is used to disable expensive visuals (e.g. heavy rain fuzz) only for those contexts.
    public let isWidgetKitPreview: Bool

    public init(date: Date, family: WidgetFamily, spec: WidgetSpec, isWidgetKitPreview: Bool = false) {
        self.date = date
        self.family = family
        self.spec = spec
        self.isWidgetKitPreview = isWidgetKitPreview
    }
}

// MARK: - Widget Configuration Intent

/// Each widget instance can follow the app’s default design or pick a specific saved design.
public struct WidgetWeaverDesignSelectionIntent: AppIntent, WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "Design" }
    public static var description: IntentDescription {
        IntentDescription("Choose a saved WidgetWeaver design for this widget.")
    }

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
        Entry(
            date: Date(),
            family: context.family,
            spec: WidgetSpec.defaultSpec(),
            isWidgetKitPreview: true
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let spec = resolveSpec(for: configuration)

        // IMPORTANT (Regression A guardrail):
        // Snapshot rendering can be used by WidgetKit in budget-tight contexts even when `context.isPreview` is false.
        // Always treat snapshots as low-budget to avoid heavy precipitation fuzz/blur paths.
        return Entry(
            date: Date(),
            family: context.family,
            spec: spec,
            isWidgetKitPreview: true
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let spec = resolveSpec(for: configuration)

        // IMPORTANT (Regression A guardrail):
        // Preview timelines should stay cheap and predictable. Keep the entry count tiny and mark as low-budget.
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

        let now = Date()

        // Base refresh: time-dependent specs want minute ticks; otherwise hourly.
        var refreshSeconds: TimeInterval = usesTime ? 60 : (60 * 60)

        // Weather (template or variables) should tick every minute for live nowcast text.
        if usesWeather { refreshSeconds = 60 }

        // Calendar countdown should tick at least every minute.
        if usesCalendar { refreshSeconds = min(refreshSeconds, 60) }

        // Steps can be slower than 60s, but avoid very long gaps in non-time specs.
        if usesSteps && !usesTime {
            refreshSeconds = min(refreshSeconds, max(60, WidgetWeaverStepsStore.shared.recommendedRefreshIntervalSeconds()))
        }

        // Use `now` as the base so a timeline reload inside the same minute produces a new entry date.
        let base: Date = now

        // Buffer enough future entries so the widget doesn't "run out" if WidgetKit delays reloads.
        let maxEntries: Int = 240
        let desiredHorizon: TimeInterval = 60 * 60 * 6
        let horizon: TimeInterval = min(desiredHorizon, refreshSeconds * Double(maxEntries - 1))
        let count = max(2, Int(horizon / refreshSeconds) + 1)

        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for i in 0..<count {
            let d = base.addingTimeInterval(Double(i) * refreshSeconds)
            entries.append(
                Entry(date: d, family: context.family, spec: spec, isWidgetKitPreview: false)
            )
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    private func resolveSpec(for configuration: Intent) -> WidgetSpec {
        if let idString = configuration.design?.id,
           let id = UUID(uuidString: idString),
           let loaded = WidgetSpecStore.shared.load(id: id) {
            return loaded
        }
        return WidgetSpecStore.shared.loadDefault()
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
                    // Budget guardrail for WidgetKit placeholder/snapshot.
                    .environment(\.wwLowGraphicsBudget, entry.isWidgetKitPreview)
                    // Secondary signal used by some rendering paths to disable costly work in previews.
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
            let d = base.addingTimeInterval(Double(i) * 60.0)
            entries.append(Entry(date: d, hasLocation: hasLocation, snapshot: snap))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private struct WidgetWeaverLockScreenWeatherView: View {
    let entry: WidgetWeaverLockScreenWeatherEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let now = entry.date

        if !entry.hasLocation {
            VStack(alignment: .leading, spacing: 3) {
                Text("Rain")
                    .font(.headline)
                Text("Set a location")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let snapshot = entry.snapshot {
            let unit = WidgetWeaverWeatherStore.shared.resolvedUnitTemperature()
            let temp = Measurement(value: snapshot.temperatureC, unit: UnitTemperature.celsius)
                .converted(to: unit)
                .value
            let tempInt = Int(round(temp))

            VStack(alignment: .leading, spacing: 4) {
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
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("Rain")
                    .font(.headline)
                Text("No data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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

// MARK: - Lock Screen Next Up (Calendar) Widget

public struct WidgetWeaverLockScreenNextUpEntry: TimelineEntry {
    public let date: Date
    public let hasAccess: Bool
    public let snapshot: WidgetWeaverCalendarSnapshot?

    public init(date: Date, hasAccess: Bool, snapshot: WidgetWeaverCalendarSnapshot?) {
        self.date = date
        self.hasAccess = hasAccess
        self.snapshot = snapshot
    }
}

struct WidgetWeaverLockScreenNextUpProvider: TimelineProvider {
    typealias Entry = WidgetWeaverLockScreenNextUpEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), hasAccess: true, snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let store = WidgetWeaverCalendarStore.shared
        let hasAccess = context.isPreview ? true : store.canReadEvents()
        let snap = store.snapshotForRender(context: context.isPreview ? .preview : .widget)
        completion(Entry(date: Date(), hasAccess: hasAccess, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        if !context.isPreview {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: false)
            }
        }

        let store = WidgetWeaverCalendarStore.shared
        let hasAccess = context.isPreview ? true : store.canReadEvents()
        let snap: WidgetWeaverCalendarSnapshot? = context.isPreview ? .sample() : store.loadSnapshot()

        let now = Date()
        let base = now
        let count = 60

        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for i in 0..<count {
            let d = base.addingTimeInterval(Double(i) * 60.0)
            entries.append(Entry(date: d, hasAccess: hasAccess, snapshot: snap))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private struct WidgetWeaverLockScreenNextUpView: View {
    let entry: WidgetWeaverLockScreenNextUpEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let now = entry.date

        if !entry.hasAccess {
            VStack(alignment: .leading, spacing: 3) {
                Text("Next Up")
                    .font(.headline)
                Text("No access")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let snapshot = entry.snapshot {
            let next = snapshot.next
            let second = snapshot.second

            if let next {
                let short = calendarShortCountdownValue(from: now, to: next.startDate, end: next.endDate)
                let label = calendarCountdownLabel(from: now, to: next.startDate, end: next.endDate)

                switch family {
                case .accessoryInline:
                    Text("\(next.title) \(label)")

                case .accessoryCircular:
                    VStack(spacing: 2) {
                        Text(short)
                            .font(.headline)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Image(systemName: "calendar")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                case .accessoryRectangular:
                    VStack(alignment: .leading, spacing: 3) {
                        Text(next.title)
                            .font(.headline)
                            .lineLimit(1)

                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if let loc = next.location, !loc.isEmpty {
                            Text(loc)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if let second {
                            let secondLabel = calendarCountdownLabel(from: now, to: second.startDate, end: second.endDate)
                            Text("Then: \(second.title) (\(secondLabel))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }

                default:
                    Text("\(next.title) \(label)")
                        .font(.caption2)
                }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next Up")
                        .font(.headline)
                    Text("No upcoming events")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                Text("Next Up")
                    .font(.headline)
                Text("No data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func calendarShortCountdownValue(from now: Date, to start: Date, end: Date) -> String {
        if start <= now, end > now {
            return compactIntervalString(seconds: end.timeIntervalSince(now))
        }
        if start > now {
            return compactIntervalString(seconds: start.timeIntervalSince(now))
        }
        return "Now"
    }

    private func calendarCountdownLabel(from now: Date, to start: Date, end: Date) -> String {
        if start <= now, end > now {
            return "ends in \(compactIntervalString(seconds: end.timeIntervalSince(now)))"
        }
        if start > now {
            return "in \(compactIntervalString(seconds: start.timeIntervalSince(now)))"
        }
        return "now"
    }

    private func compactIntervalString(seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        let minutes = Int(ceil(s / 60.0))

        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remM = minutes % 60

        if hours < 24 {
            if remM == 0 { return "\(hours)h" }
            return "\(hours)h \(remM)m"
        }

        let days = hours / 24
        let remH = hours % 24

        if remH == 0 { return "\(days)d" }
        return "\(days)d \(remH)h"
    }
}

struct WidgetWeaverLockScreenNextUpWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.lockScreenNextUp

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverLockScreenNextUpProvider()) { entry in
            WidgetWeaverLockScreenNextUpView(entry: entry)
                .wwWidgetContainerBackground()
        }
        .configurationDisplayName("Next Up (WidgetWeaver)")
        .description("Next calendar event with a live countdown.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Container background helper (Lock Screen / accessory widgets)

private extension View {
    @ViewBuilder
    func wwWidgetContainerBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) {
                Color.clear
            }
        } else {
            self
        }
    }
}
