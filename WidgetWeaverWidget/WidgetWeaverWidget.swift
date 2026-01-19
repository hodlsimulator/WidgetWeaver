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

public struct WidgetWeaverDesignSelectionIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "Design" }

    public static var description: IntentDescription {
        IntentDescription("Choose a saved WidgetWeaver design for this widget.")
    }

    @Parameter(title: "Design")
    public var design: WidgetWeaverDesignChoice?

    public static var parameterSummary: some ParameterSummary {
        Summary("Design: \(\.$design)")
    }

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

        // Clock (Icon) designs are time-dependent and previously used the generic minute-level
        // timeline builder (up to 240 distinct entries). WidgetKit may pre-render a large portion
        // of the timeline ahead-of-time; for the clock face this can exceed WidgetKit's
        // time/memory budget and it will fall back to a placeholder. Keep the timeline shallow
        // and re-query frequently.
        if familySpec.layout.template == .clockIcon {
            return makeClockIconMinuteTimeline(now: now, family: context.family, spec: spec)
        }

        let shuffleSchedule = SmartPhotoShuffleSchedule.load(for: familySpec, now: now)

        // Poster-only shuffle: schedule entries exactly at rotation boundaries.
        //
        // Important:
        // WidgetKit may pre-render a lot of timeline entries ahead-of-time. If each entry decodes a different
        // photo, a dense timeline can exceed WidgetKit’s time/memory budget and the system will fall back to
        // a placeholder.
        //
        // Keep this timeline deliberately small and ask WidgetKit to reload again soon.
        if let shuffleSchedule,
           !usesWeather,
           !usesTime,
           !usesCalendar,
           !usesSteps,
           !usesActivity
        {
            let interval = shuffleSchedule.intervalSeconds

            // Guardrail:
            // WidgetKit may pre-render a large portion of the timeline. For fast shuffle intervals
            // (notably the 2-minute testing option), keep the number of future rotations extremely small
            // so we do not decode a long run of distinct images ahead-of-time.
            let targetHorizon: TimeInterval = 60 * 30 // 30 minutes

            // 3–6 entries total (now + 2–5 future rotation boundaries).
            let baseDesiredEntries = max(3, min(6, Int((targetHorizon / interval).rounded(.down)) + 3))

            let desiredEntries: Int = {
                if interval <= 60 * 5 {
                    // Fast testing: now + 3 rotation boundaries.
                    return min(baseDesiredEntries, 4)
                }
                if interval <= 60 * 15 {
                    // Still fast: now + 4 rotation boundaries.
                    return min(baseDesiredEntries, 5)
                }
                return baseDesiredEntries
            }()

            var entries: [Entry] = []
            entries.reserveCapacity(desiredEntries)

            entries.append(Entry(date: now, family: context.family, spec: spec, isWidgetKitPreview: false))

            var d = shuffleSchedule.nextChangeDate
            if d <= now {
                d = now.addingTimeInterval(interval)
            }

            while entries.count < desiredEntries {
                entries.append(Entry(date: d, family: context.family, spec: spec, isWidgetKitPreview: false))
                d = d.addingTimeInterval(interval)
            }

            let reload = (entries.last?.date ?? now).addingTimeInterval(1)
            return Timeline(entries: entries, policy: .after(reload))
        }

        // Note:
        // The Home Screen widget host does not reliably run view-level minute timers for wall-clock text.
        // To keep time-based text (for example {{__time}}) accurate, drive updates via the WidgetKit timeline
        // even for photo posters (Photo Clock).
        let prefersViewLevelTimeTick: Bool = false

        // Base refresh:
        // - Most widgets: hourly
        // - Time-dependent widgets (including Photo Clock posters): every minute
        var refreshSeconds: TimeInterval = (usesTime && !prefersViewLevelTimeTick) ? 60 : (60 * 60)

        if let shuffleSchedule {
            refreshSeconds = min(refreshSeconds, shuffleSchedule.intervalSeconds)
        }

        // Weather (template or variables) should tick every minute for live nowcast text.
        if usesWeather { refreshSeconds = 60 }
        if usesCalendar { refreshSeconds = min(refreshSeconds, 60) }

        if usesSteps {
            refreshSeconds = min(refreshSeconds, max(60, WidgetWeaverStepsStore.shared.recommendedRefreshIntervalSeconds()))
        }

        if usesActivity {
            refreshSeconds = min(refreshSeconds, max(60, WidgetWeaverActivityStore.shared.recommendedRefreshIntervalSeconds()))
        }
        // Align to minute boundaries for clock-like text, but still include an immediate `now` entry
        // so design edits can refresh within the current minute.
        let alignedBase: Date = {
            if refreshSeconds <= 60 {
                let t = now.timeIntervalSince1970
                let aligned = floor(t / 60.0) * 60.0
                return Date(timeIntervalSince1970: aligned)
            }
            return now
        }()

        // Buffer enough future entries so the widget doesn't "run out" if WidgetKit delays reloads.
        let maxEntries: Int = {
            if let shuffleSchedule {
                // Guardrail for fast shuffle intervals: keep the future timeline shallow so WidgetKit
                // cannot pre-render a long sequence of distinct photos (budget storm / placeholder fallback).
                if shuffleSchedule.intervalSeconds <= 60 * 5 {
                    return 10
                }
                if shuffleSchedule.intervalSeconds <= 60 * 15 {
                    return 16
                }
            }
            return 240
        }()
        let desiredHorizon: TimeInterval = 60 * 60 * 6
        let horizon: TimeInterval = min(desiredHorizon, refreshSeconds * Double(maxEntries - 1))
        let count = max(2, Int(horizon / refreshSeconds) + 1)

        var dates: [Date] = []
        dates.reserveCapacity(count + 12)

        // Always include an immediate entry so WidgetKit can redraw straight away.
        dates.append(now)

        for i in 0..<count {
            dates.append(alignedBase.addingTimeInterval(TimeInterval(i) * refreshSeconds))
        }

        // Ensure the widget renders at shuffle boundaries, not merely at fixed intervals
        // starting from `now`. This prevents drift where the Home Screen snapshot can
        // stay on an old photo until the next periodic refresh.
        if let shuffleSchedule {
            let interval = shuffleSchedule.intervalSeconds
            var d = shuffleSchedule.nextChangeDate
            if d <= now {
                d = now.addingTimeInterval(interval)
            }

            let maxDate = dates.last ?? now
            while d <= maxDate {
                dates.append(d)
                d = d.addingTimeInterval(interval)
            }
        }

        dates.sort()

        // De-duplicate dates (WidgetKit can behave oddly if there are near-equal dates).
        var uniqueDates: [Date] = []
        uniqueDates.reserveCapacity(min(maxEntries, dates.count))

        for d in dates {
            if let last = uniqueDates.last {
                if abs(d.timeIntervalSince(last)) < 0.5 { continue }
            }
            uniqueDates.append(d)
            if uniqueDates.count >= maxEntries { break }
        }

        let entries: [Entry] = uniqueDates.map { d in
            Entry(date: d, family: context.family, spec: spec, isWidgetKitPreview: false)
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

    private func makeClockIconMinuteTimeline(now: Date, family: WidgetFamily, spec: WidgetSpec) -> Timeline<Entry> {
        let minuteAnchor = Self.floorToMinute(now)
        let nextMinuteBoundary = minuteAnchor.addingTimeInterval(60.0)

        // Keep the timeline deliberately shallow.
        // WidgetKit can pre-render a large portion of the timeline; for clock faces this can
        // exceed the rendering budget and the system will fall back to a placeholder.
        //
        // We still ask WidgetKit to reload soon so the widget refresh path remains healthy.
        let entries: [Entry] = [
            // Immediate entry uses `now` so edits mid-minute can render quickly.
            Entry(date: now, family: family, spec: spec, isWidgetKitPreview: false)
        ]

        // Reload shortly after the next minute boundary.
        let reload = nextMinuteBoundary.addingTimeInterval(1.0)
        return Timeline(entries: entries, policy: .after(reload))
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
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

        let intervalMinutes = manifest.rotationIntervalMinutes
        let intervalSeconds = TimeInterval(intervalMinutes) * 60.0

        let next = manifest.nextChangeDateFrom(now: now) ?? now.addingTimeInterval(intervalSeconds)

        return SmartPhotoShuffleSchedule(intervalSeconds: intervalSeconds, nextChangeDate: next)
    }
}

