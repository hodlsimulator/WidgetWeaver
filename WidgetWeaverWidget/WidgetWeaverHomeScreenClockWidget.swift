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
        return Entry(
            date: now,
            anchorDate: Self.floorToWholeSecond(now),
            tickSeconds: ProcessInfo.processInfo.isLowPowerModeEnabled ? 60.0 : 1.0,
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
            tickSeconds: isLowPower ? 60.0 : 1.0,
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let scheme = configuration.colourScheme ?? .classic

        let entry = Entry(
            date: now,
            anchorDate: Self.floorToWholeSecond(now),
            tickSeconds: isLowPower ? 60.0 : 1.0,
            colourScheme: scheme
        )

        let refreshInterval: TimeInterval = isLowPower ? (2.0 * 60.0 * 60.0) : (60.0 * 60.0)
        let nextRefresh = now.addingTimeInterval(refreshInterval)

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private static func floorToWholeSecond(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: floor(t))
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
