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
                // Black stage for mockup matching.
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

        let certainties: [Double] = samples.map { s in
            Self.clamp01(s.chance01)
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        let cfg = RainForecastSurfaceConfiguration(
            backgroundColor: .black,
            backgroundOpacity: 1.0,

            intensityCap: max(maxIntensityMMPerHour, 0.000_001),
            wetThreshold: WeatherNowcast.wetIntensityThresholdMMPerHour,
            intensityEasingPower: 0.75,
            minVisibleHeightFraction: 0.030,

            baselineYFraction: 0.82,
            edgeInsetFraction: 0.00,

            baselineColor: accent,
            baselineOpacity: 0.11,                // dropped vs previous
            baselineLineWidth: onePixel,
            baselineInsetPoints: 6.0,             // aligns with internal padding
            baselineSoftWidthMultiplier: 2.6,
            baselineSoftOpacityMultiplier: 0.32,

            fillBottomColor: accent,
            fillTopColor: accent,
            fillBottomOpacity: 0.18,
            fillTopOpacity: 0.92,

            startEaseMinutes: 3,
            endFadeMinutes: 10,
            endFadeFloor: 0.20,

            diffusionMinRadiusPoints: 1.6,
            diffusionMaxRadiusPoints: 18.0,
            diffusionMinRadiusFractionOfHeight: 0.030,
            diffusionMaxRadiusFractionOfHeight: 0.34,
            diffusionLayers: 24,                  // lighter than 32 for widget reliability

            diffusionMaxAlpha: 1.0,
            diffusionBandFalloffPower: 2.10,
            diffusionEdgeAlphaFloor: 0.02,

            diffusionRadiusUncertaintyPower: 1.4,
            diffusionStrengthUncertaintyPower: 1.2,
            diffusionStrengthMinMultiplier: 0.25,
            diffusionStrengthMaxMultiplier: 1.0,

            glowEnabled: true,
            glowColor: accent,
            glowMaxRadiusPoints: 2.8,
            glowMaxRadiusFractionOfHeight: 0.075,
            glowLayers: 5,
            glowMaxAlpha: 0.14,
            glowFalloffPower: 1.75,
            glowCertaintyPower: 1.6
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

    private static func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }
}
