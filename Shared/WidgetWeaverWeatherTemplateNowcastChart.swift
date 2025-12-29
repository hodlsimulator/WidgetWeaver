//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI
import WidgetKit

struct BucketedMinuteSeries {
    let intensityMMPerHour: [Double]
    let probability01: [Double]
}

struct WidgetWeaverWeatherTemplateNowcastChart: View {
    let nowcastPoints: [WidgetWeaverWeatherMinutePoint]
    let forecastStart: Date
    let widgetFamily: WidgetFamily
    let accent: Color
    let latitude: Double?
    let longitude: Double?
    let isWidgetExtension: Bool

    var body: some View {
        GeometryReader { proxy in
            let targetMinutes = 60
            let series = bucketedMinuteSeries(from: nowcastPoints, forecastStart: forecastStart, targetMinutes: targetMinutes)
            let intensities = series.intensityMMPerHour
            let probabilities = series.probability01

            let seed = makeNoiseSeed(
                forecastStart: forecastStart,
                widgetFamily: UInt64(widgetFamily.hashValue),
                latitude: latitude,
                longitude: longitude
            )

            let cfg: RainForecastSurfaceConfiguration = {
                var c = RainForecastSurfaceConfiguration()
                let isExt = isWidgetExtension

                // Sampling
                c.maxDenseSamples = isExt ? 200 : 900

                // Geometry (mock-measured)
                c.baselineFractionFromTop = 0.596
                c.topHeadroomFraction = 0.30
                c.typicalPeakFraction = 0.401

                // Intensity mapping
                c.robustMaxPercentile = 0.93
                c.intensityGamma = 0.64
                c.intensityReferenceMaxMMPerHour = robustReferenceMaxMMPerHour(
                    intensities: intensities,
                    robustPercentile: c.robustMaxPercentile,
                    fallbackVisualMax: 7.5
                )

                // Core fill (brighter mids; still clipped to the surface)
                c.coreBodyColor = Color(red: 0.06, green: 0.30, blue: 0.99).opacity(isExt ? 0.94 : 0.96)
                c.coreTopColor = Color(red: 0.56, green: 0.86, blue: 1.00)
                c.coreTopMix = isExt ? 0.74 : 0.78
                c.coreFadeFraction = isExt ? 0.080 : 0.070

                // Rim (thin + crisp; minimal outer aura)
                c.rimEnabled = true
                c.rimColor = Color(red: 0.62, green: 0.92, blue: 1.00)
                c.rimInnerOpacity = isExt ? 0.78 : 0.84
                c.rimInnerWidthPixels = isExt ? 1.15 : 1.25
                c.rimOuterOpacity = isExt ? 0.16 : 0.20
                c.rimOuterWidthPixels = isExt ? 4.2 : 4.8

                // Optional extras
                c.glossEnabled = false
                c.glintEnabled = false

                // Noise seed
                c.noiseSeed = seed

                // Fuzz (primary “glow”: dense particulate outside + inner weld)
                c.canEnableFuzz = true
                c.fuzzEnabled = true
                c.fuzzColor = Color(red: 0.50, green: 0.88, blue: 1.00)
                c.fuzzMaxOpacity = isExt ? 0.62 : 0.74

                c.fuzzWidthFraction = isExt ? 0.31 : 0.30
                c.fuzzWidthPixelsClamp = isExt ? (12.0...78.0) : (14.0...92.0)

                // Chance -> styling (higher chance => stronger)
                c.fuzzChanceThreshold = isExt ? 0.68 : 0.66
                c.fuzzChanceTransition = 0.22
                c.fuzzChanceFloor = isExt ? 0.14 : 0.12
                c.fuzzChanceExponent = isExt ? 2.15 : 2.05
                c.fuzzChanceMinStrength = isExt ? 0.42 : 0.48   // tail readability after wet ends

                // Composition and “tails”
                c.fuzzDensity = isExt ? 1.10 : 1.18
                c.fuzzHazeStrength = isExt ? 0.52 : 0.56
                c.fuzzSpeckStrength = 1.00
                c.fuzzLowHeightPower = isExt ? 2.35 : 2.30
                c.fuzzLowHeightBoost = isExt ? 1.25 : 1.18

                // Inside weld
                c.fuzzInsideWidthFactor = isExt ? 0.78 : 0.80
                c.fuzzInsideOpacityFactor = isExt ? 0.92 : 0.95
                c.fuzzInsideSpeckleFraction = isExt ? 0.30 : 0.26

                // Speckle shaping
                c.fuzzDistancePowerOutside = isExt ? 1.85 : 1.75
                c.fuzzDistancePowerInside = isExt ? 1.55 : 1.45
                c.fuzzAlongTangentJitter = isExt ? 0.58 : 0.66

                // Haze sizing (kept tight to avoid halos)
                c.fuzzHazeBlurFractionOfBand = isExt ? 0.14 : 0.16
                c.fuzzHazeStrokeWidthFactor = isExt ? 0.74 : 0.78
                c.fuzzInsideHazeStrokeWidthFactor = isExt ? 0.64 : 0.66

                // Speckle sizing + budgets (hard-capped in drawing)
                c.fuzzSpeckleRadiusPixels = isExt ? (0.38...1.18) : (0.42...1.38)
                c.fuzzSpeckleBudget = isExt ? 1100 : 2600

                // Erosion (cheap weld; enabled in extension at reduced strength)
                c.fuzzErodeEnabled = true
                c.fuzzErodeStrength = isExt ? 0.42 : 0.72
                c.fuzzErodeEdgePower = isExt ? 2.30 : 2.60
                c.fuzzErodeRimInsetPixels = isExt ? 1.45 : 1.85

                // Baseline
                c.baselineColor = accent
                c.baselineLineOpacity = 0.20
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
            if p.isFinite, p > 0.0 { return max(1.0, p) }
        }
        if fallbackVisualMax.isFinite, fallbackVisualMax > 0.0 { return max(1.0, fallbackVisualMax) }
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

        var intensitySum = Array(repeating: 0.0, count: targetMinutes)
        var intensityCount = Array(repeating: 0, count: targetMinutes)
        var probSum = Array(repeating: 0.0, count: targetMinutes)
        var probCount = Array(repeating: 0, count: targetMinutes)

        for p in points {
            let dt = p.date.timeIntervalSince(forecastStart)
            let m = Int(floor(dt / 60.0))
            guard m >= 0 && m < targetMinutes else { continue }

            if let v = p.precipitationIntensityMMPerHour, v.isFinite {
                intensitySum[m] += max(0.0, v)
                intensityCount[m] += 1
            }

            if let pr = p.precipitationChance01, pr.isFinite {
                probSum[m] += RainSurfaceMath.clamp01(pr)
                probCount[m] += 1
            }
        }

        var rawIntensity: [Double] = Array(repeating: Double.nan, count: targetMinutes)
        var rawProb: [Double] = Array(repeating: Double.nan, count: targetMinutes)

        for m in 0..<targetMinutes {
            if intensityCount[m] > 0 {
                rawIntensity[m] = max(0.0, intensitySum[m] / Double(intensityCount[m]))
            } else {
                rawIntensity[m] = Double.nan
            }

            if probCount[m] > 0 {
                rawProb[m] = RainSurfaceMath.clamp01(probSum[m] / Double(probCount[m]))
            } else {
                rawProb[m] = Double.nan
            }
        }

        let filled = fillMissingIntensities(rawIntensity)
        let intensityOut = filled.filled

        var probOut: [Double] = Array(repeating: 0.0, count: targetMinutes)
        for i in 0..<targetMinutes {
            if filled.wasMissing[i] {
                // Missing intensity bucket => styling fade only.
                probOut[i] = 0.0
            } else {
                // Known intensity => use probability if present, otherwise assume fully certain.
                let p = rawProb[i]
                if p.isFinite {
                    probOut[i] = RainSurfaceMath.clamp01(p)
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

        var wasMissing = Array(repeating: true, count: n)
        var sanitized = Array(repeating: Double.nan, count: n)

        for i in 0..<n {
            let v = raw[i]
            if v.isFinite {
                sanitized[i] = max(0.0, v)
                wasMissing[i] = false
            } else {
                sanitized[i] = Double.nan
                wasMissing[i] = true
            }
        }

        let filled = RainSurfaceMath.fillMissingLinearHoldEnds(sanitized)
        return (filled, wasMissing)
    }
}
