//
//  WidgetWeaverHomeScreenClockWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/23/25.
//

import Foundation
import WidgetKit
import SwiftUI
import AppIntents

private enum WWClockTimelineTuning {
    // The clock runs via a local repeating animation once rendered.
    // The timeline only needs to refresh occasionally so WidgetKit can re-evaluate the view.
    static let refreshSeconds: TimeInterval = 60.0 * 60.0
}

// MARK: - Configuration

public enum WidgetWeaverClockColourScheme: String, AppEnum, CaseIterable {
    case classic
    case ocean
    case mint
    case orchid
    case sunset
    case ember
    case graphite

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Colour Scheme")
    }

    public static var caseDisplayRepresentations: [WidgetWeaverClockColourScheme: DisplayRepresentation] {
        [
            .classic: DisplayRepresentation(title: "Classic"),
            .ocean: DisplayRepresentation(title: "Ocean"),
            .mint: DisplayRepresentation(title: "Mint"),
            .orchid: DisplayRepresentation(title: "Orchid"),
            .sunset: DisplayRepresentation(title: "Sunset"),
            .ember: DisplayRepresentation(title: "Ember"),
            .graphite: DisplayRepresentation(title: "Graphite")
        ]
    }
}

public struct WidgetWeaverClockConfigurationIntent: AppIntent, WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "Clock" }

    public static var description: IntentDescription {
        IntentDescription("Select the colour scheme for the clock widget.")
    }

    @Parameter(title: "Colour Scheme")
    public var colourScheme: WidgetWeaverClockColourScheme?

    public init() {
        self.colourScheme = .classic
    }
}

// MARK: - Timeline

public struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    public let date: Date
    public let colourScheme: WidgetWeaverClockColourScheme
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), colourScheme: .classic)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        Entry(date: Date(), colourScheme: configuration.colourScheme ?? .classic)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let scheme = configuration.colourScheme ?? .classic
        let now = Date()
        let nextRefresh = now.addingTimeInterval(WWClockTimelineTuning.refreshSeconds)

        let entry = Entry(date: now, colourScheme: scheme)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

// MARK: - Widget

struct WidgetWeaverHomeScreenClockWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.homeScreenClock

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetWeaverClockConfigurationIntent.self,
            provider: WidgetWeaverHomeScreenClockProvider()
        ) { entry in
            WidgetWeaverHomeScreenClockView(entry: entry)
        }
        .configurationDisplayName("Clock (Icon)")
        .description("A small analogue clock with a sweeping second hand.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - View

struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var mode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(scheme: entry.colourScheme, mode: mode)

        ZStack {
            WidgetWeaverClockResyncingIconView(
                palette: palette,
                colourScheme: entry.colourScheme
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}

// MARK: - Resyncing clock driver

private enum WWClockResyncTuning {
    static let smallCatchUpSeconds: TimeInterval = 2.0
    static let mediumCatchUpSeconds: TimeInterval = 10.0

    static let smallCatchUpDuration: TimeInterval = 0.30
    static let mediumCatchUpDuration: TimeInterval = 0.70

    static let fadeDuration: TimeInterval = 0.16
    static let fadeHold: TimeInterval = 0.02
}

private enum WWClockResyncStore {
    static func lastRenderKey(colourScheme: WidgetWeaverClockColourScheme) -> String {
        "widgetweaver.clock.lastRender.\(colourScheme.rawValue)"
    }

    static func readLastRenderDate(colourScheme: WidgetWeaverClockColourScheme) -> Date? {
        let key = lastRenderKey(colourScheme: colourScheme)
        let t = AppGroup.userDefaults.double(forKey: key)
        guard t > 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: t)
    }

    static func writeLastRenderDate(_ date: Date, colourScheme: WidgetWeaverClockColourScheme) {
        let key = lastRenderKey(colourScheme: colourScheme)
        AppGroup.userDefaults.set(date.timeIntervalSinceReferenceDate, forKey: key)
    }
}

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double
    let second: Double

    init(date: Date) {
        let tz = TimeInterval(TimeZone.current.secondsFromGMT(for: date))
        let local = date.timeIntervalSince1970 + tz

        let sec = local.truncatingRemainder(dividingBy: 60.0)
        let minTotal = (local / 60.0).truncatingRemainder(dividingBy: 60.0)
        let hourTotal = (local / 3600.0).truncatingRemainder(dividingBy: 12.0)

        let secondDeg = sec * 6.0
        let minuteDeg = (minTotal + sec / 60.0) * 6.0
        let hourDeg = (hourTotal + minTotal / 60.0 + sec / 3600.0) * 30.0

        self.second = secondDeg
        self.minute = minuteDeg
        self.hour = hourDeg
    }
}

