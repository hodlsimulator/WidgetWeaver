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
        let intensities: [Double] = samples.map { s in
            let i = max(0.0, s.intensityMMPerHour)
            return WeatherNowcast.isWet(intensityMMPerHour: i) ? i : 0.0
        }

        let n = samples.count
        let horizonStart = 0.15
        let horizonEndCertainty = 0.55

        let certainties: [Double] = samples.enumerated().map { idx, s in
            let chance = RainSurfaceMath.clamp01(s.chance01)
            let t = (n <= 1) ? 0.0 : (Double(idx) / Double(n - 1))
            let u = RainSurfaceMath.clamp01((t - horizonStart) / max(0.000_001, (1.0 - horizonStart)))
            let hs = RainSurfaceMath.smoothstep01(u)
            let horizonFactor = RainSurfaceMath.lerp(1.0, horizonEndCertainty, hs)
            return RainSurfaceMath.clamp01(chance * horizonFactor)
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
        let diffusionLayerCount = WidgetWeaverRuntime.isRunningInAppExtension ? 28 : 36

        let cfg: RainForecastSurfaceConfiguration = {
            var c = RainForecastSurfaceConfiguration()

            c.backgroundColor = .black
            c.backgroundOpacity = 0.0

            c.intensityCap = max(maxIntensityMMPerHour, 0.000_001)
            c.wetThreshold = WeatherNowcast.wetIntensityThresholdMMPerHour
            c.intensityEasingPower = 0.75

            c.minVisibleHeightFraction = 0.030
            c.geometrySmoothingPasses = 1
            c.baselineYFraction = 0.82
            c.edgeInsetFraction = 0.00

            // Baseline (mock-like)
            c.baselineColor = accent
            c.baselineOpacity = 0.14
            c.baselineLineWidth = onePixel
            c.baselineInsetPoints = 0.0
            c.baselineSoftWidthMultiplier = 3.0
            c.baselineSoftOpacityMultiplier = 0.34

            // Core ribbon
            c.fillBottomColor = accent
            c.fillTopColor = accent
            c.fillBottomOpacity = 0.16
            c.fillTopOpacity = 0.92

            c.startEaseMinutes = 6
            c.endFadeMinutes = 10
            c.endFadeFloor = 0.0

            // Diffusion (stacked contours; rendered subtractively in RainSurfaceDrawing via destinationOut)
            c.diffusionLayers = diffusionLayerCount
            c.diffusionFalloffPower = 2.2
            c.diffusionMinRadiusPoints = 1.5
            c.diffusionMaxRadiusPoints = 48.0
            c.diffusionMinRadiusFractionOfHeight = 0.0
            c.diffusionMaxRadiusFractionOfHeight = 0.60

            // Key: keep diffusion present unless certainty is extremely high.
            // (Lower exponents => more diffusion at high-but-not-absolute certainty.)
            c.diffusionRadiusUncertaintyPower = 0.80
            c.diffusionStrengthMax = 0.78
            c.diffusionStrengthMinUncertainTerm = 0.00
            c.diffusionStrengthUncertaintyPower = 0.85

            c.diffusionDrizzleThreshold = 0.08
            c.diffusionLowIntensityGateMin = 0.60

            // Key: remove “streaks” by sampling every point + adding a tiny blur to the diffusion mask.
            c.diffusionStopStride = 1
            c.fuzzGlobalBlurRadiusPoints = WidgetWeaverRuntime.isRunningInAppExtension ? 1.0 : 1.25

            c.diffusionJitterAmplitudePoints = 0.0
            c.diffusionEdgeSofteningWidth = 0.10

            // No internal texture
            c.textureEnabled = false
            c.textureMaxAlpha = 0.0
            c.textureMinAlpha = 0.0
            c.textureIntensityPower = 0.70
            c.textureUncertaintyAlphaBoost = 0.0
            c.textureStreaksMin = 0
            c.textureStreaksMax = 0
            c.textureLineWidthMultiplier = 0.70
            c.textureBlurRadiusPoints = 0.0
            c.textureTopInsetFractionOfHeight = 0.02

            // Diffusion enable switch
            c.fuzzEnabled = true
            c.fuzzLineWidthMultiplier = 0.0
            c.fuzzLengthMultiplier = 0.0
            c.fuzzDotsEnabled = false
            c.fuzzDotsPerSampleMax = 0
            c.fuzzRidgeEnabled = false
            c.fuzzOutsideOnly = false
            c.fuzzRidgeCoreRadiusMultiplier = 0.0
            c.fuzzRidgeCoreAlphaMultiplier = 0.0
            c.fuzzRidgeFeatherRadiusMultiplier = 0.0
            c.fuzzRidgeFeatherAlphaMultiplier = 0.0
            c.fuzzParticleAlphaMultiplier = 0.0

            // Glow (kept subtle)
            c.glowEnabled = true
            c.glowColor = accent
            c.glowLayers = 6
            c.glowMaxAlpha = 0.10
            c.glowFalloffPower = 1.75
            c.glowCertaintyPower = 1.5
            c.glowMaxRadiusPoints = 4.5
            c.glowMaxRadiusFractionOfHeight = 0.075

            return c
        }()

        RainForecastSurfaceView(intensities: intensities, certainties: certainties, configuration: cfg)
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
