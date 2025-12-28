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

public struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    public let date: Date
    public let anchorDate: Date
    public let tickSeconds: TimeInterval
    public let colourScheme: WidgetWeaverClockColourScheme
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        let tickSeconds: TimeInterval = 2.0
        return Entry(
            date: now,
            anchorDate: alignedAnchor(now, tickSeconds: tickSeconds),
            tickSeconds: tickSeconds,
            colourScheme: .classic
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let tickSeconds: TimeInterval = 2.0
        return Entry(
            date: now,
            anchorDate: alignedAnchor(now, tickSeconds: tickSeconds),
            tickSeconds: tickSeconds,
            colourScheme: configuration.colourScheme ?? .classic
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let tickSeconds: TimeInterval = 2.0
        let scheme = configuration.colourScheme ?? .classic

        let anchorDate = alignedAnchor(now, tickSeconds: tickSeconds)
        let nextRefresh = nextHourBoundary(after: now) ?? now.addingTimeInterval(3600)

        let entry = Entry(
            date: now,
            anchorDate: anchorDate,
            tickSeconds: tickSeconds,
            colourScheme: scheme
        )

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func alignedAnchor(_ now: Date, tickSeconds: TimeInterval) -> Date {
        guard tickSeconds > 0 else { return now }
        let t = now.timeIntervalSinceReferenceDate
        let aligned = (t / tickSeconds).rounded(.up) * tickSeconds
        return Date(timeIntervalSinceReferenceDate: aligned)
    }

    private func nextHourBoundary(after date: Date) -> Date? {
        let cal = Calendar.autoupdatingCurrent
        return cal.nextDate(
            after: date,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTimePreservingSmallerComponents
        )
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
            anchorDate: entry.anchorDate,
            tickSeconds: entry.tickSeconds
        )
        .padding(10)
        .containerBackground(for: .widget) {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}

public struct WidgetWeaverHomeScreenClockWidget: Widget {
    public let kind: String = WidgetWeaverWidgetKinds.homeScreenClock

    public init() {}

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetWeaverClockConfigurationIntent.self,
            provider: WidgetWeaverHomeScreenClockProvider()
        ) { entry in
            WidgetWeaverRenderClock.withNow(entry.date) {
                WidgetWeaverHomeScreenClockView(entry: entry)
            }
        }
        .configurationDisplayName("Clock (Icon)")
        .description("An analogue clock face with a configurable colour scheme.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
