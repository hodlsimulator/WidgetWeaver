//
//  WidgetWeaverWeatherTemplateView.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Weather Template

/// The weather template is opinionated and rain-first:
/// - Next hour precipitation is the primary focus (Dark Sky style).
/// - Temperature is secondary.
/// - Everything else is de-emphasised.
struct WeatherTemplateView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext
    let accent: Color

    init(
        spec: WidgetSpec,
        family: WidgetFamily,
        context: WidgetWeaverRenderContext,
        accent: Color
    ) {
        self.spec = spec
        self.family = family
        self.context = context
        self.accent = accent
    }

    var body: some View {
        let store = WidgetWeaverWeatherStore.shared
        let snapshot = store.snapshotForRender(context: context)
        let location = store.loadLocation()
        let unit = store.resolvedUnitTemperature()
        let metrics = WeatherMetrics(family: family, style: spec.style, layout: spec.layout)

        Group {
            switch context {
            case .widget:
                // In a real widget, WidgetKit may pre-render future entries.
                // Using Date() here causes every entry to look identical (blink-only).
                //
                // Use the entry date injected via WidgetWeaverRenderClock as the base, then tick
                // inside that entry so time-based visuals (chart + “Updated …”) advance even if
                // WidgetKit throttles timeline swaps.
                let baseNow = Calendar.current.dateInterval(of: .minute, for: WidgetWeaverRenderClock.now)?.start
                    ?? WidgetWeaverRenderClock.now

                TimelineView(.periodic(from: baseNow, by: 60)) { timeline in
                    WeatherTemplateContent(
                        snapshot: snapshot,
                        location: location,
                        unit: unit,
                        now: timeline.date,
                        family: family,
                        metrics: metrics,
                        accent: accent
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(accessibilityLabel(snapshot: snapshot, location: location, unit: unit, now: timeline.date))
                }

            case .simulator:
                // Simulator-only: live ticking inside the running app.
                TimelineView(.periodic(from: Date(), by: 60)) { timeline in
                    WeatherTemplateContent(
                        snapshot: snapshot,
                        location: location,
                        unit: unit,
                        now: timeline.date,
                        family: family,
                        metrics: metrics,
                        accent: accent
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(accessibilityLabel(snapshot: snapshot, location: location, unit: unit, now: timeline.date))
                }

            case .preview:
                let now = Date()
                WeatherTemplateContent(
                    snapshot: snapshot,
                    location: location,
                    unit: unit,
                    now: now,
                    family: family,
                    metrics: metrics,
                    accent: accent
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel(snapshot: snapshot, location: location, unit: unit, now: now))
            }
        }
        // The template draws a dark backdrop and relies on semantic foreground styles
        // (.primary / .secondary). In Light Mode those resolve to dark colours, which
        // makes the text effectively disappear against the dark background.
        //
        // Force Dark Mode semantics for the template so the text remains readable.
        .environment(\.colorScheme, .dark)
    }

    private func accessibilityLabel(
        snapshot: WidgetWeaverWeatherSnapshot?,
        location: WidgetWeaverWeatherLocation?,
        unit: UnitTemperature,
        now: Date
    ) -> String {
        guard let snapshot else {
            if location == nil { return "Weather. No location selected." }
            return "Weather. Updating."
        }

        let temp = wwTempString(snapshot.temperatureC, unit: unit)
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)
        let headline = nowcast.primaryText
        return "Weather. \(snapshot.locationName). \(headline). Temperature \(temp)."
    }
}

private struct WeatherTemplateContent: View {
    let snapshot: WidgetWeaverWeatherSnapshot?
    let location: WidgetWeaverWeatherLocation?
    let unit: UnitTemperature
    let now: Date
    let family: WidgetFamily
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let snapshot {
                WeatherBackdropView(
                    palette: WeatherPalette.forSnapshot(snapshot, now: now, accent: accent),
                    family: family
                )
            } else {
                WeatherBackdropView(
                    palette: WeatherPalette.fallback(accent: accent),
                    family: family
                )
            }

            if let snapshot {
                WeatherFilledStateView(
                    snapshot: snapshot,
                    unit: unit,
                    now: now,
                    family: family,
                    metrics: metrics,
                    accent: accent
                )
            } else {
                WeatherEmptyStateView(
                    location: location,
                    metrics: metrics,
                    accent: accent
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Layout Switching

private struct WeatherFilledStateView: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let unit: UnitTemperature
    let now: Date
    let family: WidgetFamily
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        WeatherGlassContainer(metrics: metrics) {
            switch family {
            case .systemSmall:
                WeatherSmallRainLayout(
                    snapshot: snapshot,
                    unit: unit,
                    now: now,
                    family: family,
                    metrics: metrics,
                    accent: accent
                )
            case .systemMedium:
                WeatherMediumRainLayout(
                    snapshot: snapshot,
                    unit: unit,
                    now: now,
                    family: family,
                    metrics: metrics,
                    accent: accent
                )
            default:
                WeatherLargeRainLayout(
                    snapshot: snapshot,
                    unit: unit,
                    now: now,
                    metrics: metrics,
                    accent: accent
                )
            }
        }
        // Small: attribution button only.
        .overlay(alignment: .bottomTrailing) {
            if family == .systemSmall {
                WeatherAttributionLink(accent: accent)
                    .padding(metrics.contentPadding)
            }
        }
        // Medium: pin footer items as overlays so they never get pushed off-screen.
        .overlay(alignment: .bottomLeading) {
            if family == .systemMedium {
                WeatherAttributionLink(accent: accent)
                    .padding(metrics.contentPadding)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if family == .systemMedium {
                Text("Updated \(wwUpdatedAgoString(from: snapshot.fetchedAt, now: now))")
                    .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(metrics.contentPadding)
            }
        }
    }
}

// MARK: - Empty State

private struct WeatherEmptyStateView: View {
    let location: WidgetWeaverWeatherLocation?
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        WeatherGlassContainer(metrics: metrics) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Rain")
                    .font(.system(size: metrics.nowcastPrimaryFontSizeMedium, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if location == nil {
                    Text("Set a location in the app.")
                        .font(.system(size: metrics.detailsFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    Text("Tap to open settings")
                        .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(accent)
                } else {
                    Text("Updating weather…")
                        .font(.system(size: metrics.detailsFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("Tap to refresh")
                        .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(accent)
                }

                Spacer(minLength: 0)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    WeatherAttributionLink(accent: accent)
                    Spacer(minLength: 0)
                    Text("WidgetWeaver")
                        .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
