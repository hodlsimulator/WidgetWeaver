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
        let intensityMMPerHour: [Double]   // finite (missing filled for continuity)
        let probability01: [Double]        // finite 0..1 (styling only)
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

            // Styling horizon fade (subtle; styling-only).
            let n = series.probability01.count
            let horizonStart: Double = 0.68
            let horizonEndFactor: Double = 0.72

            let probabilities: [Double] = series.probability01.enumerated().map { idx, p0 in
                let p = RainSurfaceMath.clamp01(p0)
                let t = (n <= 1) ? 0.0 : (Double(idx) / Double(n - 1))
                let u = RainSurfaceMath.clamp01((t - horizonStart) / max(0.000_001, (1.0 - horizonStart)))
                let hs = RainSurfaceMath.smoothstep01(u)
                let factor = RainSurfaceMath.lerp(1.0, horizonEndFactor, hs)
                return RainSurfaceMath.clamp01(p * factor)
            }

            let seed = makeNoiseSeed(
                forecastStart: forecastStart,
                widgetFamily: widgetFamilyValue,
                latitude: locationLatitude,
                longitude: locationLongitude
            )

            let isExt = WidgetWeaverRuntime.isRunningInAppExtension
            let scale = max(1.0, displayScale)

            let widthPx = proxy.size.width * scale
            let heightPx = proxy.size.height * scale
            let areaPx = Double(max(1.0, widthPx * heightPx))

            // Hard budgets (WidgetKit-safe).
            let denseSamplesBudget: Int = {
                if isExt {
                    let byWidth = Int(widthPx.rounded(.toNearestOrAwayFromZero))
                    return max(200, min(280, byWidth))
                } else {
                    return 900
                }
            }()

            let speckleBudget: Int = {
                if isExt {
                    let scaled = Int((areaPx / 180.0).rounded(.toNearestOrAwayFromZero))
                    return max(900, min(1600, scaled))
                } else {
                    return 5200
                }
            }()

            let referenceMax = robustReferenceMaxMMPerHour(
                intensities: intensities,
                robustPercentile: 0.93,
                fallbackVisualMax: maxI
            )

            let cfg: RainForecastSurfaceConfiguration = {
                var c = RainForecastSurfaceConfiguration()

                c.noiseSeed = seed
                c.maxDenseSamples = denseSamplesBudget
                c.fuzzSpeckleBudget = speckleBudget

                // Height scaling: intensity only.
                c.intensityReferenceMaxMMPerHour = referenceMax
                c.robustMaxPercentile = 0.93
                c.intensityGamma = 0.54

                // Geometry (baseline near bottom of plot; headroom stable).
                let baselineFromTop: Double = 0.90
                let headroomFromTop: Double = 0.05
                let typicalPeakHeightFraction: Double = 0.82

                c.baselineFractionFromTop = baselineFromTop
                c.topHeadroomFraction = headroomFromTop / max(0.000_001, baselineFromTop)
                c.typicalPeakFraction = baselineFromTop - ((baselineFromTop - headroomFromTop) * typicalPeakHeightFraction)

                // No chart-end tapering in geometry.
                c.edgeEasingFraction = 0.0
                c.edgeEasingPower = 1.45

                // Body tonal range (brighter mids, no background lift).
                c.coreBodyColor = Color(red: 0.00, green: 0.14, blue: 0.62)
                c.coreTopColor = accent
                c.coreTopMix = isExt ? 0.46 : 0.52
                c.coreFadeFraction = isExt ? 0.010 : 0.012

                // Crisp rim (thin, bright).
                c.rimEnabled = true
                c.rimColor = accent
                c.rimInnerOpacity = isExt ? 0.78 : 0.86
                c.rimInnerWidthPixels = 1.0
                c.rimOuterOpacity = isExt ? 0.020 : 0.028
                c.rimOuterWidthPixels = isExt ? 6.0 : 8.0

                c.glossEnabled = false
                c.glintEnabled = false

                // Fuzz: dense granular outside band (primary “glow”).
                c.fuzzEnabled = true
                c.fuzzColor = accent

                // Keep opacity strong but avoid a big halo by keeping band tight.
                c.fuzzMaxOpacity = isExt ? 0.52 : 0.64
                c.fuzzWidthFraction = 0.14
                c.fuzzWidthPixelsClamp = isExt ? (8.0...44.0) : (8.0...60.0)

                c.fuzzDensity = isExt ? 1.45 : 1.65
                c.fuzzHazeStrength = isExt ? 0.46 : 0.56
                c.fuzzSpeckStrength = isExt ? 2.30 : 2.55

                c.fuzzHazeBlurFractionOfBand = isExt ? 0.10 : 0.12
                c.fuzzHazeStrokeWidthFactor = isExt ? 0.70 : 0.78
                c.fuzzInsideHazeStrokeWidthFactor = isExt ? 0.66 : 0.72

                // Probability -> styling (higher chance => stronger styling),
                // with a non-zero floor so slopes don’t go empty.
                c.fuzzChanceThreshold = 0.06
                c.fuzzChanceTransition = 0.90
                c.fuzzChanceExponent = 0.78
                c.fuzzChanceFloor = 0.10

                // Styling-only tail guarantee after rain ends (readability).
                c.fuzzChanceMinStrength = isExt ? 0.38 : 0.46
                c.fuzzLowHeightPower = 2.05
                c.fuzzLowHeightBoost = isExt ? 1.45 : 1.55

                // Inside weld.
                c.fuzzInsideWidthFactor = 0.82
                c.fuzzInsideOpacityFactor = isExt ? 0.86 : 0.92
                c.fuzzInsideSpeckleFraction = isExt ? 0.32 : 0.40

                // Concentrate fuzz near the edge (dense band, not a uniform aura).
                c.fuzzDistancePowerOutside = 3.20
                c.fuzzDistancePowerInside = 2.20
                c.fuzzAlongTangentJitter = 0.90

                // Erosion: keep off in extensions; still inset the core so fuzz owns the boundary.
                c.fuzzErodeEnabled = isExt ? false : true
                c.fuzzErodeStrength = isExt ? 0.55 : 0.78
                c.fuzzErodeEdgePower = isExt ? 2.10 : 2.55
                c.fuzzErodeRimInsetPixels = isExt ? 1.35 : 1.65

                // Baseline integration.
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

    // Builds exactly `targetMinutes` minute buckets aligned to forecastStart.
    // Missing intensity buckets are filled for silhouette continuity; styling fades those buckets.
    private func bucketedMinuteSeries(
        from points: [WidgetWeaverWeatherMinutePoint],
        forecastStart: Date,
        targetMinutes: Int
    ) -> BucketedMinuteSeries {
        guard targetMinutes > 0 else {
            return BucketedMinuteSeries(intensityMMPerHour: [], probability01: [])
        }

        var rawIntensity: [Double] = Array(repeating: Double.nan, count: targetMinutes)
        var rawProb: [Double] = Array(repeating: Double.nan, count: targetMinutes)

        var sumI: [Double] = Array(repeating: 0.0, count: targetMinutes)
        var cntI: [Int] = Array(repeating: 0, count: targetMinutes)
        var sumP: [Double] = Array(repeating: 0.0, count: targetMinutes)
        var cntP: [Int] = Array(repeating: 0, count: targetMinutes)

        let start = forecastStart.timeIntervalSince1970

        for pt in points {
            let t = pt.date.timeIntervalSince1970
            let dt = t - start
            if !dt.isFinite { continue }
            let m = Int(floor(dt / 60.0))
            if m < 0 || m >= targetMinutes { continue }

            if let v = pt.precipitationIntensityMMPerHour, v.isFinite {
                sumI[m] += max(0.0, v)
                cntI[m] += 1
            }

            if let p = pt.precipitationChance01, p.isFinite {
                sumP[m] += RainSurfaceMath.clamp01(p)
                cntP[m] += 1
            }
        }

        for m in 0..<targetMinutes {
            if cntI[m] > 0 {
                rawIntensity[m] = max(0.0, sumI[m] / Double(cntI[m]))
            } else {
                rawIntensity[m] = Double.nan
            }

            if cntP[m] > 0 {
                rawProb[m] = RainSurfaceMath.clamp01(sumP[m] / Double(cntP[m]))
            } else {
                rawProb[m] = Double.nan
            }
        }

        let filled = fillMissingIntensities(rawIntensity)

        var intensityOut = filled.filled
        intensityOut = intensityOut.map { v in
            if !v.isFinite { return 0.0 }
            return max(0.0, v)
        }

        var probOut: [Double] = Array(repeating: 0.0, count: targetMinutes)
        for i in 0..<targetMinutes {
            if filled.wasMissing[i] {
                // Missing intensity: keep height continuity via fill, but styling fades to “unknown”.
                probOut[i] = 0.0
            } else {
                if rawProb[i].isFinite {
                    probOut[i] = RainSurfaceMath.clamp01(rawProb[i])
                } else {
                    // Known intensity but missing probability: assume fully certain styling.
                    probOut[i] = 1.0
                }
            }
        }

        return BucketedMinuteSeries(intensityMMPerHour: intensityOut, probability01: probOut)
    }

    private func fillMissingIntensities(_ raw: [Double]) -> (filled: [Double], wasMissing: [Bool]) {
        let n = raw.count
        guard n > 0 else { return ([], []) }

        let wasMissing = raw.map { !$0.isFinite }
        guard let firstKnown = raw.firstIndex(where: { $0.isFinite }) else {
            return (Array(repeating: 0.0, count: n), Array(repeating: true, count: n))
        }

        var filled = raw

        // Leading hold.
        let firstVal = raw[firstKnown]
        if firstKnown > 0 {
            for i in 0..<firstKnown { filled[i] = firstVal }
        }

        // Interior linear interpolation between known points.
        var lastKnown = firstKnown
        var i = firstKnown + 1
        while i < n {
            if raw[i].isFinite {
                let a = raw[lastKnown]
                let b = raw[i]
                let gap = i - lastKnown
                if gap > 1 {
                    for k in 1..<gap {
                        let t = Double(k) / Double(gap)
                        filled[lastKnown + k] = RainSurfaceMath.lerp(a, b, t)
                    }
                }
                lastKnown = i
            }
            i += 1
        }

        // Trailing hold.
        let lastVal = raw[lastKnown]
        if lastKnown < n - 1 {
            for j in (lastKnown + 1)..<n { filled[j] = lastVal }
        }

        // Sanitise.
        filled = filled.map { v in
            if !v.isFinite { return 0.0 }
            return max(0.0, v)
        }

        return (filled, wasMissing)
    }
}
