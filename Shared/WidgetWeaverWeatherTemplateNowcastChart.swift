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
            // Missing/unknown minutes: treat as uncertain, but the renderer also suppresses fuzz far from wet mass.
            return 0.0
        }

        var cfg = RainForecastSurfaceConfiguration()

        // Layout (match mockup proportions: baseline near bottom, big mound headroom).
        cfg.baselineFractionFromTop = 0.83
        cfg.topHeadroomFraction = 0.06
        cfg.typicalPeakFraction = 0.80

        // Soft tails.
        cfg.edgeEasingFraction = 0.040
        cfg.edgeEasingPower = 1.90

        // Intensity scaling: keep drizzle visible without turning it into a flat slab.
        cfg.intensityReferenceMaxMMPerHour = max(1.0, maxIntensityMMPerHour.isFinite ? maxIntensityMMPerHour : 1.0)
        cfg.robustMaxPercentile = 0.92
        cfg.intensityGamma = 0.78

        // Core: deep base + bright top (no forced glint).
        cfg.coreBodyColor = Color(red: 0.02, green: 0.08, blue: 0.22).opacity(0.92)
        cfg.coreTopColor = Color(red: 0.06, green: 0.62, blue: 0.99).opacity(0.98)
        cfg.coreTopMix = 0.64
        cfg.coreFadeFraction = 0.09

        // Fuzz: speckled uncertainty band (no blur).
        cfg.fuzzEnabled = true
        cfg.canEnableFuzz = true
        cfg.fuzzColor = Color(red: 0.18, green: 0.74, blue: 1.00)
        cfg.fuzzMaxOpacity = 0.38
        cfg.fuzzWidthFraction = 0.055
        cfg.fuzzWidthPixelsClamp = 2.0...30.0
        cfg.fuzzDensity = 1.00

        // Lower chance => more fuzz.
        cfg.fuzzChanceThreshold = 0.70
        cfg.fuzzChanceTransition = 0.22
        cfg.fuzzChanceExponent = 0.95
        cfg.fuzzChanceFloor = 0.18
        cfg.fuzzChanceMinStrength = 0.10

        // Stronger fuzz near base/edges + around transitions.
        cfg.fuzzTailMinutes = 7
        cfg.fuzzLowHeightPower = 1.65
        cfg.fuzzLowHeightBoost = 1.85

        // No haze blur (keeps background truly black; avoids WidgetKit cost).
        cfg.fuzzHazeStrength = 0.00
        cfg.fuzzHazeBlurFractionOfBand = 0.00

        // Inside speckles: some, but less than outside.
        cfg.fuzzInsideWidthFactor = 0.55
        cfg.fuzzInsideOpacityFactor = 0.66
        cfg.fuzzInsideSpeckleFraction = 0.25

        // Speckles: keep budgets safe for widgets.
        cfg.fuzzSpeckStrength = 1.05
        cfg.fuzzSpeckleBudget = WidgetWeaverRuntime.isRunningInAppExtension ? 1400 : 2200
        cfg.fuzzSpeckleRadiusPixels = 0.40...2.0

        // Distribution shaping.
        cfg.fuzzDistancePowerOutside = 1.55
        cfg.fuzzDistancePowerInside = 1.20
        cfg.fuzzAlongTangentJitter = 0.55

        // Suppress peppering far from rain mass.
        cfg.fuzzEdgeWindowPx = 12.0

        // Legacy erosion disabled (expensive and not needed for the speck look).
        cfg.fuzzErodeEnabled = false

        // Rim: off by default; most edge comes from speckles.
        cfg.rimEnabled = false

        // Baseline: subtle, slightly blue, fades at ends.
        cfg.baselineEnabled = true
        cfg.baselineColor = Color(red: 0.20, green: 0.58, blue: 1.00)
        cfg.baselineLineOpacity = 0.08
        cfg.baselineWidthPixels = 1.0
        cfg.baselineOffsetPixels = -0.5
        cfg.baselineEndFadeFraction = 0.20

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
