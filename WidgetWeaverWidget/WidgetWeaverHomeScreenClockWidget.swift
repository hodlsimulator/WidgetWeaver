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
    /// Timeline-driven redraw interval.
    ///
    /// Smaller values look smoother but consume more WidgetKit refresh/render budget.
    /// A value like 10s keeps the second hand moving (smooth sweep) while being far less aggressive than 2s.
    static let tickSeconds: TimeInterval = 10.0

    /// Number of entries to generate per timeline.
    ///
    /// `maxEntries * tickSeconds` is how long the widget can keep animating before WidgetKit requests a new timeline.
    /// 360 entries @ 10s ≈ 1 hour.
    static let maxEntries: Int = 360
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
        let base = Date()

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineTuning.maxEntries)

        for i in 0..<WWClockTimelineTuning.maxEntries {
            let d = base.addingTimeInterval(Double(i) * WWClockTimelineTuning.tickSeconds)
            entries.append(Entry(date: d, colourScheme: scheme))
        }

        return Timeline(entries: entries, policy: .atEnd)
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
            // Deterministic “now” during WidgetKit pre-rendering.
            WidgetWeaverRenderClock.withNow(entry.date) {
                WidgetWeaverHomeScreenClockView(entry: entry, tickSeconds: WWClockTimelineTuning.tickSeconds)
            }
        }
        .configurationDisplayName("Clock (Icon)")
        .description("A small analogue clock.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Time maths

private struct WWClockHandDegrees {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(date: Date, timeZone: TimeZone) {
        // Monotonic angles (no mod 360) so interpolation never runs backwards at wrap boundaries.
        let tz = TimeInterval(timeZone.secondsFromGMT(for: date))
        let localT = date.timeIntervalSinceReferenceDate + tz

        self.secondDegrees = localT * (360.0 / 60.0)
        self.minuteDegrees = localT * (360.0 / 3600.0)
        self.hourDegrees = localT * (360.0 / 43200.0)
    }
}

// MARK: - View

struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry
    let tickSeconds: TimeInterval

    @Environment(\.colorScheme) private var mode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: mode
        )

        let deg = WWClockHandDegrees(date: entry.date, timeZone: .autoupdatingCurrent)

        ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(deg.hourDegrees),
                minuteAngle: .degrees(deg.minuteDegrees),
                secondAngle: .degrees(deg.secondDegrees)
            )
            .animation(.linear(duration: tickSeconds), value: deg.secondDegrees)

            #if DEBUG
            VStack(alignment: .trailing, spacing: 2) {
                Text(entry.date, format: .dateTime.hour().minute().second())
                Text("tick: \(tickSeconds, format: .number)")
                Text("CLK TL")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary.opacity(0.70))
            .padding(6)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            #endif
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
