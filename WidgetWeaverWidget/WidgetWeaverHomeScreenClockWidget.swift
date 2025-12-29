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

    /// On-screen tick while visible (driven by SwiftUI TimelineView).
    private static let normalOnScreenTick: TimeInterval = 1.0

    /// Low Power Mode: reduce on-screen churn + hide second hand.
    private static let lowPowerOnScreenTick: TimeInterval = 60.0

    /// WidgetKit refresh cadence (budget-safe).
    /// The view itself will tick while visible; this is just a periodic resync.
    private static let widgetKitResyncInterval: TimeInterval = 60.0 * 60.0 // 1 hour
    private static let widgetKitTimelineHorizon: TimeInterval = 24.0 * 60.0 * 60.0 // 24 hours

    func placeholder(in context: Context) -> Entry {
        let now = Date()
        let anchor = Self.floorToWholeSecond(now)
        return Entry(
            date: now,
            anchorDate: anchor,
            tickSeconds: Self.normalOnScreenTick,
            colourScheme: .classic
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let anchor = Self.floorToWholeSecond(now)
        let scheme = configuration.colourScheme ?? .classic

        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let tick = isLowPower ? Self.lowPowerOnScreenTick : Self.normalOnScreenTick

        return Entry(
            date: now,
            anchorDate: anchor,
            tickSeconds: tick,
            colourScheme: scheme
        )
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let anchor = Self.floorToWholeSecond(now)
        let scheme = configuration.colourScheme ?? .classic

        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let tick = isLowPower ? Self.lowPowerOnScreenTick : Self.normalOnScreenTick

        let entryCount = Int(Self.widgetKitTimelineHorizon / Self.widgetKitResyncInterval) + 1

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)

        for i in 0..<entryCount {
            let d = anchor.addingTimeInterval(TimeInterval(i) * Self.widgetKitResyncInterval)
            entries.append(
                Entry(
                    date: d,
                    anchorDate: anchor,
                    tickSeconds: tick,
                    colourScheme: scheme
                )
            )
        }

        return Timeline(entries: entries, policy: .atEnd)
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
