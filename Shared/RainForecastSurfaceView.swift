//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import SwiftUI

/// Public SwiftUI wrapper.
struct RainForecastSurfaceView: View {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration

    @Environment(\.displayScale) private var displayScale
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.widgetRenderingMode) private var widgetRenderingMode

    var body: some View {
        Canvas { context, size in
            var cfg = configuration
            let isLowBudget = WidgetWeaverRuntime.thumbnailRenderingEnabled || WidgetWeaverRuntime.isPreviewOrPlaceholder
            cfg.applyWidgetPlaceholderBudgetGuardrails(
                isLowBudget: isLowBudget,
                displayScale: displayScale
            )
            let renderer = RainForecastSurfaceRenderer(
                intensities: intensities,
                certainties: certainties,
                configuration: cfg
            )
            renderer.render(in: &context, size: size, displayScale: displayScale)
        }
    }
}

/// Configuration for the surface renderer.
/// Intentionally a big bag of knobs so the template can tune without touching the renderer.
struct RainForecastSurfaceConfiguration {
    // Geometry.
    var baselineFractionFromTop: CGFloat = 0.83
    var topHeadroomFraction: CGFloat = 0.08
    var typicalPeakFraction: CGFloat = 0.78

    // Intensity scaling.
    var intensityReferenceMaxMMPerHour: Double = 3.0
    var robustMaxPercentile: Double = 0.92
    var intensityGamma: Double = 0.62

    // Sampling.
    var maxDenseSamples: Int = 780

    // Core appearance.
    var coreBodyColor: Color = Color.blue.opacity(0.75)
    var coreTopColor: Color = Color.blue.opacity(0.92)
    var coreTopMix: Double = 0.62
    var coreFadeFraction: Double = 0.0

    // Rim stroke.
    var rimEnabled: Bool = false
    var rimColor: Color = Color.white.opacity(0.20)
    var rimWidthPixels: CGFloat = 1.0

    // Baseline stroke.
    var baselineEnabled: Bool = true
    var baselineColor: Color = Color.blue.opacity(0.85)
    var baselineLineOpacity: Double = 0.12
    var baselineWidthPixels: CGFloat = 1.0
    var baselineOffsetPixels: CGFloat = 0.0
    var baselineEndFadeFraction: Double = 0.18

    // Fuzz (generic).
    var fuzzEnabled: Bool = true
    var canEnableFuzz: Bool = true
    var fuzzColor: Color = Color.blue
    var fuzzMaxOpacity: Double = 0.66
    var fuzzSpeckStrength: Double = 1.35

    // Fuzz band sizing.
    var fuzzWidthFraction: Double = 0.14
    var fuzzWidthPixelsClamp: ClosedRange<CGFloat> = 10.0...72.0

    // Certainty mapping.
    var fuzzChanceThreshold: Double = 0.80
    var fuzzChanceTransition: Double = 0.22
    var fuzzChanceExponent: Double = 1.20
    var fuzzChanceFloor: Double = 0.12
    var fuzzChanceMinStrength: Double = 0.04

    // Shape shaping for fuzz.
    var fuzzTailMinutes: Double = 8.0
    var fuzzLowHeightPower: Double = 1.05
    var fuzzLowHeightBoost: Double = 1.10
    var fuzzEdgeWindowPx: Double = 24.0

    // Texture fuzz.
    var fuzzTextureEnabled: Bool = true
    var fuzzTextureTilePixels: Int = 224
    var fuzzTextureGradientStops: Int = 32
    var fuzzTextureInnerBandMultiplier: Double = 1.15
    var fuzzTextureOuterBandMultiplier: Double = 5.40
    var fuzzTextureInnerOpacityMultiplier: Double = 1.10
    var fuzzTextureOuterOpacityMultiplier: Double = 0.50

    // Strength remap (post strength shaping before rendering)
    // Exponent < 1 boosts small strengths; > 1 suppresses them. Gain is applied after exponent.
    var fuzzStrengthExponent: Double = 1.0
    var fuzzStrengthGain: Double = 1.0

    // Outer dust (outside-the-body speckle). This is the “airy cloud” and can be disabled in widgets if needed.
    var fuzzOuterDustEnabled: Bool = true
    var fuzzOuterDustEnabledInAppExtension: Bool = false
    var fuzzOuterDustPassCount: Int = 3
    var fuzzOuterDustPassCountInAppExtension: Int = 2

    // Subtractive edge erosion.
    var fuzzErodeEnabled: Bool = true
    var fuzzErodeStrength: Double = 1.0
    var fuzzErodeStrokeWidthFactor: Double = 0.85
    var fuzzErodeEdgePower: Double = 1.35

    // Haze (soft pass).
    var fuzzHazeStrength: Double = 0.0
    var fuzzHazeBlurFractionOfBand: Double = 0.0
    var fuzzHazeStrokeWidthFactor: Double = 1.0

