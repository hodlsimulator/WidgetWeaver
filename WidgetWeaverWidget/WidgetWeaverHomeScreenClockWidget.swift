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
        return Entry(date: now, anchorDate: now, tickSeconds: 0.0, colourScheme: .classic)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        return Entry(
            date: now,
            anchorDate: now,
            tickSeconds: 0.0,
            colourScheme: configuration.colourScheme ?? .classic
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let scheme = configuration.colourScheme ?? .classic
        let now = Date()

        // Budget-safe:
        // - Keep WidgetKit timelines sparse.
        // - The view itself is responsible for per-second ticking (TimelineView inside the widget view).
        // - Still provide a periodic reload so the system can re-request a fresh timeline.
        let entry = Entry(date: now, anchorDate: now, tickSeconds: 0.0, colourScheme: scheme)

        // Reload occasionally to keep WidgetKit happy and to pick up any environment changes.
        // This does NOT drive the second-hand ticking.
        let reloadDate = now.addingTimeInterval(60.0 * 60.0)
        return Timeline(entries: [entry], policy: .after(reloadDate))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: mode
        )

        Group {
            if reduceMotion {
                TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
                    let now = timeline.date
                    WidgetWeaverRenderClock.withNow(now) {
                        WidgetWeaverClockWidgetLiveView(
                            palette: palette,
                            date: now,
                            anchorDate: now,
                            tickSeconds: 0.0
                        )
                        .unredacted()
                    }
                }
            } else {
                TimelineView(.animation(minimumInterval: 1.0, paused: false)) { timeline in
                    let now = timeline.date
                    WidgetWeaverRenderClock.withNow(now) {
                        WidgetWeaverClockWidgetLiveView(
                            palette: palette,
                            date: now,
                            anchorDate: now,
                            tickSeconds: 0.0
                        )
                        .unredacted()
                    }
                }
            }
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
