//
//  WidgetWeaverWeatherTemplateLayouts.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//
//  Layouts for the rain-first weather template.
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
        let visualMax = WeatherNowcast.visualMaxIntensityMMPerHour(forPeak: nowcast.peakIntensityMMPerHour)

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
                points: nowcast.points,
                maxIntensityMMPerHour: visualMax,
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
        let visualMax = WeatherNowcast.visualMaxIntensityMMPerHour(forPeak: nowcast.peakIntensityMMPerHour)

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
                points: nowcast.points,
                maxIntensityMMPerHour: visualMax,
                accent: accent,
                showAxisLabels: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: metrics.nowcastChartHeightMedium)

            // Footer row (keeps attribution out of the chart so it can’t block “Now”).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WeatherAttributionLink(accent: accent)
                WeatherUpdatedLabel(fetchedAt: snapshot.fetchedAt, fontSize: metrics.updatedFontSize)
            }
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
        let visualMax = WeatherNowcast.visualMaxIntensityMMPerHour(forPeak: nowcast.peakIntensityMMPerHour)

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
                points: nowcast.points,
                maxIntensityMMPerHour: visualMax,
                accent: accent,
                showAxisLabels: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: metrics.nowcastChartHeightLarge)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WeatherAttributionLink(accent: accent)
                WeatherUpdatedLabel(fetchedAt: snapshot.fetchedAt, fontSize: metrics.updatedFontSize)
            }
        }
    }
}

// MARK: - Updated label (dynamic)

private struct WeatherUpdatedLabel: View {
    let fetchedAt: Date
    let fontSize: CGFloat

    var body: some View {
        // `Text(date, style: .relative)` is a system-supported dynamic date style that tends to keep
        // ticking without requiring string recomputation.
        HStack(spacing: 4) {
            Text("Updated")
            Text(fetchedAt, style: .relative)
        }
        .font(.system(size: fontSize, weight: .medium, design: .rounded))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .multilineTextAlignment(.trailing)
    }
}