    // Noise.
    var noiseSeed: UInt64 = 0xBADC0DE

    mutating func applyWidgetPlaceholderBudgetGuardrails(isLowBudget: Bool, displayScale: CGFloat) {
        // Keep these renders cheap & stable.
        if isLowBudget {
            canEnableFuzz = false
        }

        // Geometry clamps.
        baselineFractionFromTop = max(0.60, min(baselineFractionFromTop, 0.92))
        topHeadroomFraction = max(0.0, min(topHeadroomFraction, 0.25))
        typicalPeakFraction = max(0.40, min(typicalPeakFraction, 0.92))

        // Sampling clamps.
        maxDenseSamples = max(120, min(maxDenseSamples, 1100))

        // Colour/opacity clamps.
        intensityReferenceMaxMMPerHour = max(0.1, intensityReferenceMaxMMPerHour)
        robustMaxPercentile = max(0.60, min(robustMaxPercentile, 0.995))
        intensityGamma = max(0.20, min(intensityGamma, 2.50))

        // Baseline clamps.
        baselineLineOpacity = max(0.0, min(baselineLineOpacity, 0.35))
        baselineWidthPixels = max(0.5, min(baselineWidthPixels, 2.0))
        baselineOffsetPixels = max(-4.0, min(baselineOffsetPixels, 4.0))
        baselineEndFadeFraction = max(0.0, min(baselineEndFadeFraction, 0.40))

        // Fuzz clamps.
        fuzzMaxOpacity = max(0.0, min(fuzzMaxOpacity, 0.85))
        fuzzSpeckStrength = max(0.0, min(fuzzSpeckStrength, 2.5))
        fuzzWidthFraction = max(0.02, min(fuzzWidthFraction, 0.30))
        fuzzWidthPixelsClamp = max(2.0, min(fuzzWidthPixelsClamp.lowerBound, 40.0))...max(8.0, min(fuzzWidthPixelsClamp.upperBound, 120.0))

        fuzzChanceThreshold = max(0.0, min(fuzzChanceThreshold, 1.0))
        fuzzChanceTransition = max(0.01, min(fuzzChanceTransition, 1.0))
        fuzzChanceExponent = max(0.10, min(fuzzChanceExponent, 4.0))
        fuzzChanceFloor = max(0.0, min(fuzzChanceFloor, 1.0))
        fuzzChanceMinStrength = max(0.0, min(fuzzChanceMinStrength, 1.0))

        fuzzTailMinutes = max(0.0, min(fuzzTailMinutes, 20.0))
        fuzzLowHeightPower = max(0.05, min(fuzzLowHeightPower, 4.0))
        fuzzLowHeightBoost = max(0.0, min(fuzzLowHeightBoost, 3.0))
        fuzzEdgeWindowPx = max(0.0, min(fuzzEdgeWindowPx, 60.0))

        // Texture fuzz clamps.
        fuzzTextureTilePixels = max(64, min(fuzzTextureTilePixels, 512))
        fuzzTextureGradientStops = max(8, min(fuzzTextureGradientStops, 64))
        fuzzTextureInnerBandMultiplier = max(0.10, min(fuzzTextureInnerBandMultiplier, 6.0))
        fuzzTextureOuterBandMultiplier = max(fuzzTextureInnerBandMultiplier, min(fuzzTextureOuterBandMultiplier, 10.0))
        fuzzTextureInnerOpacityMultiplier = max(0.0, min(fuzzTextureInnerOpacityMultiplier, 2.0))
        fuzzTextureOuterOpacityMultiplier = max(0.0, min(fuzzTextureOuterOpacityMultiplier, 2.0))
        fuzzStrengthExponent = max(0.05, min(fuzzStrengthExponent, 2.0))
        fuzzStrengthGain = max(0.0, min(fuzzStrengthGain, 5.0))
        fuzzOuterDustPassCount = max(0, min(fuzzOuterDustPassCount, 4))
        fuzzOuterDustPassCountInAppExtension = max(0, min(fuzzOuterDustPassCountInAppExtension, 4))

        // Erosion clamps.
        fuzzErodeStrength = max(0.0, min(fuzzErodeStrength, 1.5))
        fuzzErodeStrokeWidthFactor = max(0.05, min(fuzzErodeStrokeWidthFactor, 1.5))
        fuzzErodeEdgePower = max(0.2, min(fuzzErodeEdgePower, 4.0))

        // Haze clamps.
        fuzzHazeStrength = max(0.0, min(fuzzHazeStrength, 1.0))
        fuzzHazeBlurFractionOfBand = max(0.0, min(fuzzHazeBlurFractionOfBand, 1.0))
        fuzzHazeStrokeWidthFactor = max(0.1, min(fuzzHazeStrokeWidthFactor, 3.0))
    }
}
