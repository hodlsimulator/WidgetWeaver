//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI

/// Nowcast chart for the weather template.
struct WeatherNowcastChart: View {
    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool
    let forecastStart: Date
    let locationLatitude: Double?
    let locationLongitude: Double?

    var body: some View {
        let base = forecastStart

        // WeatherKit minute forecasts are not guaranteed to contain a full 60 points.
        // When fewer points arrive (e.g. 35), stretching them to the full width makes the chart appear to
        // "keep raining" until 60m.
        //
        // Build a fixed 60-minute axis from `forecastStart` and place each sample by its minute offset.
        var intensityByMinute = Array(repeating: 0.0, count: 60)
        var chanceByMinute = Array(repeating: 0.0, count: 60)

        let sorted = points.sorted { $0.date < $1.date }
        for p in sorted {
            let dt = p.date.timeIntervalSince(base)
            if dt < 0 { continue }
            let idx = Int(dt / 60.0)

            if idx >= 60 { continue }

            let iRaw = p.precipitationIntensityMMPerHour ?? 0.0
            let i0 = (iRaw.isFinite) ? max(0.0, iRaw) : 0.0

            let cRaw = p.precipitationChance01 ?? 1.0
            let c0 = (cRaw.isFinite) ? min(1.0, max(0.0, cRaw)) : 0.0

            // Expected intensity matches the “Rain now / Ends in Xm” logic.
            let expected = i0 * c0

            // Use max to handle duplicate/near-duplicate samples landing in the same minute bucket.
            intensityByMinute[idx] = max(intensityByMinute[idx], expected)
            chanceByMinute[idx] = max(chanceByMinute[idx], c0)
        }

        // Remove “ghost rain” after the computed end by clamping sub-wet values to 0.
        // This keeps the visual tail aligned with the wording thresholds.
        let intensities: [Double] = intensityByMinute.map { v in
            (v >= WeatherNowcast.wetIntensityThresholdMMPerHour) ? v : 0.0
        }

        // Treated as “certainty” for dissipation shaping:
        // - higher => less fuzz
        // - lower  => more fuzz
        let certainties: [Double] = chanceByMinute.map { c in
            (c.isFinite) ? min(1.0, max(0.0, c)) : 0.0
        }

        var cfg = RainForecastSurfaceConfiguration()

        // Geometry.
        cfg.baselineFractionFromTop = 0.83
        cfg.topHeadroomFraction = 0.075
        cfg.typicalPeakFraction = 0.78

        // Intensity shaping.
        cfg.intensityReferenceMaxMMPerHour = max(1.0, maxIntensityMMPerHour.isFinite ? maxIntensityMMPerHour : 1.0)
        cfg.robustMaxPercentile = 0.92
        cfg.intensityGamma = 0.62

        // Avoid artificially tapering real “rain at now / rain at 60m” cases.
        // Taper comes from segment rendering + midpoint sampling instead.
        cfg.edgeEasingFraction = 0.0
        cfg.edgeEasingPower = 1.0

        // Core colours (no cyan; deep blue only).
        cfg.coreBodyColor = Color(red: 0.02, green: 0.08, blue: 0.55).opacity(0.92)
        cfg.coreTopColor = Color(red: 0.04, green: 0.12, blue: 0.78).opacity(0.95)
        cfg.coreTopMix = 0.38
        cfg.coreFadeFraction = 0.00

        // Rim (off for the mock look — dissipation replaces the outline).
        cfg.rimEnabled = false

        // Baseline.
        cfg.baselineEnabled = true
        cfg.baselineColor = Color(red: 0.20, green: 0.32, blue: 0.90)
        cfg.baselineLineOpacity = 0.11
        cfg.baselineWidthPixels = 1.0
        cfg.baselineOffsetPixels = 0.0
        cfg.baselineEndFadeFraction = 0.18

        // Dissipation (texture-based; no particles).
        cfg.fuzzEnabled = true
        cfg.canEnableFuzz = true

        cfg.fuzzColor = cfg.coreBodyColor
        cfg.fuzzMaxOpacity = 0.72

        // Base band width around the contour.
        cfg.fuzzWidthFraction = 0.18
        cfg.fuzzWidthPixelsClamp = 12.0...88.0

        // Keep silhouette sampling reasonable in extensions.
        cfg.maxDenseSamples = WidgetWeaverRuntime.isRunningInAppExtension ? 560 : 820

        // Uncertainty mapping.
        cfg.fuzzChanceThreshold = 0.78
        cfg.fuzzChanceTransition = 0.22
        cfg.fuzzChanceExponent = 1.20
        cfg.fuzzChanceFloor = 0.20
        cfg.fuzzChanceMinStrength = 0.06

        // Tail bloom + low-height emphasis.
        cfg.fuzzTailMinutes = 11.0
        cfg.fuzzLowHeightPower = 1.35
        cfg.fuzzLowHeightBoost = 2.10
        cfg.fuzzEdgeWindowPx = 28.0

        // Texture (bounded draw calls).
        cfg.fuzzTextureEnabled = true
        cfg.fuzzTextureTilePixels = WidgetWeaverRuntime.isRunningInAppExtension ? 192 : 224
        cfg.fuzzTextureGradientStops = WidgetWeaverRuntime.isRunningInAppExtension ? 22 : 30

        // Inner -> outer expansion.
        cfg.fuzzTextureInnerBandMultiplier = 1.55
        cfg.fuzzTextureOuterBandMultiplier = 4.40
        cfg.fuzzTextureInnerOpacityMultiplier = 1.00
        cfg.fuzzTextureOuterOpacityMultiplier = 0.65

        // IMPORTANT: keep the background pure black.
        // Any outside-the-body mist will lift the black background and read as a halo.
        cfg.fuzzOuterDustEnabled = false
        cfg.fuzzOuterDustEnabledInAppExtension = false
        cfg.fuzzOuterDustPassCount = 2
        cfg.fuzzOuterDustPassCountInAppExtension = 2

        // Subtle edge softening.
        cfg.fuzzErodeEnabled = true
        cfg.fuzzErodeStrength = 0.90

        // Cheap coherence haze (disabled; handled by noise layering).
        cfg.fuzzHazeStrength = 0.0
        cfg.fuzzHazeBlurFractionOfBand = 0.0
        cfg.fuzzHazeStrokeWidthFactor = 0.95

        // Deterministic noise seed.
        cfg.noiseSeed = 0xBADC0DE

        return ZStack {
            Color.black

            RainForecastSurfaceView(
                intensities: intensities,
                certainties: certainties,
                configuration: cfg
            )

            if showAxisLabels {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    HStack {
                        Text("Now")
                        Spacer(minLength: 0)
                        Text("60m")
                    }
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 6)
                    .padding(.bottom, 2)
                }
                .allowsHitTesting(false)
            }
        }
    }
}
