//
//  WidgetWeaverWeatherTemplateLayouts.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Layouts

struct WeatherSmallRainLayout: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let unit: UnitTemperature
    let now: Date
    let family: WidgetFamily
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)

        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.locationName)
                        .font(.system(size: metrics.locationFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(nowcast.primaryText)
                        .font(.system(size: metrics.nowcastPrimaryFontSizeSmall, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }

            WeatherNowcastChart(
                buckets: nowcast.buckets(for: family),
                maxIntensityMMPerHour: nowcast.peakIntensityMMPerHour,
                accent: accent,
                showAxisLabels: false
            )
            .frame(height: metrics.nowcastChartHeightSmall)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(wwTempString(snapshot.temperatureC, unit: unit))
                    .font(.system(size: metrics.temperatureFontSizeSmall, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if let hi = snapshot.highTemperatureC, let lo = snapshot.lowTemperatureC {
                    Text("H \(wwTempString(hi, unit: unit)) L \(wwTempString(lo, unit: unit))")
                        .font(.system(size: metrics.detailsFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)
            }
        }
    }
}

struct WeatherMediumRainLayout: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let unit: UnitTemperature
    let now: Date
    let family: WidgetFamily
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)

        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.locationName)
                        .font(.system(size: metrics.locationFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(nowcast.primaryText)
                        .font(.system(size: metrics.nowcastPrimaryFontSizeMedium, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if let secondary = nowcast.secondaryText {
                        Text(secondary)
                            .font(.system(size: metrics.detailsFontSize, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 0)

                Text(wwTempString(snapshot.temperatureC, unit: unit))
                    .font(.system(size: metrics.temperatureFontSizeMedium, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            WeatherNowcastChart(
                buckets: nowcast.buckets(for: family),
                maxIntensityMMPerHour: nowcast.peakIntensityMMPerHour,
                accent: accent,
                showAxisLabels: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: metrics.nowcastChartHeightMedium)

            // Leaves room at the bottom for the pinned footer overlays.
            Spacer(minLength: 0)
                .frame(height: 18)
        }
    }
}

struct WeatherLargeRainLayout: View {
    let snapshot: WidgetWeaverWeatherSnapshot
    let unit: UnitTemperature
    let now: Date
    let metrics: WeatherMetrics
    let accent: Color

    var body: some View {
        let nowcast = WeatherNowcast(snapshot: snapshot, now: now)

        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.locationName)
                        .font(.system(size: metrics.locationFontSizeLarge, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(nowcast.primaryText)
                        .font(.system(size: metrics.nowcastPrimaryFontSizeLarge, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    if let secondary = nowcast.secondaryText {
                        Text(secondary)
                            .font(.system(size: metrics.detailsFontSizeLarge, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(wwTempString(snapshot.temperatureC, unit: unit))
                        .font(.system(size: metrics.temperatureFontSizeLarge, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let hi = snapshot.highTemperatureC, let lo = snapshot.lowTemperatureC {
                        Text("H \(wwTempString(hi, unit: unit)) L \(wwTempString(lo, unit: unit))")
                            .font(.system(size: metrics.detailsFontSizeLarge, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
            }

            WeatherNowcastChart(
                buckets: nowcast.buckets(for: .systemLarge),
                maxIntensityMMPerHour: max(0.6, nowcast.peakIntensityMMPerHour),
                accent: accent,
                showAxisLabels: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: metrics.nowcastChartHeightLarge)

            HStack(alignment: .firstTextBaseline) {
                WeatherAttributionLink(accent: accent)
                Spacer(minLength: 0)
                Text("Updated \(wwUpdatedAgoString(from: snapshot.fetchedAt, now: now))")
                    .font(.system(size: metrics.updatedFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}
