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
        let intensityMMPerHour: [Double] // finite
        let probability01: [Double]      // finite, 0..1 (drives styling only)
    }

    var body: some View {
        GeometryReader { proxy in
            let series = bucketedMinuteSeries(from: points, forecastStart: forecastStart, targetMinutes: 60)

            let maxI0 = maxIntensityMMPerHour.isFinite ? maxIntensityMMPerHour : 1.0
            let maxI = max(0.000_001, maxI0)

            let intensities: [Double] = series.intensityMMPerHour.map { v in
                if !v.isFinite { return 0.0 }
                return max(0.0, v)
            }

            // Styling horizon fade (kept subtle). Probability remains styling-only.
            let n = series.probability01.count
            let horizonStart: Double = 0.65
            let horizonEnd: Double = 0.72
            let probabilities: [Double] = series.probability01.enumerated().map { idx, p0 in
                let p = RainSurfaceMath.clamp01(p0)
                let t = (n <= 1) ? 0.0 : (Double(idx) / Double(n - 1))
                let u = RainSurfaceMath.clamp01((t - horizonStart) / max(0.000_001, (1.0 - horizonStart)))
                let hs = RainSurfaceMath.smoothstep01(u)
                let horizonFactor = RainSurfaceMath.lerp(1.0, horizonEnd, hs)
                return RainSurfaceMath.clamp01(p * horizonFactor)
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

            let speckleBudget: Int = {
                if isExt {
                    // Lower ceiling to stay WidgetKit-safe; density is handled by strength + beads.
                    let scaled = Int((areaPx / 240.0).rounded(.toNearestOrAwayFromZero))
                    return max(320, min(850, scaled))
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

                // Do not taper at edges.
                c.edgeEasingFraction = 0.0
                c.edgeEasingPower = 1.45

                // Brighter body + clipped top glow (background remains pure black).
                c.coreBodyColor = Color(red: 0.00, green: 0.14, blue: 0.62)
                c.coreTopColor = accent
                c.coreTopMix = isExt ? 0.28 : 0.32
                c.coreFadeFraction = isExt ? 0.012 : 0.015

                // Crisp rim (thin; the “volume” comes from granular fuzz).
                c.rimEnabled = true
                c.rimColor = accent
                c.rimInnerOpacity = isExt ? 0.34 : 0.38
                c.rimInnerWidthPixels = 1.0
                c.rimOuterOpacity = isExt ? 0.07 : 0.09
                c.rimOuterWidthPixels = isExt ? 9.0 : 11.0

                c.glossEnabled = false
                c.glintEnabled = false

                // Fuzz: probability (chance) drives strength positively.
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

                // Chance mapping (dry => no fuzz).
                c.fuzzChanceThreshold = 0.18
                c.fuzzChanceTransition = 0.55
                c.fuzzChanceExponent = 1.35
                c.fuzzChanceFloor = 0.0

                // Ensures a tapered fuzzy “tail” right after rain ends (styling-only).
                c.fuzzChanceMinStrength = isExt ? 0.22 : 0.28

                c.fuzzLowHeightPower = 2.05
                c.fuzzLowHeightBoost = isExt ? 0.98 : 1.08

                // Inside weld.
                c.fuzzInsideWidthFactor = 0.78
                c.fuzzInsideOpacityFactor = isExt ? 0.55 : 0.72
                c.fuzzInsideSpeckleFraction = isExt ? 0.18 : 0.26

                c.fuzzDistancePowerOutside = 2.25
                c.fuzzDistancePowerInside = 1.80
                c.fuzzAlongTangentJitter = 0.95

                // Core erosion disabled in extensions for safety.
                c.fuzzErodeEnabled = isExt ? false : true
                c.fuzzErodeStrength = isExt ? 0.60 : 0.80
                c.fuzzErodeEdgePower = isExt ? 2.10 : 2.50
                c.fuzzErodeRimInsetPixels = isExt ? 1.6 : 1.9

                c.baselineColor = accent
                c.baselineLineOpacity = 0.22
                c.baselineEndFadeFraction = 0.035

                return c
            }()

            RainForecastSurfaceView(intensities: intensities, certainties: probabilities, configuration: cfg)
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
    // Missing intensity buckets are filled by interpolation to preserve silhouette continuity.
    // Probability is set to 0 for buckets with missing source intensity (styling-only fade).
    private func bucketedMinuteSeries(
        from points: [WidgetWeaverWeatherMinutePoint],
        forecastStart: Date,
        targetMinutes: Int
    ) -> BucketedMinuteSeries {
        guard targetMinutes > 0 else {
            return BucketedMinuteSeries(intensityMMPerHour: [], probability01: [])
        }

        let sorted = points.sorted { $0.date < $1.date }

        var rawIntensity: [Double] = Array(repeating: Double.nan, count: targetMinutes)
        var rawProb: [Double] = Array(repeating: Double.nan, count: targetMinutes)

        var idx = 0
        for m in 0..<targetMinutes {
            let bucketStart = forecastStart.addingTimeInterval(Double(m) * 60.0)
            let bucketEnd = bucketStart.addingTimeInterval(60.0)

            var intensitySum: Double = 0.0
            var intensityCount = 0
            var probSum: Double = 0.0
            var probCount = 0

            while idx < sorted.count, sorted[idx].date < bucketEnd {
                if sorted[idx].date >= bucketStart {
                    if let v = sorted[idx].precipitationIntensityMMPerHour, v.isFinite {
                        intensitySum += max(0.0, v)
                        intensityCount += 1
                    }
                    if let p = sorted[idx].precipitationChance01, p.isFinite {
                        probSum += RainSurfaceMath.clamp01(p)
                        probCount += 1
                    }
                }
                idx += 1
            }

            if intensityCount > 0 {
                rawIntensity[m] = max(0.0, intensitySum / Double(intensityCount))
            } else {
                rawIntensity[m] = Double.nan
            }

            if probCount > 0 {
                rawProb[m] = RainSurfaceMath.clamp01(probSum / Double(probCount))
            } else {
                rawProb[m] = Double.nan
            }
        }

        let filled = fillMissingIntensities(rawIntensity)

        var intensityOut = filled.filled
        var probOut: [Double] = Array(repeating: 0.0, count: targetMinutes)
        for i in 0..<targetMinutes {
            intensityOut[i] = intensityOut[i].isFinite ? max(0.0, intensityOut[i]) : 0.0

            if filled.wasMissing[i] {
                // Missing source intensity => styling fade only.
                probOut[i] = 0.0
            } else {
                // Known intensity => use probability if present, otherwise assume fully certain.
                if rawProb[i].isFinite {
                    probOut[i] = RainSurfaceMath.clamp01(rawProb[i])
                } else {
                    probOut[i] = 1.0
                }
            }
        }

        return BucketedMinuteSeries(intensityMMPerHour: intensityOut, probability01: probOut)
    }

    private func fillMissingIntensities(_ raw: [Double]) -> (filled: [Double], wasMissing: [Bool]) {
        let n = raw.count
        guard n > 0 else { return ([], []) }

        var filled = raw
        let wasMissing = raw.map { !$0.isFinite }

        guard let firstKnown = raw.firstIndex(where: { $0.isFinite }) else {
            return (Array(repeating: 0.0, count: n), Array(repeating: true, count: n))
        }

        // Leading fill.
        let firstVal = raw[firstKnown]
        if firstKnown > 0 {
            for i in 0..<firstKnown {
                filled[i] = firstVal
            }
        }

        var i = firstKnown
        while i < n {
            if raw[i].isFinite {
                filled[i] = raw[i]
                i += 1
                continue
            }

            // raw[i] missing; interpolate until next known.
            let leftIndex = i - 1
            let leftVal = filled[leftIndex]

            var j = i + 1
            while j < n, !raw[j].isFinite {
                j += 1
            }

            if j >= n {
                // Trailing fill.
                for k in i..<n {
                    filled[k] = leftVal
                }
                break
            } else {
                let rightVal = raw[j]
                let span = Double(j - leftIndex)
                for k in (leftIndex + 1)..<j {
                    let t = Double(k - leftIndex) / span
                    filled[k] = leftVal + (rightVal - leftVal) * t
                }
                filled[j] = rightVal
                i = j + 1
            }
        }

        // Clamp any remaining non-finite.
        for idx in 0..<n {
            if !filled[idx].isFinite {
                filled[idx] = 0.0
            }
        }

        return (filled, wasMissing)
    }
}
