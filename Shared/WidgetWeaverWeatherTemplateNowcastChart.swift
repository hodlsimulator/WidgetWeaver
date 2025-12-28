//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//
//  Nowcast chart for the weather template.
//

import Foundation
import SwiftUI

#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Chart View

struct WeatherNowcastChart: View {
    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool
    let forecastStart: Date
    let locationLatitude: Double?
    let locationLongitude: Double?

    private var displayScale: CGFloat {
        #if canImport(UIKit)
        return UIScreen.main.scale
        #else
        return 2.0
        #endif
    }

    var body: some View {
        WeatherNowcastSurfacePlot(
            points: points,
            maxIntensityMMPerHour: maxIntensityMMPerHour,
            accent: accent,
            showAxisLabels: showAxisLabels,
            forecastStart: forecastStart,
            locationLatitude: locationLatitude,
            locationLongitude: locationLongitude
        )
    }
}

// MARK: - Surface Plot

private struct WeatherNowcastSurfacePlot: View {
    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool
    let forecastStart: Date
    let locationLatitude: Double?
    let locationLongitude: Double?

    private var displayScale: CGFloat {
        #if canImport(UIKit)
        return UIScreen.main.scale
        #else
        return 2.0
        #endif
    }

    private func samples(from points: [WidgetWeaverWeatherMinutePoint], targetMinutes: Int) -> [WidgetWeaverWeatherMinutePoint] {
        // If WeatherKit minute forecast isn't available, return empty samples.
        guard !points.isEmpty else { return [] }

        // Ensure forward-ordered, clamped to the next targetMinutes.
        let sorted = points.sorted(by: { $0.date < $1.date })
        let start = sorted.first?.date ?? forecastStart
        let end = Calendar.current.date(byAdding: .minute, value: targetMinutes - 1, to: start) ?? start

        // Fill missing minutes with interpolated chance + zero intensity.
        var byMinute: [Int: WidgetWeaverWeatherMinutePoint] = [:]
        for p in sorted {
            let delta = Int(p.date.timeIntervalSince(start) / 60.0)
            if delta >= 0 && delta < targetMinutes {
                byMinute[delta] = p
            }
        }

        var out: [WidgetWeaverWeatherMinutePoint] = []
        out.reserveCapacity(targetMinutes)

        for i in 0..<targetMinutes {
            if let exact = byMinute[i] {
                out.append(exact)
            } else {
                let d = Calendar.current.date(byAdding: .minute, value: i, to: start) ?? start.addingTimeInterval(TimeInterval(i * 60))
                out.append(
                    WidgetWeaverWeatherMinutePoint(
                        date: d,
                        precipitationChance01: 0.0,
                        precipitationIntensityMMPerHour: 0.0
                    )
                )
            }
        }

        // Clamp to end.
        return out.filter { $0.date <= end }
    }

    private func makeNoiseSeed(lat: Double?, lon: Double?, start: Date) -> UInt64 {
        // A deterministic per-location/per-hour seed so the "surface relief" pattern is stable.
        let hour = Calendar.current.dateInterval(of: .hour, for: start)?.start ?? start
        let t = UInt64(max(0, Int(hour.timeIntervalSince1970)))

        if let lat, let lon, lat.isFinite, lon.isFinite {
            let key = String(format: "lat%.4f_lon%.4f_t%llu", lat, lon, t)
            return RainSurfacePRNG.hashString64(key)
        }

        return RainSurfacePRNG.hashString64("no-location_t\(t)")
    }

