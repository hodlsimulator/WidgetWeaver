//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Nowcast chart using RainForecastSurfaceView (filled ribbon + inward diffused top edge).
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
    struct Sample: Hashable {
        var intensityMMPerHour: Double
        var chance01: Double
    }

    let samples: [Sample]
    let maxIntensityMMPerHour: Double
    let accent: Color

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        // Enforce wet definition: dry intensities render nothing above the baseline.
        let intensities: [Double] = samples.map { s in
            let i = max(0.0, s.intensityMMPerHour)
            return WeatherNowcast.isWet(intensityMMPerHour: i) ? i : 0.0
        }

        // chance01 is treated as certainty (1 = very certain, 0 = very uncertain).
        let certainties: [Double] = samples.map { s in
            Self.clamp01(s.chance01)
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        // Tuned for a visibly diffused top edge:
        // - diffusionMaxAlpha is 1.0 because the cap is part of the fill (not an overlay).
        // - diffusionUncertaintyAlphaFloor controls how “present” the very top edge is.
        let cfg = RainForecastSurfaceConfiguration(
            intensityCap: max(maxIntensityMMPerHour, 0.000_001),
            wetThreshold: WeatherNowcast.wetIntensityThresholdMMPerHour,

            intensityEasingPower: 0.75,
            minVisibleHeightFraction: 0.065,

            baselineYFraction: 0.82,
            edgeInsetFraction: 0.00,

            baselineColor: .white,
            baselineOpacity: 0.12,
            baselineLineWidth: onePixel,

            fillBottomColor: accent,
            fillTopColor: accent,
            fillBottomOpacity: 0.14,
            fillTopOpacity: 0.62,

            diffusionMinRadiusPoints: 3.0,
            diffusionMaxRadiusPoints: 18.0,
            diffusionMinRadiusFractionOfHeight: 0.04,
            diffusionMaxRadiusFractionOfHeight: 0.35,
            diffusionLayers: 24,
            diffusionMaxAlpha: 1.0,
            diffusionFalloffPower: 1.75,
            diffusionUncertaintyAlphaFloor: 0.10,

            glowEnabled: true,
            glowColor: accent,
            glowMaxRadiusPoints: 2.6,
            glowMaxRadiusFractionOfHeight: 0.06,
            glowLayers: 4,
            glowMaxAlpha: 0.10,
            glowFalloffPower: 1.65,
            glowCertaintyPower: 1.25
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
