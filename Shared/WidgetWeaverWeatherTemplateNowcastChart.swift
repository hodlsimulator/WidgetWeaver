//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//
//  Nowcast chart for the weather template.
//

import SwiftUI

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

        // Core colours.
        cfg.coreBodyColor = Color(red: 0.02, green: 0.22, blue: 0.86).opacity(0.84)
        cfg.coreTopColor = Color(red: 0.46, green: 0.90, blue: 1.00).opacity(0.98)
        cfg.coreTopMix = 0.64
        cfg.coreFadeFraction = 0.10

        // Fuzz: main look.
        cfg.fuzzEnabled = true
        cfg.canEnableFuzz = true
        cfg.fuzzColor = Color(red: 0.52, green: 0.93, blue: 1.00)
        cfg.fuzzMaxOpacity = 0.44

        // Wider band is now safe (texture-based, bounded draw calls).
        cfg.fuzzWidthFraction = 0.18
        cfg.fuzzWidthPixelsClamp = 10.0...72.0

        // Prefer texture fuzz in widgets.
        cfg.fuzzTextureEnabled = true
        cfg.fuzzTextureTilePixels = WidgetWeaverRuntime.isRunningInAppExtension ? 256 : 320
        cfg.fuzzTextureGradientStops = WidgetWeaverRuntime.isRunningInAppExtension ? 26 : 34
        cfg.fuzzTextureInnerBandMultiplier = 1.35
        cfg.fuzzTextureOuterBandMultiplier = 2.75
        cfg.fuzzTextureInnerOpacityMultiplier = 0.85
        cfg.fuzzTextureOuterOpacityMultiplier = 0.48

        // Keep silhouette sampling reasonable in extensions.
        cfg.maxDenseSamples = WidgetWeaverRuntime.isRunningInAppExtension ? 520 : 780

        // Uncertainty mapping.
        cfg.fuzzChanceThreshold = 0.70
        cfg.fuzzChanceTransition = 0.23
        cfg.fuzzChanceExponent = 1.85
        cfg.fuzzChanceFloor = 0.20
        cfg.fuzzChanceMinStrength = 0.06

        // Tail bloom + low-height emphasis.
        cfg.fuzzTailMinutes = 7.0
        cfg.fuzzLowHeightPower = 1.85
        cfg.fuzzLowHeightBoost = 1.20

        // Cheap haze stroke (no blur).
        cfg.fuzzHazeStrength = 0.12
        cfg.fuzzHazeBlurFractionOfBand = 0.0
        cfg.fuzzHazeStrokeWidthFactor = 1.20

        // Rim.
        cfg.rimEnabled = true
        cfg.rimColor = Color(red: 0.72, green: 0.96, blue: 1.00)
        cfg.rimInnerOpacity = 0.05
        cfg.rimInnerWidthPixels = 1.0
        cfg.rimOuterOpacity = 0.10
        cfg.rimOuterWidthPixels = 2.6

        // Baseline.
        cfg.baselineEnabled = true
        cfg.baselineColor = Color(red: 0.76, green: 0.92, blue: 1.00)
        cfg.baselineLineOpacity = 0.10
        cfg.baselineWidthPixels = 1.0
        cfg.baselineOffsetPixels = 0.0
        cfg.baselineEndFadeFraction = 0.18

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