    var body: some View {
        let series = samples(from: points, targetMinutes: 60)

        let maxI0 = maxIntensityMMPerHour.isFinite ? maxIntensityMMPerHour : 1.0
        let maxI = max(0.0, maxI0)

        // Convert to arrays for the surface renderer.
        let intensities: [Double] = series.map {
            let raw0 = $0.precipitationIntensityMMPerHour ?? 0.0
            let raw = raw0.isFinite ? raw0 : 0.0
            let nonNeg = max(0.0, raw)
            let clamped = min(nonNeg, maxI)
            return WeatherNowcast.isWet(intensityMMPerHour: clamped) ? clamped : 0.0
        }

        let certainties: [Double] = series.enumerated().map { idx, p in
            let c0 = p.precipitationChance01 ?? 0.0
            let c = c0.isFinite ? max(0.0, min(1.0, c0)) : 0.0

            // Apply a subtle horizon fade so the far-right fuzz isn't overpowering.
            let t = Double(idx) / Double(max(1, series.count - 1))
            let horizonFactor = 1.0 - 0.25 * pow(t, 1.6)
            return max(0.0, min(1.0, c * horizonFactor))
        }

        let noiseSeed = makeNoiseSeed(lat: locationLatitude, lon: locationLongitude, start: forecastStart)

        return GeometryReader { proxy in
            let size = proxy.size

            ZStack {
                // Surface.
                let cfg: RainForecastSurfaceConfiguration = {
                    var c = RainForecastSurfaceConfiguration()

                    c.maxDenseSamples = 900

                    // Geometry tuned to match the mock.
                    c.baselineFractionFromTop = 0.90

                    // Give the renderer a real “typical height” budget so variation can show.
                    c.topHeadroomFraction = 0.14
                    c.typicalPeakFraction = 0.55

                    c.robustMaxPercentile = 0.93
                    c.intensityGamma = 0.62

                    // Lock the renderer's normalisation to this chart's visual max so
                    // steady/light rain does not collapse into a flat baseline band.
                    c.intensityReferenceMaxMMPerHour = maxI

                    c.edgeEasingFraction = 0.18
                    c.edgeEasingPower = 1.45

                    c.coreBodyColor = Color(red: 0.00, green: 0.10, blue: 0.42)
                    c.coreTopColor = accent
                    c.coreTopMix = 0.0
                    c.coreFadeFraction = 0.06

                    c.rimEnabled = true
                    c.rimColor = accent
                    c.rimInnerOpacity = 0.10
                    c.rimInnerWidthPixels = 1.0
                    c.rimOuterOpacity = 0.045
                    c.rimOuterWidthPixels = 16.0

                    c.glossEnabled = false
                    c.glintEnabled = false

                    c.noiseSeed = noiseSeed

                    c.canEnableFuzz = true
                    c.fuzzEnabled = true
                    c.fuzzColor = accent

                    // Fuzz tuning (these are the knobs that were being adjusted).
                    c.fuzzChanceThreshold = 0.60
                    c.fuzzChanceTransition = 0.24
                    c.fuzzChanceFloor = 0.22
                    c.fuzzMaxOpacity = 0.34
                    c.fuzzWidthFraction = 0.22
                    c.fuzzErodeStrength = 0.95

                    c.baselineEnabled = true
                    c.baselineColor = accent
                    c.baselineLineOpacity = 0.22
                    c.baselineWidthPixels = 1.0
                    c.baselineOffsetPixels = 0.0
                    c.baselineEndFadeFraction = 0.035

                    return c
                }()

                RainForecastSurfaceView(
                    intensities: intensities,
                    certainties: certainties,
                    configuration: cfg
                )
                .frame(width: size.width, height: size.height)

                // Optional axis labels.
                if showAxisLabels {
                    WeatherNowcastAxisOverlay(
                        width: size.width,
                        height: size.height,
                        start: forecastStart,
                        accent: accent
                    )
                }
            }
        }
    }
}

// MARK: - Axis Overlay

private struct WeatherNowcastAxisOverlay: View {
    let width: CGFloat
    let height: CGFloat
    let start: Date
    let accent: Color

    var body: some View {
        let cal = Calendar.current
        let base = cal.dateInterval(of: .hour, for: start)?.start ?? start

        let t0 = base
        let t30 = cal.date(byAdding: .minute, value: 30, to: base) ?? base.addingTimeInterval(60 * 30)
        let t60 = cal.date(byAdding: .minute, value: 60, to: base) ?? base.addingTimeInterval(60 * 60)

        let f = DateFormatter()
        f.dateFormat = "h:mm"

        let left = f.string(from: t0)
        let mid = f.string(from: t30)
        let right = f.string(from: t60)

        return VStack {
            Spacer(minLength: 0)

            HStack {
                Text(left)
                Spacer(minLength: 0)
                Text(mid)
                Spacer(minLength: 0)
                Text(right)
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(accent.opacity(0.75))
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }
}
