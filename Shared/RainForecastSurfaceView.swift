//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Forecast surface view + configuration.
//

import Foundation
import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

struct RainForecastSurfaceConfiguration: Hashable {
    // MARK: - Data
    var intensityCap: Double = 1.0
    var wetThreshold: Double = 0.0

    // MARK: - Background (renderer enforces pure black)
    var backgroundColor: Color = .black
    var backgroundOpacity: Double = 1.0

    // MARK: - Geometry (spec-driven; kept for compatibility)
    var edgeInsetFraction: CGFloat = 0.0
    var baselineYFraction: CGFloat = 0.596
    var maxCoreHeightFractionOfPlotHeight: CGFloat = 0.195
    var minVisibleHeightFractionOfMax: CGFloat = 0.012
    var intensityEasingPower: Double = 0.78
    var geometryTailInSamples: Int = 2
    var geometryTailOutSamples: Int = 3
    var geometrySmoothingPasses: Int = 2

    // MARK: - Alpha taper (legacy; core is now drawn opaque)
    var alphaTaperStartSamples: Int = 2
    var alphaTaperEndSamples: Int = 5
    var alphaTaperFloor: Double = 0.38

    // MARK: - Baseline
    var baselineColor: Color = Color(red: 0.40, green: 0.74, blue: 1.0)
    var baselineOpacity: Double = 0.70
    var baselineLineWidth: CGFloat = 1.0
    var baselineSoftWidthMultiplier: CGFloat = 3.0
    var baselineSoftOpacity: Double = 0.18
    var baselineGlowWidthMultiplier: CGFloat = 12.0
    var baselineGlowOpacity: Double = 0.055

    // MARK: - Core fill colours (opaque)
    var fillBottomColor: Color = Color(red: 0.02, green: 0.05, blue: 0.12)
    var fillMidColor: Color = Color(red: 0.10, green: 0.30, blue: 0.90)
    var fillTopColor: Color = Color(red: 0.20, green: 0.55, blue: 1.0)
    var fillBottomOpacity: Double = 1.0
    var fillMidOpacity: Double = 1.0
    var fillTopOpacity: Double = 1.0

    // MARK: - Crest lift (used as inside-only gloss band)
    var crestLiftEnabled: Bool = true
    var crestLiftBandHeightFractionOfCore: CGFloat = 0.20
    var crestLiftMaxOpacity: Double = 0.14
    var crestLiftBlurFractionOfPlotHeight: CGFloat = 0.016

    // MARK: - Bloom (disabled; spec forbids global lift)
    var bloomEnabled: Bool = false
    var bloomOpacity: Double = 0.11
    var bloomBlurFractionOfPlotHeight: CGFloat = 0.16

    // MARK: - Mist (disabled; spec forbids haze)
    var mistEnabled: Bool = false
    var mistColor: Color = Color(red: 0.38, green: 0.70, blue: 1.0)
    var mistMaxOpacity: Double = 0.060
    var mistThicknessFractionOfPlotHeight: CGFloat = 0.24
    var mistLiftFractionOfPlotHeight: CGFloat = 0.040
    var mistBlurFractionOfPlotHeight: CGFloat = 0.060

    // MARK: - Shell (reinterpreted as fuzz speckle envelope)
    var shellEnabled: Bool = true
    var shellColor: Color = Color(red: 0.70, green: 0.92, blue: 1.0)
    var shellMaxOpacity: Double = 0.16
    var shellNoiseAmount: Double = 0.28
    var shellAboveThicknessPoints: CGFloat = 10.0
    var shellBelowThicknessPoints: CGFloat = 18.0
    var shellBlurFractionOfPlotHeight: CGFloat = 0.008
    var shellPuffsPerSample: Int = 7
    var shellPuffRadiusPoints: CGFloat = 1.30
    var shellPuffRadiusJitterPoints: CGFloat = 0.70
    var shellPuffHorizontalJitterPoints: CGFloat = 1.20

    // MARK: - Ridge highlight (disabled; spec forbids bright rim)
    var ridgeHighlightEnabled: Bool = false
    var ridgeHighlightColor: Color = Color(red: 0.90, green: 0.98, blue: 1.0)
    var ridgeHighlightMaxOpacity: Double = 0.16
    var ridgeHighlightBandHeightFractionOfCore: CGFloat = 0.09
    var ridgeHighlightBlurFractionOfPlotHeight: CGFloat = 0.006

    // MARK: - Glint (tiny + localised)
    var glintEnabled: Bool = true
    var glintColor: Color = Color(red: 0.98, green: 1.0, blue: 1.0)
    var glintMaxOpacity: Double = 0.78
    var glintBlurRadiusPoints: CGFloat = 1.6
    var glintCount: Int = 2
    var glintHorizontalJitterFractionOfSample: Double = 0.16
    var glintVerticalOffsetFractionOfBand: Double = 0.22

    // MARK: - Determinism / certainty shaping
    /// If zero, RainForecastSurfaceView derives a deterministic seed.
    var noiseSeed: UInt64 = 0

    /// Rounding for the time component of the derived seed.
    var noiseSeedRoundingSeconds: Int = 15 * 60

    /// How strongly certainty suppresses the solid core height. (Higher => smaller core when certainty is low.)
    var coreCertaintyPower: Double = 0.85
}

struct RainForecastSurfaceView: View {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration

    @Environment(\.displayScale) private var displayScale
    #if canImport(WidgetKit)
    @Environment(\.widgetFamily) private var widgetFamily
    #endif

    init(
        intensities: [Double],
        certainties: [Double],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
    }

    var body: some View {
        Canvas { context, size in
            var config = configuration

            // Deterministic seed: rounded render-clock time + pixel size + widget family.
            if config.noiseSeed == 0 {
                let now = WidgetWeaverRenderClock.now
                let rounded = RainSurfacePRNG.roundedTimestampSeconds(now, roundingSeconds: config.noiseSeedRoundingSeconds)

                let pxW = max(1, Int(ceil(size.width * max(displayScale, 1.0))))
                let pxH = max(1, Int(ceil(size.height * max(displayScale, 1.0))))

                #if canImport(WidgetKit)
                let familyRaw = widgetFamily.rawValue
                #else
                let familyRaw = 0
                #endif

                config.noiseSeed = RainSurfacePRNG.seed(
                    roundedTimestampSeconds: rounded,
                    pixelWidth: pxW,
                    pixelHeight: pxH,
                    widgetFamilyRaw: familyRaw
                )
            }

            let renderer = RainForecastSurfaceRenderer(
                intensities: intensities,
                certainties: certainties,
                configuration: config,
                displayScale: displayScale
            )

            renderer.render(in: &context, size: size)
        }
        .compositingGroup()
    }
}
