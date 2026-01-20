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
        IntentDescription("Configure Clock (Quick) (Small). For deep customisation, create a Clock (Designer) design in the app and apply it to a WidgetWeaver widget.")
    }

    @Parameter(title: "Colour Scheme", default: .classic)
    public var colourScheme: WidgetWeaverClockWidgetColourScheme

    public static var parameterSummary: some ParameterSummary {
        Summary("Colour Scheme: \(\.$colourScheme)")
    }

    public init() {}
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
    let isWidgetKitPreview: Bool
}

private enum WWClockTimelineConfig {
    static let maxEntriesPerTimeline: Int = 2
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverHomeScreenClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        return Entry(
            date: now,
            tickMode: .minuteOnly,
            tickSeconds: 60.0,
            colourScheme: .classic,
            isWidgetKitPreview: true
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let scheme = configuration.colourScheme.paletteScheme

        return Entry(
            date: now,
            tickMode: .secondsSweep,
            tickSeconds: 0.0,
            colourScheme: scheme,
            isWidgetKitPreview: context.isPreview
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let scheme = configuration.colourScheme.paletteScheme

        WWClockInstrumentation.recordTimelineBuild(now: now, scheme: scheme)

        // Always publish a live (non-preview) entry for Home Screen rendering.
        // Some iOS widget-hosting paths can treat freshly-added widgets as “preview” for longer than expected.
        // If live rendering is keyed off `context.isPreview`, those instances can get stuck in the low-budget face.
        return makeMinuteTimeline(now: now, colourScheme: scheme, isWidgetKitPreview: false)
    }

    private func makeMinuteTimeline(
        now: Date,
        colourScheme: WidgetWeaverClockColourScheme,
        isWidgetKitPreview: Bool
    ) -> Timeline<Entry> {
        let minuteAnchorNow = Self.floorToMinute(now)
        let nextMinuteBoundary = minuteAnchorNow.addingTimeInterval(60.0)

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineConfig.maxEntriesPerTimeline)

        entries.append(
            Entry(
                date: now,
                tickMode: .secondsSweep,
                tickSeconds: 0.0,
                colourScheme: colourScheme,
                isWidgetKitPreview: isWidgetKitPreview
            )
        )

        if entries.count < WWClockTimelineConfig.maxEntriesPerTimeline {
            entries.append(
                Entry(
                    date: nextMinuteBoundary,
                    tickMode: .secondsSweep,
                    tickSeconds: 0.0,
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

            return "provider.timeline scheme=\(colourScheme.rawValue) nowRef=\(nowRef) anchorRef=\(anchorRef) nextRef=\(nextRef) entries=\(entries.count) firstRef=\(firstRef) lastRef=\(lastRef) policy=atEnd"
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
    private static let countPrefix = "widgetweaver.clock.timelineBuild.count."

    static func recordTimelineBuild(now: Date, scheme: WidgetWeaverClockColourScheme) {
        let defaults = AppGroup.userDefaults
        defaults.set(now, forKey: lastKey)
        defaults.set(scheme.rawValue, forKey: schemeKey)

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
        .description("A standalone analogue clock (Small only) with fast setup. For deep customisation, use Clock (Designer) in a WidgetWeaver widget.")
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

        Group {
            if entry.isWidgetKitPreview {
                WidgetWeaverClockLowBudgetFace(
                    palette: palette,
                    date: entry.date
                )
            } else {
                WidgetWeaverClockWidgetLiveView(
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
    let palette: WidgetWeaverClockPalette
    let date: Date

    var body: some View {
        let angles = WWClockLowBudgetAngles(date: date)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: angles.hour,
            minuteAngle: angles.minute,
            secondAngle: .degrees(0),
            showsSecondHand: false,
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

        self.hour = .degrees(hourDeg)
        self.minute = .degrees(minuteDeg)
    }
}