// MARK: - Clock design host (main widget)

private struct WidgetWeaverClockIconDesignWidgetView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let entryDate: Date
    let isLowBudget: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if family != .systemSmall {
            clockUnsupportedSize
        } else {
            let scheme = Self.scheme(for: spec)
            let palette = WidgetWeaverClockPalette.resolve(scheme: scheme, mode: colorScheme)

            Group {
                if isLowBudget {
                    WWMainClockStaticFace(
                        palette: palette,
                        date: entryDate,
                        showsSecondsHand: false
                    )
                } else {
                    WidgetWeaverClockWidgetLiveView(
                        palette: palette,
                        entryDate: entryDate,
                        tickMode: .secondsSweep,
                        tickSeconds: 0.0
                    )
                }
            }
            .wwWidgetContainerBackground {
                WidgetWeaverClockBackgroundView(palette: palette)
            }
            .clipShape(ContainerRelativeShape())
        }
    }

    private var clockUnsupportedSize: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Clock", systemImage: "clock")
                .font(.headline)

            Text("Clock designs are available in Small widgets only.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .wwWidgetContainerBackground {
            Color(.secondarySystemGroupedBackground)
        }
        .clipShape(ContainerRelativeShape())
    }

    private static func scheme(for spec: WidgetSpec) -> WidgetWeaverClockColourScheme {
        let theme = (spec.clockConfig?.theme ?? WidgetWeaverClockDesignConfig.defaultTheme)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch theme {
        case "ocean":
            return .ocean
        case "graphite":
            return .graphite
        default:
            return .classic
        }
    }
}

