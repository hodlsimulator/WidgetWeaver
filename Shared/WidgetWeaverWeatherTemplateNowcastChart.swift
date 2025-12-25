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
#if canImport(WidgetKit)
import WidgetKit
#endif

struct WeatherNowcastChart: View {
    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool

    var body: some View {
        let topInset: CGFloat = 10
        let bottomInset: CGFloat = 10
        let labelAreaHeight: CGFloat = showAxisLabels ? 18 : 0

        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(1.0))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(spacing: 0) {
                if points.isEmpty {
                    Spacer(minLength: 0)
                    Text("—")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                } else {
                    WeatherNowcastSurfacePlot(
                        samples: WeatherNowcastSurfacePlot.samples(from: points, targetMinutes: 60),
                        maxIntensityMMPerHour: maxIntensityMMPerHour,
                        accent: accent
                    )
                    .padding(.horizontal, 10)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if showAxisLabels {
                    WeatherNowcastAxisLabels()
                        .padding(.horizontal, 12)
                        .frame(height: labelAreaHeight)
                }
            }
        }
    }
}

private struct WeatherNowcastAxisLabels: View {
    var body: some View {
        HStack {
            Text("Now")
            Spacer(minLength: 0)
            Text("60m")
        }
        .font(.system(size: 11, weight: .medium, design: .rounded))
        .foregroundColor(.white.opacity(0.55))
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
    #if canImport(WidgetKit)
    @Environment(\.widgetFamily) private var widgetFamily
    #endif

    private enum FamilyKind {
        case large
        case medium
    }

    private var familyKind: FamilyKind {
        #if canImport(WidgetKit)
        switch widgetFamily {
        case .systemMedium:
            return .medium
        case .systemLarge:
            return .large
        default:
            return .large
        }
        #else
        return .large
        #endif
    }

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
            let chance = clamp01(s.chance01)
            let t = (n <= 1) ? 0.0 : (Double(idx) / Double(n - 1))
            let u = clamp01((t - horizonStart) / max(0.000_001, (1.0 - horizonStart)))
            let hs = RainSurfaceMath.smoothstep01(u)
            let horizonFactor = lerp(1.0, horizonEndCertainty, hs)
            return clamp01(chance * horizonFactor)
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        let cfg: RainForecastSurfaceConfiguration = {
            var c = RainForecastSurfaceConfiguration()

            // Height + remap per family (plot-rect based inside renderer)
            switch familyKind {
            case .large:
                c.maxCoreHeightFractionOfPlotHeight = 0.37
                c.intensityEasingPower = 0.75
                c.ridgeThicknessPoints = 4.0
                c.ridgeBlurFractionOfPlotHeight = 0.11

                c.shellAboveThicknessPoints = 10.0
                c.shellNoiseAmount = 0.28

                c.mistHeightPoints = 95.0
                c.mistHeightFractionOfPlotHeight = 0.85

                c.bloomBlurFractionOfPlotHeight = 0.54
                c.bloomBandHeightFractionOfPlotHeight = 0.72

                c.baselineOpacity = 0.10

            case .medium:
                c.maxCoreHeightFractionOfPlotHeight = 0.62
                c.intensityEasingPower = 0.60
                c.ridgeThicknessPoints = 3.0
                c.ridgeBlurFractionOfPlotHeight = 0.13

                c.shellAboveThicknessPoints = 7.0
                c.shellNoiseAmount = 0.18

                c.mistHeightPoints = 50.0
                c.mistHeightFractionOfPlotHeight = 0.78

                c.bloomBlurFractionOfPlotHeight = 0.40
                c.bloomBandHeightFractionOfPlotHeight = 0.62

                c.baselineOpacity = 0.08
            }

            c.intensityCap = max(maxIntensityMMPerHour, 0.000_001)
            c.wetThreshold = WeatherNowcast.wetIntensityThresholdMMPerHour

            c.baselineYFraction = 0.82
            c.edgeInsetFraction = 0.00
            c.minVisibleHeightFraction = 0.022
            c.geometrySmoothingPasses = 1

            // End tapers are ALPHA ONLY
            c.wetRegionFadeInSamples = 9
            c.wetRegionFadeOutSamples = 14

            // Segment settling (geometry tails)
            c.geometryTailInSamples = 6
            c.geometryTailOutSamples = 12
            c.geometryTailPower = 2.25

            // Baseline behind fill (reduced prominence)
            c.baselineColor = accent
            c.baselineLineWidth = onePixel
            c.baselineInsetPoints = 0.0
            c.baselineSoftWidthMultiplier = 2.6
            c.baselineSoftOpacityMultiplier = 0.22

            // Core depth (smooth)
            c.fillBottomColor = Color(red: 0.02, green: 0.04, blue: 0.09)
            c.fillMidColor = Color(red: 0.05, green: 0.10, blue: 0.22)
            c.fillTopColor = accent
            c.fillBottomOpacity = 0.90
            c.fillMidOpacity = 0.55
            c.fillTopOpacity = 0.38
            c.crestLiftEnabled = true
            c.crestLiftMaxOpacity = 0.10

            // Ridge highlight
            c.ridgeEnabled = true
            c.ridgeColor = Color(red: 0.78, green: 0.95, blue: 1.0)
            c.ridgeMaxOpacity = 0.22
            c.ridgePeakBoost = 0.55

            // Bloom
            c.bloomEnabled = true
            c.bloomColor = accent
            c.bloomMaxOpacity = 0.06

            // Shell fuzz (boundary-attached; texture only here)
            c.shellEnabled = true
            c.shellColor = Color(red: 0.70, green: 0.92, blue: 1.0)
            c.shellMaxOpacity = 0.15
            c.shellInsideThicknessPoints = 2.0
            c.shellBlurFractionOfPlotHeight = 0.030
            c.shellPuffsPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 4 : 5
            c.shellPuffMinRadiusPoints = 0.7
            c.shellPuffMaxRadiusPoints = 2.8

            // Mist
            c.mistEnabled = true
            c.mistColor = accent
            c.mistMaxOpacity = 0.18
            c.mistFalloffPower = 1.70
            c.mistNoiseEnabled = true
            c.mistNoiseInfluence = 0.25
            c.mistPuffsPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 10 : 12
            c.mistFineGrainPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 6 : 8
            c.mistParticleMinRadiusPoints = 0.7
            c.mistParticleMaxRadiusPoints = 3.6
            c.mistFineParticleMinRadiusPoints = 0.35
            c.mistFineParticleMaxRadiusPoints = 1.05

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

    private func clamp01(_ v: Double) -> Double {
        max(0.0, min(1.0, v))
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}
