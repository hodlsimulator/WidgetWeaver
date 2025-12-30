//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/29/25.
//
//  Nowcast chart for the weather template.
//  Tuned to match the mockup:
//  - baseline near ~0.83 height (leaves room for “Now / 60m”)
//  - deep blue core gradient
//  - speckled fuzz band (uncertainty) that remains WidgetKit-safe
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

        // Geometry: match mock baseline position.
        cfg.baselineFractionFromTop = 0.83
        cfg.topHeadroomFraction = 0.075
        cfg.typicalPeakFraction = 0.78

        // Intensity shaping: keep drizzle readable.
        cfg.intensityReferenceMaxMMPerHour = max(1.0, maxIntensityMMPerHour.isFinite ? maxIntensityMMPerHour : 1.0)
        cfg.robustMaxPercentile = 0.92
        cfg.intensityGamma = 0.62

        // Core colours: bright cyan top into deep blue body.
        cfg.coreBodyColor = Color(red: 0.02, green: 0.22, blue: 0.86).opacity(0.84)
        cfg.coreTopColor = Color(red: 0.46, green: 0.90, blue: 1.00).opacity(0.98)
        cfg.coreTopMix = 0.64
        cfg.coreFadeFraction = 0.10

        // Fuzz: the key look.
        cfg.fuzzEnabled = true
        cfg.canEnableFuzz = true
        cfg.fuzzColor = Color(red: 0.52, green: 0.93, blue: 1.00)
        cfg.fuzzMaxOpacity = 0.42

        // Band width close to mock (avoid cartoon “thick cloud”).
        cfg.fuzzWidthFraction = 0.10
        cfg.fuzzWidthPixelsClamp = 6.0...38.0

        // Keep WidgetKit safe: lower draw complexity in extensions.
        cfg.maxDenseSamples = WidgetWeaverRuntime.isRunningInAppExtension ? 520 : 780

        // Budget is hard-clamped again in the renderer (Regression A guardrails).
        cfg.fuzzDensity = 0.90
        cfg.fuzzSpeckleBudget = WidgetWeaverRuntime.isRunningInAppExtension ? 1300 : 2200
        cfg.fuzzSpeckleRadiusPixels = 0.25...2.40

        // Uncertainty mapping.
        cfg.fuzzChanceThreshold = 0.70
        cfg.fuzzChanceTransition = 0.23
        cfg.fuzzChanceExponent = 1.85
        cfg.fuzzChanceFloor = 0.20
        cfg.fuzzChanceMinStrength = 0.06

        // Fuzz blooms at wet↔dry transitions and at low heights (mock tails).
        cfg.fuzzTailMinutes = 7.0
        cfg.fuzzLowHeightPower = 1.85
        cfg.fuzzLowHeightBoost = 1.15

        // Cheap haze stroke (no blur) to make the band feel “continuous” with fewer speckles.
        cfg.fuzzHazeStrength = 0.10
        cfg.fuzzHazeBlurFractionOfBand = 0.0
        cfg.fuzzHazeStrokeWidthFactor = 1.15

        // Inside vs outside balance.
        cfg.fuzzInsideWidthFactor = 0.62
        cfg.fuzzInsideOpacityFactor = 0.60
        cfg.fuzzInsideSpeckleFraction = WidgetWeaverRuntime.isRunningInAppExtension ? 0.34 : 0.44

        cfg.fuzzDistancePowerOutside = 1.60
        cfg.fuzzDistancePowerInside = 1.15
        cfg.fuzzAlongTangentJitter = 0.55

        // Rim: subtle.
        cfg.rimEnabled = true
        cfg.rimColor = Color(red: 0.72, green: 0.96, blue: 1.00)
        cfg.rimInnerOpacity = 0.05
        cfg.rimInnerWidthPixels = 1.0
        cfg.rimOuterOpacity = 0.10
        cfg.rimOuterWidthPixels = 2.6

        // Baseline: subtle with faded ends.
        cfg.baselineEnabled = true
        cfg.baselineColor = Color(red: 0.76, green: 0.92, blue: 1.00)
        cfg.baselineLineOpacity = 0.10
        cfg.baselineWidthPixels = 1.0
        cfg.baselineOffsetPixels = 0.0
        cfg.baselineEndFadeFraction = 0.18

        // Deterministic noise.
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
