//
// WidgetWeaverWeatherTemplateView.swift
// WidgetWeaver
//
// Created by . . on 12/20/25.
//
// Rain-first weather template.
//
// MINUTE-BY-MINUTE UPDATE CONTRACT
// -------------------------------
// The template is expected to tick every minute so the following stay accurate:
// - Nowcast headline offsets (“…in 46m” / “Stopping in …m”)
// - Chart window alignment (“Now” and the next 60 minutes)
// - Updated-at label
//
// The minute tick is implemented with a TimelineView(.periodic(..., by: 60)) and a `.id(minuteID)`
// derived from the floored minute.
//
// Removing the `.id`, widening the interval, or moving time-sensitive computation outside the TimelineView
// can cause subtle staleness where some text appears live but other parts lag.

import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(UIKit)
import UIKit
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

        let trimmedTitle = spec.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmedTitle.isEmpty ? "Rain" : trimmedTitle

        let style = spec.style
        let metrics = WeatherMetrics(family: family, style: style, layout: spec.layout)

        Group {
            switch context {
            case .widget:
                // WidgetKit can pre-render future entries.
                // The render clock supplies the entry date.
                //
                // A live TimelineView drives minute-by-minute updates, but the effective "now" never
                // goes earlier than the entry date (so pre-rendered future entries remain distinct).
                let entryNow = floorToMinute(WidgetWeaverRenderClock.now)
                let scheduleStart = floorToMinute(Date())

                TimelineView(.periodic(from: scheduleStart, by: 60)) { timeline in
                    let liveNow = floorToMinute(timeline.date)
                    let now = maxDate(entryNow, liveNow)
                    let minuteID = Int(now.timeIntervalSince1970 / 60.0)

                    WeatherTemplateContent(
                        snapshot: snapshot,
                        location: location,
                        unit: unit,
                        now: now,
                        family: family,
                        metrics: metrics,
                        accent: accent,
                        style: style,
                        title: title
                    )
                    .id(minuteID)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(accessibilityLabel(snapshot: snapshot, location: location, unit: unit, now: now))
                }

            case .simulator:
                // Simulator-only: live ticking inside the running app.
                let scheduleStart = floorToMinute(Date())

                TimelineView(.periodic(from: scheduleStart, by: 60)) { timeline in
                    let now = floorToMinute(timeline.date)
                    let minuteID = Int(now.timeIntervalSince1970 / 60.0)

                    WeatherTemplateContent(
                        snapshot: snapshot,
                        location: location,
                        unit: unit,
                        now: now,
                        family: family,
                        metrics: metrics,
                        accent: accent,
                        style: style,
                        title: title
                    )
                    .id(minuteID)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(accessibilityLabel(snapshot: snapshot, location: location, unit: unit, now: now))
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
                    accent: accent,
                    style: style,
                    title: title
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel(accessibilityLabel(snapshot: snapshot, location: location, unit: unit, now: now))
            }
        }
        // Preserve the existing rain-first look by forcing Dark Mode semantics only when the
        // built-in adaptive weather backdrop is active. When a custom editor background is selected,
        // leaving colour scheme alone allows text/materials to remain legible across light/dark themes.
        .environment(\.wwRenderContext, context)
        .wwApplyIf(style.background == .subtleMaterial) { view in
            view.environment(\.colorScheme, .dark)
        }
    }

    private func accessibilityLabel(
        snapshot: WidgetWeaverWeatherSnapshot?,
        location: WidgetWeaverWeatherLocation?,
        unit: UnitTemperature,
        now: Date
    ) -> String {
        guard let snapshot else {
            if location == nil {
                return "Weather. No location selected."
            }
            return "Weather. Updating."
        }

        let temp = wwTempString(snapshot.temperatureC, unit: unit)
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)
        let headline = nowcast.primaryText
        return "Weather. \(snapshot.locationName). \(headline). Temperature \(temp)."
    }

    private func floorToMinute(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .minute, for: date)?.start ?? date
    }

    private func maxDate(_ a: Date, _ b: Date) -> Date {
        (a > b) ? a : b
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
    let style: StyleSpec
    let title: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            WeatherTemplateBackground(
                snapshot: snapshot,
                now: now,
                family: family,
                accent: accent,
                style: style
            )

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
                    title: title,
                    location: location,
                    metrics: metrics,
                    accent: accent
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct WeatherTemplateBackground: View {
    let snapshot: WidgetWeaverWeatherSnapshot?
    let now: Date
    let family: WidgetFamily
    let accent: Color
    let style: StyleSpec

    var body: some View {
        ZStack {
            if style.background == .subtleMaterial {
                WeatherBackdropView(
                    palette: palette,
                    family: family
                )
            } else {
                systemBackground
                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))
            }

            Rectangle()
                .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                .opacity(style.backgroundOverlayOpacity)

            if style.backgroundGlowEnabled {
                Circle()
                    .fill(accent)
                    .blur(radius: 70)
                    .opacity(0.18)
                    .offset(x: -120, y: -120)

                Circle()
                    .fill(accent)
                    .blur(radius: 90)
                    .opacity(0.12)
                    .offset(x: 140, y: 160)
            }
        }
        .ignoresSafeArea()
    }

    private var palette: WeatherPalette {
        if let snapshot {
            return WeatherPalette.forSnapshot(snapshot, now: now, accent: accent)
        }
        return WeatherPalette.fallback(accent: accent)
    }

    @ViewBuilder
    private var systemBackground: some View {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color.black
        #endif
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
        // Small: attribution only.
        .overlay(alignment: .bottomTrailing) {
            if family == .systemSmall {
                WeatherAttributionLink(accent: accent)
                    .padding(metrics.contentPadding)
            }
        }
    }
}

// MARK: - Empty State

private struct WeatherEmptyStateView: View {
    let title: String
    let location: WidgetWeaverWeatherLocation?
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        WeatherGlassContainer(metrics: metrics) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
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

private extension View {
    @ViewBuilder
    func wwApplyIf<Transformed: View>(
        _ condition: Bool,
        transform: (Self) -> Transformed
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
