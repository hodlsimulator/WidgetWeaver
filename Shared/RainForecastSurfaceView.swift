//
// RainForecastSurfaceView.swift
// WidgetWeaver
//
// Created by . . on 12/23/25.
//

import Foundation
import SwiftUI

// MARK: - Configuration

struct RainForecastSurfaceConfiguration: Hashable {
    var backgroundColor: Color = .clear
    var backgroundOpacity: Double = 0.0

    var intensityCap: Double = 1.0
    var wetThreshold: Double = 0.0
    var intensityEasingPower: Double = 0.75
    var minVisibleHeightFraction: CGFloat = 0.03

    var geometrySmoothingPasses: Int = 1

    var baselineYFraction: CGFloat = 0.82
    var edgeInsetFraction: CGFloat = 0.0

    var baselineColor: Color = Color(red: 0.55, green: 0.65, blue: 0.85)
    var baselineOpacity: Double = 0.09
    var baselineLineWidth: CGFloat = 1.0
    var baselineInsetPoints: CGFloat = 6.0
    var baselineSoftWidthMultiplier: CGFloat = 2.6
    var baselineSoftOpacityMultiplier: Double = 0.28

    var fillBottomColor: Color = Color(red: 0.10, green: 0.20, blue: 0.40)
    var fillTopColor: Color = Color(red: 0.25, green: 0.55, blue: 0.95)
    var fillBottomOpacity: Double = 0.18
    var fillTopOpacity: Double = 0.92

    var startEaseMinutes: Int = 6
    var endFadeMinutes: Int = 10
    var endFadeFloor: Double = 0.0

    var diffusionLayers: Int = 32
    var diffusionFalloffPower: Double = 2.20

    var diffusionMinRadiusPoints: CGFloat = 1.5
    var diffusionMaxRadiusPoints: CGFloat = 52.0
    var diffusionMinRadiusFractionOfHeight: CGFloat = 0.0
    var diffusionMaxRadiusFractionOfHeight: CGFloat = 0.42
    var diffusionRadiusUncertaintyPower: Double = 1.15

    var diffusionStrengthMax: Double = 0.78
    var diffusionStrengthMinUncertainTerm: Double = 0.30
    var diffusionStrengthUncertaintyPower: Double = 1.05

    var diffusionDrizzleThreshold: Double = 0.08
    var diffusionLowIntensityGateMin: Double = 0.60

    var diffusionLightRainMeanThreshold: Double = 0.18
    var diffusionLightRainMaxRadiusScale: Double = 0.80
    var diffusionLightRainStrengthScale: Double = 0.85
    var diffusionStopStride: Int = 2
    var diffusionJitterAmplitudePoints: Double = 0.0
    var diffusionEdgeSofteningWidth: Double = 0.08

    var textureEnabled: Bool = false
    var textureMaxAlpha: Double = 0.0
    var textureMinAlpha: Double = 0.0
    var textureIntensityPower: Double = 0.70
    var textureUncertaintyAlphaBoost: Double = 0.0
    var textureStreaksMin: Int = 0
    var textureStreaksMax: Int = 0
    var textureLineWidthMultiplier: CGFloat = 0.70
    var textureBlurRadiusPoints: CGFloat = 0.0
    var textureTopInsetFractionOfHeight: CGFloat = 0.02

    var fuzzEnabled: Bool = true
    var fuzzGlobalBlurRadiusPoints: CGFloat = 0.0
    var fuzzLineWidthMultiplier: CGFloat = 0.0
    var fuzzLengthMultiplier: CGFloat = 0.0
    var fuzzDotsEnabled: Bool = false
    var fuzzDotsPerSampleMax: Int = 0
    var fuzzRidgeEnabled: Bool = false
    var fuzzOutsideOnly: Bool = false
    var fuzzRidgeCoreRadiusMultiplier: Double = 0.0
    var fuzzRidgeCoreAlphaMultiplier: Double = 0.0
    var fuzzRidgeFeatherRadiusMultiplier: Double = 0.0
    var fuzzRidgeFeatherAlphaMultiplier: Double = 0.0
    var fuzzParticleAlphaMultiplier: Double = 0.0

    var glowEnabled: Bool = true
    var glowColor: Color = Color(red: 0.35, green: 0.70, blue: 1.0)
    var glowLayers: Int = 6
    var glowMaxAlpha: Double = 0.12
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
