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
    let forecastStart: Date
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
            return Insets(plotHorizontal: 10, plotTop: 8, plotBottom: showAxisLabels ? 0 : 8, axisHorizontal: 18, axisTop: 0, axisBottom: 10)
        case .systemMedium:
            return Insets(plotHorizontal: 10, plotTop: 10, plotBottom: showAxisLabels ? 0 : 8, axisHorizontal: 18, axisTop: 0, axisBottom: 12)
        default:
            return Insets(plotHorizontal: 12, plotTop: 10, plotBottom: showAxisLabels ? 1 : 8, axisHorizontal: 18, axisTop: 0, axisBottom: 12)
        }
        #else
        return Insets(plotHorizontal: 12, plotTop: 10, plotBottom: showAxisLabels ? 1 : 8, axisHorizontal: 18, axisTop: 0, axisBottom: 12)
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

            // Certainty tapers towards the horizon.
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

                let isExt = WidgetWeaverRuntime.isRunningInAppExtension
                c.maxDenseSamples = isExt ? 180 : 900

                // Fill the available plot height.
                c.baselineFractionFromTop = 0.90
                c.topHeadroomFraction = 0.05
                c.typicalPeakFraction = 0.80
                c.robustMaxPercentile = 0.93
                c.intensityGamma = 0.52

                // Keep endings tapered.
                c.edgeEasingFraction = 0.18
                c.edgeEasingPower = 1.45

                // Core (no vertical gradient for the “no gradient” request).
                c.coreBodyColor = Color(red: 0.00, green: 0.10, blue: 0.42)
                c.coreTopColor = accent

                // Edge treatments off; fuzz defines the surface.
                c.rimEnabled = false
                c.glossEnabled = false
                c.glintEnabled = false

                // ---------
                // Fuzz: big behaviour changes:
                // - Minimum fuzz always present so the surface reads as fuzz, not a crisp cut-out.
                // - Threshold at 60%: below is strongly fuzzy.
                // - Core-edge erosion on: fuzz replaces the surface instead of floating above it.
                // ---------

                c.fuzzEnabled = true
                c.fuzzColor = accent
                c.fuzzRasterMaxPixels = isExt ? 140_000 : 360_000

                c.fuzzMaxOpacity = isExt ? 0.46 : 0.50

                c.fuzzWidthFraction = 0.22
                c.fuzzWidthPixelsClamp = 12.0...105.0

                c.fuzzBaseDensity = 0.96
                c.fuzzHazeStrength = isExt ? 0.98 : 0.92
                c.fuzzSpeckStrength = isExt ? 1.50 : 1.55

                c.fuzzEdgePower = 1.05
                c.fuzzClumpCellPixels = 10.0
                c.fuzzMicroBlurPixels = isExt ? 0.55 : 0.75

                // Chance → fuzz.
                c.fuzzChanceThreshold = 0.60
                c.fuzzChanceTransition = 0.12
                c.fuzzChanceMinStrength = 0.32

                // Legacy uncertainty shaping still helps a bit near the horizon.
                c.fuzzUncertaintyFloor = 0.10
                c.fuzzUncertaintyExponent = 1.55

                // Ensure tapered / low-height regions stay fuzzy.
                c.fuzzLowHeightPower = 2.05
                c.fuzzLowHeightBoost = 1.20

                // Inside contribution so fuzz straddles and extends below the surface.
                c.fuzzInsideWidthFactor = 0.98
                c.fuzzInsideOpacityFactor = 0.90
                c.fuzzInsideSpeckleFraction = 0.90

                // Spread grain through the band (less “only at the edge”).
                c.fuzzDistancePowerOutside = 1.55
                c.fuzzDistancePowerInside = 1.45

                // Erode the core near the surface.
                c.fuzzErodeEnabled = true
                c.fuzzErodeStrength = 0.78
                c.fuzzErodeEdgePower = 2.35

                // Baseline.
                c.baselineColor = accent
                c.baselineLineOpacity = 0.20
                c.baselineEndFadeFraction = 0.035

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
