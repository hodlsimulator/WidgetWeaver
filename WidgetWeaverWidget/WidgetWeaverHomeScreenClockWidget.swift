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
    /// Keep comfortably under the “too many entries” danger zone.
    static let maxEntriesPerTimeline: Int = 120

    /// Budget-safe second-hand movement: a short tick interval + linear interpolation.
    /// 10s * 120 entries = 20 minutes of coverage per timeline.
    static let secondsTickSeconds: TimeInterval = 10.0

    static let defaultTickMode: WidgetWeaverClockTickMode = .secondsSweep
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverHomeScreenClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        return Entry(
            date: now,
            tickMode: .secondsSweep,
            tickSeconds: WWClockTimelineConfig.secondsTickSeconds,
            colourScheme: .classic
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let scheme = configuration.colourScheme ?? .classic
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        let tickMode: WidgetWeaverClockTickMode = isLowPower ? .minuteOnly : WWClockTimelineConfig.defaultTickMode
        let tickSeconds: TimeInterval = (tickMode == .secondsSweep) ? WWClockTimelineConfig.secondsTickSeconds : 60.0

        return Entry(
            date: now,
            tickMode: tickMode,
            tickSeconds: tickSeconds,
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let scheme = configuration.colourScheme ?? .classic
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        WWClockInstrumentation.recordTimelineBuild(now: now)

        // Previews should stay cheap and predictable.
        if context.isPreview { return makeMinuteTimeline(now: now, colourScheme: scheme) }

        // Low Power Mode forces minute-only.
        if isLowPower { return makeMinuteTimeline(now: now, colourScheme: scheme) }

        // Shipping path: short tick entries + linear sweep between entries.
        return makeSecondsSweepTimeline(now: now, colourScheme: scheme)
    }

    // MARK: - Timelines

    private func makeMinuteTimeline(now: Date, colourScheme: WidgetWeaverClockColourScheme) -> Timeline<Entry> {
        let minuteAnchorNow = Self.floorToMinute(now)

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineConfig.maxEntriesPerTimeline)

        entries.append(
            Entry(
                date: minuteAnchorNow,
                tickMode: .minuteOnly,
                tickSeconds: 60.0,
                colourScheme: colourScheme
            )
        )

        var next = minuteAnchorNow.addingTimeInterval(60.0)
        while entries.count < WWClockTimelineConfig.maxEntriesPerTimeline {
            entries.append(
                Entry(
                    date: next,
                    tickMode: .minuteOnly,
                    tickSeconds: 60.0,
                    colourScheme: colourScheme
                )
            )
            next = next.addingTimeInterval(60.0)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    private func makeSecondsSweepTimeline(now: Date, colourScheme: WidgetWeaverClockColourScheme) -> Timeline<Entry> {
        let tick = WWClockTimelineConfig.secondsTickSeconds
        let start = Self.floorToSecond(now)

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineConfig.maxEntriesPerTimeline)

        entries.append(
            Entry(
                date: start,
                tickMode: .secondsSweep,
                tickSeconds: tick,
                colourScheme: colourScheme
            )
        )

        var next = start.addingTimeInterval(tick)
        while entries.count < WWClockTimelineConfig.maxEntriesPerTimeline {
            entries.append(
                Entry(
                    date: next,
                    tickMode: .secondsSweep,
                    tickSeconds: tick,
                    colourScheme: colourScheme
                )
            )
            next = next.addingTimeInterval(tick)
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    // MARK: - Time helpers

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }

    private static func floorToSecond(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t)
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
