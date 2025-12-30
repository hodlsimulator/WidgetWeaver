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
    var topHeadroomFraction: Double = 0.10
    var typicalPeakFraction: Double = 0.55
    var edgeEasingFraction: Double = 0.07
    var edgeEasingPower: Double = 1.6

    // MARK: - Intensity scaling
    var intensityReferenceMaxMMPerHour: Double = 18.0
    var robustMaxPercentile: Double = 0.92
    var intensityGamma: Double = 0.60

    // MARK: - Core (fill)
    var coreBodyColor: Color = Color(red: 0.00, green: 0.14, blue: 0.55)
    var coreTopColor: Color = Color(red: 0.35, green: 0.85, blue: 1.00)
    var coreTopMix: Double = 0.55
    var coreFadeFraction: Double = 0.06

    // MARK: - Fuzz (styling only; never height)
    var fuzzEnabled: Bool = true
    var canEnableFuzz: Bool = true
    var fuzzColor: Color = Color(red: 0.45, green: 0.88, blue: 1.00)
    var fuzzMaxOpacity: Double = 0.24

    var fuzzWidthFraction: CGFloat = 0.12
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 7.0...52.0

    var fuzzDensity: Double = 1.0

    // Chance → strength mapping (lower chance => more fuzz). This is *styling only*.
    var fuzzChanceThreshold: Double = 0.60
    var fuzzChanceTransition: Double = 0.24
    var fuzzChanceExponent: Double = 2.25
    var fuzzChanceFloor: Double = 0.16
    var fuzzChanceMinStrength: Double = 0.00

    // Tail length (minutes). Applied as styling into adjacent dry samples (both sides).
    var fuzzTailMinutes: Int = 5

    // Extra boost for low heights (helps tapered blob beginnings/ends)
    var fuzzLowHeightPower: Double = 1.75
    var fuzzLowHeightBoost: Double = 0.70

    // Haze (optional; keep low to avoid lifting black background)
    var fuzzHazeStrength: Double = 0.12
    var fuzzHazeBlurFractionOfBand: Double = 0.18
    var fuzzHazeStrokeWidthFactor: Double = 1.15
    var fuzzInsideHazeStrokeWidthFactor: Double = 0.90

    var fuzzInsideWidthFactor: CGFloat = 0.60
    var fuzzInsideOpacityFactor: Double = 0.55

    // Speckles
    var fuzzSpeckStrength: Double = 1.0
    var fuzzSpeckleBudget: Int = 5200
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.25...2.3
    var fuzzInsideSpeckleFraction: Double = 0.40
    var fuzzDistancePowerOutside: Double = 2.4
    var fuzzDistancePowerInside: Double = 1.6
    var fuzzAlongTangentJitter: Double = 0.85

    // Core erosion (destinationOut) for dissolution near the rim
    var fuzzErodeEnabled: Bool = true
    var fuzzErodeStrength: Double = 0.80
    var fuzzErodeBlurFractionOfBand: Double = 0.16
    var fuzzErodeStrokeWidthFactor: Double = 0.95
    var fuzzErodeEdgePower: Double = 2.2
    var fuzzErodeRimInsetPixels: Double = 1.4

    // MARK: - Gloss
    var glossEnabled: Bool = false
    var glossMaxOpacity: Double = 0.12
    var glossHeightFraction: Double = 0.32

    // MARK: - Glints
    var glintEnabled: Bool = false
    var glintMaxOpacity: Double = 0.12
    var glintCount: Int = 2
    var glintSeed: UInt64 = 0xC0FFEE

    // MARK: - Rim
    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.68, green: 0.95, blue: 1.00)
    var rimInnerOpacity: Double = 0.06
    var rimInnerWidthPixels: Double = 1.2
    var rimOuterOpacity: Double = 0.10
    var rimOuterWidthPixels: Double = 2.6

    // MARK: - Baseline
    var baselineEnabled: Bool = true
    var baselineColor: Color = .white
    var baselineLineOpacity: Double = 0.12
    var baselineWidthPixels: Double = 1.0
    var baselineOffsetPixels: Double = 0.0
    var baselineEndFadeFraction: Double = 0.18

    // MARK: - Misc
    var maxDenseSamples: Int = 900
    var noiseSeed: UInt64 = 0xA11CE
}
