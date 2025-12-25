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
    /// Timeline cadence. The system may coalesce faster timelines anyway.
    static let tickSeconds: TimeInterval = 2.0

    /// Number of entries emitted per timeline request.
    /// 1800 @ 2s ≈ 1 hour of motion before WidgetKit asks for a new timeline.
    static let maxEntries: Int = 1800

    static var providerRefreshSeconds: TimeInterval {
        tickSeconds * Double(maxEntries)
    }
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
            .graphite: DisplayRepresentation(title: "Graphite"),
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
        let start = Date()

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineTuning.maxEntries)

        for i in 0..<WWClockTimelineTuning.maxEntries {
            let d = start.addingTimeInterval(Double(i) * WWClockTimelineTuning.tickSeconds)
            entries.append(Entry(date: d, colourScheme: scheme))
        }

        let nextRefresh = start.addingTimeInterval(WWClockTimelineTuning.providerRefreshSeconds)
        return Timeline(entries: entries, policy: .after(nextRefresh))
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
        .description("A small analogue clock.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Time maths

private struct WWClockHandAngles {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(date: Date, timeZone: TimeZone) {
        let tz = TimeInterval(timeZone.secondsFromGMT(for: date))
        let localT = date.timeIntervalSinceReferenceDate + tz

        // Monotonic angles (no mod 360) to avoid reverse interpolation at wrap boundaries.
        self.secondDegrees = localT * (360.0 / 60.0)
        self.minuteDegrees = localT * (360.0 / 3600.0)
        self.hourDegrees = localT * (360.0 / 43200.0)
    }
}

// MARK: - View

struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme)
    private var mode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: mode
        )

        let angles = WWClockHandAngles(
            date: entry.date,
            timeZone: .autoupdatingCurrent
        )

        ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(angles.hourDegrees),
                minuteAngle: .degrees(angles.minuteDegrees),
                secondAngle: .degrees(angles.secondDegrees)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Animate the hands between timeline entries.
            .animation(.linear(duration: WWClockTimelineTuning.tickSeconds), value: angles.secondDegrees)
            .animation(.linear(duration: WWClockTimelineTuning.tickSeconds), value: angles.minuteDegrees)
            .animation(.linear(duration: WWClockTimelineTuning.tickSeconds), value: angles.hourDegrees)

            #if DEBUG
            Text(entry.date, format: .dateTime.hour().minute().second())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.35))
                .padding(6)
            #endif
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
