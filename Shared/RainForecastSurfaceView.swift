//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  SwiftUI wrapper view for the nowcast surface chart. Includes shared configuration.
//

import SwiftUI

struct RainForecastSurfaceView: View {
    @Environment(\.displayScale) private var displayScale

    let intensities: [Double]
    let certainties: [Double?]
    let configuration: RainForecastSurfaceConfiguration

    init(
        intensities: [Double],
        certainties: [Double?] = [],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            var ctx = context

            // Keep the background pure black regardless of widget/container background.
            ctx.fill(Path(rect), with: .color(.black))

            let renderer = RainForecastSurfaceRenderer(
                intensities: intensities,
                certainties: certainties,
                configuration: configuration
            )
            renderer.render(in: &ctx, rect: rect, displayScale: displayScale)
        }
        .background(Color.black)
    }
}

struct RainForecastSurfaceConfiguration {
    var baselineFractionFromTop: Double = 0.68
    var topHeadroomFraction: Double = 0.07
    var typicalPeakFraction: Double = 0.72
    var edgeEasingFraction: Double = 0.03
    var edgeEasingPower: Double = 1.90
    var intensityReferenceMaxMMPerHour: Double = 6.0
    var robustMaxPercentile: Double = 0.92
    var intensityGamma: Double = 1.20

    var coreBodyColor: Color = Color(red: 0.12, green: 0.43, blue: 0.98).opacity(0.78)
    var coreTopColor: Color = Color(red: 0.40, green: 0.86, blue: 1.00).opacity(0.94)
    var coreTopMix: Double = 0.62
    var coreFadeFraction: Double = 0.15

    var fuzzEnabled: Bool = true
    var canEnableFuzz: Bool = true
    var fuzzColor: Color = Color.white
    var fuzzMaxOpacity: Double = 0.42
    var fuzzWidthFraction: Double = 0.040
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 2.0...24.0
    var fuzzDensity: Double = 1.45

    var fuzzChanceThreshold: Double = 0.60
    var fuzzChanceTransition: Double = 0.24
    var fuzzChanceExponent: Double = 1.35
    var fuzzChanceFloor: Double = 0.24
    var fuzzChanceMinStrength: Double = 0.08

    var fuzzTailMinutes: Double = 7.0
    var fuzzLowHeightPower: Double = 1.7
    var fuzzLowHeightBoost: Double = 1.55

    var fuzzHazeStrength: Double = 0.12
    var fuzzHazeBlurFractionOfBand: Double = 0.26
    var fuzzHazeStrokeWidthFactor: Double = 1.10
    var fuzzInsideHazeStrokeWidthFactor: Double = 0.55

    var fuzzInsideWidthFactor: Double = 0.62
    var fuzzInsideOpacityFactor: Double = 0.88

    var fuzzSpeckStrength: Double = 1.35
    var fuzzSpeckleBudget: Int = 7800
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.30...2.0
    var fuzzInsideSpeckleFraction: Double = 0.55
    var fuzzDistancePowerOutside: Double = 1.10
    var fuzzDistancePowerInside: Double = 0.75
    var fuzzAlongTangentJitter: Double = 0.35
    var fuzzSlopeReferenceBandFraction: Double = 0.25
    var fuzzEdgeWindowPx: Double = 12.0

    var fuzzErodeEnabled: Bool = true
    var fuzzErodeStrength: Double = 1.05
    var fuzzErodeBlurFractionOfBand: Double = 0.06
    var fuzzErodeStrokeWidthFactor: Double = 0.56
    var fuzzErodeEdgePower: Double = 1.35
    var fuzzErodeRimInsetPixels: Double = 1.0

    var glossEnabled: Bool = false
    var glossMaxOpacity: Double = 0.10
    var glossHeightPower: Double = 1.20

    var glintEnabled: Bool = false
    var glintCount: Int = 10
    var glintMaxOpacity: Double = 0.18
    var glintRadiusPixels: ClosedRange<Double> = 0.7...2.2

    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.55, green: 0.95, blue: 1.00)
    var rimOpacity: Double = 0.18
    var rimWidthPixels: Double = 1.0

    var baselineEnabled: Bool = true
    var baselineColor: Color = Color.white
    var baselineLineOpacity: Double = 0.05
    var baselineWidthPixels: Double = 1.0
    var baselineOffsetPixels: Double = 0.0
    var baselineEndFadeFraction: Double = 0.20

    var sourceMinuteCount: Int = 60

    var maxDenseSamples: Int = 900
    var noiseSeed: UInt64 = 0xF00D_F00D_CAFE_BEEF
}
