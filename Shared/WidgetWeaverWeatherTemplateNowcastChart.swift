//
// WidgetWeaverWeatherTemplateNowcastChart.swift
// WidgetWeaver
//
// Created by . . on 12/23/25.
//
// Nowcast chart using RainForecastSurfaceView.
//

import Foundation
import SwiftUI

struct WeatherNowcastChart: View {
    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool

    var body: some View {
        GeometryReader { _ in
            let plotInset: CGFloat = 10

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(1.0))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                if points.isEmpty {
                    Text("—")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    WeatherNowcastSurfacePlot(
                        samples: WeatherNowcastSurfacePlot.samples(from: points, targetMinutes: 60),
                        maxIntensityMMPerHour: maxIntensityMMPerHour,
                        accent: accent
                    )
                    .padding(.horizontal, plotInset)
                    .padding(.vertical, plotInset)
                }

                if showAxisLabels {
                    WeatherNowcastAxisLabels()
                }
            }
        }
    }
}

private struct WeatherNowcastAxisLabels: View {
    var body: some View {
        VStack {
            Spacer(minLength: 0)

            HStack {
                Text("Now")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text("60m")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
    }
}

private struct WeatherNowcastSurfacePlot: View {
    struct Sample: Hashable {
        var intensityMMPerHour: Double
        var chance01: Double
    }

    let samples: [Sample]
    let maxIntensityMMPerHour: Double
    let accent: Color

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Wet contract: dry intensities render nothing above baseline.
        let intensities: [Double] = samples.map { s in
            let i = max(0.0, s.intensityMMPerHour)
            return WeatherNowcast.isWet(intensityMMPerHour: i) ? i : 0.0
        }

        // Certainty model:
        // - base certainty from chance01
        // - plus a gentle horizon falloff so the chart can show both surfaces (smooth near-term, fuzzy further out)
        let n = samples.count
        let horizonStart = 0.15         // start easing certainty down after ~9 minutes
        let horizonEndCertainty = 0.55  // certainty floor at the horizon

        let certainties: [Double] = samples.enumerated().map { idx, s in
            let chance = RainSurfaceMath.clamp01(s.chance01)
            let t = (n <= 1) ? 0.0 : (Double(idx) / Double(n - 1))
            let u = RainSurfaceMath.clamp01((t - horizonStart) / max(0.000_001, (1.0 - horizonStart)))
            let hs = RainSurfaceMath.smoothstep01(u)
            let horizonFactor = RainSurfaceMath.lerp(1.0, horizonEndCertainty, hs)
            return RainSurfaceMath.clamp01(chance * horizonFactor)
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        // Widgets have tight render budgets; avoid extreme layer counts in the extension.
        let diffusionLayerCount = WidgetWeaverRuntime.isRunningInAppExtension ? 28 : 36

        // Configuration tuned for:
        // - one ribbon (no 2nd band)
        // - fuzzy top only when certainty is low (via destinationOut diffusion)
        // - baseline visible across the whole chart
        var cfg = RainForecastSurfaceConfiguration()

        cfg.backgroundColor = .black
        cfg.backgroundOpacity = 0.0

        cfg.intensityCap = max(maxIntensityMMPerHour, 0.000_001)
        cfg.wetThreshold = WeatherNowcast.wetIntensityThresholdMMPerHour
        cfg.intensityEasingPower = 0.75
        cfg.minVisibleHeightFraction = 0.030

        cfg.geometrySmoothingPasses = 1
        cfg.baselineYFraction = 0.82
        cfg.edgeInsetFraction = 0.00

        // Baseline (match mock: thin, clean, visible even under fill)
        cfg.baselineColor = accent
        cfg.baselineOpacity = 0.14
        cfg.baselineLineWidth = onePixel
        cfg.baselineInsetPoints = 0.0
        cfg.baselineSoftWidthMultiplier = 3.0
        cfg.baselineSoftOpacityMultiplier = 0.34

        // Core ribbon
        cfg.fillBottomColor = accent
        cfg.fillTopColor = accent
        cfg.fillBottomOpacity = 0.16
        cfg.fillTopOpacity = 0.92

        cfg.startEaseMinutes = 6
        cfg.endFadeMinutes = 10
        cfg.endFadeFloor = 0.0

        // Layer 3: diffusion (stacked alpha, but rendered as alpha erosion to black)
        cfg.diffusionLayers = diffusionLayerCount
        cfg.diffusionFalloffPower = 2.2

        cfg.diffusionMinRadiusPoints = 1.5        // treated as px in renderer
        cfg.diffusionMaxRadiusPoints = 48.0       // treated as px in renderer (clamp max)
        cfg.diffusionMinRadiusFractionOfHeight = 0.0
        cfg.diffusionMaxRadiusFractionOfHeight = 0.60
        cfg.diffusionRadiusUncertaintyPower = 1.15

        cfg.diffusionStrengthMax = 0.78
        cfg.diffusionStrengthMinUncertainTerm = 0.00
        cfg.diffusionStrengthUncertaintyPower = 1.05

        cfg.diffusionDrizzleThreshold = 0.08
        cfg.diffusionLowIntensityGateMin = 0.60

        cfg.diffusionStopStride = 2
        cfg.diffusionJitterAmplitudePoints = 0.0
        cfg.diffusionEdgeSofteningWidth = 0.10

        // No internal texture
        cfg.textureEnabled = false
        cfg.textureMaxAlpha = 0.0
        cfg.textureMinAlpha = 0.0
        cfg.textureIntensityPower = 0.70
        cfg.textureUncertaintyAlphaBoost = 0.0
        cfg.textureStreaksMin = 0
        cfg.textureStreaksMax = 0
        cfg.textureLineWidthMultiplier = 0.70
        cfg.textureBlurRadiusPoints = 0.0
        cfg.textureTopInsetFractionOfHeight = 0.02

        // Use fuzzEnabled as the diffusion enable switch; no particles/dots
        cfg.fuzzEnabled = true
        cfg.fuzzGlobalBlurRadiusPoints = 0.0
        cfg.fuzzLineWidthMultiplier = 0.0
        cfg.fuzzLengthMultiplier = 0.0
        cfg.fuzzDotsEnabled = false
        cfg.fuzzDotsPerSampleMax = 0
        cfg.fuzzRidgeEnabled = false
        cfg.fuzzOutsideOnly = false
        cfg.fuzzRidgeCoreRadiusMultiplier = 0.0
        cfg.fuzzRidgeCoreAlphaMultiplier = 0.0
        cfg.fuzzRidgeFeatherRadiusMultiplier = 0.0
        cfg.fuzzRidgeFeatherAlphaMultiplier = 0.0
        cfg.fuzzParticleAlphaMultiplier = 0.0

        // Layer 4: subtle inward glow (kept tight and clipped)
        cfg.glowEnabled = true
        cfg.glowColor = accent
        cfg.glowLayers = 6
        cfg.glowMaxAlpha = 0.10
        cfg.glowFalloffPower = 1.75
        cfg.glowCertaintyPower = 1.5
        cfg.glowMaxRadiusPoints = 4.5            // treated as px in renderer
        cfg.glowMaxRadiusFractionOfHeight = 0.075

        RainForecastSurfaceView(
            intensities: intensities,
            certainties: certainties,
            configuration: cfg
        )
    }

    static func samples(from points: [WidgetWeaverWeatherMinutePoint], targetMinutes: Int) -> [Sample] {
        let clipped = Array(points.prefix(targetMinutes))

        var out: [Sample] = []
        out.reserveCapacity(targetMinutes)

        for p in clipped {
            out.append(
                Sample(
                    intensityMMPerHour: max(0.0, p.precipitationIntensityMMPerHour ?? 0.0),
                    chance01: clamp01(p.precipitationChance01 ?? 0.0)
                )
            )
        }

        if out.count < targetMinutes {
            let missing = targetMinutes - out.count
            for _ in 0..<missing {
                out.append(
                    Sample(
                        intensityMMPerHour: 0.0,
                        chance01: 0.0
                    )
                )
            }
        }

        return out
    }

    private static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }
}
