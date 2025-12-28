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

struct WidgetWeaverWeatherTemplateNowcastChart: View {
    struct Insets {
        let plotHorizontal: CGFloat
        let plotTop: CGFloat
        let plotBottom: CGFloat
        let axisHorizontal: CGFloat
        let axisTop: CGFloat
        let axisBottom: CGFloat

        var plotInsets: EdgeInsets {
            EdgeInsets(top: plotTop, leading: plotHorizontal, bottom: plotBottom, trailing: plotHorizontal)
        }

        var axisInsets: EdgeInsets {
            EdgeInsets(top: axisTop, leading: axisHorizontal, bottom: axisBottom, trailing: axisHorizontal)
        }
    }

    private static func insets(for family: WidgetFamily?, showsLabels: Bool) -> Insets {
        #if canImport(WidgetKit)
        switch family {
        case .systemSmall:
            return Insets(plotHorizontal: 10, plotTop: 10, plotBottom: showsLabels ? 1 : 8, axisHorizontal: 12, axisTop: 0, axisBottom: 10)
        case .systemMedium:
            return Insets(plotHorizontal: 12, plotTop: 10, plotBottom: showsLabels ? 1 : 8, axisHorizontal: 18, axisTop: 0, axisBottom: 12)
        case .systemLarge:
            return Insets(plotHorizontal: 14, plotTop: 12, plotBottom: showsLabels ? 1 : 10, axisHorizontal: 22, axisTop: 0, axisBottom: 14)
        case .systemExtraLarge:
            return Insets(plotHorizontal: 16, plotTop: 14, plotBottom: showsLabels ? 1 : 10, axisHorizontal: 24, axisTop: 0, axisBottom: 14)
        default:
            return Insets(plotHorizontal: 12, plotTop: 10, plotBottom: showsLabels ? 1 : 8, axisHorizontal: 18, axisTop: 0, axisBottom: 12)
        }
        #else
        return Insets(plotHorizontal: 12, plotTop: 10, plotBottom: showsLabels ? 1 : 8, axisHorizontal: 18, axisTop: 0, axisBottom: 12)
        #endif
    }

    let points: [WeatherNowcastPoint]
    let maxIntensityMMPerHour: Double
    let showAxisLabels: Bool
    let accent: Color
    let forecastStart: Date
    let locationLatitude: Double?
    let locationLongitude: Double?
    let widgetFamilyValue: UInt64

    @Environment(\.displayScale) private var displayScale

    private var insets: Insets {
        #if canImport(WidgetKit)
        return Self.insets(for: WidgetWeaverRuntime.widgetFamily, showsLabels: showAxisLabels)
        #else
        return Self.insets(for: nil, showsLabels: showAxisLabels)
        #endif
    }

    var body: some View {
        let insets = insets

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black)

            VStack(spacing: 0) {
                ZStack {
                    GeometryReader { proxy in
                        let plotRect = CGRect(
                            x: 0,
                            y: 0,
                            width: proxy.size.width,
                            height: proxy.size.height
                        )

                        ZStack {
                            NowcastSurfacePlot(
                                points: points,
                                maxIntensityMMPerHour: maxIntensityMMPerHour,
                                accent: accent,
                                forecastStart: forecastStart,
                                locationLatitude: locationLatitude,
                                locationLongitude: locationLongitude,
                                widgetFamilyValue: widgetFamilyValue
                            )
                            .frame(width: plotRect.width, height: plotRect.height)
                        }
                    }
                }
                .padding(insets.plotInsets)

                if showAxisLabels {
                    NowcastAxisLabels(accent: accent)
                        .padding(insets.axisInsets)
                }
            }
        }
    }
}

