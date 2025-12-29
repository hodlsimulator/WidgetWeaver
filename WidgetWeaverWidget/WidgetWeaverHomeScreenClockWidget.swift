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

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Clock Colour Scheme"
    }

    static var caseDisplayRepresentations: [WidgetWeaverClockColourScheme: DisplayRepresentation] {
        [
            .classic: "Classic",
            .ocean: "Ocean",
            .mint: "Mint",
            .orchid: "Orchid",
            .sunset: "Sunset",
            .ember: "Ember",
            .graphite: "Graphite"
        ]
    }
}

struct WidgetWeaverHomeScreenClockConfigurationIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Clock" }

    static var description: IntentDescription {
        IntentDescription("Configure the clock widget.")
    }

    @Parameter(title: "Colour Scheme")
    var colourScheme: WidgetWeaverClockColourScheme?

    init() {
        self.colourScheme = .classic
    }
}

struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    let date: Date
    let anchorDate: Date
    let tickSeconds: TimeInterval
    let colourScheme: WidgetWeaverClockColourScheme
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverHomeScreenClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        return makeEntry(
            date: now,
            tickSeconds: defaultTickSeconds(isLowPower: isLowPower),
            colourScheme: .classic
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let scheme = configuration.colourScheme ?? .classic

        return makeEntry(
            date: now,
            tickSeconds: defaultTickSeconds(isLowPower: isLowPower),
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let scheme = configuration.colourScheme ?? .classic

        if isLowPower {
            // Low Power Mode: minute-level only, no seconds.
            return makeMinuteTimeline(now: now, colourScheme: scheme, horizonSeconds: 2.0 * 60.0 * 60.0)
        }

        switch WidgetWeaverClockMotionConfig.implementation {
        case .timeDrivenPrimitives:
            // Sparse timeline; the view attempts to tick via time-driven primitives when supported.
            let entry = makeEntry(date: now, tickSeconds: 1.0, colourScheme: scheme)

            let nextRefresh = now.addingTimeInterval(60.0 * 60.0) // hourly
            return Timeline(entries: [entry], policy: .after(nextRefresh))

        case .burstTimelineHybrid:
            // Hybrid: short 1 Hz burst, then minute-level timeline entries.
            return makeBurstHybridTimeline(now: now, colourScheme: scheme)
        }
    }

    // MARK: - Timeline builders

    private func defaultTickSeconds(isLowPower: Bool) -> TimeInterval {
        if isLowPower { return 60.0 }

        switch WidgetWeaverClockMotionConfig.implementation {
        case .timeDrivenPrimitives:
            return 1.0
        case .burstTimelineHybrid:
            return 60.0
        }
    }

    private func makeEntry(date: Date, tickSeconds: TimeInterval, colourScheme: WidgetWeaverClockColourScheme) -> Entry {
        Entry(
            date: date,
            anchorDate: Self.floorToWholeSecond(date),
            tickSeconds: tickSeconds,
            colourScheme: colourScheme
        )
    }

    private func makeMinuteTimeline(
        now: Date,
        colourScheme: WidgetWeaverClockColourScheme,
        horizonSeconds: TimeInterval
    ) -> Timeline<Entry> {
        let horizonEnd = now.addingTimeInterval(horizonSeconds)

        var entries: [Entry] = []
        entries.reserveCapacity(1 + Int(horizonSeconds / 60.0) + 2)

        // Immediate correctness.
        entries.append(makeEntry(date: now, tickSeconds: 60.0, colourScheme: colourScheme))

        // Then update on minute boundaries.
        var next = Self.nextMinuteBoundary(after: now)
        while next <= horizonEnd {
            entries.append(makeEntry(date: next, tickSeconds: 60.0, colourScheme: colourScheme))
            next = next.addingTimeInterval(60.0)
        }

        return Timeline(entries: entries, policy: .after(horizonEnd))
    }

    private func makeBurstHybridTimeline(
        now: Date,
        colourScheme: WidgetWeaverClockColourScheme
    ) -> Timeline<Entry> {
        let horizonEnd = now.addingTimeInterval(WidgetWeaverClockMotionConfig.burstTimelineHorizonSeconds)
        let shouldBurst = WidgetWeaverClockBurstBudget.consumeBurstAllowance(now: now)

        guard shouldBurst else {
            // No burst allowed right now: minute-only timeline, still budget-safe.
            return makeMinuteTimeline(
                now: now,
                colourScheme: colourScheme,
                horizonSeconds: WidgetWeaverClockMotionConfig.burstTimelineHorizonSeconds
            )
        }

        var entries: [Entry] = []
        entries.reserveCapacity(
            1 + WidgetWeaverClockMotionConfig.burstSeconds + 1 + Int(WidgetWeaverClockMotionConfig.burstTimelineHorizonSeconds / 60.0) + 2
        )

        // Immediate correctness.
        entries.append(makeEntry(date: now, tickSeconds: 1.0, colourScheme: colourScheme))

        // 1 Hz burst.
        if WidgetWeaverClockMotionConfig.burstSeconds > 0 {
            for i in 1...WidgetWeaverClockMotionConfig.burstSeconds {
                let t = now.addingTimeInterval(TimeInterval(i))
                entries.append(makeEntry(date: t, tickSeconds: 1.0, colourScheme: colourScheme))
            }
        }

        // Burst end: drop to minute-level, keeping time correct at the transition.
        let burstEnd = now.addingTimeInterval(TimeInterval(WidgetWeaverClockMotionConfig.burstSeconds))
        entries.append(makeEntry(date: burstEnd, tickSeconds: 60.0, colourScheme: colourScheme))

        // Then minute boundaries to the horizon.
        var next = Self.nextMinuteBoundary(after: burstEnd)
        while next <= horizonEnd {
            entries.append(makeEntry(date: next, tickSeconds: 60.0, colourScheme: colourScheme))
            next = next.addingTimeInterval(60.0)
        }

        return Timeline(entries: entries, policy: .after(horizonEnd))
    }

    // MARK: - Rounding helpers

    private static func floorToWholeSecond(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: floor(t))
    }

    private static func nextMinuteBoundary(after date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let next = (floor(t / 60.0) + 1.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: next)
    }
}

// MARK: - Burst budget guard

private enum WidgetWeaverClockBurstBudget {
    private static let lastBurstKey = "widgetweaver.clock.burst.last"
    private static let countPrefix = "widgetweaver.clock.burst.count."

    static func consumeBurstAllowance(now: Date) -> Bool {
        let defaults = AppGroup.userDefaults

        let last = defaults.object(forKey: lastBurstKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= WidgetWeaverClockMotionConfig.burstMinSpacingSeconds else {
            return false
        }

        let dayKey = Self.dayKey(for: now)
        let countKey = countPrefix + dayKey
        let count = defaults.integer(forKey: countKey)
        guard count < WidgetWeaverClockMotionConfig.burstMaxPerDay else {
            return false
        }

        defaults.set(now, forKey: lastBurstKey)
        defaults.set(count + 1, forKey: countKey)

        return true
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
            date: entry.date,
            anchorDate: entry.anchorDate,
            tickSeconds: entry.tickSeconds
        )
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
