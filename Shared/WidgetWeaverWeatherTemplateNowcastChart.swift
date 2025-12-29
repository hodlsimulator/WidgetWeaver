//
// WidgetWeaverWeatherTemplateNowcastChart.swift
// WidgetWeaver
//
// Created by . . on 12/23/25.
//
// Nowcast chart container + axis labels.
// Chart area is dedicated to surface rendering; labels are outside.
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
            return Insets(
                plotHorizontal: 10,
                plotTop: 8,
                plotBottom: showAxisLabels ? 0 : 8,
                axisHorizontal: 18,
                axisTop: 0,
                axisBottom: 10
            )
        case .systemMedium:
            return Insets(
                plotHorizontal: 10,
                plotTop: 10,
                plotBottom: showAxisLabels ? 0 : 8,
                axisHorizontal: 18,
                axisTop: 0,
                axisBottom: 12
            )
        default:
            return Insets(
                plotHorizontal: 12,
                plotTop: 10,
                plotBottom: showAxisLabels ? 1 : 8,
                axisHorizontal: 18,
                axisTop: 0,
                axisBottom: 12
            )
        }
        #else
        return Insets(
            plotHorizontal: 12,
            plotTop: 10,
            plotBottom: showAxisLabels ? 1 : 8,
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

    private struct BucketedMinuteSeries {
        let intensityMMPerHour: [Double] // may contain NaN for unknown
        let certainty01: [Double]        // may contain NaN for unknown
    }

    var body: some View {
        GeometryReader { proxy in
            let series = bucketedMinuteSeries(from: points, forecastStart: forecastStart, targetMinutes: 60)

            let maxI0 = maxIntensityMMPerHour.isFinite ? maxIntensityMMPerHour : 1.0
            let maxI = max(0.000_001, maxI0)

            // Height semantics:
            // - Unknown stays unknown (NaN).
            // - Intensity drives HEIGHT only.
            let intensities: [Double] = series.intensityMMPerHour.map { v in
                guard v.isFinite else { return Double.nan }
                return max(0.0, v)
            }

            // Styling semantics:
            // - Certainty drives styling only (opacity/edge/fuzz), never height.
            // - Unknown stays unknown (NaN) and will fade out downstream.
            let n = series.certainty01.count
            let horizonStart: Double = 0.65
            let horizonEndCertainty: Double = 0.72
            let certainties: [Double] = series.certainty01.enumerated().map { idx, c0 in
                guard c0.isFinite else { return Double.nan }
                let t = (n <= 1) ? 0.0 : (Double(idx) / Double(n - 1))
                let u = RainSurfaceMath.clamp01((t - horizonStart) / max(0.000_001, (1.0 - horizonStart)))
                let hs = RainSurfaceMath.smoothstep01(u)
                let horizonFactor = RainSurfaceMath.lerp(1.0, horizonEndCertainty, hs)
                return RainSurfaceMath.clamp01(c0 * horizonFactor)
            }

            let seed = makeNoiseSeed(
                forecastStart: forecastStart,
                widgetFamily: widgetFamilyValue,
                latitude: locationLatitude,
                longitude: locationLongitude
            )

            let isExt = WidgetWeaverRuntime.isRunningInAppExtension
            let widthPx = proxy.size.width * max(1.0, displayScale)
            let heightPx = proxy.size.height * max(1.0, displayScale)
            let areaPx = Double(max(1.0, widthPx * heightPx))

            let denseSamplesBudget: Int = {
                if isExt {
                    let byWidth = Int(widthPx.rounded(.toNearestOrAwayFromZero))
                    return max(180, min(240, byWidth))
                } else {
                    return 900
                }
            }()

            // Denser than stock, still hard-capped for widget safety.
            let speckleBudget: Int = {
                if isExt {
                    let scaled = Int((areaPx / 185.0).rounded(.toNearestOrAwayFromZero))
                    return max(450, min(1200, scaled))
                } else {
                    return 5200
                }
            }()

            let referenceMaxMMPerHour = robustReferenceMaxMMPerHour(
                intensities: intensities,
                robustPercentile: 0.93,
                fallbackVisualMax: maxI
            )

            let cfg: RainForecastSurfaceConfiguration = {
                var c = RainForecastSurfaceConfiguration()
                c.noiseSeed = seed
                c.maxDenseSamples = denseSamplesBudget
                c.fuzzSpeckleBudget = speckleBudget

                // Robust within-window reference max to prevent “slab” saturation and preserve structure.
                c.intensityReferenceMaxMMPerHour = referenceMaxMMPerHour

                // Values converted from the legacy tuning:
                // baseline = 0.90, headroom(top) = 0.05 of chart height,
                // typical peak height = 0.80 of maxHeight.
                let baselineFromTop: Double = 0.90
                let legacyHeadroomFromTop: Double = 0.05
                let legacyTypicalPeakHeightFraction: Double = 0.80

                c.baselineFractionFromTop = baselineFromTop
                c.topHeadroomFraction = legacyHeadroomFromTop / baselineFromTop
                c.typicalPeakFraction = baselineFromTop - ((baselineFromTop - legacyHeadroomFromTop) * legacyTypicalPeakHeightFraction)

                c.robustMaxPercentile = 0.93
                c.intensityGamma = 0.52

                // Accuracy: do not taper the chart at the left/right edges.
                // (“Now” can be wet; “60m” can be wet.)
                c.edgeEasingFraction = 0.0
                c.edgeEasingPower = 1.45

                // Body: brighter mid-tones + internal top glow (clipped), background stays pure black.
                c.coreBodyColor = Color(red: 0.00, green: 0.14, blue: 0.62)
                c.coreTopColor = accent
                c.coreTopMix = isExt ? 0.28 : 0.32
                c.coreFadeFraction = isExt ? 0.012 : 0.015

                // Crisp edge (thin rim light) + dense granular fuzz does most of the “glow” work.
                c.rimEnabled = true
                c.rimColor = accent
                c.rimInnerOpacity = isExt ? 0.34 : 0.38
                c.rimInnerWidthPixels = 1.0
                c.rimOuterOpacity = isExt ? 0.07 : 0.09
                c.rimOuterWidthPixels = isExt ? 9.0 : 11.0

                c.glossEnabled = false
                c.glintEnabled = false

                // Fuzz (primary volume). No big halo: haze is tight + low strength; speckles carry the look.
                c.fuzzEnabled = true
                c.fuzzColor = accent
                c.fuzzMaxOpacity = isExt ? 0.30 : 0.38

                c.fuzzWidthFraction = 0.20
                c.fuzzWidthPixelsClamp = isExt ? (10.0...58.0) : (10.0...78.0)

                c.fuzzDensity = isExt ? 1.05 : 1.20
                c.fuzzHazeStrength = isExt ? 0.35 : 0.42
                c.fuzzSpeckStrength = isExt ? 1.45 : 1.60

                c.fuzzHazeBlurFractionOfBand = isExt ? 0.16 : 0.20
                c.fuzzHazeStrokeWidthFactor = isExt ? 0.88 : 0.98
                c.fuzzInsideHazeStrokeWidthFactor = isExt ? 0.75 : 0.85

                // Styling-only taper: keep tails readable even when certainty is high.
                c.fuzzChanceThreshold = 0.60
                c.fuzzChanceTransition = 0.20
                c.fuzzChanceExponent = 2.10
                c.fuzzChanceFloor = 0.18
                c.fuzzChanceMinStrength = 0.44

                c.fuzzLowHeightPower = 2.05
                c.fuzzLowHeightBoost = isExt ? 0.98 : 1.08

                // Inside weld (prevents “floating” fuzz).
                c.fuzzInsideWidthFactor = 0.78
                c.fuzzInsideOpacityFactor = isExt ? 0.55 : 0.72
                c.fuzzInsideSpeckleFraction = isExt ? 0.26 : 0.34

                c.fuzzDistancePowerOutside = 2.25
                c.fuzzDistancePowerInside = 1.80
                c.fuzzAlongTangentJitter = 0.95

                // Core edge removal so fuzz “is” the surface (disabled in extensions for safety).
                c.fuzzErodeEnabled = isExt ? false : true
                c.fuzzErodeStrength = isExt ? 0.60 : 0.80
                c.fuzzErodeEdgePower = isExt ? 2.10 : 2.50
                c.fuzzErodeRimInsetPixels = isExt ? 1.6 : 1.9

                c.baselineColor = accent
                c.baselineLineOpacity = 0.22
                c.baselineEndFadeFraction = 0.035

                return c
            }()

            RainForecastSurfaceView(intensities: intensities, certainties: certainties, configuration: cfg)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func robustReferenceMaxMMPerHour(
        intensities: [Double],
        robustPercentile: Double,
        fallbackVisualMax: Double
    ) -> Double {
        let positive = intensities.filter { $0.isFinite && $0 > 0.0 }
        if !positive.isEmpty {
            let p = RainSurfaceMath.percentile(positive, p: robustPercentile)
            if p.isFinite, p > 0.0 {
                return max(1.0, p)
            }
        }
        if fallbackVisualMax.isFinite, fallbackVisualMax > 0.0 {
            return max(1.0, fallbackVisualMax)
        }
        return 1.0
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

    // Builds exactly 60 minute buckets aligned to forecastStart.
    // Missing buckets stay unknown (NaN), never padded as zero.
    private func bucketedMinuteSeries(
        from points: [WidgetWeaverWeatherMinutePoint],
        forecastStart: Date,
        targetMinutes: Int
    ) -> BucketedMinuteSeries {
        guard targetMinutes > 0 else {
            return BucketedMinuteSeries(intensityMMPerHour: [], certainty01: [])
        }

        let sorted = points.sorted { $0.date < $1.date }

        var intensityOut: [Double] = []
        var certaintyOut: [Double] = []
        intensityOut.reserveCapacity(targetMinutes)
        certaintyOut.reserveCapacity(targetMinutes)

        var idx = 0
        for m in 0..<targetMinutes {
            let bucketStart = forecastStart.addingTimeInterval(Double(m) * 60.0)
            let bucketEnd = bucketStart.addingTimeInterval(60.0)

            var intensitySum: Double = 0.0
            var intensityCount = 0
            var chanceSum: Double = 0.0
            var chanceCount = 0

            while idx < sorted.count, sorted[idx].date < bucketEnd {
                if sorted[idx].date >= bucketStart {
                    if let v = sorted[idx].precipitationIntensityMMPerHour, v.isFinite {
                        intensitySum += max(0.0, v)
                        intensityCount += 1
                    }

                    if let c = sorted[idx].precipitationChance01, c.isFinite {
                        chanceSum += RainSurfaceMath.clamp01(c)
                        chanceCount += 1
                    }
                }
                idx += 1
            }

            let intensity: Double = {
                if intensityCount > 0 {
                    let avg = intensitySum / Double(intensityCount)
                    return avg.isFinite ? max(0.0, avg) : Double.nan
                }
                return Double.nan
            }()

            // If intensity is unknown, certainty must also be unknown so the renderer can fade it out
            // (and avoid accidentally showing filled continuity for missing buckets).
            let certainty: Double = {
                guard intensity.isFinite else { return Double.nan }
                if chanceCount > 0 {
                    let avg = chanceSum / Double(chanceCount)
                    return avg.isFinite ? RainSurfaceMath.clamp01(avg) : Double.nan
                }
                return 1.0
            }()

            intensityOut.append(intensity)
            certaintyOut.append(certainty)
        }

        return BucketedMinuteSeries(intensityMMPerHour: intensityOut, certainty01: certaintyOut)
    }
}
