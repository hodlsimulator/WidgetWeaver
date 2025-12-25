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
import WidgetKit

// MARK: - Public view

struct WeatherNowcastChart: View {

    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color
    let showAxisLabels: Bool

    @Environment(\.widgetFamily) private var widgetFamily

    init(
        points: [WidgetWeaverWeatherMinutePoint],
        maxIntensityMMPerHour: Double,
        accent: Color,
        showAxisLabels: Bool
    ) {
        self.points = points
        self.maxIntensityMMPerHour = maxIntensityMMPerHour
        self.accent = accent
        self.showAxisLabels = showAxisLabels
    }

    var body: some View {
        let kind = familyKind(for: widgetFamily)

        let cornerRadius: CGFloat = (kind == .small) ? 12 : 14
        let horizontalInset: CGFloat = (kind == .small) ? 8 : 10
        let topInset: CGFloat = (kind == .small) ? 6 : 10
        let bottomInset: CGFloat = (kind == .small) ? 6 : (showAxisLabels ? 6 : 10)
        let spacing: CGFloat = (kind == .small) ? 4 : 6

        VStack(spacing: spacing) {
            WeatherNowcastSurfacePlot(
                points: points,
                maxIntensityMMPerHour: maxIntensityMMPerHour,
                accent: accent
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, horizontalInset)
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)

            if showAxisLabels {
                HStack {
                    Text("Now")
                    Spacer()
                    Text("+60m")
                }
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .padding(.horizontal, horizontalInset + 4)
                .padding(.bottom, (kind == .small) ? 0 : 8)
            }
        }
        .background {
            // Black field, no border (the baseline is the only horizon line).
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private enum WidgetFamilyKind {
        case small
        case medium
        case large
    }

    private func familyKind(for widgetFamily: WidgetFamily) -> WidgetFamilyKind {
        switch widgetFamily {
        case .systemSmall:
            return .small
        case .systemMedium:
            return .medium
        default:
            return .large
        }
    }
}

// MARK: - Surface plot (Canvas)

private struct WeatherNowcastSurfacePlot: View {

    struct Sample {
        let intensityMMPerHour: Double
        let chance01: Double
    }

    let points: [WidgetWeaverWeatherMinutePoint]
    let maxIntensityMMPerHour: Double
    let accent: Color

    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let familyKind = familyKind(for: widgetFamily)

        let samples = Self.samples(from: points, targetMinutes: 60)
        let intensitiesMM = samples.map { max(0.0, $0.intensityMMPerHour) }
        let chances = samples.map { RainSurfaceMath.clamp01($0.chance01) }

        // Certainty shaping:
        // - chance drives certainty
        // - horizon factor reduces certainty slightly towards the end of the hour (more diffusion later)
        let horizonStart = 35.0
        let horizonEnd = 60.0
        let certainties: [Double] = (0..<samples.count).map { idx in
            let t = Double(idx)
            let horizon = Self.smoothstep(horizonStart, horizonEnd, t)
            let horizonFactor = 1.0 - 0.22 * horizon
            return RainSurfaceMath.clamp01(chances[idx] * horizonFactor)
        }

        let onePixel = max(0.33, 1.0 / max(1.0, displayScale))

        var c = RainForecastSurfaceConfiguration()

        // Behaviour
        let cap = max(0.000_001, maxIntensityMMPerHour)
        c.intensityCap = cap
        c.wetThreshold = WeatherNowcast.wetIntensityThresholdMMPerHour
        c.intensityEasingPower = (familyKind == .large) ? 0.78 : 0.72
        c.geometrySmoothingPasses = 2

        // Geometry (baseline position and height cap tuned to the mock)
        c.baselineYFraction = (familyKind == .large) ? 0.60 : 0.66
        c.maxCoreHeightFractionOfPlotHeight = (familyKind == .large) ? 0.22 : 0.30
        c.minVisibleHeightFraction = 0.018
        c.edgeInsetFraction = 0.0

        // Wet region tapers / tails (keeps ends settled into the horizon).
        c.wetRegionFadeInSamples = 10
        c.wetRegionFadeOutSamples = 16
        c.geometryTailInSamples = 8
        c.geometryTailOutSamples = 14
        c.geometryTailPower = 2.20

        // Baseline (horizontal falloff is implemented in RainSurfaceDrawing)
        c.baselineColor = Color(red: 140.0 / 255.0, green: 173.0 / 255.0, blue: 237.0 / 255.0) // #8CADED
        c.baselineLineWidth = onePixel
        c.baselineOpacity = (familyKind == .large) ? 0.68 : 0.62
        c.baselineSoftWidthMultiplier = 4.6
        c.baselineSoftOpacityMultiplier = 0.22
        c.baselineInsetPoints = 0.0

