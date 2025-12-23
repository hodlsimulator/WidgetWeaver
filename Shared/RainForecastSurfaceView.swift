//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Target look:
//  - One filled ribbon above a subtle baseline
//  - Uncertainty expressed as a fuzzy mist around the top edge
//  - Certainty stays smooth/crisp (minimal fuzz)
//  - Optional tight glow (no hard outline)
//

import Foundation
import SwiftUI

// MARK: - Configuration

struct RainForecastSurfaceConfiguration: Hashable {
    // Background (usually handled by the chart stage view; kept here for flexibility)
    var backgroundColor: Color = .clear
    var backgroundOpacity: Double = 0.0

    // Data mapping
    var intensityCap: Double = 1.0
    var wetThreshold: Double = 0.0
    var intensityEasingPower: Double = 0.75
    var minVisibleHeightFraction: CGFloat = 0.03

    // Geometry smoothing (visual only; keep small)
    var geometrySmoothingPasses: Int = 1

    // Layout
    var baselineYFraction: CGFloat = 0.82
    var edgeInsetFraction: CGFloat = 0.0

    // Baseline (felt, not seen)
    var baselineColor: Color = .white
    var baselineOpacity: Double = 0.09
    var baselineLineWidth: CGFloat = 1.0
    var baselineInsetPoints: CGFloat = 6.0
    var baselineSoftWidthMultiplier: CGFloat = 2.6
    var baselineSoftOpacityMultiplier: Double = 0.28

    // Core ribbon fill (matte)
    var fillBottomColor: Color = .blue
    var fillTopColor: Color = .blue
    var fillBottomOpacity: Double = 0.18
    var fillTopOpacity: Double = 0.92

    // Boundary modifiers (rendering only)
    var startEaseMinutes: Int = 6
    var endFadeMinutes: Int = 10
    var endFadeFloor: Double = 0.0

    // Diffusion controls (used as the “fuzz richness” dial)
    var diffusionLayers: Int = 24
    var diffusionFalloffPower: Double = 2.2

    // Uncertainty -> diffusion radius
    var diffusionMinRadiusPoints: CGFloat = 1.5
    var diffusionMaxRadiusPoints: CGFloat = 18.0
    var diffusionMinRadiusFractionOfHeight: CGFloat = 0.03
    var diffusionMaxRadiusFractionOfHeight: CGFloat = 0.34
    var diffusionRadiusUncertaintyPower: Double = 1.35

    // Uncertainty -> diffusion strength
    var diffusionStrengthMax: Double = 0.60
    var diffusionStrengthMinUncertainTerm: Double = 0.30
    var diffusionStrengthUncertaintyPower: Double = 1.15

    // Intensity gating (keeps drizzle calm but present)
    var diffusionDrizzleThreshold: Double = 0.10
    var diffusionLowIntensityGateMin: Double = 0.55

    // Light-rain restraint (summary intensity)
    var diffusionLightRainMeanThreshold: Double = 0.18
    var diffusionLightRainMaxRadiusScale: Double = 0.80
    var diffusionLightRainStrengthScale: Double = 0.85

    // Anti-banding controls
    var diffusionStopStride: Int = 2
    var diffusionJitterAmplitudePoints: Double = 0.35
    var diffusionEdgeSofteningWidth: Double = 0.08

    // Internal texture (optional; avoids streaks by default)
    var textureEnabled: Bool = false
    var textureMaxAlpha: Double = 0.22
    var textureMinAlpha: Double = 0.04
    var textureIntensityPower: Double = 0.70
    var textureUncertaintyAlphaBoost: Double = 0.35
    var textureStreaksMin: Int = 1
    var textureStreaksMax: Int = 3
    var textureLineWidthMultiplier: CGFloat = 0.70
    var textureBlurRadiusPoints: CGFloat = 0.6
    var textureTopInsetFractionOfHeight: CGFloat = 0.02

    // Top fuzz / uncertainty mist
    var fuzzEnabled: Bool = true
    var fuzzGlobalBlurRadiusPoints: CGFloat = 1.0
    var fuzzLineWidthMultiplier: CGFloat = 0.70
    var fuzzLengthMultiplier: CGFloat = 1.15
    var fuzzDotsEnabled: Bool = true
    var fuzzDotsPerSampleMax: Int = 3

    // Mist style (ridge = continuous haze; particles = fine spray)
    var fuzzRidgeEnabled: Bool = true
    var fuzzOutsideOnly: Bool = true
    var fuzzRidgeCoreRadiusMultiplier: Double = 0.55
    var fuzzRidgeCoreAlphaMultiplier: Double = 0.32
    var fuzzRidgeFeatherRadiusMultiplier: Double = 1.10
    var fuzzRidgeFeatherAlphaMultiplier: Double = 0.14
    var fuzzParticleAlphaMultiplier: Double = 0.55

    // Glow (optional; tight inward concentration, never a hard outline)
    var glowEnabled: Bool = true
    var glowColor: Color = .blue
    var glowLayers: Int = 6
    var glowMaxAlpha: Double = 0.22
    var glowFalloffPower: Double = 1.75
    var glowCertaintyPower: Double = 1.6
    var glowMaxRadiusPoints: CGFloat = 3.8
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
