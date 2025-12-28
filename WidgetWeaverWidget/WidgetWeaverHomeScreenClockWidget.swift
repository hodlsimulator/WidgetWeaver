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

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        return Entry(date: now, anchorDate: now, tickSeconds: 30.0, colourScheme: .classic)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        return Entry(
            date: now,
            anchorDate: now,
            tickSeconds: 30.0,
            colourScheme: configuration.colourScheme ?? .classic
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let scheme = configuration.colourScheme ?? .classic

        // Budget-safe strategy:
        // - Avoid 1 Hz WidgetKit timelines.
        // - Use sparse entries plus a linear animation that spans the entire interval.
        // - 60s ticks can land on a 360° second-hand delta per entry (can appear frozen).
        // - 30s ticks land on 180° deltas, which stays visually alive while cutting update rate.
        let tickSeconds: TimeInterval = context.isPreview ? 2.0 : 30.0

        // Keep under the common ~250 entry ceiling.
        // 240 * 30s = 7200s (≈ 2 hours horizon), then WidgetKit reloads the timeline.
        let maxEntries: Int = context.isPreview ? 30 : 240

        let anchorDate: Date = Date()

        var entries: [Entry] = []
        entries.reserveCapacity(maxEntries)

        for i in 0..<maxEntries {
            let d = anchorDate.addingTimeInterval(TimeInterval(i) * tickSeconds)
            entries.append(Entry(date: d, anchorDate: anchorDate, tickSeconds: tickSeconds, colourScheme: scheme))
        }

        let refreshDate = anchorDate.addingTimeInterval(TimeInterval(maxEntries) * tickSeconds)
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

        WidgetWeaverRenderClock.withNow(entry.date) {
            WidgetWeaverClockWidgetLiveView(
                palette: palette,
                date: entry.date,
                anchorDate: entry.anchorDate,
                tickSeconds: entry.tickSeconds
            )
            .unredacted()
            .id(entry.anchorDate)
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
