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

public struct WidgetWeaverHomeScreenClockConfigurationIntent: WidgetConfigurationIntent {
    public static var title: LocalizedStringResource { "Clock (Quick)" }

    public static var description: IntentDescription {
        IntentDescription(
            "Configure Clock (Quick) (Small). Choose a colour scheme and toggle the seconds hand (on by default). For deep customisation, create a Clock (Designer) design in the app and apply it to a WidgetWeaver widget."
        )
    }

    @Parameter(title: "Colour Scheme", default: .classic)
    public var colourScheme: WidgetWeaverClockWidgetColourScheme

    @Parameter(title: "Seconds Hand", default: true)
    public var secondsHandEnabled: Bool

    public static var parameterSummary: some ParameterSummary {
        Summary("Colour Scheme: \(\.$colourScheme), Seconds Hand: \(\.$secondsHandEnabled)")
    }

    public init() {}
}

enum WidgetWeaverClockTickMode: Int {
    case minuteOnly = 0
    case secondsSweep = 1
}

struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    let date: Date
    let face: WidgetWeaverClockFaceToken
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval
    let colourScheme: WidgetWeaverClockColourScheme
    let isWidgetKitPreview: Bool
}

private enum WWClockTimelineConfig {
    static let maxEntriesPerTimeline: Int = 2
}

private enum WWQuickClockDefaults {
    static let face: WidgetWeaverClockFaceToken = .icon
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverHomeScreenClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        return Entry(
            date: now,
            face: WWQuickClockDefaults.face,
            tickMode: .secondsSweep,
            tickSeconds: 0.0,
            colourScheme: .classic,
            isWidgetKitPreview: true
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let scheme = configuration.colourScheme.paletteScheme

        let tickMode: WidgetWeaverClockTickMode = configuration.secondsHandEnabled ? .secondsSweep : .minuteOnly
        let tickSeconds: TimeInterval = configuration.secondsHandEnabled ? 0.0 : 60.0

        return Entry(
            date: now,
            face: WWQuickClockDefaults.face,
            tickMode: tickMode,
            tickSeconds: tickSeconds,
            colourScheme: scheme,
            isWidgetKitPreview: context.isPreview
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let scheme = configuration.colourScheme.paletteScheme

        let tickMode: WidgetWeaverClockTickMode = configuration.secondsHandEnabled ? .secondsSweep : .minuteOnly
        let tickSeconds: TimeInterval = configuration.secondsHandEnabled ? 0.0 : 60.0

        WWClockInstrumentation.recordTimelineBuild(
            now: now,
            scheme: scheme,
            secondsHandEnabled: configuration.secondsHandEnabled
        )

        // Always publish a live (non-preview) entry for Home Screen rendering.
        // Some iOS widget-hosting paths can treat freshly-added widgets as “preview” for longer than expected.
        // If live rendering is keyed off `context.isPreview`, those instances can get stuck in the low-budget face.
        return makeMinuteTimeline(
            now: now,
            face: WWQuickClockDefaults.face,
            colourScheme: scheme,
            tickMode: tickMode,
            tickSeconds: tickSeconds,
            isWidgetKitPreview: false
        )
    }

    private func makeMinuteTimeline(
        now: Date,
        face: WidgetWeaverClockFaceToken,
        colourScheme: WidgetWeaverClockColourScheme,
        tickMode: WidgetWeaverClockTickMode,
        tickSeconds: TimeInterval,
        isWidgetKitPreview: Bool
    ) -> Timeline<Entry> {
        let minuteAnchorNow = Self.floorToMinute(now)
        let nextMinuteBoundary = minuteAnchorNow.addingTimeInterval(60.0)

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineConfig.maxEntriesPerTimeline)

        entries.append(
            Entry(
                date: now,
                face: face,
                tickMode: tickMode,
                tickSeconds: tickSeconds,
                colourScheme: colourScheme,
                isWidgetKitPreview: isWidgetKitPreview
            )
        )

        if entries.count < WWClockTimelineConfig.maxEntriesPerTimeline {
            entries.append(
                Entry(
                    date: nextMinuteBoundary,
                    face: face,
                    tickMode: tickMode,
                    tickSeconds: tickSeconds,
                    colourScheme: colourScheme,
                    isWidgetKitPreview: isWidgetKitPreview
                )
            )
        }

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

            return "provider.timeline face=\(face.rawValue) scheme=\(colourScheme.rawValue) mode=\(tickMode) nowRef=\(nowRef) anchorRef=\(anchorRef) nextRef=\(nextRef) entries=\(entries.count) firstRef=\(firstRef) lastRef=\(lastRef) policy=atEnd"
        }

        return Timeline(entries: entries, policy: .atEnd)
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
    private static let schemeKey = "widgetweaver.clock.timelineBuild.scheme"
    private static let secondsKey = "widgetweaver.clock.timelineBuild.secondsHandEnabled"
    private static let countPrefix = "widgetweaver.clock.timelineBuild.count."

    static func recordTimelineBuild(now: Date, scheme: WidgetWeaverClockColourScheme, secondsHandEnabled: Bool) {
        let defaults = AppGroup.userDefaults
        defaults.set(now, forKey: lastKey)
        defaults.set(scheme.rawValue, forKey: schemeKey)
        defaults.set(secondsHandEnabled, forKey: secondsKey)

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
                .id(entry.date)
                .transaction { transaction in
                    transaction.animation = nil
                }
        }
        .configurationDisplayName("Clock (Quick)")
        .description("A standalone analogue clock (Small only) with fast setup. Choose a colour scheme and toggle the seconds hand (on by default). For deep customisation, use Clock (Designer) in a WidgetWeaver widget.")
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

        let face = entry.face

        Group {
            if entry.isWidgetKitPreview {
                WidgetWeaverClockLowBudgetFace(
                    face: face,
                    palette: palette,
                    date: entry.date,
                    showsSecondHand: (entry.tickMode == .secondsSweep)
                )
            } else {
                WidgetWeaverClockWidgetLiveView(
                    face: face,
                    palette: palette,
                    entryDate: entry.date,
                    tickMode: entry.tickMode,
                    tickSeconds: entry.tickSeconds
                )
            }
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
        .clipShape(ContainerRelativeShape())
        .widgetURL(URL(string: "widgetweaver://clock"))
        #if DEBUG
        .overlay(alignment: .topLeading) {
            Text("scheme=\(entry.colourScheme.rawValue)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.65))
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        #endif
    }
}

private struct WidgetWeaverClockLowBudgetFace: View {
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette
    let date: Date
    let showsSecondHand: Bool

    var body: some View {
        let angles = WWClockLowBudgetAngles(date: date)

        WidgetWeaverClockFaceView(
            face: face,
            palette: palette,
            hourAngle: angles.hour,
            minuteAngle: angles.minute,
            secondAngle: angles.second,
            showsSecondHand: showsSecondHand,
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

private struct WWClockLowBudgetAngles {
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
