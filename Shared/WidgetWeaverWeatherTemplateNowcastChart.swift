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

            let peakIntensity = intensities.max() ?? 0.0
            let peak01 = RainSurfaceMath.clamp01(peakIntensity / max(maxIntensityMMPerHour, 0.000_001))

            let onePixel = max(0.33, 1.0 / max(1.0, displayScale))
            let plotH = max(onePixel, proxy.size.height)

            let desiredBottomInset = max(0.0, baselineLabelSafeBottom + 2.0)
            let computedBaselineFraction = 1.0 - Double(desiredBottomInset / plotH)
            let baselineFraction = CGFloat(RainSurfaceMath.clamp(computedBaselineFraction, min: 0.70, max: 0.985))

            let cfg: RainForecastSurfaceConfiguration = {
                var c = RainForecastSurfaceConfiguration()

                // Palette tuned to match the mockup: deep navy base, saturated body, electric crest.
                let deepNavy = Color(red: 0.00, green: 0.02, blue: 0.18)
                let saturatedBody = Color(red: 0.00, green: 0.11, blue: 0.55)

                // Fixed blur radii (expressed via fractions to keep the configuration format).
                func fraction(forPoints points: CGFloat) -> CGFloat {
                    points / max(onePixel, plotH)
                }

                switch familyKind {
                case .large:
                    c.maxCoreHeightFractionOfPlotHeight = 0.44
                    c.intensityEasingPower = 0.74

                    c.ridgeThicknessPoints = 4.0
                    c.ridgeBlurFractionOfPlotHeight = fraction(forPoints: 5.0)

                    c.shellAboveThicknessPoints = 14.0
                    c.shellNoiseAmount = 0.42
                    c.shellBlurFractionOfPlotHeight = fraction(forPoints: 1.10)

                    c.baselineOpacity = 0.28
                    c.baselineSoftWidthMultiplier = 3.2
                    c.baselineSoftOpacityMultiplier = 0.45

                    // Halo-like bloom is disabled for the mockup match.
                    c.bloomEnabled = false

                    // The mockup reads as boundary fuzz rather than tall mist.
                    c.mistEnabled = false

                case .medium:
                    c.maxCoreHeightFractionOfPlotHeight = 0.80
                    c.intensityEasingPower = 0.56

                    c.ridgeThicknessPoints = 3.0
                    c.ridgeBlurFractionOfPlotHeight = fraction(forPoints: 4.2)

                    c.shellAboveThicknessPoints = 11.0
                    c.shellNoiseAmount = 0.38
                    c.shellBlurFractionOfPlotHeight = fraction(forPoints: 1.00)

                    c.baselineOpacity = 0.26
                    c.baselineSoftWidthMultiplier = 3.0
                    c.baselineSoftOpacityMultiplier = 0.44

                    c.bloomEnabled = false
                    c.mistEnabled = false

                case .small:
                    c.maxCoreHeightFractionOfPlotHeight = 0.55
                    c.intensityEasingPower = 0.70

                    c.ridgeThicknessPoints = 3.0
                    c.ridgeBlurFractionOfPlotHeight = fraction(forPoints: 4.0)

                    c.shellAboveThicknessPoints = 10.0
                    c.shellNoiseAmount = 0.36
                    c.shellBlurFractionOfPlotHeight = fraction(forPoints: 1.00)

                    c.baselineOpacity = 0.25
                    c.baselineSoftWidthMultiplier = 3.0
                    c.baselineSoftOpacityMultiplier = 0.44

                    c.bloomEnabled = false
                    c.mistEnabled = false
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

                c.fillBottomColor = deepNavy
                c.fillMidColor = saturatedBody
                c.fillTopColor = accent

                // Brighter fill to match the mockup.
                c.fillBottomOpacity = 0.98

                switch familyKind {
                case .large:
                    c.fillMidOpacity = RainSurfaceMath.clamp01(0.90 + 0.05 * peak01)
                    c.fillTopOpacity = RainSurfaceMath.clamp01(0.92 + 0.06 * peak01)
                case .medium:
                    c.fillMidOpacity = RainSurfaceMath.clamp01(0.88 + 0.05 * peak01)
                    c.fillTopOpacity = RainSurfaceMath.clamp01(0.90 + 0.06 * peak01)
                case .small:
                    c.fillMidOpacity = RainSurfaceMath.clamp01(0.86 + 0.05 * peak01)
                    c.fillTopOpacity = RainSurfaceMath.clamp01(0.88 + 0.06 * peak01)
                }

                c.crestLiftEnabled = true
                switch familyKind {
                case .large:
                    c.crestLiftMaxOpacity = RainSurfaceMath.clamp01(0.22 + 0.12 * peak01)
                case .medium:
                    c.crestLiftMaxOpacity = RainSurfaceMath.clamp01(0.20 + 0.12 * peak01)
                case .small:
                    c.crestLiftMaxOpacity = RainSurfaceMath.clamp01(0.18 + 0.10 * peak01)
                }

                c.ridgeEnabled = true
                c.ridgeColor = Color(red: 0.78, green: 0.95, blue: 1.0)
                c.ridgeMaxOpacity = RainSurfaceMath.clamp01(0.38 + 0.18 * peak01)
                c.ridgePeakBoost = 0.85 + 0.30 * peak01

                // Specular peak glint (small white highlight at the crest).
                c.glintEnabled = true
                c.glintColor = Color(red: 0.98, green: 1.0, blue: 1.0)
                c.glintMaxOpacity = RainSurfaceMath.clamp01(0.92 + 0.06 * peak01)
                c.glintThicknessPoints = 1.05
                c.glintBlurRadiusPoints = 1.15
                c.glintHaloOpacityMultiplier = 0.0
                c.glintSpanSamples = 5
                c.glintMinPeakHeightFractionOfSegmentMax = 0.70

                c.shellEnabled = true
                c.shellColor = Color(red: 0.70, green: 0.92, blue: 1.0)
                c.shellMaxOpacity = 0.24
                c.shellInsideThicknessPoints = 2.0

                c.shellPuffsPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 5 : 7
                c.shellPuffMinRadiusPoints = 0.60
                c.shellPuffMaxRadiusPoints = 2.20

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