private func wwClockNegativeOffsetDegrees(previous: Double, current: Double) -> Double {
    var prev = previous.truncatingRemainder(dividingBy: 360.0)
    var cur = current.truncatingRemainder(dividingBy: 360.0)

    if prev < 0 { prev += 360.0 }
    if cur < 0 { cur += 360.0 }

    var diff = prev - cur
    if diff > 0 { diff -= 360.0 }
    return diff
}

private struct WidgetWeaverClockResyncingIconView: View {
    let palette: WidgetWeaverClockPalette
    let colourScheme: WidgetWeaverClockColourScheme

    @State private var baseHour: Double = 0
    @State private var baseMinute: Double = 0
    @State private var baseSecond: Double = 0

    @State private var hourPhase: Double = 0
    @State private var minutePhase: Double = 0
    @State private var secondPhase: Double = 0

    @State private var hourOffset: Double = 0
    @State private var minuteOffset: Double = 0
    @State private var secondOffset: Double = 0

    @State private var handsOpacity: Double = 1.0

    var body: some View {
        let hourAngle = Angle.degrees(baseHour + hourPhase * 360.0 + hourOffset)
        let minuteAngle = Angle.degrees(baseMinute + minutePhase * 360.0 + minuteOffset)
        let secondAngle = Angle.degrees(baseSecond + secondPhase * 360.0 + secondOffset)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: hourAngle,
            minuteAngle: minuteAngle,
            secondAngle: secondAngle,
            handsOpacity: handsOpacity
        )
        .onAppear {
            let now = Date()
            let previous = WWClockResyncStore.readLastRenderDate(colourScheme: colourScheme)

            WWClockResyncStore.writeLastRenderDate(now, colourScheme: colourScheme)
            restart(now: now, previous: previous)
        }
    }

    private func restart(now: Date, previous: Date?) {
        let base = WWClockBaseAngles(date: now)

        var prevBase: WWClockBaseAngles? = nil
        var elapsed: TimeInterval = 0

        if let previous {
            elapsed = now.timeIntervalSince(previous)
            if elapsed > 0 {
                prevBase = WWClockBaseAngles(date: previous)
            }
        }

        let initialOffsets: (hour: Double, minute: Double, second: Double)
        if let prevBase {
            initialOffsets = (
                wwClockNegativeOffsetDegrees(previous: prevBase.hour, current: base.hour),
                wwClockNegativeOffsetDegrees(previous: prevBase.minute, current: base.minute),
                wwClockNegativeOffsetDegrees(previous: prevBase.second, current: base.second)
            )
        } else {
            initialOffsets = (0, 0, 0)
        }

        withTransaction(Transaction(animation: nil)) {
            baseHour = base.hour
            baseMinute = base.minute
            baseSecond = base.second

            hourPhase = 0
            minutePhase = 0
            secondPhase = 0

            hourOffset = initialOffsets.hour
            minuteOffset = initialOffsets.minute
            secondOffset = initialOffsets.second

            handsOpacity = 1.0
        }

        withAnimation(.linear(duration: 60.0).repeatForever(autoreverses: false)) {
            secondPhase = 1
        }
        withAnimation(.linear(duration: 3600.0).repeatForever(autoreverses: false)) {
            minutePhase = 1
        }
        withAnimation(.linear(duration: 43200.0).repeatForever(autoreverses: false)) {
            hourPhase = 1
        }

        guard prevBase != nil else { return }

        if elapsed <= WWClockResyncTuning.smallCatchUpSeconds {
            withAnimation(.easeOut(duration: WWClockResyncTuning.smallCatchUpDuration)) {
                hourOffset = 0
                minuteOffset = 0
                secondOffset = 0
            }
            return
        }

        if elapsed <= WWClockResyncTuning.mediumCatchUpSeconds {
            withAnimation(.easeOut(duration: WWClockResyncTuning.mediumCatchUpDuration)) {
                hourOffset = 0
                minuteOffset = 0
                secondOffset = 0
            }
            return
        }

        withAnimation(.easeOut(duration: WWClockResyncTuning.fadeDuration)) {
            handsOpacity = 0.0
        }

        DispatchQueue.main.asyncAfter(
            deadline: .now() + WWClockResyncTuning.fadeDuration + WWClockResyncTuning.fadeHold
        ) {
            withTransaction(Transaction(animation: nil)) {
                hourOffset = 0
                minuteOffset = 0
                secondOffset = 0
            }
            withAnimation(.easeIn(duration: WWClockResyncTuning.fadeDuration)) {
                handsOpacity = 1.0
            }
        }
    }
}
