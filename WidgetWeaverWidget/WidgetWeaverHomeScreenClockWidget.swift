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
        return makeEntry(date: now, tickSeconds: 60.0, colourScheme: .classic)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let scheme = configuration.colourScheme ?? .classic
        return makeEntry(date: now, tickSeconds: 60.0, colourScheme: scheme)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let scheme = configuration.colourScheme ?? .classic

        WidgetWeaverClockInstrumentation.recordTimelineBuild(now: now)

        if isLowPower {
            return makeMinuteTimeline(now: now, colourScheme: scheme, chainAfter: nil)
        }

        switch WidgetWeaverClockMotionConfig.implementation {
        case .burstTimelineHybrid:
            return makeBurstHybridTimeline(now: now, colourScheme: scheme)
        }
    }

    // MARK: - Builders

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
        chainAfter: Date?
    ) -> Timeline<Entry> {
        let horizonEnd = now.addingTimeInterval(WidgetWeaverClockMotionConfig.minuteHorizonSeconds)

        var entries: [Entry] = []
        entries.reserveCapacity(min(WidgetWeaverClockMotionConfig.maxTimelineEntries, 140))

        entries.append(makeEntry(date: now, tickSeconds: 60.0, colourScheme: colourScheme))

        var next = Self.nextMinuteBoundary(after: now)
        while next <= horizonEnd && entries.count < WidgetWeaverClockMotionConfig.maxTimelineEntries {
            entries.append(makeEntry(date: next, tickSeconds: 60.0, colourScheme: colourScheme))
            next = next.addingTimeInterval(60.0)
        }

        let policyDate = chainAfter ?? horizonEnd
        return Timeline(entries: entries, policy: .after(policyDate))
    }

    private func makeBurstHybridTimeline(
        now: Date,
        colourScheme: WidgetWeaverClockColourScheme
    ) -> Timeline<Entry> {

        // Session decides whether chaining is allowed.
        let session = WidgetWeaverClockBurstSession.sessionPlan(now: now)

        // Always generate at least minute-level.
        guard session.shouldBurst else {
            return makeMinuteTimeline(now: now, colourScheme: colourScheme, chainAfter: nil)
        }

        let burstSeconds = max(1, WidgetWeaverClockMotionConfig.burstSeconds)
        let burstEnd = now.addingTimeInterval(TimeInterval(burstSeconds))

        // Minute horizon after the burst.
        let horizonEnd = now.addingTimeInterval(WidgetWeaverClockMotionConfig.minuteHorizonSeconds)

        var entries: [Entry] = []
        entries.reserveCapacity(WidgetWeaverClockMotionConfig.maxTimelineEntries)

        // Seconds entries: [now, now+1, ... now+(burstSeconds-1)]
        // Then a minute-mode entry at burstEnd to hide the seconds hand immediately.
        for i in 0..<burstSeconds {
            if entries.count >= WidgetWeaverClockMotionConfig.maxTimelineEntries { break }
            let t = now.addingTimeInterval(TimeInterval(i))
            entries.append(makeEntry(date: t, tickSeconds: 1.0, colourScheme: colourScheme))
        }

        if entries.count < WidgetWeaverClockMotionConfig.maxTimelineEntries {
            entries.append(makeEntry(date: burstEnd, tickSeconds: 60.0, colourScheme: colourScheme))
        }

        // Minute entries after burst end (bounded by maxTimelineEntries).
        var next = Self.nextMinuteBoundary(after: burstEnd)
        while next <= horizonEnd && entries.count < WidgetWeaverClockMotionConfig.maxTimelineEntries {
            entries.append(makeEntry(date: next, tickSeconds: 60.0, colourScheme: colourScheme))
            next = next.addingTimeInterval(60.0)
        }

        // Chaining: ask for a new timeline at burstEnd, but only while the session is active.
        let chainEnabled = WidgetWeaverClockMotionConfig.burstChainingEnabled && session.shouldChain
        let chainAfter: Date? = {
            guard chainEnabled else { return nil }
            guard burstEnd < session.sessionUntil else { return nil }
            return burstEnd
        }()

        let policyDate = chainAfter ?? horizonEnd
        return Timeline(entries: entries, policy: .after(policyDate))
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

// MARK: - Instrumentation (App Group)

private enum WidgetWeaverClockInstrumentation {
    private static let lastKey = "widgetweaver.clock.timelineBuild.last"
    private static let countPrefix = "widgetweaver.clock.timelineBuild.count."

    static func recordTimelineBuild(now: Date) {
        let defaults = AppGroup.userDefaults
        defaults.set(now, forKey: lastKey)

        let dayKey = Self.dayKey(for: now)
        let k = countPrefix + dayKey
        let c = defaults.integer(forKey: k)
        defaults.set(c + 1, forKey: k)
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

// MARK: - Burst session planner (App Group)

private enum WidgetWeaverClockBurstSession {
    private static let sessionUntilKey = "widgetweaver.clock.session.until"
    private static let sessionLastStartKey = "widgetweaver.clock.session.lastStart"
    private static let sessionCountPrefix = "widgetweaver.clock.session.count."

    // Optional “wake” request, set by the main app.
    private static let wakeRequestKey = "widgetweaver.clock.wake.request.until"

    struct Plan {
        let shouldBurst: Bool
        let shouldChain: Bool
        let sessionUntil: Date
    }

    static func sessionPlan(now: Date) -> Plan {
        let defaults = AppGroup.userDefaults

        // Consume wake request (one-shot window).
        let wakeUntil = (defaults.object(forKey: wakeRequestKey) as? Date) ?? .distantPast
        let wakeRequested = wakeUntil > now
        if wakeRequested {
            defaults.set(Date.distantPast, forKey: wakeRequestKey)
        }

        // Active session?
        let existingUntil = (defaults.object(forKey: sessionUntilKey) as? Date) ?? .distantPast
        if existingUntil > now {
            return Plan(shouldBurst: true, shouldChain: true, sessionUntil: existingUntil)
        }

        // Start a new session?
        let canStart = canStartSession(now: now)
        if wakeRequested && canStart {
            let until = beginSession(now: now)
            return Plan(shouldBurst: true, shouldChain: true, sessionUntil: until)
        }

        // Auto-start (budget-safe caps).
        if WidgetWeaverClockMotionConfig.burstChainingEnabled && canStart {
            let until = beginSession(now: now)
            return Plan(shouldBurst: true, shouldChain: true, sessionUntil: until)
        }

        // No session: no seconds.
        return Plan(shouldBurst: false, shouldChain: false, sessionUntil: .distantPast)
    }

    private static func canStartSession(now: Date) -> Bool {
        let defaults = AppGroup.userDefaults
        let dayKey = Self.dayKey(for: now)

        let countKey = sessionCountPrefix + dayKey
        let sessionsToday = defaults.integer(forKey: countKey)
        guard sessionsToday < WidgetWeaverClockMotionConfig.burstSessionMaxPerDay else {
            return false
        }

        let lastStart = (defaults.object(forKey: sessionLastStartKey) as? Date) ?? .distantPast
        guard now.timeIntervalSince(lastStart) >= WidgetWeaverClockMotionConfig.burstSessionMinSpacingSeconds else {
            return false
        }

        return true
    }

    private static func beginSession(now: Date) -> Date {
        let defaults = AppGroup.userDefaults
        let until = now.addingTimeInterval(WidgetWeaverClockMotionConfig.burstSessionMaxSeconds)

        defaults.set(until, forKey: sessionUntilKey)
        defaults.set(now, forKey: sessionLastStartKey)

        let dayKey = Self.dayKey(for: now)
        let countKey = sessionCountPrefix + dayKey
        let c = defaults.integer(forKey: countKey)
        defaults.set(c + 1, forKey: countKey)

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
