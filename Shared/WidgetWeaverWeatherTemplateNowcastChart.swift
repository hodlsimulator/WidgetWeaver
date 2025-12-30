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

        let certainties: [Double] = points.map { p in
            if let c = p.precipitationChance01, c.isFinite {
                return min(1.0, max(0.0, c))
            }
            // Missing/unknown minutes fade via styling only.
            return 0.0
        }

        var cfg = RainForecastSurfaceConfiguration()

        // Scale so drizzle doesn’t become a slab.
        cfg.intensityReferenceMaxMMPerHour = max(1.0, maxIntensityMMPerHour.isFinite ? maxIntensityMMPerHour : 1.0)
        cfg.robustMaxPercentile = 0.92
        cfg.intensityGamma = 0.60

        // Core: brighter mid-tones (readable), with a lighter top highlight.
        cfg.coreBodyColor = Color(red: 0.00, green: 0.16, blue: 0.58)
        cfg.coreTopColor = Color(red: 0.40, green: 0.88, blue: 1.00)
        cfg.coreTopMix = 0.62
        cfg.coreFadeFraction = 0.10

        // Fuzz: dense + fine grain, strong at tapered ends + into gaps (styling only).
        cfg.fuzzEnabled = true
        cfg.canEnableFuzz = true

        cfg.fuzzColor = Color(red: 0.52, green: 0.92, blue: 1.00)
        cfg.fuzzMaxOpacity = 0.26

        cfg.fuzzWidthFraction = 0.13
        cfg.fuzzWidthPixelsClamp = 8.0...56.0
        cfg.fuzzDensity = 1.05

        // Lower chance => more fuzz. Keeps long high-confidence ridges from getting peppered.
        cfg.fuzzChanceThreshold = 0.66
        cfg.fuzzChanceTransition = 0.30
        cfg.fuzzChanceExponent = 2.2
        cfg.fuzzChanceFloor = 0.06
        cfg.fuzzChanceMinStrength = 0.00

        // Bidirectional tails at wet↔dry edges (implemented in the renderer).
        cfg.fuzzTailMinutes = 6
        cfg.fuzzLowHeightPower = 2.05
        cfg.fuzzLowHeightBoost = 0.95

        // Haze kept near-zero to avoid lifting black background.
        cfg.fuzzHazeStrength = 0.00

        cfg.fuzzInsideWidthFactor = 0.62
        cfg.fuzzInsideOpacityFactor = 0.62

        cfg.fuzzSpeckStrength = 1.15
        cfg.fuzzSpeckleBudget = WidgetWeaverRuntime.isRunningInAppExtension ? 3600 : 4600
        cfg.fuzzSpeckleRadiusPixels = 0.14...1.75
        cfg.fuzzInsideSpeckleFraction = 0.55
        cfg.fuzzDistancePowerOutside = 2.7
        cfg.fuzzDistancePowerInside = 1.7
        cfg.fuzzAlongTangentJitter = 0.95

        cfg.fuzzErodeEnabled = true
        cfg.fuzzErodeStrength = 0.90
        cfg.fuzzErodeBlurFractionOfBand = 0.14
        cfg.fuzzErodeStrokeWidthFactor = 0.95
        cfg.fuzzErodeEdgePower = 2.35
        cfg.fuzzErodeRimInsetPixels = 1.2

        // Rim: very subtle; most “edge” comes from beads.
        cfg.rimEnabled = true
        cfg.rimColor = Color(red: 0.72, green: 0.96, blue: 1.00)
        cfg.rimInnerOpacity = 0.05
        cfg.rimInnerWidthPixels = 1.0
        cfg.rimOuterOpacity = 0.10
        cfg.rimOuterWidthPixels = 2.6

        // Baseline: subtle.
        cfg.baselineEnabled = true
        cfg.baselineColor = .white
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
