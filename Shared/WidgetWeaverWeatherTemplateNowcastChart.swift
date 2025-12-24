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
        let intensities: [Double] = samples.map { s in
            let i = max(0.0, s.intensityMMPerHour)
            return WeatherNowcast.isWet(intensityMMPerHour: i) ? i : 0.0
        }

        // Certainty must allow both “smooth” and “fuzzy” regions to coexist.
        // Chance alone is frequently near-constant during active rain, so a horizon falloff
        // is applied to create lower certainty further out in time.
        let n = max(1, samples.count)
        let horizonStart = 0.10
        let horizonEndCertainty = 0.45

        let certainties: [Double] = samples.enumerated().map { idx, s in
            let chance = Self.clamp01(s.chance01)
            let t = (n <= 1) ? 0.0 : (Double(idx) / Double(n - 1))
            let u = Self.clamp01((t - horizonStart) / max(0.000_001, (1.0 - horizonStart)))
            let hs = Self.smoothstep01(u)
            let horizonFactor = Self.lerp(1.0, horizonEndCertainty, hs)
            return Self.clamp01(chance * horizonFactor)
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        // Widget budgets are tight; diffusion thickness comes from radius/strength, not just K.
        let diffusionLayerCount = WidgetWeaverRuntime.isRunningInAppExtension ? 32 : 44

        let cfg = RainForecastSurfaceConfiguration(
            backgroundColor: .black,
            backgroundOpacity: 0.0,

            intensityCap: max(maxIntensityMMPerHour, 0.000_001),
            wetThreshold: WeatherNowcast.wetIntensityThresholdMMPerHour,
            intensityEasingPower: 0.75,
            minVisibleHeightFraction: 0.030,

            geometrySmoothingPasses: 1,
            baselineYFraction: 0.82,
            edgeInsetFraction: 0.00,

            // Baseline matches mockup: brighter + full width + clean.
            baselineColor: accent,
            baselineOpacity: 0.22,
            baselineLineWidth: onePixel,
            baselineInsetPoints: 0.0,
            baselineSoftWidthMultiplier: 3.0,
            baselineSoftOpacityMultiplier: 0.45,

            fillBottomColor: accent,
            fillTopColor: accent,
            fillBottomOpacity: 0.14,
            fillTopOpacity: 0.94,

            startEaseMinutes: 6,
            endFadeMinutes: 10,
            endFadeFloor: 0.0,

            // Diffusion: extreme, “surface haze” tuning.
            diffusionLayers: diffusionLayerCount,
            diffusionFalloffPower: 1.65,

            diffusionMinRadiusPoints: 1.0,     // px-like
            diffusionMaxRadiusPoints: 140.0,   // clamp (px-like)
            diffusionMinRadiusFractionOfHeight: 0.0,
            diffusionMaxRadiusFractionOfHeight: 0.75,
            diffusionRadiusUncertaintyPower: 0.55,

            diffusionStrengthMax: 0.92,
            diffusionStrengthMinUncertainTerm: 0.02,
            diffusionStrengthUncertaintyPower: 0.65,

            diffusionDrizzleThreshold: 0.08,
            diffusionLowIntensityGateMin: 0.60,

            diffusionLightRainMeanThreshold: 0.18,
            diffusionLightRainMaxRadiusScale: 0.80,
            diffusionLightRainStrengthScale: 0.85,
            diffusionStopStride: 2,
            diffusionJitterAmplitudePoints: 0.0,
            diffusionEdgeSofteningWidth: 0.10,

            textureEnabled: false,
            textureMaxAlpha: 0.0,
            textureMinAlpha: 0.0,
            textureIntensityPower: 0.70,
            textureUncertaintyAlphaBoost: 0.0,
            textureStreaksMin: 0,
            textureStreaksMax: 0,
            textureLineWidthMultiplier: 0.70,
            textureBlurRadiusPoints: 0.0,
            textureTopInsetFractionOfHeight: 0.02,

            fuzzEnabled: true,
            fuzzGlobalBlurRadiusPoints: 0.0,
            fuzzLineWidthMultiplier: 0.0,
            fuzzLengthMultiplier: 0.0,
            fuzzDotsEnabled: false,
            fuzzDotsPerSampleMax: 0,
            fuzzRidgeEnabled: false,
            fuzzOutsideOnly: false,
            fuzzRidgeCoreRadiusMultiplier: 0.0,
            fuzzRidgeCoreAlphaMultiplier: 0.0,
            fuzzRidgeFeatherRadiusMultiplier: 0.0,
            fuzzRidgeFeatherAlphaMultiplier: 0.0,
            fuzzParticleAlphaMultiplier: 0.0,

            // Glow stays subtle and inward.
            glowEnabled: true,
            glowColor: accent,
            glowLayers: 6,
            glowMaxAlpha: 0.10,
            glowFalloffPower: 1.75,
            glowCertaintyPower: 1.6,
            glowMaxRadiusPoints: 3.8,
            glowMaxRadiusFractionOfHeight: 0.075
        )

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

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        let tt = clamp01(t)
        return a + (b - a) * tt
    }

    private static func smoothstep01(_ u: Double) -> Double {
        let x = clamp01(u)
        return x * x * (3.0 - 2.0 * x)
    }
}
