//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//

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
        // Plot expected intensity so the chart matches the “Rain now / Ends in Xm” logic.
        // Missing values are treated as 0 to avoid fill/hold artefacts at the tail.
        let intensities: [Double] = points.map { p in
            let iRaw = p.precipitationIntensityMMPerHour ?? 0.0
            let i0 = (iRaw.isFinite) ? max(0.0, iRaw) : 0.0

            let cRaw = p.precipitationChance01 ?? 1.0
            let c0 = (cRaw.isFinite) ? min(1.0, max(0.0, cRaw)) : 0.0

            return i0 * c0
        }

        // Treated as “certainty” for dissipation shaping:
        // - higher => less fuzz
        // - lower  => more fuzz
        let certainties: [Double] = points.map { p in
            if let c = p.precipitationChance01, c.isFinite {
                return min(1.0, max(0.0, c))
            }
            return 0.0
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

        // Outer dust is part of the mock look and is widget-safe with the texture method.
        cfg.fuzzOuterDustEnabled = true
        cfg.fuzzOuterDustEnabledInAppExtension = true
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
