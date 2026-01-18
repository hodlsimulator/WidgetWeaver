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

struct WidgetWeaverHomeScreenClockConfigurationIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Clock" }
    static var description: IntentDescription { IntentDescription("Configure the clock widget.") }

    @Parameter(title: "Colour Scheme", default: .classic)
    var colourScheme: WidgetWeaverClockColourScheme

    init() {}
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
    /// 120 minute-boundary entries (plus the current minute anchor) ≈ 2 hours of reliable ticking.
    /// Kept intentionally small to stay within WidgetKit’s timeline budget.
    static let maxEntriesPerTimeline: Int = 121

    /// Request a refresh *before* the current timeline runs out.
    /// This prevents a gap (no future entries) that makes WidgetKit fall back to placeholder rendering.
    static let reloadAfterMinutes: Int = 60
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverHomeScreenClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()

        return Entry(
            date: now,
            tickMode: .secondsSweep,
            tickSeconds: 0.0,
            colourScheme: .classic
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let scheme = configuration.colourScheme

        return Entry(
            date: now,
            tickMode: .secondsSweep,
            tickSeconds: 0.0,
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let scheme = configuration.colourScheme

        WWClockInstrumentation.recordTimelineBuild(now: now)

        // Minute-boundary entries are reliable for hour/minute ticks.
        // The seconds hand is handled by a time-aware SwiftUI text view, not the timeline.
        return makeMinuteTimeline(now: now, colourScheme: scheme)
    }

    private func makeMinuteTimeline(now: Date, colourScheme: WidgetWeaverClockColourScheme) -> Timeline<Entry> {
        let minuteAnchorNow = Self.floorToMinute(now)
        // Offset the timeline dates by a tiny amount derived from the colour scheme.
        //
        // WidgetKit can keep an archived rendering for an entry *date*. If a user changes the
        // configuration mid-minute, the minute-anchored entry date can remain identical, and the
        // widget may not visually update until the next minute boundary. This keeps minute-boundary
        // stability while ensuring the current entry date changes when the scheme changes.
        let schemeOffset = TimeInterval(colourScheme.rawValue) / 1000.0

        let firstEntryDate = minuteAnchorNow.addingTimeInterval(schemeOffset)
        let nextMinuteBoundary = firstEntryDate.addingTimeInterval(60.0)

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineConfig.maxEntriesPerTimeline)

        // Immediate entry (aligned to the current minute boundary, with a tiny scheme offset).
        //
        // Using `now` here causes the minute hand to jump mid-minute whenever WidgetKit reloads the
        // timeline, which reads as “late ticking”. Keeping the first entry on the minute anchor makes
        // the widget stable until the next minute-boundary entry.
        entries.append(
            Entry(
                date: firstEntryDate,
                tickMode: .secondsSweep,
                tickSeconds: 0.0,
                colourScheme: colourScheme
            )
        )

        // Minute-boundary entries.
        var next = nextMinuteBoundary
        while entries.count < WWClockTimelineConfig.maxEntriesPerTimeline {
            entries.append(
                Entry(
                    date: next,
                    tickMode: .secondsSweep,
                    tickSeconds: 0.0,
                    colourScheme: colourScheme
                )
            )
            next = next.addingTimeInterval(60.0)
        }

        let reloadDate = minuteAnchorNow.addingTimeInterval(
            TimeInterval(WWClockTimelineConfig.reloadAfterMinutes * 60)
        )

        WWClockDebugLog.appendLazy(
            category: "clock",
            throttleID: "clockWidget.provider.timeline",
            minInterval: 60.0,
            now: now
        ) {
            let nowRef = Int(now.timeIntervalSinceReferenceDate.rounded())
            let anchorRef = Int(minuteAnchorNow.timeIntervalSinceReferenceDate.rounded())
            let nextRef = Int(nextMinuteBoundary.timeIntervalSinceReferenceDate.rounded())

            let firstRef = Int((entries.first?.date ?? now).timeIntervalSinceReferenceDate.rounded())
            let lastRef = Int((entries.last?.date ?? now).timeIntervalSinceReferenceDate.rounded())

            let reloadRef = Int(reloadDate.timeIntervalSinceReferenceDate.rounded())

            return "provider.timeline nowRef=\(nowRef) anchorRef=\(anchorRef) nextRef=\(nextRef) entries=\(entries.count) firstRef=\(firstRef) lastRef=\(lastRef) reloadRef=\(reloadRef) policy=after"
        }

        return Timeline(entries: entries, policy: .after(reloadDate))
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
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
            // Force per-entry refresh on the Home Screen.
            //
            // WidgetKit can keep an archived snapshot and stop applying timeline advances. On device,
            // that often surfaces as a black/placeholder tile (preview looks fine, Home Screen is not).
            WidgetWeaverHomeScreenClockView(entry: entry)
                .id(entry.date)
                .transaction { transaction in
                    transaction.animation = nil
                }
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
