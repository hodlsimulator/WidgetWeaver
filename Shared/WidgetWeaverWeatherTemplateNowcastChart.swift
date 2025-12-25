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

            // Step 1: scale cap first
            c.maxCoreHeightFractionOfPlotHeight = 0.30
            c.maxCoreHeightPoints = 0.0

            // Value shaping (gamma)
            c.intensityCap = max(maxIntensityMMPerHour, 0.000_001)
            c.wetThreshold = WeatherNowcast.wetIntensityThresholdMMPerHour
            c.intensityEasingPower = 0.70

            // Baseline placement
            c.baselineYFraction = 0.82
            c.edgeInsetFraction = 0.00
            c.minVisibleHeightFraction = 0.025
            c.geometrySmoothingPasses = 1

            // Step 2: wet-region taper (applies to all layers)
            c.wetRegionFadeInSamples = 8
            c.wetRegionFadeOutSamples = 14
            c.segmentEdgeTaperSamples = 5
            c.segmentEdgeTaperPower = 1.35

            // Baseline
            c.baselineColor = accent
            c.baselineOpacity = 0.14
            c.baselineLineWidth = onePixel
            c.baselineInsetPoints = 0.0
            c.baselineSoftWidthMultiplier = 3.0
            c.baselineSoftOpacityMultiplier = 0.34

            // Step 8: core fill depth (dark base + lifted crest)
            c.fillBottomColor = Color(red: 0.05, green: 0.11, blue: 0.25)
            c.fillTopColor = accent
            c.fillBottomOpacity = 0.22
            c.fillTopOpacity = 0.72

            // Step 4: ridge highlight
            c.ridgeEnabled = true
            c.ridgeColor = Color(red: 0.82, green: 0.94, blue: 1.0)
            c.ridgeMaxOpacity = 0.22
            c.ridgeThicknessPoints = max(onePixel, onePixel * 3.5)  // ~2–6 px in practice
            c.ridgeBlurRadiusPoints = WidgetWeaverRuntime.isRunningInAppExtension ? 9.0 : 11.0
            c.ridgePeakBoost = 0.55

            // Step 5–7: mist band (bounded, clipped, textured)
            c.mistEnabled = true
            c.mistColor = accent
            c.mistMaxOpacity = 0.18
            c.mistHeightPoints = WidgetWeaverRuntime.isRunningInAppExtension ? 56.0 : 62.0
            c.mistHeightFractionOfPlotHeight = 0.55
            c.mistBlurRadiusPoints = 0.0 // auto

            c.mistFalloffPower = 1.70
            c.mistEdgeSofteningWidth = 0.10

            c.mistNoiseEnabled = true
            c.mistNoiseInfluence = 0.25

            c.mistPuffsPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 10 : 12
            c.mistFineGrainPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 6 : 8

            c.mistParticleMinRadiusPoints = 0.7
            c.mistParticleMaxRadiusPoints = 3.6
            c.mistFineParticleMinRadiusPoints = 0.35
            c.mistFineParticleMaxRadiusPoints = 1.05

            // Controlled glow (optional)
            c.glowEnabled = true
            c.glowColor = accent
            c.glowLayers = 6
            c.glowMaxAlpha = 0.06
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