private struct NowcastSurfacePlot: View {
    let points: [WeatherNowcastPoint]
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
                let raw = p.precipitationIntensityMMPerHour ?? 0.0
                let finite = raw.isFinite ? raw : 0.0
                let nonNeg = max(0.0, finite)
                let clamped = min(nonNeg, maxIntensityMMPerHour)
                return WeatherNowcast.isWet(intensityMMPerHour: clamped) ? clamped : 0.0
            }

            let n = series.count

            // Certainty tapers towards the horizon.
            let horizonStart: Double = 0.65
            let horizonEndCertainty: Double = 0.72
            let certainties: [Double] = series.enumerated().map { idx, p in
                let rawChance = p.precipitationChance01 ?? 0.0
                let chance = RainSurfaceMath.clamp01(rawChance)
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

                // Core (solid).
                c.coreBodyColor = Color(red: 0.00, green: 0.10, blue: 0.42)
                c.coreTopColor = accent

                // Edge treatments off; fuzz defines the surface.
                c.rimEnabled = false
                c.glossEnabled = false
                c.glintEnabled = false

                // ---------
                // Fuzz tuned to the mockup:
                // - Uses the new 2D distance-to-surface band, so it appears on vertical sides too.
                // - Narrower and less “floor fog”.
                // - Still replaces the surface via erosion.
                // ---------
                c.fuzzEnabled = true
                c.fuzzColor = accent
                c.fuzzRasterMaxPixels = isExt ? 140_000 : 360_000

                c.fuzzMaxOpacity = isExt ? 0.28 : 0.32
                c.fuzzWidthFraction = 0.18
                c.fuzzWidthPixelsClamp = 10.0...90.0

                c.fuzzBaseDensity = 0.90
                c.fuzzHazeStrength = isExt ? 0.78 : 0.74
                c.fuzzSpeckStrength = isExt ? 1.18 : 1.25
                c.fuzzEdgePower = 1.65
                c.fuzzClumpCellPixels = 12.0
                c.fuzzMicroBlurPixels = isExt ? 0.45 : 0.65

                // Chance → fuzz.
                c.fuzzChanceThreshold = 0.60
                c.fuzzChanceTransition = 0.14
                c.fuzzChanceMinStrength = 0.26

                // Uncertainty shaping.
                c.fuzzUncertaintyFloor = 0.06
                c.fuzzUncertaintyExponent = 2.15

                // Low-height reinforcement (keeps tapered ends fuzzy without creating a huge fog field).
                c.fuzzLowHeightPower = 2.10
                c.fuzzLowHeightBoost = 0.55

                // Straddle the surface (some fuzz below), but not an 0.98-wide inside slab.
                c.fuzzInsideWidthFactor = 0.72
                c.fuzzInsideOpacityFactor = 0.62
                c.fuzzInsideSpeckleFraction = 0.40

                // Keep fuzz near the surface.
                c.fuzzDistancePowerOutside = 2.00
                c.fuzzDistancePowerInside = 1.70

                // Erode the core near the surface so fuzz *is* the boundary.
                c.fuzzErodeEnabled = true
                c.fuzzErodeStrength = 0.82
                c.fuzzErodeEdgePower = 2.70

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
            let latBits = UInt64(bitPattern: Int64(latitude * 10_000))
            let lonBits = UInt64(bitPattern: Int64(longitude * 10_000))
            seed = RainSurfacePRNG.combine(seed, RainSurfacePRNG.combine(latBits, lonBits))
        }

        return seed
    }

    private func samples(from points: [WeatherNowcastPoint], targetMinutes: Int) -> [WeatherNowcastPoint] {
        guard !points.isEmpty else { return [] }
        if points.count == targetMinutes { return points }
        if points.count < 2 {
            return Array(repeating: points[0], count: targetMinutes)
        }

        var out: [WeatherNowcastPoint] = []
        out.reserveCapacity(targetMinutes)

        for i in 0..<targetMinutes {
            let t = Double(i) / Double(max(1, targetMinutes - 1))
            let u = t * Double(points.count - 1)
            let i0 = max(0, min(points.count - 2, Int(floor(u))))
            let frac = u - Double(i0)
            let a = points[i0]
            let b = points[i0 + 1]
            out.append(a.lerp(to: b, t: frac))
        }

        return out
    }
}

private struct NowcastAxisLabels: View {
    let accent: Color

    var body: some View {
        HStack {
            Text("Now")
            Spacer(minLength: 6)
            Text("60m")
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .foregroundStyle(accent.opacity(0.85))
    }
}

// MARK: - WeatherNowcastPoint helpers

private extension WeatherNowcastPoint {
    func lerp(to other: WeatherNowcastPoint, t: Double) -> WeatherNowcastPoint {
        WeatherNowcastPoint(
            date: date.addingTimeInterval((other.date.timeIntervalSince(date)) * t),
            precipitationIntensityMMPerHour: RainSurfaceMath.lerp(precipitationIntensityMMPerHour ?? 0.0, other.precipitationIntensityMMPerHour ?? 0.0, t),
            precipitationChance01: RainSurfaceMath.lerp(precipitationChance01 ?? 0.0, other.precipitationChance01 ?? 0.0, t)
        )
    }
}
