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

        // Horizon certainty falloff.
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

        let cfg: RainForecastSurfaceConfiguration = {
            var c = RainForecastSurfaceConfiguration()

            c.backgroundColor = .black
            c.backgroundOpacity = 0.0

            // Leave headroom so peaks do not “hit the ceiling”.
            c.intensityCap = max(maxIntensityMMPerHour, 0.000_001)
            c.intensityCapHeadroomFraction = 0.18

            c.wetThreshold = WeatherNowcast.wetIntensityThresholdMMPerHour
            c.intensityEasingPower = 0.75

            // Geometry: leave negative space above.
            c.surfaceHeightScale = 0.78
            c.minVisibleHeightFraction = 0.030
            c.geometrySmoothingPasses = 1
            c.baselineYFraction = 0.82
            c.edgeInsetFraction = 0.00

            // Remove start/end cliffs even when rain begins/ends at chart edges.
            c.segmentEdgeTaperSamples = 9
            c.segmentEdgeTaperPower = 1.35

            // Baseline
            c.baselineColor = accent
            c.baselineOpacity = 0.14
            c.baselineLineWidth = onePixel
            c.baselineInsetPoints = 0.0
            c.baselineSoftWidthMultiplier = 3.0
            c.baselineSoftOpacityMultiplier = 0.34

            // Fill depth (dark base -> bright crest)
            c.fillBottomColor = accent
            c.fillTopColor = accent
            c.fillBottomOpacity = 0.16
            c.fillTopOpacity = 0.92

            c.startEaseMinutes = 6
            c.endFadeMinutes = 10
            c.endFadeFloor = 0.0

            // Atmospheric diffusion band: uncertainty-aware, ridge-attached, fades upward.
            c.fuzzEnabled = true
            c.diffusionLayers = WidgetWeaverRuntime.isRunningInAppExtension ? 54 : 66

            // Thickness bounds
            c.diffusionMinRadiusPoints = 1.2
            c.diffusionMaxRadiusPoints = 70.0
            c.diffusionMaxRadiusFractionOfHeight = 0.52

            // Uncertainty mapping
            c.diffusionRadiusUncertaintyPower = 0.78
            c.diffusionStrengthMax = 0.92
            c.diffusionStrengthMinUncertainTerm = 0.12
            c.diffusionStrengthUncertaintyPower = 0.92
            c.diffusionFalloffPower = 1.75

            // Edge softening within segments
            c.diffusionEdgeSofteningWidth = 0.10

            // Jitter adds organic variation without streaks (true 2D noise is from dots)
            c.diffusionJitterAmplitudePoints = WidgetWeaverRuntime.isRunningInAppExtension ? 2.0 : 2.4

            // Dots are the diffusion texture (no vertical streaking).
            c.fuzzDotsEnabled = true
            c.fuzzDotsPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 18 : 24
            c.fuzzGlobalBlurRadiusPoints = WidgetWeaverRuntime.isRunningInAppExtension ? 1.00 : 1.15

            // Optional continuous haze body stroke (kept subtle)
            c.fuzzLineWidthMultiplier = 0.22

            // Crest highlight (adds depth without an outline)
            c.crestEnabled = true
            c.crestColor = accent
            c.crestMaxOpacity = 0.22
            c.crestLineWidthPoints = max(onePixel, onePixel * 1.35)
            c.crestBlurRadiusPoints = WidgetWeaverRuntime.isRunningInAppExtension ? 1.10 : 1.25
            c.crestPeakBoost = 0.55

            // Turn off any legacy internal texture
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

            // Glow: subtle, ridge-derived, does not create a second silhouette
            c.glowEnabled = true
            c.glowColor = accent
            c.glowLayers = 6
            c.glowMaxAlpha = 0.08
            c.glowFalloffPower = 1.75
            c.glowCertaintyPower = 1.5
            c.glowMaxRadiusPoints = 4.5
            c.glowMaxRadiusFractionOfHeight = 0.075

            return c
        }()

        return RainForecastSurfaceView(
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
