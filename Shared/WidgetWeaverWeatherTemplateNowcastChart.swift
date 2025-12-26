//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Nowcast chart container + axis labels.
//  Chart area is dedicated to surface rendering; labels are outside.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

struct WeatherNowcastChart: View {
    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool

    /// Seed component (rounded to minute) for deterministic fuzz.
    let forecastStart: Date

    /// Location components for deterministic fuzz.
    let locationLatitude: Double?
    let locationLongitude: Double?

    #if canImport(WidgetKit)
    @Environment(\.widgetFamily) private var widgetFamily
    #endif

    var body: some View {
        let insets = WeatherNowcastChartInsets()

        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black)

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

            VStack(spacing: 0) {
                WeatherNowcastSurfacePlot(
                    points: points,
                    maxIntensityMMPerHour: maxIntensityMMPerHour,
                    accent: accent,
                    forecastStart: forecastStart,
                    locationLatitude: locationLatitude,
                    locationLongitude: locationLongitude
                )
                .padding(.horizontal, insets.plotHorizontal)
                .padding(.top, insets.plotTop)
                .padding(.bottom, showAxisLabels ? insets.plotBottomWithAxis : insets.plotBottomNoAxis)

                if showAxisLabels {
                    WeatherNowcastAxisLabels(accent: accent)
                        .padding(.horizontal, insets.axisHorizontal)
                        .padding(.bottom, insets.axisBottom)
                        .padding(.top, insets.axisTop)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct WeatherNowcastChartInsets {
    let plotHorizontal: CGFloat = 12
    let plotTop: CGFloat = 10
    let plotBottomWithAxis: CGFloat = 6
    let plotBottomNoAxis: CGFloat = 10

    let axisHorizontal: CGFloat = 16
    let axisTop: CGFloat = 0
    let axisBottom: CGFloat = 10
}

private struct WeatherNowcastAxisLabels: View {
    let accent: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            axis("Now")
            Spacer(minLength: 0)
            axis("10m")
            Spacer(minLength: 0)
            axis("20m")
            Spacer(minLength: 0)
            axis("30m")
            Spacer(minLength: 0)
            axis("40m")
            Spacer(minLength: 0)
            axis("50m")
        }
    }

    private func axis(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.65))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

private struct WeatherNowcastSurfacePlot: View {
    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color

    let forecastStart: Date
    let locationLatitude: Double?
    let locationLongitude: Double?

    #if canImport(WidgetKit)
    @Environment(\.widgetFamily) private var widgetFamily
    #endif

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let series = samples(from: points, targetMinutes: 60)

            let intensities: [Double] = series.map { p in
                let raw = max(0.0, p.precipitationIntensityMMPerHour ?? 0.0)
                let clamped = min(raw, maxIntensityMMPerHour)
                return WeatherNowcast.isWet(intensityMMPerHour: clamped) ? clamped : 0.0
            }

            let certainties: [Double] = series.enumerated().map { (i, p) in
                let chance = RainSurfaceMath.clamp01(p.precipitationChance01 ?? 0.0)
                let t = Double(i) / 59.0
                let horizonFactor = 1.0 - 0.35 * RainSurfaceMath.smoothstep01(t)
                return RainSurfaceMath.clamp01(chance * horizonFactor)
            }

            let seed = makeNoiseSeed(
                forecastStart: forecastStart,
                widgetFamily: widgetFamilyValue(),
                latitude: locationLatitude,
                longitude: locationLongitude
            )

            let config: RainForecastSurfaceConfiguration = {
                var c = RainForecastSurfaceConfiguration()
                c.noiseSeed = seed
                c.maxDenseSamples = 256
                c.glossEnabled = true
                c.glintEnabled = false
                c.fuzzEnabled = true

                c.coreTopColor = accent
                c.coreMidColor = Color(red: 0.03, green: 0.22, blue: 0.78)
                c.coreBottomColor = Color(red: 0.00, green: 0.05, blue: 0.18)

                c.fuzzColor = Color(red: 0.62, green: 0.88, blue: 1.00)
                c.baselineColor = accent
                c.baselineLineOpacity = 0.30

                return c
            }()

            RainForecastSurfaceView(
                intensities: intensities,
                certainties: certainties,
                configuration: config
            )
            .frame(width: size.width, height: size.height)
        }
    }

    // MARK: - Seed

    private func widgetFamilyValue() -> UInt64 {
        #if canImport(WidgetKit)
        switch widgetFamily {
        case .systemSmall: return 1
        case .systemMedium: return 2
        case .systemLarge: return 3
        case .systemExtraLarge: return 4
        default: return 0
        }
        #else
        return 0
        #endif
    }

    private func makeNoiseSeed(
        forecastStart: Date,
        widgetFamily: UInt64,
        latitude: Double?,
        longitude: Double?
    ) -> UInt64 {
        let minute = Int64(floor(forecastStart.timeIntervalSince1970 / 60.0))
        var seed = RainSurfacePRNG.combine(UInt64(bitPattern: minute), widgetFamily)

        if let latitude, let longitude {
            let latQ = Int64((latitude * 10_000.0).rounded())
            let lonQ = Int64((longitude * 10_000.0).rounded())
            seed = RainSurfacePRNG.combine(seed, UInt64(bitPattern: latQ))
            seed = RainSurfacePRNG.combine(seed, UInt64(bitPattern: lonQ))
        } else {
            seed = RainSurfacePRNG.combine(seed, RainSurfacePRNG.hashString64("no-location"))
        }

        return seed
    }

    // MARK: - Data shaping

    private func samples(from points: [WidgetWeaverWeatherMinutePoint], targetMinutes: Int) -> [WidgetWeaverWeatherMinutePoint] {
        guard targetMinutes > 0 else { return [] }
        guard !points.isEmpty else {
            return Array(
                repeating: WidgetWeaverWeatherMinutePoint(
                    date: Date(),
                    precipitationChance01: 0.0,
                    precipitationIntensityMMPerHour: 0.0
                ),
                count: targetMinutes
            )
        }

        let sorted = points.sorted(by: { $0.date < $1.date })
        var out: [WidgetWeaverWeatherMinutePoint] = Array(sorted.prefix(targetMinutes))

        if out.count < targetMinutes {
            let lastDate = out.last?.date ?? Date()
            let cal = Calendar.current
            let start = cal.dateInterval(of: .minute, for: lastDate)?.start ?? lastDate
            let needed = targetMinutes - out.count
            for i in 1...needed {
                let d = cal.date(byAdding: .minute, value: i, to: start) ?? start.addingTimeInterval(Double(i) * 60.0)
                out.append(.init(date: d, precipitationChance01: 0.0, precipitationIntensityMMPerHour: 0.0))
            }
        }

        return out
    }
}
