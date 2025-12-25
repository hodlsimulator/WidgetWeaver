//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  Nowcast chart (minute-level precipitation intensity + chance) rendered as a soft “rain surface”.
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

    #if canImport(WidgetKit)
    @Environment(\.widgetFamily) private var widgetFamily
    #endif

    var body: some View {
        ZStack {
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
                chartBody
            }
        }
    }

    private var chartBody: some View {
        let insets = chartInsets

        return ZStack(alignment: .bottom) {
            WeatherNowcastSurfacePlot(
                samples: WeatherNowcastSurfacePlot.samples(from: points, targetMinutes: 60),
                maxIntensityMMPerHour: maxIntensityMMPerHour,
                accent: accent,
                baselineLabelSafeBottom: showAxisLabels ? insets.axisSafeBottom : 0
            )
            .padding(.horizontal, insets.plotHorizontal)
            .padding(.top, insets.plotTop)
            .padding(.bottom, insets.plotBottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showAxisLabels {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.0), location: 0.0),
                        .init(color: Color.black.opacity(0.80), location: 0.55),
                        .init(color: Color.black.opacity(1.0), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: insets.axisSafeBottom + 10)
                .allowsHitTesting(false)

                WeatherNowcastAxisLabels()
                    .padding(.horizontal, insets.axisHorizontal)
                    .padding(.bottom, insets.axisBottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private struct Insets {
        let plotHorizontal: CGFloat
        let plotTop: CGFloat
        let plotBottom: CGFloat
        let axisSafeBottom: CGFloat
        let axisHorizontal: CGFloat
        let axisBottom: CGFloat
    }

    private var chartInsets: Insets {
        #if canImport(WidgetKit)
        switch widgetFamily {
        case .systemMedium:
            return Insets(
                plotHorizontal: 10,
                plotTop: 6,
                plotBottom: 6,
                axisSafeBottom: 24,
                axisHorizontal: 18,
                axisBottom: 10
            )
        case .systemLarge:
            return Insets(
                plotHorizontal: 10,
                plotTop: 10,
                plotBottom: 10,
                axisSafeBottom: 32,
                axisHorizontal: 18,
                axisBottom: 12
            )
        default:
            return Insets(
                plotHorizontal: 10,
                plotTop: 8,
                plotBottom: 8,
                axisSafeBottom: 24,
                axisHorizontal: 18,
                axisBottom: 10
            )
        }
        #else
        return Insets(
            plotHorizontal: 10,
            plotTop: 8,
            plotBottom: 8,
            axisSafeBottom: 28,
            axisHorizontal: 18,
            axisBottom: 10
        )
        #endif
    }
}

private struct WeatherNowcastAxisLabels: View {
    var body: some View {
        HStack {
            Text("Now")
            Spacer(minLength: 0)
            Text("+60m")
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

    /// Vertical space reserved for the axis labels overlay.
    /// The renderer baseline is positioned just above this region.
    let baselineLabelSafeBottom: CGFloat

    @Environment(\.displayScale) private var displayScale

    #if canImport(WidgetKit)
    @Environment(\.widgetFamily) private var widgetFamily
    #endif

    private enum FamilyKind {
        case small
        case medium
        case large
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
        GeometryReader { proxy in
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
            let plotH = max(1.0, proxy.size.height)

            let desiredBottomInset = max(0.0, baselineLabelSafeBottom + 2.0)
            let computedBaselineFraction = 1.0 - Double(desiredBottomInset / plotH)
            let baselineFraction = CGFloat(RainSurfaceMath.clamp(computedBaselineFraction, min: 0.70, max: 0.985))

            let cfg: RainForecastSurfaceConfiguration = {
                var c = RainForecastSurfaceConfiguration()

                switch familyKind {
                case .large:
                    c.maxCoreHeightFractionOfPlotHeight = 0.42
                    c.intensityEasingPower = 0.74

                    c.ridgeThicknessPoints = 4.0
                    c.ridgeBlurFractionOfPlotHeight = 0.11

                    c.shellAboveThicknessPoints = 10.0
                    c.shellNoiseAmount = 0.26

                    c.mistHeightPoints = 95.0
                    c.mistHeightFractionOfPlotHeight = 0.85

                    c.bloomBlurFractionOfPlotHeight = 0.54
                    c.bloomBandHeightFractionOfPlotHeight = 0.72

                    c.baselineOpacity = 0.10
                    c.mistMaxOpacity = 0.16

                case .medium:
                    c.maxCoreHeightFractionOfPlotHeight = 0.80
                    c.intensityEasingPower = 0.56

                    c.ridgeThicknessPoints = 3.0
                    c.ridgeBlurFractionOfPlotHeight = 0.12

                    c.shellAboveThicknessPoints = 8.0
                    c.shellNoiseAmount = 0.16

                    c.mistHeightPoints = 44.0
                    c.mistHeightFractionOfPlotHeight = 0.62

                    c.bloomBlurFractionOfPlotHeight = 0.40
                    c.bloomBandHeightFractionOfPlotHeight = 0.62

                    c.baselineOpacity = 0.08
                    c.mistMaxOpacity = 0.12

                case .small:
                    c.maxCoreHeightFractionOfPlotHeight = 0.55
                    c.intensityEasingPower = 0.70
                    c.ridgeThicknessPoints = 3.0
                    c.ridgeBlurFractionOfPlotHeight = 0.12
                    c.shellAboveThicknessPoints = 7.0
                    c.shellNoiseAmount = 0.14
                    c.mistHeightPoints = 40.0
                    c.mistHeightFractionOfPlotHeight = 0.65
                    c.bloomBlurFractionOfPlotHeight = 0.42
                    c.bloomBandHeightFractionOfPlotHeight = 0.60
                    c.baselineOpacity = 0.08
                    c.mistMaxOpacity = 0.12
                }

                c.intensityCap = max(maxIntensityMMPerHour, 0.000_001)
                c.wetThreshold = WeatherNowcast.wetIntensityThresholdMMPerHour

                c.baselineYFraction = baselineFraction
                c.edgeInsetFraction = 0.00

                c.minVisibleHeightFraction = (familyKind == .medium) ? 0.040 : 0.022

                c.geometrySmoothingPasses = 1

                c.wetRegionFadeInSamples = 9
                c.wetRegionFadeOutSamples = 14

                c.geometryTailInSamples = 6
                c.geometryTailOutSamples = 12
                c.geometryTailPower = 2.25

                c.baselineColor = accent
                c.baselineLineWidth = onePixel
                c.baselineInsetPoints = 0.0
                c.baselineSoftWidthMultiplier = 2.6
                c.baselineSoftOpacityMultiplier = 0.22

                c.fillBottomColor = Color(red: 0.02, green: 0.04, blue: 0.09)
                c.fillMidColor = Color(red: 0.05, green: 0.10, blue: 0.22)
                c.fillTopColor = accent

                c.fillBottomOpacity = 0.90
                c.fillMidOpacity = 0.55
                c.fillTopOpacity = 0.38

                c.crestLiftEnabled = true
                c.crestLiftMaxOpacity = 0.10

                c.ridgeEnabled = true
                c.ridgeColor = Color(red: 0.78, green: 0.95, blue: 1.0)
                c.ridgeMaxOpacity = 0.22
                c.ridgePeakBoost = 0.55

                c.bloomEnabled = true
                c.bloomColor = accent
                c.bloomMaxOpacity = 0.06

                c.shellEnabled = true
                c.shellColor = Color(red: 0.70, green: 0.92, blue: 1.0)
                c.shellMaxOpacity = 0.15
                c.shellInsideThicknessPoints = 2.0
                c.shellBlurFractionOfPlotHeight = 0.030

                c.shellPuffsPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 4 : 5
                c.shellPuffMinRadiusPoints = 0.7
                c.shellPuffMaxRadiusPoints = 2.8

                c.mistEnabled = true
                c.mistColor = accent
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

            RainForecastSurfaceView(
                intensities: intensities,
                certainties: certainties,
                configuration: cfg
            )
        }
    }

    static func samples(from points: [WidgetWeaverWeatherMinutePoint], targetMinutes: Int) -> [Sample] {
        let clipped = Array(points.prefix(targetMinutes))
        var out: [Sample] = []
        out.reserveCapacity(targetMinutes)

        for p in clipped {
            out.append(
                Sample(
                    intensityMMPerHour: max(0.0, p.precipitationIntensityMMPerHour ?? 0.0),
                    chance01: RainSurfaceMath.clamp01(p.precipitationChance01 ?? 0.0)
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
}
