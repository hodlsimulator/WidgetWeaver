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
    /// Provider refresh cadence.
    ///
    /// The clock motion is driven by a live-updating `Text(..., style: .timer)` inside the widget view.
    /// The timeline refresh exists only as a safety net for palette/config changes and long-running host quirks.
    static let providerRefreshSeconds: TimeInterval = 60.0 * 60.0 * 6.0
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

        let entry = Entry(date: now, colourScheme: scheme)
        let nextRefresh = now.addingTimeInterval(WWClockTimelineTuning.providerRefreshSeconds)

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
        .description("A small analogue clock.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Time maths

private struct WWClockHandAngles {
    let hour: Angle
    let minute: Angle
    let second: Angle

    init(date: Date, timeZone: TimeZone, quantiseToWholeSeconds: Bool) {
        let tz = TimeInterval(timeZone.secondsFromGMT(for: date))
        var localT = date.timeIntervalSinceReferenceDate + tz

        if quantiseToWholeSeconds {
            localT = floor(localT)
        }

        // Monotonic angles (no mod 360) to avoid reverse interpolation at wrap boundaries.
        let secondDegrees = localT * (360.0 / 60.0)
        let minuteDegrees = localT * (360.0 / 3600.0)
        let hourDegrees = localT * (360.0 / 43200.0)

        self.second = .degrees(secondDegrees)
        self.minute = .degrees(minuteDegrees)
        self.hour = .degrees(hourDegrees)
    }
}

// MARK: - Per-second driver

private struct WWPerSecondDriver<Content: View>: View {
    let anchorDate: Date
    let content: (Date) -> Content

    var body: some View {
        Text(anchorDate, style: .timer)
            .font(.system(size: 1).monospacedDigit())
            .foregroundStyle(Color.clear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .background {
                content(Date())
            }
    }
}

// MARK: - View

struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var mode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: mode
        )

        WWPerSecondDriver(anchorDate: entry.date) { now in
            let angles = WWClockHandAngles(
                date: now,
                timeZone: .autoupdatingCurrent,
                quantiseToWholeSeconds: true
            )

            return ZStack(alignment: .bottomTrailing) {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: angles.hour,
                    minuteAngle: angles.minute,
                    secondAngle: angles.second
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transaction { txn in
                    txn.animation = nil
                }

                #if DEBUGz
                Text(entry.date, style: .timer)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.35))
                    .padding(6)
                #endif
            }
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}

