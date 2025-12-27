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

    private struct Insets {
        var plotHorizontal: CGFloat
        var plotTop: CGFloat
        var plotBottom: CGFloat
        var axisHorizontal: CGFloat
        var axisTop: CGFloat
        var axisBottom: CGFloat
    }

    private var insets: Insets {
        #if canImport(WidgetKit)
        switch widgetFamily {
        case .systemSmall:
            return Insets(
                plotHorizontal: 10,
                plotTop: 8,
                plotBottom: showAxisLabels ? 2 : 8,
                axisHorizontal: 18,
                axisTop: 0,
                axisBottom: 10
            )
        case .systemMedium:
            return Insets(
                plotHorizontal: 10,
                plotTop: 10,
                plotBottom: showAxisLabels ? 2 : 8,
                axisHorizontal: 18,
                axisTop: 0,
                axisBottom: 12
            )
        default:
            return Insets(
                plotHorizontal: 12,
                plotTop: 10,
                plotBottom: showAxisLabels ? 3 : 8,
                axisHorizontal: 18,
                axisTop: 0,
                axisBottom: 12
            )
        }
        #else
        return Insets(
            plotHorizontal: 12,
            plotTop: 10,
            plotBottom: showAxisLabels ? 3 : 8,
            axisHorizontal: 18,
            axisTop: 0,
            axisBottom: 12
        )
        #endif
    }

    var body: some View {
        let insets = insets

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)

            VStack(spacing: 0) {
                WeatherNowcastSurfacePlot(
                    points: points,
                    maxIntensityMMPerHour: maxIntensityMMPerHour,
                    accent: accent,
                    forecastStart: forecastStart,
                    locationLatitude: locationLatitude,
                    locationLongitude: locationLongitude,
                    widgetFamilyValue: widgetFamilySeedValue()
                )
                .padding(.horizontal, insets.plotHorizontal)
                .padding(.top, insets.plotTop)
                .padding(.bottom, insets.plotBottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showAxisLabels {
                    WeatherNowcastAxisLabels()
                        .padding(.horizontal, insets.axisHorizontal)
                        .padding(.top, insets.axisTop)
                        .padding(.bottom, insets.axisBottom)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func widgetFamilySeedValue() -> UInt64 {
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
}

private struct WeatherNowcastAxisLabels: View {
    var body: some View {
        HStack {
            Text("Now")
            Spacer(minLength: 0)
            Text("60m")
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundColor(.white.opacity(0.55))
    }
}

private struct WeatherNowcastSurfacePlot: View {
    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let forecastStart: Date
    let locationLatitude: Double?
    let locationLongitude: Double?
    let widgetFamilyValue: UInt64

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let series = samples(from: points, targetMinutes: 60)

            let intensities: [Double] = series.map { p in
                let raw = max(0.0, p.precipitationIntensityMMPerHour ?? 0.0)
                let clamped = min(raw, maxIntensityMMPerHour)
                return WeatherNowcast.isWet(intensityMMPerHour: clamped) ? clamped : 0.0
            }

            let n = series.count

            // Certainty: chance with a gentle horizon softening.
            let horizonStart: Double = 0.65
            let horizonEndCertainty: Double = 0.72
            let certainties: [Double] = series.enumerated().map { idx, p in
                let chance = RainSurfaceMath.clamp01(p.precipitationChance01 ?? 0.0)
                let t = (n <= 1) ? 0.0 : (Double(idx) / Double(n - 1))
                let u = RainSurfaceMath.clamp01((t - horizonStart) / max(0.000_001, (1.0 - horizonStart)))
                let hs = RainSurfaceMath.smoothstep01(u)
                let horizonFactor = RainSurfaceMath.lerp(1.0, horizonEndCertainty, hs)
                return RainSurfaceMath.clamp01(chance * horizonFactor)
            }

            let seed = makeNoiseSeed(
                forecastStart: forecastStart,
                widgetFamily: widgetFamilyValue,
                latitude: locationLatitude,
                longitude: locationLongitude
            )

            let cfg: RainForecastSurfaceConfiguration = {
                var c = RainForecastSurfaceConfiguration()
                c.noiseSeed = seed

                // Widget-safe sampling (prevents placeholder timeouts).
                c.maxDenseSamples = WidgetWeaverRuntime.isRunningInAppExtension ? 220 : 900

                // Geometry: baseline low (near labels) and tall peaks for heavy rain.
                c.baselineFractionFromTop = 0.88
                c.topHeadroomFraction = 0.14
                c.typicalPeakFraction = 0.56
                c.robustMaxPercentile = 0.93
                c.intensityGamma = 0.62
                c.edgeEasingFraction = 0.10
                c.edgeEasingPower = 1.7

                // Core: solid body fill (no vertical gradient) + highlight colour for rim/gloss.
                c.coreBodyColor = Color(red: 0.00, green: 0.10, blue: 0.42)
                c.coreTopColor = accent

                // Rim: keep subtle (avoid a traced neon line look).
                c.rimEnabled = true
                c.rimColor = accent
                c.rimInnerOpacity = 0.22
                c.rimInnerWidthPixels = 1.05
                c.rimOuterOpacity = 0.10
                c.rimOuterWidthPixels = 4.8

                // Gloss band (inside-only).
                c.glossEnabled = true
                c.glossMaxOpacity = 0.12
                c.glossDepthPixels = 9.0...14.0

                // Tiny apex glint (local maxima only). Kept subtle.
                c.glintEnabled = true
                c.glintMaxCount = 1
                c.glintMinHeightFraction = 0.82
                c.glintMaxOpacity = 0.16
                c.glintColor = Color(red: 0.98, green: 1.0, blue: 1.0)

                // Fuzz: dense granular mist (blue-only), outside-only, strongest near baseline/shoulders.
                c.fuzzEnabled = true
                c.fuzzColor = Color(red: 0.05, green: 0.32, blue: 1.00)
                c.fuzzMaxOpacity = 0.22
                c.fuzzWidthFraction = 0.26
                c.fuzzWidthPixelsClamp = 12.0...130.0
                c.fuzzBaseDensity = 0.86
                c.fuzzLowHeightPower = 2.8
                c.fuzzUncertaintyFloor = 0.18
                c.fuzzRasterMaxPixels = WidgetWeaverRuntime.isRunningInAppExtension ? 220_000 : 620_000
                c.fuzzClumpCellPixels = 12.0
                c.fuzzEdgePower = 0.65
                c.fuzzHazeStrength = 0.72
                c.fuzzSpeckStrength = 1.0
                c.fuzzInsideThreshold = 14

                // Baseline.
                c.baselineColor = accent
                c.baselineLineOpacity = 0.22
                c.baselineEndFadeFraction = 0.040

                return c
            }()

            RainForecastSurfaceView(
                intensities: intensities,
                certainties: certainties,
                configuration: cfg
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
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
            let cal = Calendar.current
            let lastDate = out.last?.date ?? Date()
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
