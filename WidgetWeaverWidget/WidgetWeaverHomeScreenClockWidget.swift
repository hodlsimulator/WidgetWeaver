//
//  WidgetWeaverHomeScreenClockWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/23/25.
//

import AppIntents
import SwiftUI
import WidgetKit

enum WidgetWeaverClockColourScheme: Int, AppEnum {
    case now
    case vibrant

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Clock Colour Scheme"
    }

    static var caseDisplayRepresentations: [WidgetWeaverClockColourScheme: DisplayRepresentation] {
        [
            .now: "Now",
            .vibrant: "Vibrant"
        ]
    }
}

struct WidgetWeaverHomeScreenClockEntry: TimelineEntry {
    let date: Date
    let anchorDate: Date

    /// Kept for compatibility with the existing clock renderer, but no longer used to drive WidgetKit refreshes.
    /// The view decides whether to show seconds based on TimelineView cadence.
    let tickSeconds: TimeInterval

    let colourScheme: WidgetWeaverClockColourScheme
}

struct WidgetWeaverHomeScreenClockProvider: AppIntentTimelineProvider {

    func placeholder(in context: Context) -> WidgetWeaverHomeScreenClockEntry {
        let now = Date()
        let anchor = Self.roundedDownToSecond(now)

        return WidgetWeaverHomeScreenClockEntry(
            date: now,
            anchorDate: anchor,
            tickSeconds: 60.0,
            colourScheme: .now
        )
    }

    func snapshot(
        for configuration: WidgetWeaverHomeScreenClockConfigurationIntent,
        in context: Context
    ) async -> WidgetWeaverHomeScreenClockEntry {
        let now = Date()
        let anchor = Self.roundedDownToSecond(now)

        return WidgetWeaverHomeScreenClockEntry(
            date: now,
            anchorDate: anchor,
            tickSeconds: 60.0,
            colourScheme: configuration.colourScheme
        )
    }

    func timeline(
        for configuration: WidgetWeaverHomeScreenClockConfigurationIntent,
        in context: Context
    ) async -> Timeline<WidgetWeaverHomeScreenClockEntry> {

        let now = Date()
        let anchor = Self.roundedDownToSecond(now)

        // Only one entry. The “ticking” is done by TimelineView inside the widget view.
        let entry = WidgetWeaverHomeScreenClockEntry(
            date: now,
            anchorDate: anchor,
            tickSeconds: 60.0,
            colourScheme: configuration.colourScheme
        )

        // Budget-safe: schedule an infrequent reload to pick up intent/appearance changes and keep things fresh.
        // Low Power Mode: refresh less often.
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let refreshInterval: TimeInterval = isLowPowerMode ? (2 * 60 * 60) : (60 * 60)
        let nextRefresh = now.addingTimeInterval(refreshInterval)

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private static func roundedDownToSecond(_ date: Date) -> Date {
        let t = floor(date.timeIntervalSince1970)
        return Date(timeIntervalSince1970: t)
    }
}

struct WidgetWeaverHomeScreenClockWidget: Widget {
    let kind: String = "WidgetWeaverHomeScreenClockWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetWeaverHomeScreenClockConfigurationIntent.self,
            provider: WidgetWeaverHomeScreenClockProvider()
        ) { entry in
            WidgetWeaverHomeScreenClockView(entry: entry)
        }
        .configurationDisplayName("Clock (Icon)")
        .description("A tiny analogue clock.")
        .supportedFamilies([.systemSmall])
    }
}

private struct WidgetWeaverHomeScreenClockView: View {
    let entry: WidgetWeaverHomeScreenClockEntry

    @Environment(\.colorScheme) private var colorScheme

    private func shouldShowSecondHand(_ cadence: TimelineView.Context.Cadence) -> Bool {
        switch cadence {
        case .live, .seconds:
            return true
        case .minutes:
            return false
        @unknown default:
            return false
        }
    }

    var body: some View {
        let palette = WidgetWeaverClockPalette.resolve(
            scheme: entry.colourScheme,
            mode: colorScheme
        )

        // This is the key: the widget “ticks” using SwiftUI’s TimelineView.
        // The system controls cadence (seconds when visible, slower when not).
        TimelineView(.periodic(from: entry.anchorDate, by: 1.0)) { context in
            let showSeconds = shouldShowSecondHand(context.cadence)

            WidgetWeaverClockWidgetLiveView(
                palette: palette,
                date: context.date,
                anchorDate: entry.anchorDate,
                tickSeconds: showSeconds ? 1.0 : 60.0
            )
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .wwWidgetContainerBackground {
            WidgetWeaverClockBackgroundView(palette: palette)
        }
    }
}
