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
    // WidgetKit commonly coalesces sub-second and 1s timelines on Home Screen.
    // 2s segments have been the most reliable for visible sweeping.
    static let stepSeconds: TimeInterval = 2.0
    static let entriesAfterBoundary: Int = 180 // ~6 minutes (+ one "now" entry)
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
    public let endDate: Date
    public let colourScheme: WidgetWeaverClockColourScheme
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        return Entry(
            date: now,
            endDate: now.addingTimeInterval(WWClockTimelineTuning.stepSeconds),
            colourScheme: .classic
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let scheme = configuration.colourScheme ?? .classic
        let now = Date()
        return Entry(
            date: now,
            endDate: now.addingTimeInterval(WWClockTimelineTuning.stepSeconds),
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let scheme = configuration.colourScheme ?? .classic

        let now = Date()
        let step = WWClockTimelineTuning.stepSeconds

        let t = now.timeIntervalSince1970
        let nextBoundaryT = ceil(t / step) * step
        var boundary = Date(timeIntervalSince1970: nextBoundaryT)
        if boundary <= now {
            boundary = boundary.addingTimeInterval(step)
        }

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineTuning.entriesAfterBoundary + 1)

        // First entry starts at real "now" so the widget never shows the boundary time instantly.
        entries.append(
            Entry(
                date: now,
                endDate: boundary,
                colourScheme: scheme
            )
        )

        // Phase-locked entries on whole boundaries.
        for i in 0..<WWClockTimelineTuning.entriesAfterBoundary {
            let start = boundary.addingTimeInterval(Double(i) * step)
            let end = start.addingTimeInterval(step)
            entries.append(
                Entry(
                    date: start,
                    endDate: end,
                    colourScheme: scheme
                )
            )
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
            WidgetWeaverRenderClock.withNow(entry.date) {
                WidgetWeaverHomeScreenClockView(entry: entry)
            }
        }
        .configurationDisplayName("Clock (Icon)")
        .description("A small analogue clock.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - View

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
            intervalStart: entry.date,
            intervalEnd: entry.endDate
        )
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
