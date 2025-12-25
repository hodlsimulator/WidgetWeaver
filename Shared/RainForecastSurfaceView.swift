//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
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

    /// Mild smoothing passes over heights (post-mapping, pre-taper).
    var geometrySmoothingPasses: Int = 1

    // MARK: Scale cap (Step 1)

    /// Hard cap: the filled core surface never exceeds this fraction of plot height.
    /// Recommended 0.25–0.35 (start at 0.30).
    var maxCoreHeightFractionOfPlotHeight: CGFloat = 0.30

    /// Optional absolute cap in points. 0 disables.
    var maxCoreHeightPoints: CGFloat = 0.0

    // MARK: Wet-region taper (Step 2)

    /// Fade-in over first N samples of the first wet region.
    /// Recommended 6–10.
    var wetRegionFadeInSamples: Int = 8

    /// Fade-out over last N samples of the last wet region.
    /// Recommended 10–16.
    var wetRegionFadeOutSamples: Int = 14

    /// Extra softening at every wet segment start/end (internal cliffs).
    /// This is separate from wetRegionFadeIn/Out and applies to all segments.
    var segmentEdgeTaperSamples: Int = 5
    var segmentEdgeTaperPower: Double = 1.35

    // Baseline styling
    var baselineColor: Color = Color(red: 0.55, green: 0.65, blue: 0.85)
    var baselineOpacity: Double = 0.09
    var baselineLineWidth: CGFloat = 1.0
    var baselineInsetPoints: CGFloat = 6.0
    var baselineSoftWidthMultiplier: CGFloat = 2.6
    var baselineSoftOpacityMultiplier: Double = 0.28

    // Core fill styling (Step 8.1)
    var fillBottomColor: Color = Color(red: 0.06, green: 0.12, blue: 0.26)
    var fillTopColor: Color = Color(red: 0.22, green: 0.48, blue: 0.92)
    var fillBottomOpacity: Double = 0.20
    var fillTopOpacity: Double = 0.78

    // MARK: Ridge highlight (Step 4)

    var ridgeEnabled: Bool = true
    var ridgeColor: Color = Color(red: 0.72, green: 0.90, blue: 1.0)
    var ridgeMaxOpacity: Double = 0.22

    /// Ridge thickness in points (pre-blur). Recommended 2–6.
    var ridgeThicknessPoints: CGFloat = 4.0

    /// Ridge blur radius in points. Recommended 6–14 (scale-dependent).
    var ridgeBlurRadiusPoints: CGFloat = 10.0

    /// Extra ridge emphasis on local peaks.
    var ridgePeakBoost: Double = 0.55

    // MARK: Mist band (Step 5–7)

    var mistEnabled: Bool = true
    var mistColor: Color = Color(red: 0.50, green: 0.74, blue: 1.0)

    /// Overall mist opacity cap. Keep subtle.
    var mistMaxOpacity: Double = 0.18

    /// Mist band height in points (upper bound). Recommended 40–90 depending on size.
    var mistHeightPoints: CGFloat = 60.0

    /// Mist band height as fraction of plot height (primary limiter for small widgets).
    var mistHeightFractionOfPlotHeight: CGFloat = 0.55

    /// Mist blur radius in points. 0 enables auto (≈ mistHeight * 0.33).
    var mistBlurRadiusPoints: CGFloat = 0.0

    /// Mist vertical falloff power (higher = faster decay upward).
    var mistFalloffPower: Double = 1.70

    /// Horizontal softening near the ends of each segment (0..0.5 typical).
    var mistEdgeSofteningWidth: Double = 0.10

    // Mist texture (Step 6)
    var mistNoiseEnabled: Bool = true

    /// 0.15–0.30 recommended.
    var mistNoiseInfluence: Double = 0.25

    /// Low-to-mid frequency “puffs”.
    var mistPuffsPerSampleMax: Int = 12

    /// Subtle fine grain (very low alpha).
    var mistFineGrainPerSampleMax: Int = 8

    var mistParticleMinRadiusPoints: CGFloat = 0.7
    var mistParticleMaxRadiusPoints: CGFloat = 3.8
    var mistFineParticleMinRadiusPoints: CGFloat = 0.35
    var mistFineParticleMaxRadiusPoints: CGFloat = 1.1

    // MARK: Controlled glow (optional; clipped and mask-derived)

    var glowEnabled: Bool = true
    var glowColor: Color = Color(red: 0.35, green: 0.70, blue: 1.0)
    var glowLayers: Int = 6
    var glowMaxAlpha: Double = 0.08
    var glowFalloffPower: Double = 1.75
    var glowCertaintyPower: Double = 1.5
    var glowMaxRadiusPoints: CGFloat = 4.5
    var glowMaxRadiusFractionOfHeight: CGFloat = 0.075
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
