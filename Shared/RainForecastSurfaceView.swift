//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  SwiftUI view wrapper + configuration.
//

import Foundation
import SwiftUI

struct RainForecastSurfaceConfiguration {

    // MARK: - Determinism
    var noiseSeed: UInt64 = 0

    // MARK: - Sampling / shaping
    var maxDenseSamples: Int = 420
    var baselineFractionFromTop: CGFloat = 0.86
    var topHeadroomFraction: CGFloat = 0.18
    var typicalPeakFraction: CGFloat = 0.70
    var robustMaxPercentile: Double = 0.93
    var intensityGamma: Double = 0.62

    var edgeEasingFraction: Double = 0.18
    var edgeEasingPower: Double = 1.45

    // MARK: - Core
    var coreBodyColor: Color = Color(red: 0.00, green: 0.10, blue: 0.42)
    var coreTopColor: Color = Color(red: 0.10, green: 0.35, blue: 1.00)

    // MARK: - Rim
    var rimEnabled: Bool = true
    var rimColor: Color = .white
    var rimInnerOpacity: Double = 0.10
    var rimInnerWidthPixels: Double = 1.0
    var rimOuterOpacity: Double = 0.04
    var rimOuterWidthPixels: Double = 16.0

    // MARK: - Gloss
    var glossEnabled: Bool = false
    var glossDepthPixels: Double = 22.0
    var glossMaxOpacity: Double = 0.14
    var glossSoftBlurPixels: Double = 18.0

    // MARK: - Glints
    var glintEnabled: Bool = false
    var glintColor: Color = .white
    var glintMaxOpacity: Double = 0.10
    var glintBlurPixels: Double = 10.0
    var glintMinHeightFraction: Double = 0.18
    var glintMaxCount: Int = 2

    // MARK: - Baseline
    var baselineColor: Color = .white
    var baselineLineOpacity: Double = 0.16
    var baselineEndFadeFraction: Double = 0.04

    // MARK: - Fuzz
    var fuzzEnabled: Bool = true
    var fuzzColor: Color = .white

    var fuzzRasterMaxPixels: Int = 180_000
    var fuzzMaxOpacity: Double = 0.26

    var fuzzWidthFraction: Double = 0.18
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 10.0...90.0

    var fuzzBaseDensity: Double = 0.88
    var fuzzHazeStrength: Double = 0.78
    var fuzzSpeckStrength: Double = 1.18
    var fuzzEdgePower: Double = 1.60

    var fuzzClumpCellPixels: Double = 12.0
    var fuzzMicroBlurPixels: Double = 0.55

    // Chance → fuzz
    var fuzzChanceThreshold: Double = 0.60
    var fuzzChanceTransition: Double = 0.14
    var fuzzChanceMinStrength: Double = 0.14

    // Legacy uncertainty shaping
    var fuzzUncertaintyFloor: Double = 0.06
    var fuzzUncertaintyExponent: Double = 2.10

    // Low-height reinforcement
    var fuzzLowHeightPower: Double = 2.10
    var fuzzLowHeightBoost: Double = 0.55

    // Inside band contribution
    var fuzzInsideWidthFactor: Double = 0.72
    var fuzzInsideOpacityFactor: Double = 0.62
    var fuzzInsideSpeckleFraction: Double = 0.40

    // Distance falloff within the band
    var fuzzDistancePowerOutside: Double = 2.00
    var fuzzDistancePowerInside: Double = 1.70

    // Core erosion near the surface
    var fuzzErodeEnabled: Bool = true
    var fuzzErodeStrength: Double = 0.82
    var fuzzErodeEdgePower: Double = 2.70

    // Extra knobs kept for compatibility (may be set by DEBUG harness / older configs)
    var fuzzSpeckleBudget: Int = 0
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.50...1.20
    var fuzzAlongTangentJitterFraction: Double = 0.0
    var fuzzHazeBlurFractionOfBand: Double = 0.0
    var fuzzHazeStrokeWidthFactor: Double = 0.0
    var fuzzInsideHazeStrokeWidthFactor: Double = 0.0

    // MARK: - Convenience

    var canEnableFuzz: Bool {
        fuzzEnabled && fuzzMaxOpacity > 0.000_1 && fuzzWidthFraction > 0.000_1
    }
}

struct RainForecastSurfaceView: View {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { gc, size in
            var context = gc
            let renderer = RainForecastSurfaceRenderer(
                intensities: intensities,
                certainties: certainties,
                configuration: configuration,
                displayScale: displayScale
            )
            renderer.render(in: &context, size: size)
        }
        .accessibilityHidden(true)
    }
}
