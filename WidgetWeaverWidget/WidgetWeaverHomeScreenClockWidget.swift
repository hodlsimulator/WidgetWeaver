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
    /// Keep WidgetKit entries modest to avoid relying on frequent refreshes.
    /// The second-hand sweep is driven by TimelineView(.animation) in the view.
    static let entryStepSeconds: TimeInterval = 60.0 * 30.0 // 30 minutes
    static let maxEntries: Int = 48 // 24 hours @ 30 minutes
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

        // Important: use a base that changes on each timeline request to help avoid cached renders.
        let base = Date()

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineTuning.maxEntries)

        for i in 0..<WWClockTimelineTuning.maxEntries {
            let d = base.addingTimeInterval(WWClockTimelineTuning.entryStepSeconds * Double(i))
            entries.append(Entry(date: d, colourScheme: scheme))
        }

        return Timeline(entries: entries, policy: .atEnd)
    }
}

// MARK: - View

private struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var colourMode

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(scheme: entry.colourScheme, mode: colourMode)

        // Wrap in RenderClock scope so any other time-dependent widget content stays deterministic.
        WidgetWeaverRenderClock.withNow(entry.date) {
            WidgetWeaverClockWidgetLiveView(palette: palette, anchorDate: entry.date)
                .id(entry.date) // reset internal anchor state per entry
                .wwWidgetContainerBackground {
                    WidgetWeaverClockBackgroundView(palette: palette)
                }
        }
    }
}

// MARK: - Widget

public struct WidgetWeaverHomeScreenClockWidget: Widget {
    public init() {}

    public let kind: String = WidgetWeaverWidgetKinds.homeScreenClock

    public var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetWeaverClockConfigurationIntent.self,
            provider: WidgetWeaverHomeScreenClockProvider()
        ) { entry in
            WidgetWeaverHomeScreenClockView(entry: entry)
        }
        .configurationDisplayName("Clock (WidgetWeaver)")
        .description("An analogue clock widget.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
