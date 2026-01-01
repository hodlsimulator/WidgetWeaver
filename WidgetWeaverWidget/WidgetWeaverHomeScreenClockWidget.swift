//
//  WidgetWeaverHomeScreenClockWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/23/25.
//

import AppIntents
import Foundation
import SwiftUI
import WidgetKit

enum WidgetWeaverClockColourScheme: Int, AppEnum, CaseIterable {
    case classic
    case ocean
    case mint
    case orchid
    case sunset
    case ember
    case graphite

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Clock Colour Scheme" }

    static var caseDisplayRepresentations: [WidgetWeaverClockColourScheme: DisplayRepresentation] {
        [
            .classic: "Classic",
            .ocean: "Ocean",
            .mint: "Mint",
            .orchid: "Orchid",
            .sunset: "Sunset",
            .ember: "Ember",
            .graphite: "Graphite",
        ]
    }
}

struct WidgetWeaverHomeScreenClockConfigurationIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Clock" }
    static var description: IntentDescription { IntentDescription("Configure the clock widget.") }

    @Parameter(title: "Colour Scheme")
    var colourScheme: WidgetWeaverClockColourScheme?

    init() {
        self.colourScheme = .classic
    }
}

enum WidgetWeaverClockTickMode: Int {
    case minuteOnly = 0
    case secondsSweep = 1
}

struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    let date: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval
    let colourScheme: WidgetWeaverClockColourScheme
}

private enum WWClockTimelineConfig {
    // 24 hours of 5-minute entries (WidgetKit guidance is to avoid sub-5-minute schedules).
    static let maxEntriesPerTimeline: Int = 288
    static let step: TimeInterval = 300.0
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverHomeScreenClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        let anchor = Self.floorToStep(now, step: WWClockTimelineConfig.step)

        return Entry(
            date: anchor,
            tickMode: .minuteOnly,
            tickSeconds: WWClockTimelineConfig.step,
            colourScheme: .classic
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let scheme = configuration.colourScheme ?? .classic
        let anchor = Self.floorToStep(now, step: WWClockTimelineConfig.step)

        return Entry(
            date: anchor,
            tickMode: .minuteOnly,
            tickSeconds: WWClockTimelineConfig.step,
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let scheme = configuration.colourScheme ?? .classic

        WWClockInstrumentation.recordTimelineBuild(now: now)

        return makeTimeline(now: now, colourScheme: scheme)
    }

    private func makeTimeline(now: Date, colourScheme: WidgetWeaverClockColourScheme) -> Timeline<Entry> {
        let anchorNow = Self.floorToStep(now, step: WWClockTimelineConfig.step)

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineConfig.maxEntriesPerTimeline)

        var t = anchorNow
        while entries.count < WWClockTimelineConfig.maxEntriesPerTimeline {
            entries.append(
                Entry(
                    date: t,
                    tickMode: .minuteOnly,
                    tickSeconds: WWClockTimelineConfig.step,
                    colourScheme: colourScheme
                )
            )
            t = t.addingTimeInterval(WWClockTimelineConfig.step)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    private static func floorToStep(_ date: Date, step: TimeInterval) -> Date {
        guard step > 0 else { return date }
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / step) * step
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

// MARK: - Instrumentation (App Group)

private enum WWClockInstrumentation {
    private static let lastKey = "widgetweaver.clock.timelineBuild.last"
    private static let countPrefix = "widgetweaver.clock.timelineBuild.count."

    static func recordTimelineBuild(now: Date) {
        let defaults = AppGroup.userDefaults
        defaults.set(now, forKey: lastKey)

        let dayKey = Self.dayKey(for: now)
        let countKey = countPrefix + dayKey
        let c = defaults.integer(forKey: countKey)
        defaults.set(c + 1, forKey: countKey)
    }

    private static func dayKey(for date: Date) -> String {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d%02d%02d", y, m, d)
    }
}

struct WidgetWeaverHomeScreenClockWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.homeScreenClock

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetWeaverHomeScreenClockConfigurationIntent.self,
            provider: WidgetWeaverHomeScreenClockProvider()
        ) { entry in
            WidgetWeaverHomeScreenClockView(entry: entry)
        }
        .configurationDisplayName("Clock (Icon)")
        .description("A small analogue clock.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: colorScheme
        )

        WidgetWeaverClockWidgetLiveView(
            palette: palette,
            entryDate: entry.date,
            tickMode: entry.tickMode,
            tickSeconds: entry.tickSeconds
        )
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
