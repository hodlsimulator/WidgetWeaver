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
    // 30 minutes -> 48 aligned entries/day.
    static let stepSeconds: TimeInterval = 60.0 * 30.0
    static let alignedEntriesPerDay: Int = 48

    /// The next whole-step boundary strictly after the provided date.
    ///
    /// Alignment is performed in epoch seconds to keep the sweep phase-locked.
    static func nextAlignedBoundary(after date: Date) -> Date {
        let step = stepSeconds
        let t = date.timeIntervalSince1970

        var boundaryT = (t / step).rounded(.up) * step
        if boundaryT <= t {
            boundaryT += step
        }

        return Date(timeIntervalSince1970: boundaryT)
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

    /// The next entry date used as the animation target for a smooth sweep.
    public let nextDate: Date

    public let colourScheme: WidgetWeaverClockColourScheme
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenClockEntry
    typealias Intent = WidgetWeaverClockConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        return Entry(
            date: now,
            nextDate: now.addingTimeInterval(WWClockTimelineTuning.stepSeconds),
            colourScheme: .classic
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let scheme = configuration.colourScheme ?? .classic
        let now = Date()

        return Entry(
            date: now,
            nextDate: now.addingTimeInterval(WWClockTimelineTuning.stepSeconds),
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let scheme = configuration.colourScheme ?? .classic

        let now = Date()
        let step = WWClockTimelineTuning.stepSeconds

        let nextBoundary = WWClockTimelineTuning.nextAlignedBoundary(after: now)

        // One immediate entry for correct phase on first render, then aligned entries.
        var dates: [Date] = [now]
        dates.reserveCapacity(1 + WWClockTimelineTuning.alignedEntriesPerDay)

        for i in 0..<WWClockTimelineTuning.alignedEntriesPerDay {
            let d = nextBoundary.addingTimeInterval(TimeInterval(i) * step)
            dates.append(d)
        }

        var entries: [Entry] = []
        entries.reserveCapacity(dates.count)

        for i in 0..<dates.count {
            let d = dates[i]
            let next = (i + 1 < dates.count) ? dates[i + 1] : d.addingTimeInterval(step)

            entries.append(
                Entry(
                    date: d,
                    nextDate: next,
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
            entryDate: entry.date,
            nextDate: entry.nextDate
        )
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
