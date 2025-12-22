//
//  WidgetWeaverWeatherTemplateLayouts.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//
//  Layouts tuned so the rain graphic is the dominant element on Medium.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

struct WeatherSmallRainLayout: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let nowcast: WeatherNowcast

    let attributionURL: URL?
    let accent: Color
    let metrics: WeatherMetrics

    let nowMinute: Date
    let nowExact: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(snapshot.locationName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(metrics.temperatureText(fromCelsius: snapshot.temperatureC))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            HStack(alignment: .center, spacing: 10) {
                WeatherConditionIcon(symbolName: snapshot.symbolName, accent: accent)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(nowcast.primaryText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let secondary = nowcast.secondaryText {
                        Text(secondary)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }

            // Minimal strip to hint at upcoming rain without clutter.
            if !nowcast.buckets(for: .systemSmall).isEmpty {
                WeatherNowcastChart(
                    buckets: nowcast.buckets(for: .systemSmall),
                    accent: accent,
                    metrics: metrics,
                    axis: .none
                )
                .frame(height: metrics.smallGraphHeight)
            }

            Spacer(minLength: 0)
        }
        .padding(metrics.innerPadding)
    }
}

struct WeatherMediumRainLayout: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let nowcast: WeatherNowcast

    let attributionURL: URL?
    let accent: Color
    let metrics: WeatherMetrics

    let nowMinute: Date
    let nowExact: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: location + updated (keeps ticking each minute)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(snapshot.locationName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text("Updated \(wwUpdatedAgoString(from: snapshot.fetchedAt, now: nowExact))")
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Compact condition row (keeps visual dominance on the chart)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(nowcast.primaryText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let secondary = nowcast.secondaryText {
                        Text(secondary)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(metrics.temperatureText(fromCelsius: snapshot.temperatureC))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            // Main element: rain chart (intensity + certainty + uncertainty)
            WeatherNowcastChart(
                buckets: nowcast.buckets(for: .systemMedium),
                accent: accent,
                metrics: metrics,
                axis: .nowTo60m
            )
            .frame(maxWidth: .infinity)
            .frame(height: metrics.mediumGraphHeight)

            // Minimal footer (keeps clutter down)
            HStack(spacing: 8) {
                WeatherAttributionBadge(attributionURL: attributionURL)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(metrics.innerPadding)
    }
}

struct WeatherLargeRainLayout: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let nowcast: WeatherNowcast

    let attributionURL: URL?
    let accent: Color
    let metrics: WeatherMetrics

    let nowMinute: Date
    let nowExact: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.locationName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(nowcast.primaryText)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(metrics.temperatureText(fromCelsius: snapshot.temperatureC))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .monospacedDigit()

                    Text("Updated \(wwUpdatedAgoString(from: snapshot.fetchedAt, now: nowExact))")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            WeatherNowcastChart(
                buckets: nowcast.buckets(for: .systemLarge),
                accent: accent,
                metrics: metrics,
                axis: .nowTo60m
            )
            .frame(height: metrics.largeGraphHeight)

            if let summary = nowcast.longerSummaryText {
                Text(summary)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                WeatherAttributionBadge(attributionURL: attributionURL)
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)
        }
        .padding(metrics.innerPadding)
    }
}
