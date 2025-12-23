//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Modularised out of WidgetWeaverWeatherTemplateComponents.swift
//  Replaced “Core + Halo + Stroke” with a single forecast-surface ribbon:
//  - One filled band
//  - Inward diffusion near the top edge controlled by uncertainty
//  - No halo envelope, no top stroke
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
                WeatherGlassBackground(cornerRadius: 10)

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
    /// One sample per minute (target: 60).
    /// Wet/dry is driven only by intensity via `WeatherNowcast.isWet`.
    struct Sample: Hashable {
        var intensityMMPerHour: Double
        var chance01: Double
    }

    let samples: [Sample] // exactly 60 samples, padded
    let maxIntensityMMPerHour: Double
    let accent: Color

    var body: some View {
        // Enforce the “wet definition contract”:
        // if intensity is considered dry, force it to 0 so the renderer cannot draw wet pixels.
        let intensities: [Double] = samples.map { s in
            let i = max(0.0, s.intensityMMPerHour)
            return WeatherNowcast.isWet(intensityMMPerHour: i) ? i : 0.0
        }

        let certainties: [Double] = samples.map { s in
            Self.clamp01(s.chance01)
        }

        let cfg = RainForecastSurfaceConfiguration(
            intensityCap: max(maxIntensityMMPerHour, 0.000_001),
            wetThreshold: WeatherNowcast.wetIntensityThresholdMMPerHour,

            intensityEasingPower: 0.75,
            minVisibleHeightFraction: 0.065,

            baselineYFraction: 0.82,
            edgeInsetFraction: 0.00,

            baselineColor: .white,
            baselineOpacity: 0.12,
            baselineLineWidth: 1,

            fillBottomColor: accent,
            fillTopColor: accent,
            fillBottomOpacity: 0.18,
            fillTopOpacity: 0.72,

            diffusionColor: accent,
            diffusionMinRadiusPoints: 1.5,
            diffusionMaxRadiusPoints: 18.0,
            diffusionMinRadiusFractionOfHeight: 0.02,
            diffusionMaxRadiusFractionOfHeight: 0.30,
            diffusionLayers: 12,
            diffusionMaxAlpha: 0.22,
            diffusionFalloffPower: 2.0,
            diffusionUncertaintyAlphaFloor: 0.15,

            glowEnabled: true,
            glowColor: accent,
            glowMaxRadiusPoints: 2.75,
            glowMaxRadiusFractionOfHeight: 0.06,
            glowLayers: 4,
            glowMaxAlpha: 0.08,
            glowFalloffPower: 1.7,
            glowCertaintyPower: 1.25
        )

        RainForecastSurfaceView(
            intensities: intensities,
            certainties: certainties,
            configuration: cfg
        )
    }

    // MARK: - Data shaping

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

    private static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }
}
