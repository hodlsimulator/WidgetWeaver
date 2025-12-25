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
    /// The clock display is driven by time-aware SwiftUI views (`ProgressView(timerInterval:)`).
    /// Timeline refresh exists only as a safety net.
    static let providerRefreshSeconds: TimeInterval = 60.0 * 60.0 * 6.0
}

private enum WWClockTimeDriverTuning {
    /// Length of the driving date-range for `ProgressView(timerInterval:)`.
    ///
    /// A long duration avoids the progress view reaching the end during normal use.
    static let driverDurationSeconds: TimeInterval = 60.0 * 60.0 * 24.0 * 7.0
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
        .description("A small analogue clock with a ticking second hand.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - View

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

        let secondDegrees = localT * (360.0 / 60.0)
        let minuteDegrees = localT * (360.0 / 3600.0)
        let hourDegrees = localT * (360.0 / 43200.0)

        self.second = .degrees(secondDegrees)
        self.minute = .degrees(minuteDegrees)
        self.hour = .degrees(hourDegrees)
    }
}

private struct WWClockTimeDrivenProgressStyle: ProgressViewStyle {
    let palette: WidgetWeaverClockPalette
    let startDate: Date
    let endDate: Date
    let timeZone: TimeZone

    func makeBody(configuration: Configuration) -> some View {
        let duration = max(1.0, endDate.timeIntervalSince(startDate))
        let fraction = configuration.fractionCompleted ?? 0.0
        let clamped = min(max(fraction, 0.0), 1.0)

        let now = startDate.addingTimeInterval(duration * clamped)
        let angles = WWClockHandAngles(date: now, timeZone: timeZone, quantiseToWholeSeconds: true)

        return WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: angles.hour,
            minuteAngle: angles.minute,
            secondAngle: angles.second
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}

private struct WWClockTimeDrivenView: View {
    let palette: WidgetWeaverClockPalette
    let startDate: Date
    let timeZone: TimeZone

    var body: some View {
        let endDate = startDate.addingTimeInterval(WWClockTimeDriverTuning.driverDurationSeconds)

        ProgressView(
            timerInterval: startDate...endDate,
            countsDown: false,
            label: { EmptyView() },
            currentValueLabel: { EmptyView() }
        )
        .progressViewStyle(
            WWClockTimeDrivenProgressStyle(
                palette: palette,
                startDate: startDate,
                endDate: endDate,
                timeZone: timeZone
            )
        )
    }
}

struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var mode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(scheme: entry.colourScheme, mode: mode)

        WWClockTimeDrivenView(
            palette: palette,
            startDate: entry.date,
            timeZone: .autoupdatingCurrent
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