        // Core fill (smooth vertical gradient)
        c.fillBottomColor = Color(red: 0.0 / 255.0, green: 4.0 / 255.0, blue: 34.0 / 255.0) // #000422
        c.fillMidColor = Color(red: 0.0 / 255.0, green: 31.0 / 255.0, blue: 165.0 / 255.0) // #001FA5
        c.fillTopColor = Color(red: 0.0 / 255.0, green: 84.0 / 255.0, blue: 227.0 / 255.0) // #0054E3
        c.fillBottomOpacity = 0.88
        c.fillMidOpacity = 0.86
        c.fillTopOpacity = 0.78

        c.crestLiftEnabled = true
        c.crestLiftMaxOpacity = 0.10

        // Ridge highlight (broad cyan band)
        c.ridgeEnabled = true
        c.ridgeColor = Color(red: 61.0 / 255.0, green: 200.0 / 255.0, blue: 252.0 / 255.0) // #3DC8FC
        c.ridgeMaxOpacity = 0.30
        c.ridgePeakBoost = 0.65
        c.ridgeThicknessPoints = (familyKind == .large) ? 4.0 : 3.0
        c.ridgeBlurFractionOfPlotHeight = (familyKind == .large) ? 0.09 : 0.11

        // Specular glint (tiny white hotspot at the peak)
        c.glintEnabled = true
        c.glintColor = Color(red: 253.0 / 255.0, green: 254.0 / 255.0, blue: 254.0 / 255.0) // #FDFEFE
        c.glintMaxOpacity = 0.92
        c.glintThicknessPoints = (familyKind == .large) ? 1.30 : 1.15
        c.glintBlurRadiusPoints = (familyKind == .large) ? 1.70 : 1.45
        c.glintHaloOpacityMultiplier = 0.18
        c.glintSpanSamples = (familyKind == .large) ? 6 : 5
        c.glintMinPeakHeightFractionOfSegmentMax = 0.72

        // Bloom (restrained)
        c.bloomEnabled = true
        c.bloomColor = c.ridgeColor
        c.bloomMaxOpacity = 0.045
        c.bloomBlurFractionOfPlotHeight = (familyKind == .large) ? 0.33 : 0.36
        c.bloomBandHeightFractionOfPlotHeight = (familyKind == .large) ? 0.50 : 0.56

        // Shell fuzz (edge-attached)
        c.shellEnabled = true
        c.shellColor = Color(red: 0.10, green: 0.56, blue: 1.0)
        c.shellMaxOpacity = 0.16
        c.shellInsideThicknessPoints = 1.6
        c.shellAboveThicknessPoints = (familyKind == .large) ? 10.0 : 8.0
        c.shellNoiseAmount = (familyKind == .large) ? 0.30 : 0.22
        c.shellBlurFractionOfPlotHeight = 0.020
        c.shellPuffsPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 4 : 5
        c.shellPuffMinRadiusPoints = 0.6
        c.shellPuffMaxRadiusPoints = 2.6

        // Mist (subtle, outside-only)
        c.mistEnabled = true
        c.mistColor = c.shellColor
        c.mistMaxOpacity = 0.12
        c.mistHeightPoints = (familyKind == .large) ? 80.0 : 58.0
        c.mistHeightFractionOfPlotHeight = (familyKind == .large) ? 0.70 : 0.74
        c.mistFalloffPower = 1.85
        c.mistNoiseEnabled = true
        c.mistNoiseInfluence = 0.18
        c.mistPuffsPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 8 : 10
        c.mistFineGrainPerSampleMax = WidgetWeaverRuntime.isRunningInAppExtension ? 5 : 6
        c.mistParticleMinRadiusPoints = 0.6
        c.mistParticleMaxRadiusPoints = 3.2
        c.mistFineParticleMinRadiusPoints = 0.35
        c.mistFineParticleMaxRadiusPoints = 0.95

        return RainForecastSurfaceView(
            intensities: intensitiesMM,
            certainties: certainties,
            configuration: c
        )
    }

    private enum WidgetFamilyKind {
        case medium
        case large
    }

    private func familyKind(for widgetFamily: WidgetFamily) -> WidgetFamilyKind {
        switch widgetFamily {
        case .systemMedium:
            return .medium
        default:
            return .large
        }
    }

    private static func samples(from points: [WidgetWeaverWeatherMinutePoint], targetMinutes: Int) -> [Sample] {
        var out: [Sample] = []
        out.reserveCapacity(targetMinutes)

        for p in points.prefix(targetMinutes) {
            let intensity = max(0.0, p.precipitationIntensityMMPerHour ?? 0.0)
            let chance = RainSurfaceMath.clamp01(p.precipitationChance01 ?? 0.0)
            out.append(Sample(intensityMMPerHour: intensity, chance01: chance))
        }

        if out.count < targetMinutes {
            for _ in 0..<(targetMinutes - out.count) {
                out.append(Sample(intensityMMPerHour: 0.0, chance01: 0.0))
            }
        }

        return out
    }

    private static func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
        if edge0 == edge1 { return x < edge0 ? 0.0 : 1.0 }
        let t = RainSurfaceMath.clamp01((x - edge0) / (edge1 - edge0))
        return t * t * (3.0 - 2.0 * t)
    }
}