private struct WWMainClockStaticFace: View {
    let palette: WidgetWeaverClockPalette
    let date: Date
    let showsSecondsHand: Bool

    var body: some View {
        let angles = WWMainClockAngles(date: date)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: angles.hour,
            minuteAngle: angles.minute,
            secondAngle: angles.second,
            showsSecondHand: showsSecondsHand,
            showsMinuteHand: true,
            showsHandShadows: false,
            showsGlows: false,
            showsCentreHub: true,
            handsOpacity: 1.0
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct WWMainClockAngles {
    let hour: Angle
    let minute: Angle
    let second: Angle

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = secondInt + (nano / 1_000_000_000.0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        let hourDeg = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
        let minuteDeg = (minuteInt + sec / 60.0) * 6.0
        let secondDeg = sec * 6.0

        self.hour = .degrees(hourDeg)
        self.minute = .degrees(minuteDeg)
        self.second = .degrees(secondDeg)
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
            let liveSpec = WidgetSpecStore.shared.load(id: entry.spec.id) ?? entry.spec

            let familySpec = liveSpec.resolved(for: entry.family)

            Group {
                if familySpec.layout.template == .clockIcon {
                    WidgetWeaverClockIconDesignWidgetView(
                        spec: familySpec,
                        family: entry.family,
                        entryDate: entry.date,
                        isLowBudget: entry.isWidgetKitPreview
                    )
                } else {
                    WidgetWeaverSpecView(spec: liveSpec, family: entry.family, context: .widget, now: entry.date)
                        .environment(\.wwLowGraphicsBudget, entry.isWidgetKitPreview)
                        .environment(\.wwThumbnailRenderingEnabled, !entry.isWidgetKitPreview)
                }
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
        .containerBackground(.fill.tertiary, for: .widget)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        }
        .configurationDisplayName("Rain (WidgetWeaver)")
        .description("Next hour precipitation, temperature, and nowcast.")
        .supportedFamilies([.accessoryRectangular])
    }
}
