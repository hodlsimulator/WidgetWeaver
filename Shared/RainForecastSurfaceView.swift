//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  SwiftUI view wrapper + configuration.
//

import SwiftUI

struct RainForecastSurfaceConfiguration {
    // Sampling.
    var maxDenseSamples: Int = 900

    // Geometry ratios (measured from the mock).
    // baselineFractionFromTop: baseline Y as fraction of chart height from top.
    var baselineFractionFromTop: CGFloat = 0.596

    // topHeadroomFraction: fraction of baseline distance-from-top reserved as headroom.
    // (This makes it stable across different baseline placements.)
    var topHeadroomFraction: CGFloat = 0.30

    // typicalPeakFraction: typical peak Y as fraction of chart height from top.
    // (Used as a geometric target for scaling; not a “cap”.)
    var typicalPeakFraction: CGFloat = 0.195

    // Intensity mapping.
    var robustMaxPercentile: Double = 0.93
    var intensityGamma: Double = 0.65

    // Edge easing.
    var edgeEasingFraction: CGFloat = 0.22
    var edgeEasingPower: Double = 1.45

    // Core fill.
    var coreBodyColor: Color = Color(red: 0.00, green: 0.10, blue: 0.42)
    var coreTopColor: Color = .blue
    var coreTopMix: CGFloat = 0.0   // 0 = solid coreBodyColor, 1 = overlay coreTopColor
    var coreFadeFraction: CGFloat = 0.06 // extra fade-out at the top of the core (destinationOut)

    // Rim.
    var rimEnabled: Bool = true
    var rimColor: Color = .blue
    var rimInnerOpacity: Double = 0.10
    var rimInnerWidthPixels: CGFloat = 1.0
    var rimOuterOpacity: Double = 0.045
    var rimOuterWidthPixels: CGFloat = 16.0

    // Gloss (optional).
    var glossEnabled: Bool = false
    var glossMaxOpacity: Double = 0.06
    var glossDepthPixels: CGFloat = 18.0
    var glossBlurPixels: CGFloat = 10.0
    var glossVerticalOffsetFraction: CGFloat = 0.06

    // Glints (optional).
    var glintEnabled: Bool = false
    var glintCount: Int = 7
    var glintMaxOpacity: Double = 0.16
    var glintSigmaPixels: CGFloat = 11.0
    var glintVerticalOffsetPixels: CGFloat = 10.0

    // Noise.
    var noiseSeed: UInt64 = 0

    // Allow the caller to hard-disable fuzz for performance or widget restrictions.
    var canEnableFuzz: Bool = true

    // Fuzz band.
    var fuzzEnabled: Bool = true
    var fuzzColor: Color = .blue
    var fuzzMaxOpacity: Double = 0.28
    var fuzzWidthFraction: CGFloat = 0.24
    var fuzzWidthPixelsClamp: ClosedRange<CGFloat> = 10.0...90.0

    // Chance → fuzz strength.
    // “Chance” here is certainty/probability 0..1 (higher = more confident rain).
    // Below threshold => fuzzier.
    var fuzzChanceThreshold: Double = 0.60
    var fuzzChanceTransition: Double = 0.24
    var fuzzChanceFloor: Double = 0.16
    var fuzzChanceExponent: Double = 2.25

    // Fuzz composition.
    var fuzzDensity: Double = 0.95
    var fuzzHazeStrength: Double = 0.95
    var fuzzSpeckStrength: Double = 1.00

    // Extra fuzz at low heights (tapered ends).
    var fuzzLowHeightPower: Double = 2.15
    var fuzzLowHeightBoost: Double = 0.92

    // Inside-band behaviour.
    var fuzzInsideWidthFactor: Double = 0.66
    var fuzzInsideOpacityFactor: Double = 0.70
    var fuzzInsideSpeckleFraction: Double = 0.36

    // Distance shaping and tangential jitter.
    var fuzzDistancePowerOutside: Double = 1.90
    var fuzzDistancePowerInside: Double = 1.55
    var fuzzAlongTangentJitter: Double = 0.95

    // Haze sizing.
    var fuzzHazeBlurFractionOfBand: Double = 0.36
    var fuzzHazeStrokeWidthFactor: Double = 1.35
    var fuzzInsideHazeStrokeWidthFactor: Double = 1.12

    // Speckle sizing and budget.
    var fuzzSpeckleRadiusPixels: ClosedRange<CGFloat> = 0.50...1.20
    var fuzzSpeckleBudget: Int = 5200

    // Core edge removal so fuzz “is” the surface (key to the mock).
    var fuzzErodeEnabled: Bool = true
    var fuzzErodeStrength: Double = 0.80
    var fuzzErodeEdgePower: Double = 1.50
    var fuzzErodeRimInsetPixels: CGFloat = 1.0

    // Baseline.
    var baselineEnabled: Bool = true
    var baselineColor: Color = .blue
    var baselineLineOpacity: Double = 0.20
    var baselineWidthPixels: CGFloat = 1.0
    var baselineOffsetPixels: CGFloat = 0.0
    var baselineEndFadeFraction: CGFloat = 0.035

    // -------------------------------------------------------------------------
    // Compatibility aliases (keeps older Nowcast config code compiling).
    // -------------------------------------------------------------------------

    var fuzzBaseDensity: Double {
        get { fuzzDensity }
        set { fuzzDensity = newValue }
    }

    var fuzzUncertaintyFloor: Double {
        get { fuzzChanceFloor }
        set { fuzzChanceFloor = newValue }
    }

    var fuzzUncertaintyExponent: Double {
        get { fuzzChanceExponent }
        set { fuzzChanceExponent = newValue }
    }

    var fuzzChanceSoftness: Double {
        get { fuzzChanceTransition }
        set { fuzzChanceTransition = newValue }
    }

    var fuzzAlongTangentJitterFraction: Double {
        get { fuzzAlongTangentJitter }
        set { fuzzAlongTangentJitter = newValue }
    }

    var baselineOpacity: Double {
        get { baselineLineOpacity }
        set { baselineLineOpacity = newValue }
    }

    var glossOpacity: Double {
        get { glossMaxOpacity }
        set { glossMaxOpacity = newValue }
    }

    var glintOpacity: Double {
        get { glintMaxOpacity }
        set { glintMaxOpacity = newValue }
    }
}

struct RainForecastSurfaceView: View {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration

    @Environment(\.displayScale) private var displayScale

    init(
        intensities: [Double],
        certainties: [Double] = [],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let renderer = RainForecastSurfaceRenderer(
                    intensities: intensities,
                    certainties: certainties,
                    configuration: configuration,
                    displayScale: displayScale
                )
                var ctx = context
                renderer.render(in: &ctx, size: size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
