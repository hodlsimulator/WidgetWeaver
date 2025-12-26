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
    // Conservative: avoids WidgetKit reload budget issues.
    static let tickSeconds: TimeInterval = 60.0 * 15.0
    static let maxEntries: Int = 96
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
        let step = WWClockTimelineTuning.tickSeconds
        let t = now.timeIntervalSince1970
        let alignedT = floor(t / step) * step
        let base = Date(timeIntervalSince1970: alignedT)

        var entries: [Entry] = []
        entries.reserveCapacity(WWClockTimelineTuning.maxEntries)

        for i in 0..<WWClockTimelineTuning.maxEntries {
            let d = base.addingTimeInterval(Double(i) * step)
            entries.append(Entry(date: d, colourScheme: scheme))
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
            anchorDate: entry.date
        )
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
