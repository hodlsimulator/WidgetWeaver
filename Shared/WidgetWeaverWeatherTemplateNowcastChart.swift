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

        // Core colours (no cyan). The mockup’s “magic” is alpha structure, so keep the fill simple for now.
        let coreBlue = Color(red: 0.03, green: 0.10, blue: 0.55)
        cfg.coreBodyColor = coreBlue.opacity(0.92)
        cfg.coreTopColor = coreBlue.opacity(0.92)
        cfg.coreTopMix = 0.0
        cfg.coreFadeFraction = 0.0

        // Rim (off for the mock look — dissipation replaces the outline).
        cfg.rimEnabled = false

        // Baseline.
        cfg.baselineEnabled = true
        cfg.baselineColor = Color(red: 0.18, green: 0.26, blue: 0.80)
        cfg.baselineLineOpacity = 0.14
        cfg.baselineWidthPixels = 1.0
        cfg.baselineOffsetPixels = 0.0
        cfg.baselineEndFadeFraction = 0.18

        // Fuzz (texture-based dissipation).
        cfg.fuzzEnabled = true
        cfg.canEnableFuzz = true

        // These colours are largely ignored by the texture path, but keep them aligned with the core anyway.
        cfg.fuzzColor = coreBlue
        cfg.fuzzMaxOpacity = 0.66
        cfg.fuzzSpeckStrength = 1.0

        // Band sizing. Outer dust pass expands beyond this.
        cfg.fuzzWidthFraction = 0.14
        cfg.fuzzWidthPixelsClamp = 10.0...72.0

        // Keep silhouette sampling reasonable in extensions.
        cfg.maxDenseSamples = WidgetWeaverRuntime.isRunningInAppExtension ? 520 : 780

        // Uncertainty mapping.
        cfg.fuzzChanceThreshold = 0.80
        cfg.fuzzChanceTransition = 0.22
        cfg.fuzzChanceExponent = 1.20
        cfg.fuzzChanceFloor = 0.12
        cfg.fuzzChanceMinStrength = 0.04

        // Tail bloom + low-height emphasis.
        cfg.fuzzTailMinutes = 8.0
        cfg.fuzzLowHeightPower = 1.05
        cfg.fuzzLowHeightBoost = 1.10
        cfg.fuzzEdgeWindowPx = 24.0

        // Strength remap (pushes “unmistakable” erosion without needing glows).
        cfg.fuzzStrengthExponent = 0.75
        cfg.fuzzStrengthGain = 1.90

        // Texture (bounded draw calls).
        cfg.fuzzTextureEnabled = true
        cfg.fuzzTextureTilePixels = WidgetWeaverRuntime.isRunningInAppExtension ? 192 : 224
        cfg.fuzzTextureGradientStops = WidgetWeaverRuntime.isRunningInAppExtension ? 24 : 32

        // Inner -> outer dust expansion.
        cfg.fuzzTextureInnerBandMultiplier = 1.15
        cfg.fuzzTextureOuterBandMultiplier = 5.40
        cfg.fuzzTextureInnerOpacityMultiplier = 1.10
        cfg.fuzzTextureOuterOpacityMultiplier = 0.50

        // Enable the “airy dust” outside the body in widgets too (bounded by pass count + low-budget guardrails).
        cfg.fuzzOuterDustEnabled = true
        cfg.fuzzOuterDustEnabledInAppExtension = true
        cfg.fuzzOuterDustPassCount = 3
        cfg.fuzzOuterDustPassCountInAppExtension = 2

        // Subtractive erosion (eats into the slope, not just a soft edge).
        cfg.fuzzErodeEnabled = true
        cfg.fuzzErodeStrength = 1.0
        cfg.fuzzErodeStrokeWidthFactor = 0.85

        // Haze off (mock look is grainy, not smoky).
        cfg.fuzzHazeStrength = 0.0
        cfg.fuzzHazeBlurFractionOfBand = 0.0
        cfg.fuzzHazeStrokeWidthFactor = 1.0

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
