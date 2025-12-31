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
        let intensities: [Double] = points.map { p in
            if let v = p.precipitationIntensityMMPerHour, v.isFinite {
                return max(0.0, v)
            }
            return Double.nan
        }

        // Treated as “certainty” for fuzz shaping:
        // - higher => less fuzz
        // - lower => more fuzz
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

        // Rim (off for the mock look — erosion replaces the outline).
        cfg.rimEnabled = false

        // Baseline.
        cfg.baselineEnabled = true
        cfg.baselineColor = Color(red: 0.20, green: 0.32, blue: 0.90)
        cfg.baselineLineOpacity = 0.11
        cfg.baselineWidthPixels = 1.0
        cfg.baselineOffsetPixels = 0.0
        cfg.baselineEndFadeFraction = 0.18

        // Fuzz (subtractive + dust).
        cfg.fuzzEnabled = true
        cfg.canEnableFuzz = true

        cfg.fuzzColor = cfg.coreBodyColor
        cfg.fuzzMaxOpacity = 0.82

        // Wider base band improves the “solid → grain → nothing” transition.
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

        // Inner -> outer dust expansion.
        cfg.fuzzTextureInnerBandMultiplier = 1.30
        cfg.fuzzTextureOuterBandMultiplier = 7.60
        cfg.fuzzTextureInnerOpacityMultiplier = 0.95
        cfg.fuzzTextureOuterOpacityMultiplier = 0.45

        cfg.fuzzOuterDustEnabled = true
        cfg.fuzzOuterDustEnabledInAppExtension = true
        cfg.fuzzOuterDustPassCount = 3
        cfg.fuzzOuterDustPassCountInAppExtension = 2

        // Subtractive erosion.
        cfg.fuzzErodeEnabled = true
        cfg.fuzzErodeStrength = 1.25
        cfg.fuzzErodeStrokeWidthFactor = 0.95

        // Cheap coherence haze (no blur).
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
