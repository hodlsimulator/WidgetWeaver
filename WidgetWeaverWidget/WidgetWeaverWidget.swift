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

    public init(date: Date, family: WidgetFamily, spec: WidgetSpec) {
        self.date = date
        self.family = family
        self.spec = spec
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

    // Computed (not stored) to avoid nonisolated global shared mutable state
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
        Entry(date: Date(), family: context.family, spec: WidgetSpec.defaultSpec())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let spec = resolveSpec(for: configuration)
        return Entry(date: Date(), family: context.family, spec: spec)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let spec = resolveSpec(for: configuration)

        let usesWeather = spec.usesWeatherRendering()
        let usesTime = spec.usesTimeDependentRendering()
        let usesCalendar = (spec.layout.template == LayoutTemplateToken.nextUpCalendar)
        let usesSteps = spec.usesStepsRendering()

        if !context.isPreview {
            if usesWeather {
                Task.detached(priority: .utility) {
                    _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded(force: false)
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
        }

        let now = Date()

        var refreshSeconds: TimeInterval = usesTime ? 60 : (60 * 60)

        // Weather (template or variables) should tick every minute for live nowcast text.
        if usesWeather {
            refreshSeconds = 60
        }

        if usesCalendar {
            refreshSeconds = min(refreshSeconds, 60)
        }

        if usesSteps && !usesTime {
            refreshSeconds = min(refreshSeconds, max(60, WidgetWeaverStepsStore.shared.recommendedRefreshIntervalSeconds()))
        }

        let base: Date
        if refreshSeconds <= 60 {
            base = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now
        } else {
            base = now
        }

        let horizon: TimeInterval = 60 * 60
        let count = max(2, Int(horizon / refreshSeconds) + 1)

        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for i in 0..<count {
            let t = base.addingTimeInterval(TimeInterval(i) * refreshSeconds)
            entries.append(Entry(date: t, family: context.family, spec: spec))
        }

        let policy: TimelineReloadPolicy
        if usesWeather {
            // Pull a fresh WeatherKit snapshot periodically so the next-hour window stays accurate.
            policy = .after(now.addingTimeInterval(60 * 10))
        } else {
            policy = .atEnd
        }

        return Timeline(entries: entries, policy: policy)
    }

    private func resolveSpec(for configuration: Intent) -> WidgetSpec {
        if
            let idString = configuration.design?.id,
            let id = UUID(uuidString: idString),
            let loaded = WidgetSpecStore.shared.load(id: id)
        {
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
            kind: kind,
            intent: WidgetWeaverDesignSelectionIntent.self,
            provider: WidgetWeaverProvider()
        ) { entry in
            WidgetWeaverSpecView(spec: entry.spec, family: entry.family, context: .widget)
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
        // Fire-and-forget refresh (does not capture `completion`)
        if !context.isPreview {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded(force: false)
            }
        }

        let store = WidgetWeaverWeatherStore.shared
        let hasLocation = context.isPreview ? true : (store.loadLocation() != nil)
        let snap = context.isPreview ? store.snapshotForRender(context: .preview) : store.loadSnapshot()

        let now = Date()
        let base = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now

        let count = 60
        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for i in 0..<count {
            let d = base.addingTimeInterval(TimeInterval(i) * 60)
            entries.append(Entry(date: d, hasLocation: hasLocation, snapshot: snap))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WidgetWeaverLockScreenWeatherView: View {
    let entry: WidgetWeaverLockScreenWeatherEntry

    var body: some View {
        let now = entry.date

        if !entry.hasLocation {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set a location")
                    .font(.headline)
                    .bold()
                Text("Open WidgetWeaver to choose one.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else if let snapshot = entry.snapshot {
            weatherContent(snapshot: snapshot, now: now)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("Updating…")
                    .font(.headline)
                    .bold()
                Text("Open the app to refresh now.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func weatherContent(snapshot: WidgetWeaverWeatherSnapshot, now: Date) -> some View {
        let unit = WidgetWeaverWeatherStore.shared.resolvedUnitTemperature()
        let temp = Measurement(value: snapshot.temperatureC, unit: UnitTemperature.celsius).converted(to: unit).value
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
        // Fire-and-forget refresh (does not capture `completion`)
        if !context.isPreview {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: false)
            }
        }

        let store = WidgetWeaverCalendarStore.shared
        let hasAccess = context.isPreview ? true : store.canReadEvents()
        let snap: WidgetWeaverCalendarSnapshot? = context.isPreview ? .sample() : store.loadSnapshot()

        let now = Date()
        let base = Calendar.current.dateInterval(of: .minute, for: now)?.start ?? now

        let count = 60
        var entries: [Entry] = []
        entries.reserveCapacity(count)

        for i in 0..<count {
            let d = base.addingTimeInterval(TimeInterval(i) * 60)
            entries.append(Entry(date: d, hasAccess: hasAccess, snapshot: snap))
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct WidgetWeaverLockScreenNextUpView: View {
    let entry: WidgetWeaverLockScreenNextUpEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        let now = entry.date

        Group {
            if !entry.hasAccess {
                Text("Calendar access off")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let snap = entry.snapshot, let next = snap.next {
                content(now: now, next: next, after: snap.second)
            } else {
                Text("No upcoming events")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func content(now: Date, next: WidgetWeaverCalendarEvent, after: WidgetWeaverCalendarEvent?) -> some View {
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

                if let after {
                    let afterLabel = calendarCountdownLabel(from: now, to: after.startDate, end: after.endDate)
                    Text("After: \(after.title) (\(afterLabel))")
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
    }

    private func calendarShortCountdownValue(from now: Date, to start: Date, end: Date) -> String {
        if start <= now, end > now { return compactIntervalString(seconds: end.timeIntervalSince(now)) }
        if start > now { return compactIntervalString(seconds: start.timeIntervalSince(now)) }
        return "Now"
    }

    private func calendarCountdownLabel(from now: Date, to start: Date, end: Date) -> String {
        if start <= now, end > now { return "ends in \(compactIntervalString(seconds: end.timeIntervalSince(now)))" }
        if start > now { return "in \(compactIntervalString(seconds: start.timeIntervalSince(now)))" }
        return "now"
    }

    private func compactIntervalString(seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        let minutes = Int(ceil(s / 60.0))

        if minutes < 60 { return "\(minutes)m" }

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
            self.containerBackground(for: .widget) { Color.clear }
        } else {
            self
        }
    }
}
