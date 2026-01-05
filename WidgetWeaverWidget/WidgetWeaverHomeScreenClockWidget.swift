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
    /// Keep the entry count fixed for budget safety.
    /// 1 “now” entry + 120 scheduled entries.
    static let maxEntriesPerTimeline: Int = 121

    /// Hour/minute refresh cadence.
    /// Keep this at 60s (minute boundary).
    /// Smooth/continuous motion is handled in-view (time-aware) for the seconds-sweep mode.
    static let tickStepSeconds: TimeInterval = 60.0
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
        let scheme = configuration.colourScheme ?? .classic

        return Entry(
            date: now,
            tickMode: .secondsSweep,
            tickSeconds: 0.0,
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let scheme = configuration.colourScheme ?? .classic

        WWClockInstrumentation.recordTimelineBuild(now: now)

        // Hour/minute hands: timeline-driven. Seconds: time-aware glyph text.
        return makeTickTimeline(now: now, colourScheme: scheme)
    }

    private func makeTickTimeline(now: Date, colourScheme: WidgetWeaverClockColourScheme) -> Timeline<Entry> {
        let step = WWClockTimelineConfig.tickStepSeconds

        let stepAnchorNow = Self.floorToStep(now, stepSeconds: step)
        let nextBoundary = stepAnchorNow.addingTimeInterval(step)

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineConfig.maxEntriesPerTimeline)

        // Immediate entry.
        entries.append(
            Entry(
                date: now,
                tickMode: .secondsSweep,
                tickSeconds: 0.0,
                colourScheme: colourScheme
            )
        )

        // Step entries (minute cadence).
        var next = nextBoundary
        while entries.count < WWClockTimelineConfig.maxEntriesPerTimeline {
            entries.append(
                Entry(
                    date: next,
                    tickMode: .secondsSweep,
                    tickSeconds: 0.0,
                    colourScheme: colourScheme
                )
            )
            next = next.addingTimeInterval(step)
        }

        WWClockDebugLog.appendLazy(
            category: "clock",
            throttleID: "clockWidget.provider.timeline",
            minInterval: 60.0,
            now: now
        ) {
            let nowRef = Int(now.timeIntervalSinceReferenceDate.rounded())
            let anchorRef = Int(stepAnchorNow.timeIntervalSinceReferenceDate.rounded())
            let nextRef = Int(nextBoundary.timeIntervalSinceReferenceDate.rounded())

            let firstRef = Int((entries.first?.date ?? now).timeIntervalSinceReferenceDate.rounded())
            let lastRef = Int((entries.last?.date ?? now).timeIntervalSinceReferenceDate.rounded())

            let stepMs = Int((step * 1000.0).rounded())

            return "provider.timeline nowRef=\(nowRef) anchorRef=\(anchorRef) nextRef=\(nextRef) stepMs=\(stepMs) entries=\(entries.count) firstRef=\(firstRef) lastRef=\(lastRef) policy=atEnd"
        }

        return Timeline(entries: entries, policy: .atEnd)
    }

    private static func floorToStep(_ date: Date, stepSeconds: TimeInterval) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / stepSeconds) * stepSeconds
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
            // Without an entry-keyed identity, WidgetKit can keep an archived snapshot and the minute hand
            // will lag (even if the provider is generating correct minute-boundary entries).
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
