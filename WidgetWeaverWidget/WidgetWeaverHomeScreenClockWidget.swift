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

public struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    public let date: Date
    public let anchorDate: Date
    public let tickSeconds: TimeInterval
    public let colourScheme: WidgetWeaverClockColourScheme
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverClockConfigurationIntent

    /// WidgetKit guidance is to keep timelines reasonably sized.
    /// This caps per-second timelines to stay under common entry limits.
    private static let maxSecondEntries: Int = 180   // 3 minutes at 1 Hz
    private static let secondTick: TimeInterval = 1.0

    /// Low Power Mode fallback: minute ticks for a longer span.
    private static let lowPowerTick: TimeInterval = 60.0
    private static let lowPowerEntries: Int = 180    // 3 hours at 1/min

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        return Entry(date: now, anchorDate: now, tickSeconds: Self.secondTick, colourScheme: .classic)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        return Entry(
            date: now,
            anchorDate: now,
            tickSeconds: Self.secondTick,
            colourScheme: configuration.colourScheme ?? .classic
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let scheme = configuration.colourScheme ?? .classic
        let now = Date()

        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let tick: TimeInterval = isLowPower ? Self.lowPowerTick : Self.secondTick
        let entryCount: Int = isLowPower ? Self.lowPowerEntries : Self.maxSecondEntries

        let anchor = now

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)

        for i in 0..<entryCount {
            let d = anchor.addingTimeInterval(TimeInterval(i) * tick)
            entries.append(
                Entry(
                    date: d,
                    anchorDate: anchor,
                    tickSeconds: tick,
                    colourScheme: scheme
                )
            )
        }

        let refreshDate = anchor.addingTimeInterval(TimeInterval(entryCount) * tick)
        return Timeline(entries: entries, policy: .after(refreshDate))
    }
}

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

private struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var mode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: mode
        )

        WidgetWeaverClockWidgetLiveView(
            palette: palette,
            date: entry.date,
            anchorDate: entry.anchorDate,
            tickSeconds: entry.tickSeconds
        )
        .unredacted()
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
