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

// MARK: - Configuration

struct RainForecastSurfaceConfiguration: Hashable {

    // Background
    var backgroundColor: Color = .clear
    var backgroundOpacity: Double = 0.0

    // Input normalisation
    var intensityCap: Double = 1.0
    var wetThreshold: Double = 0.0

    /// Value shaping gamma for v in [0, 1].
    /// vShaped = pow(v, intensityEasingPower)
    var intensityEasingPower: Double = 0.70

    // Geometry
    var baselineYFraction: CGFloat = 0.82
    var edgeInsetFraction: CGFloat = 0.0

    /// Minimum visible height for wet samples, expressed as a fraction of maxCoreHeight.
    var minVisibleHeightFraction: CGFloat = 0.025

    /// Mild smoothing passes over heights (post-mapping, pre-masks).
    var geometrySmoothingPasses: Int = 1

    // MARK: - Height mapping (MUST be plot-rect based)

    /// Hard cap: the filled core surface never exceeds this fraction of plot rect height.
    /// (Large: 0.37 start, Medium: 0.62 start)
    var maxCoreHeightFractionOfPlotHeight: CGFloat = 0.30

    /// Optional absolute cap in points. 0 disables.
    var maxCoreHeightPoints: CGFloat = 0.0

    // MARK: - End tapers (ALPHA ONLY)

    /// Fade-in over first N samples of the first wet region.
    var wetRegionFadeInSamples: Int = 8

    /// Fade-out over last N samples of the last wet region.
    var wetRegionFadeOutSamples: Int = 14

    // MARK: - Segment drop settling (GEOMETRY, not end-taper)

    /// Adds short geometric tails into neighbouring dry samples to avoid vertical walls at segment boundaries.
    /// This does not “squash” the curve; it extends the curve into the baseline.
    var geometryTailInSamples: Int = 6
    var geometryTailOutSamples: Int = 12
    var geometryTailPower: Double = 2.25

    // Baseline styling.
    var baselineColor: Color = Color(red: 0.55, green: 0.65, blue: 0.85)
    var baselineOpacity: Double = 0.10
    var baselineLineWidth: CGFloat = 1.0
    var baselineInsetPoints: CGFloat = 0.0
    var baselineSoftWidthMultiplier: CGFloat = 2.6
    var baselineSoftOpacityMultiplier: Double = 0.24

    // MARK: - Core fill depth (smooth, no noise)

    var fillBottomColor: Color = Color(red: 0.02, green: 0.04, blue: 0.09) // near-black navy
    var fillMidColor: Color = Color(red: 0.05, green: 0.10, blue: 0.22) // mid-body lift
    var fillTopColor: Color = Color(red: 0.18, green: 0.42, blue: 0.86) // near crest

    var fillBottomOpacity: Double = 0.88
    var fillMidOpacity: Double = 0.55
    var fillTopOpacity: Double = 0.40

    /// Optional “crest lift” inside the fill (still smooth).
    var crestLiftEnabled: Bool = true
    var crestLiftMaxOpacity: Double = 0.10

    // MARK: - Ridge highlight (mask-derived)

    var ridgeEnabled: Bool = true
    var ridgeColor: Color = Color(red: 0.72, green: 0.92, blue: 1.0)
    var ridgeMaxOpacity: Double = 0.22

    /// Ridge thickness r in points (pre-blur). Large start 4, Medium start 3.
    var ridgeThicknessPoints: CGFloat = 4.0

    /// Ridge blur as a fraction of plot rect height (derived from plotRectHeight).
    var ridgeBlurFractionOfPlotHeight: CGFloat = 0.11
    var ridgePeakBoost: Double = 0.55

    // MARK: - Specular glint (small peak highlight)

    var glintEnabled: Bool = true
    var glintColor: Color = Color(red: 0.99, green: 1.0, blue: 1.0)
    var glintMaxOpacity: Double = 0.85
    var glintThicknessPoints: CGFloat = 1.2
    var glintBlurRadiusPoints: CGFloat = 1.6
    var glintHaloOpacityMultiplier: Double = 0.20
    var glintSpanSamples: Int = 6
    var glintMinPeakHeightFractionOfSegmentMax: Double = 0.70

    // MARK: - Broad bloom (unused by the nowcast spec implementation)

    var bloomEnabled: Bool = true
    var bloomColor: Color = Color(red: 0.42, green: 0.78, blue: 1.0)
    var bloomMaxOpacity: Double = 0.06
    var bloomBlurFractionOfPlotHeight: CGFloat = 0.52
    var bloomBandHeightFractionOfPlotHeight: CGFloat = 0.70

    // MARK: - Surface shell fuzz

    var shellEnabled: Bool = true
    var shellColor: Color = Color(red: 0.60, green: 0.86, blue: 1.0)
    var shellMaxOpacity: Double = 0.16
    var shellInsideThicknessPoints: CGFloat = 2.0

    /// Historical name: shellAboveThicknessPoints (kept for API stability).
    var shellAboveThicknessPoints: CGFloat = 10.0
    var shellNoiseAmount: Double = 0.28
    var shellBlurFractionOfPlotHeight: CGFloat = 0.030
    var shellPuffsPerSampleMax: Int = 5
    var shellPuffMinRadiusPoints: CGFloat = 0.7
    var shellPuffMaxRadiusPoints: CGFloat = 3.0

    // MARK: - Above-surface mist (unused by the nowcast spec implementation)

    var mistEnabled: Bool = true
    var mistColor: Color = Color(red: 0.50, green: 0.74, blue: 1.0)
    var mistMaxOpacity: Double = 0.18
    var mistHeightPoints: CGFloat = 60.0
    var mistHeightFractionOfPlotHeight: CGFloat = 0.85
    var mistFalloffPower: Double = 1.70
    var mistNoiseEnabled: Bool = true
    var mistNoiseInfluence: Double = 0.25
    var mistPuffsPerSampleMax: Int = 12
    var mistFineGrainPerSampleMax: Int = 8
    var mistParticleMinRadiusPoints: CGFloat = 0.7
    var mistParticleMaxRadiusPoints: CGFloat = 3.8
    var mistFineParticleMinRadiusPoints: CGFloat = 0.35
    var mistFineParticleMaxRadiusPoints: CGFloat = 1.1
}

// MARK: - View

struct RainForecastSurfaceView: View {

    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration

    @Environment(\.displayScale) private var displayScale

    init(
        intensities: [Double],
        certainties: [Double],
        configuration: RainForecastSurfaceConfiguration
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
    }

    var body: some View {
        Canvas { context, size in
            let renderer = RainForecastSurfaceRenderer(
                intensities: intensities,
                certainties: certainties,
                configuration: configuration,
                displayScale: displayScale
            )
            renderer.render(in: &context, size: size)
        }
    }
}
