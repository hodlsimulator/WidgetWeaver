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

        let store = WidgetWeaverWeatherStore.shared
        let hasRecentFailure: Bool = {
            guard store.loadLastError() != nil else { return false }
            guard let attempt = store.loadLastRefreshAttemptAt() else { return true }
            if let success = store.loadLastSuccessfulRefreshAt() {
                return attempt > success
            }
            return true
        }()

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
                showAxisLabels: false,
                forecastStart: now,
                locationLatitude: snapshot.latitude,
                locationLongitude: snapshot.longitude
            )
            .frame(height: metrics.nowcastChartHeightSmall)

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(wwTempDegreesWithUnitString(snapshot.temperatureC, unit: unit))
                    .font(.system(size: metrics.temperatureFontSizeSmall, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                if let hi = snapshot.highTemperatureC, let lo = snapshot.lowTemperatureC {
                    Text("H \(wwTempDegreesString(hi, unit: unit)) L \(wwTempDegreesString(lo, unit: unit))")
                        .font(.system(size: metrics.detailsFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                if hasRecentFailure {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: metrics.updatedFontSize, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
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

                Text(wwTempDegreesWithUnitString(snapshot.temperatureC, unit: unit))
                    .font(.system(size: metrics.temperatureFontSizeMedium, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }

            WeatherNowcastChart(
                points: nowcast.points,
                maxIntensityMMPerHour: visualMax,
                accent: accent,
                showAxisLabels: true,
                forecastStart: now,
                locationLatitude: snapshot.latitude,
                locationLongitude: snapshot.longitude
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: metrics.nowcastChartHeightMedium)

            // Footer row (keeps attribution out of the chart so it can’t block “Now”).
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WeatherAttributionLink(accent: accent)
                WeatherUpdatedLabel(now: now, fetchedAt: snapshot.fetchedAt, fontSize: metrics.updatedFontSize)
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
                    Text(wwTempDegreesWithUnitString(snapshot.temperatureC, unit: unit))
                        .font(.system(size: metrics.temperatureFontSizeLarge, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let hi = snapshot.highTemperatureC, let lo = snapshot.lowTemperatureC {
                        Text("H \(wwTempDegreesString(hi, unit: unit)) L \(wwTempDegreesString(lo, unit: unit))")
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
                showAxisLabels: true,
                forecastStart: now,
                locationLatitude: snapshot.latitude,
                locationLongitude: snapshot.longitude
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: metrics.nowcastChartHeightLarge)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WeatherAttributionLink(accent: accent)
                WeatherUpdatedLabel(now: now, fetchedAt: snapshot.fetchedAt, fontSize: metrics.updatedFontSize)
            }
        }
    }
}

// MARK: - Footer status

private struct WeatherUpdatedLabel: View {
    let now: Date
    let fetchedAt: Date
    let fontSize: CGFloat

    var body: some View {
        let store = WidgetWeaverWeatherStore.shared
        let updated = wwUpdatedAgoString(from: fetchedAt, now: now)

        let hasRecentFailure: Bool = {
            guard store.loadLastError() != nil else { return false }
            guard let attempt = store.loadLastRefreshAttemptAt() else { return true }
            if let success = store.loadLastSuccessfulRefreshAt() {
                return attempt > success
            }
            return true
        }()

        let text = hasRecentFailure ? "Updated \(updated) · Update failed" : "Updated \(updated)"

        return Text(text)
            .font(.system(size: fontSize, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .multilineTextAlignment(.trailing)
    }
}
