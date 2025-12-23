//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Nowcast chart using RainForecastSurfaceView.
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

        // chance01 is treated as certainty for fuzz:
        // - certainty 1.0 => minimal fuzz
        // - certainty 0.0 => maximum fuzz
        let certainties: [Double] = samples.map { s in
            Self.clamp01(s.chance01)
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        // Tuning targets vs mock:
        // - stronger internal streak texture
        // - fuzz/spray above the top edge scales with (1 - chance)
        // - glow remains tight (no “stroke” outline)
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

            baselineColor: accent,
            baselineOpacity: 0.085,
            baselineLineWidth: onePixel,
            baselineInsetPoints: 6.0,
            baselineSoftWidthMultiplier: 2.6,
            baselineSoftOpacityMultiplier: 0.26,

            fillBottomColor: accent,
            fillTopColor: accent,
            fillBottomOpacity: 0.18,
            fillTopOpacity: 0.92,

            startEaseMinutes: 6,
            endFadeMinutes: 10,
            endFadeFloor: 0.0,

            diffusionLayers: 30,
            diffusionFalloffPower: 2.2,

            diffusionMinRadiusPoints: 1.8,
            diffusionMaxRadiusPoints: 24.0,
            diffusionMinRadiusFractionOfHeight: 0.030,
            diffusionMaxRadiusFractionOfHeight: 0.40,
            diffusionRadiusUncertaintyPower: 1.25,

            diffusionStrengthMax: 0.78,
            diffusionStrengthMinUncertainTerm: 0.32,
            diffusionStrengthUncertaintyPower: 1.10,

            diffusionDrizzleThreshold: 0.10,
            diffusionLowIntensityGateMin: 0.55,

            diffusionLightRainMeanThreshold: 0.18,
            diffusionLightRainMaxRadiusScale: 0.85,
            diffusionLightRainStrengthScale: 0.90,

            diffusionStopStride: 2,
            diffusionJitterAmplitudePoints: 0.35,
            diffusionEdgeSofteningWidth: 0.08,

            textureEnabled: true,
            textureMaxAlpha: 0.26,
            textureMinAlpha: 0.05,
            textureIntensityPower: 0.70,
            textureUncertaintyAlphaBoost: 0.45,
            textureStreaksMin: 1,
            textureStreaksMax: 3,
            textureLineWidthMultiplier: 0.70,
            textureBlurRadiusPoints: 0.65,
            textureTopInsetFractionOfHeight: 0.02,

            fuzzEnabled: true,
            fuzzGlobalBlurRadiusPoints: 1.15,
            fuzzLineWidthMultiplier: 0.70,
            fuzzLengthMultiplier: 1.20,
            fuzzDotsEnabled: true,
            fuzzDotsPerSampleMax: 3,

            glowEnabled: true,
            glowColor: accent,
            glowLayers: 6,
            glowMaxAlpha: 0.24,
            glowFalloffPower: 1.75,
            glowCertaintyPower: 1.6,
            glowMaxRadiusPoints: 4.0,
            glowMaxRadiusFractionOfHeight: 0.085
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
                out.append(Sample(intensityMMPerHour: 0.0, chance01: 0.0))
            }
        }

        return out
    }

    static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }
}
