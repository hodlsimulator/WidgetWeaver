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

private enum WWClockBurstConfig {
    static let burstSeconds: Int = 60
    static let minuteHorizonSeconds: TimeInterval = 60.0 * 60.0 // 1 hour

    static let sessionMaxSeconds: TimeInterval = 60.0 * 30.0 // 30 minutes
    static let sessionMaxPerDay: Int = 2
    static let sessionMinSpacingSeconds: TimeInterval = 60.0 * 60.0 * 4.0 // 4 hours

    #if DEBUG
    static let autoStartSessionInDebug: Bool = true
    static let debugIgnoreSessionCaps: Bool = true
    static let debugInactiveRetrySeconds: TimeInterval = 10.0
    #else
    static let autoStartSessionInDebug: Bool = false
    static let debugIgnoreSessionCaps: Bool = false
    static let debugInactiveRetrySeconds: TimeInterval = 60.0 * 60.0
    #endif
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverHomeScreenClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        return Entry(
            date: now,
            anchorDate: Self.floorToWholeSecond(now),
            tickSeconds: isLowPower ? 60.0 : 60.0,
            colourScheme: .classic
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let scheme = configuration.colourScheme ?? .classic

        return Entry(
            date: now,
            anchorDate: Self.floorToWholeSecond(now),
            tickSeconds: isLowPower ? 60.0 : 60.0,
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let scheme = configuration.colourScheme ?? .classic

        WWClockInstrumentation.recordTimelineBuild(now: now)

        // Never start seconds bursts in previews (widget gallery / template contexts).
        if context.isPreview {
            return makeMinuteTimeline(
                now: now,
                colourScheme: scheme,
                policyAfter: now.addingTimeInterval(60.0 * 60.0)
            )
        }

        if isLowPower {
            return makeMinuteTimeline(
                now: now,
                colourScheme: scheme,
                policyAfter: now.addingTimeInterval(60.0 * 60.0)
            )
        }

        let plan = WWClockBurstSession.sessionPlan(now: now, isPreview: context.isPreview)

        if plan.sessionActive {
            return makeBurstThenMinuteTimeline(
                now: now,
                sessionUntil: plan.sessionUntil,
                colourScheme: scheme,
                allowChaining: plan.allowChaining
            )
        } else {
            // In DEBUG, retry soon so seconds mode can kick in without waiting for a long policy delay.
            let retryAfter = now.addingTimeInterval(WWClockBurstConfig.debugInactiveRetrySeconds)

            return makeMinuteTimeline(
                now: now,
                colourScheme: scheme,
                policyAfter: retryAfter
            )
        }
    }

    // MARK: - Timeline builders

    private func makeMinuteTimeline(now: Date, colourScheme: WidgetWeaverClockColourScheme, policyAfter: Date) -> Timeline<Entry> {
        var entries: [Entry] = []
        entries.reserveCapacity(70)

        entries.append(Entry(
            date: now,
            anchorDate: Self.floorToWholeSecond(now),
            tickSeconds: 60.0,
            colourScheme: colourScheme
        ))

        let horizonEnd = now.addingTimeInterval(WWClockBurstConfig.minuteHorizonSeconds)

        var next = Self.nextMinuteBoundary(after: now)
        while next <= horizonEnd {
            entries.append(Entry(
                date: next,
                anchorDate: Self.floorToWholeSecond(next),
                tickSeconds: 60.0,
                colourScheme: colourScheme
            ))
            next = next.addingTimeInterval(60.0)
        }

        return Timeline(entries: entries, policy: .after(policyAfter))
    }

    private func makeBurstThenMinuteTimeline(
        now: Date,
        sessionUntil: Date,
        colourScheme: WidgetWeaverClockColourScheme,
        allowChaining: Bool
    ) -> Timeline<Entry> {
        let burstSeconds = max(1, WWClockBurstConfig.burstSeconds)
        let burstEnd = now.addingTimeInterval(TimeInterval(burstSeconds))

        var entries: [Entry] = []
        entries.reserveCapacity(burstSeconds + 80)

        // 1 Hz seconds
        for i in 0..<burstSeconds {
            let t = now.addingTimeInterval(TimeInterval(i))
            entries.append(Entry(
                date: t,
                anchorDate: Self.floorToWholeSecond(t),
                tickSeconds: 1.0,
                colourScheme: colourScheme
            ))
        }

        // Immediately fall back to minute-mode entry after the burst
        entries.append(Entry(
            date: burstEnd,
            anchorDate: Self.floorToWholeSecond(burstEnd),
            tickSeconds: 60.0,
            colourScheme: colourScheme
        ))

        let horizonEnd = now.addingTimeInterval(WWClockBurstConfig.minuteHorizonSeconds)

        var next = Self.nextMinuteBoundary(after: burstEnd)
        while next <= horizonEnd {
            entries.append(Entry(
                date: next,
                anchorDate: Self.floorToWholeSecond(next),
                tickSeconds: 60.0,
                colourScheme: colourScheme
            ))
            next = next.addingTimeInterval(60.0)
        }

        // Chaining: ask WidgetKit for another timeline exactly at burst end, but only within the session window.
        let chainAllowedNow = allowChaining && (burstEnd < sessionUntil)
        let policyAfter = chainAllowedNow ? burstEnd : horizonEnd

        return Timeline(entries: entries, policy: .after(policyAfter))
    }

    // MARK: - Time helpers

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

// MARK: - Instrumentation

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

// MARK: - Session planner

private enum WWClockBurstSession {
    private static let sessionUntilKey = "widgetweaver.clock.session.until"
    private static let sessionLastStartKey = "widgetweaver.clock.session.lastStart"
    private static let sessionCountPrefix = "widgetweaver.clock.session.count."
    private static let wakeRequestKey = "widgetweaver.clock.wake.request.until"

    struct Plan {
        let sessionActive: Bool
        let allowChaining: Bool
        let sessionUntil: Date
    }

    static func sessionPlan(now: Date, isPreview: Bool) -> Plan {
        let defaults = AppGroup.userDefaults

        if isPreview {
            return Plan(sessionActive: false, allowChaining: false, sessionUntil: .distantPast)
        }

        let existingUntil = (defaults.object(forKey: sessionUntilKey) as? Date) ?? .distantPast
        if existingUntil > now {
            return Plan(sessionActive: true, allowChaining: true, sessionUntil: existingUntil)
        }

        let wakeUntil = (defaults.object(forKey: wakeRequestKey) as? Date) ?? .distantPast
        let wakeRequested = wakeUntil > now
        if wakeRequested {
            defaults.set(Date.distantPast, forKey: wakeRequestKey)
        }

        if wakeRequested {
            if let until = tryBeginSession(now: now, ignoreCaps: WWClockBurstConfig.debugIgnoreSessionCaps) {
                return Plan(sessionActive: true, allowChaining: true, sessionUntil: until)
            } else {
                return Plan(sessionActive: false, allowChaining: false, sessionUntil: .distantPast)
            }
        }

        if WWClockBurstConfig.autoStartSessionInDebug {
            if let until = tryBeginSession(now: now, ignoreCaps: WWClockBurstConfig.debugIgnoreSessionCaps) {
                return Plan(sessionActive: true, allowChaining: true, sessionUntil: until)
            } else {
                return Plan(sessionActive: false, allowChaining: false, sessionUntil: .distantPast)
            }
        }

        return Plan(sessionActive: false, allowChaining: false, sessionUntil: .distantPast)
    }

    private static func tryBeginSession(now: Date, ignoreCaps: Bool) -> Date? {
        let defaults = AppGroup.userDefaults
        let dayKey = Self.dayKey(for: now)

        let countKey = sessionCountPrefix + dayKey
        let sessionsToday = defaults.integer(forKey: countKey)

        if !ignoreCaps {
            guard sessionsToday < WWClockBurstConfig.sessionMaxPerDay else { return nil }

            let lastStart = (defaults.object(forKey: sessionLastStartKey) as? Date) ?? .distantPast
            guard now.timeIntervalSince(lastStart) >= WWClockBurstConfig.sessionMinSpacingSeconds else { return nil }
        }

        let until = now.addingTimeInterval(WWClockBurstConfig.sessionMaxSeconds)

        defaults.set(until, forKey: sessionUntilKey)
        defaults.set(now, forKey: sessionLastStartKey)
        defaults.set(sessionsToday + 1, forKey: countKey)

        return until
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
