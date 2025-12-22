//
//  WidgetWeaverWeatherTemplateView.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//
//  Weather template root view.
//  Preserves minute-by-minute refresh for both graphics and text.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

struct WeatherTemplateView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext

    var body: some View {
        let store = WidgetWeaverWeatherStore.shared
        let snapshot = store.snapshotForRender(context: context)
        let attributionURL = store.attributionLegalURL()

        let accent = spec.style.accent.swiftUIColor

        // WidgetKit can pre-render future timeline entries.
        // The render clock supplies the entry date for each entry render.
        // A live TimelineView drives per-minute updates when the system keeps the view live.
        // The effective "now" never goes earlier than the entry date.
        let entryNowExact = WidgetWeaverRenderClock.now
        let scheduleStart = Date()

        TimelineView(.periodic(from: scheduleStart, by: 60)) { timeline in
            let liveNowExact = timeline.date
            let nowExact = maxDate(entryNowExact, liveNowExact)

            // Minute-aligned time is used for bucketing and to avoid sub-minute jitter in the chart.
            let nowMinute = floorToMinute(nowExact)

            // Forces a full recompute once per minute (chart + "Updated …" label).
            let minuteID = Int(nowMinute.timeIntervalSince1970 / 60)

            WeatherTemplateContent(
                spec: spec,
                family: family,
                context: context,
                snapshot: snapshot,
                attributionURL: attributionURL,
                accent: accent,
                nowMinute: nowMinute,
                nowExact: nowExact
            )
            .id(minuteID)
        }
        // The flagship weather card is designed for a dark presentation.
        // Backgrounds are editable, but the typography + materials are tuned for dark.
        .environment(\.colorScheme, .dark)
    }

    private func floorToMinute(_ date: Date) -> Date {
        let time = date.timeIntervalSince1970
        let floored = floor(time / 60.0) * 60.0
        return Date(timeIntervalSince1970: floored)
    }

    private func maxDate(_ a: Date, _ b: Date) -> Date {
        (a > b) ? a : b
    }
}

private struct WeatherTemplateContent: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext

    let snapshot: WidgetWeaverWeatherSnapshot?
    let attributionURL: URL?

    let accent: Color

    let nowMinute: Date
    let nowExact: Date

    var body: some View {
        if let snapshot {
            WeatherFilledStateView(
                spec: spec,
                family: family,
                snapshot: snapshot,
                attributionURL: attributionURL,
                accent: accent,
                nowMinute: nowMinute,
                nowExact: nowExact
            )
        } else {
            WeatherEmptyStateView(
                spec: spec,
                family: family,
                accent: accent
            )
        }
    }
}

private struct WeatherFilledStateView: View {
    let spec: WidgetSpec
    let family: WidgetFamily

    let snapshot: WidgetWeaverWeatherSnapshot
    let attributionURL: URL?

    let accent: Color

    let nowMinute: Date
    let nowExact: Date

    var body: some View {
        let metrics = WeatherMetrics(style: spec.style, family: family)
        let nowcast = WeatherNowcast(snapshot: snapshot, now: nowMinute)

        WeatherCardContainer(
            metrics: metrics,
            style: spec.style,
            accent: accent,
            nowcast: nowcast
        ) {
            switch family {
            case .systemSmall:
                WeatherSmallRainLayout(
                    snapshot: snapshot,
                    nowcast: nowcast,
                    attributionURL: attributionURL,
                    accent: accent,
                    metrics: metrics,
                    nowMinute: nowMinute,
                    nowExact: nowExact
                )
            case .systemMedium:
                WeatherMediumRainLayout(
                    snapshot: snapshot,
                    nowcast: nowcast,
                    attributionURL: attributionURL,
                    accent: accent,
                    metrics: metrics,
                    nowMinute: nowMinute,
                    nowExact: nowExact
                )
            default:
                WeatherLargeRainLayout(
                    snapshot: snapshot,
                    nowcast: nowcast,
                    attributionURL: attributionURL,
                    accent: accent,
                    metrics: metrics,
                    nowMinute: nowMinute,
                    nowExact: nowExact
                )
            }
        }
        .padding(metrics.outerPadding)
    }
}

private struct WeatherEmptyStateView: View {
    let spec: WidgetSpec
    let family: WidgetFamily
    let accent: Color

    var body: some View {
        let metrics = WeatherMetrics(style: spec.style, family: family)

        WeatherCardContainer(
            metrics: metrics,
            style: spec.style,
            accent: accent,
            nowcast: nil
        ) {
            VStack(spacing: 10) {
                Image(systemName: "location.slash")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent.opacity(0.85))

                Text("Weather needs a location")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("Open the app and choose a place for Weather.")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(metrics.innerPadding)
        }
        .padding(metrics.outerPadding)
    }
}
