//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  SwiftUI view wrapper + configuration.
//

import SwiftUI

struct RainForecastSurfaceView: View {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            var ctx = context
            let renderer = RainForecastSurfaceRenderer(
                intensities: intensities,
                certainties: certainties,
                configuration: configuration,
                displayScale: displayScale
            )
            renderer.render(in: &ctx, size: size)
        }
    }
}

struct RainForecastSurfaceConfiguration {
    // MARK: - Geometry
    var baselineFractionFromTop: Double = 0.88
    var topHeadroomFraction: Double = 0.08
    var typicalPeakFraction: Double = 0.22
    var edgeEasingFraction: Double = 0.10
    var edgeEasingPower: Double = 1.8

    // MARK: - Intensity scaling (height is intensity-driven only)
    var intensityReferenceMaxMMPerHour: Double = 6.0
    var robustMaxPercentile: Double = 0.93
    var intensityGamma: Double = 0.60

    // MARK: - Core (fill)
    var coreBodyColor: Color = Color(red: 0.00, green: 0.10, blue: 0.42)
    var coreTopColor: Color = Color(red: 0.20, green: 0.70, blue: 1.00)
    var coreTopMix: Double = 0.55
    var coreFadeFraction: Double = 0.06

    // MARK: - Fuzz (styling only)
    var fuzzEnabled: Bool = true
    var canEnableFuzz: Bool = true
    var fuzzColor: Color = Color(red: 0.20, green: 0.70, blue: 1.00)
    var fuzzMaxOpacity: Double = 0.28
    var fuzzWidthFraction: CGFloat = 0.12
    var fuzzWidthPixelsClamp: ClosedRange<CGFloat> = (7.0...52.0)
    var fuzzDensity: Double = 1.0

    // Chance → strength mapping (styling only)
    var fuzzChanceThreshold: Double = 0.60
    var fuzzChanceTransition: Double = 0.24
    var fuzzChanceExponent: Double = 2.25
    var fuzzChanceFloor: Double = 0.16
    var fuzzChanceMinStrength: Double = 0.0

    // Styling-only tail after the last wet minute (minutes). Recommended 2–6.
    var fuzzTailMinutes: Int = 4

    // Low height + shoulder boost (styling only)
    var fuzzLowHeightPower: Double = 1.8
    var fuzzLowHeightBoost: Double = 0.72

    // Haze (outside-heavy; optional)
    var fuzzHazeStrength: Double = 0.36
    var fuzzHazeBlurFractionOfBand: Double = 0.13
    var fuzzHazeStrokeWidthFactor: Double = 0.70
    var fuzzInsideHazeStrokeWidthFactor: Double = 0.60
    var fuzzInsideWidthFactor: CGFloat = 0.68
    var fuzzInsideOpacityFactor: Double = 0.70

    // Speckles (outside-heavy particulate)
    var fuzzSpeckStrength: Double = 1.0
    var fuzzSpeckleBudget: Int = 5200
    var fuzzSpeckleRadiusPixels: ClosedRange<CGFloat> = (0.25...2.3)
    var fuzzInsideSpeckleFraction: Double = 0.40
    var fuzzDistancePowerOutside: Double = 2.2
    var fuzzDistancePowerInside: Double = 1.5
    var fuzzAlongTangentJitter: Double = 0.75

    // Erode / inset (optional)
    var fuzzErodeEnabled: Bool = true
    var fuzzErodeStrength: Double = 0.70
    var fuzzErodeBlurFractionOfBand: Double = 0.18
    var fuzzErodeStrokeWidthFactor: Double = 1.05
    var fuzzErodeEdgePower: Double = 2.5
    var fuzzErodeRimInsetPixels: Double = 1.4

    // Gloss (optional)
    var glossEnabled: Bool = true
    var glossMaxOpacity: Double = 0.10
    var glossHeightFraction: Double = 0.38

    // Glints (optional)
    var glintEnabled: Bool = false
    var glintMaxOpacity: Double = 0.16
    var glintCount: Int = 14
    var glintSeed: UInt64 = 0

    // Rim (styling only)
    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.30, green: 0.85, blue: 1.0)
    var rimInnerOpacity: Double = 0.10
    var rimInnerWidthPixels: Double = 1.25
    var rimOuterOpacity: Double = 0.14
    var rimOuterWidthPixels: Double = 3.0

    // Baseline
    var baselineEnabled: Bool = true
    var baselineColor: Color = Color.white
    var baselineLineOpacity: Double = 0.10
    var baselineWidthPixels: Double = 1.0
    var baselineOffsetPixels: Double = 0.0
    var baselineEndFadeFraction: Double = 0.05

    // Misc / budgets
    var maxDenseSamples: Int = 900
    var noiseSeed: UInt64 = 0
}
