//
//  WidgetWeaverWeatherTemplateNowcastChart.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import SwiftUI

struct WidgetWeaverWeatherTemplateNowcastChart: View {

    let model: WidgetWeaverWeatherTemplateModel
    let style: WidgetWeaverWeatherTemplateStyle
    let geo: GeometryProxy

    init(model: WidgetWeaverWeatherTemplateModel, style: WidgetWeaverWeatherTemplateStyle, geo: GeometryProxy) {
        self.model = model
        self.style = style
        self.geo = geo
    }

    var body: some View {
        let accent = style.accentColor
        let bg = style.backgroundColor

        let isWidgetExtension = WidgetWeaverRuntime.isWidgetExtension

        let cfg: RainForecastSurfaceConfiguration = {
            var c = RainForecastSurfaceConfiguration()
            c.fillBackgroundBlack = true

            // Core: slightly lifted top for mid-tone readability.
            c.coreBodyColor = accent
            c.coreTopColor = accent
            c.coreOpacity = 0.92
            c.coreTopMix = 0.65
            c.coreTopLiftEnabled = true
            c.coreTopLiftOpacity = 0.34
            c.coreTopLiftPower = 2.10

            // Core edge: reduce clean vector edge (no stroke-line look).
            c.coreFadeFraction = isWidgetExtension ? 0.012 : 0.016
            c.coreInsetMax = isWidgetExtension ? 0.070 : 0.085

            // Fuzz: width and budgets.
            c.fuzzWidthFraction = 0.14
            c.maxDenseSamples = isWidgetExtension ? 260 : 680
            c.fuzzSpeckleBudget = isWidgetExtension ? 1_250 : 5_200

            // Colour: bright blue grains (no background halo wash).
            c.fuzzColor = accent
            c.fuzzColorBoost = 0.12

            // Strength: dense, fine grain; haze disabled for “no halo”.
            c.fuzzMaxOpacity = isExt ? 0.56 : 0.62
            c.fuzzDensity = isExt ? 1.65 : 1.85
            c.fuzzHazeStrength = 0.0
            c.fuzzSpeckStrength = isExt ? 2.70 : 3.05

            // Fine grain: lots of micro speckles; a small minority of slightly larger soft grains.
            c.fuzzSpeckleRadiusPixels = isExt ? (0.14...1.45) : (0.15...1.70)

            // Haze parameters (kept for non-nowcast variants; no-op here since hazeStrength == 0).
            c.fuzzHazeBlurFractionOfBand = isExt ? 0.08 : 0.10
            c.fuzzHazeStrokeWidthFactor = isExt ? 0.64 : 0.72

            // Inside haze: generally subtle; no-op in nowcast haze-disabled config.
            c.fuzzInsideHazeStrength = isExt ? 0.00 : 0.12
            c.fuzzInsideHazeBlurFractionOfBand = isExt ? 0.06 : 0.07
            c.fuzzInsideHazeStrokeWidthFactor = isExt ? 0.62 : 0.68

            // Mapping from probability/certainty to styling strength.
            c.fuzzChanceThreshold = 0.22
            c.fuzzChanceTransition = 0.55
            c.fuzzChanceExponent = 1.55
            c.fuzzChanceFloor = isExt ? 0.20 : 0.24
            c.fuzzChanceMinStrength = isExt ? 0.44 : 0.54
            c.fuzzTailMinutes = 5.0

            // Geometry-based emphasis.
            c.fuzzLowHeightBoost = isExt ? 0.48 : 0.56
            c.fuzzSlopeBoost = isExt ? 0.38 : 0.44

            // Speck distribution: outside-heavy but welded inside; strong near edge.
            c.fuzzInsideWidthFactor = 0.86
            c.fuzzInsideOpacityFactor = isExt ? 0.90 : 0.96
            c.fuzzInsideSpeckleFraction = isExt ? 0.46 : 0.52
            c.fuzzDistancePowerOutside = 3.55
            c.fuzzDistancePowerInside = 2.55
            c.fuzzAlongTangentJitter = 0.95

            // Erode (blurred destinationOut): off in widget extension; cheap perforation handles dissolve there.
            c.fuzzErodeEnabled = !isWidgetExtension
            c.fuzzErodeStrength = 0.62
            c.fuzzErodeBlurFractionOfBand = 0.10
            c.fuzzErodeStrokeWidthFactor = 0.72

            // Rim: keep luminous but avoid reading like a stroked path.
            c.rimEnabled = true
            c.rimColor = accent
            c.rimOuterOpacity = isExt ? 0.018 : 0.022
            c.rimOuterWidth = isExt ? 0.90 : 0.98
            c.rimInnerOpacity = isExt ? 0.42 : 0.48
            c.rimInnerWidthPixels = isExt ? 0.96 : 1.05
            c.rimBeadOpacity = isExt ? 0.34 : 0.40
            c.rimBeadRadiusPixels = isExt ? (0.35...1.35) : (0.35...1.55)

            // Baseline: subtle grain only.
            c.baselineGrainEnabled = true
            c.baselineGrainColor = accent
            c.baselineGrainOpacity = 0.22
            c.baselineGrainBudget = isWidgetExtension ? 320 : 620
            c.baselineGrainRadiusPixels = isWidgetExtension ? (0.25...1.05) : (0.25...1.25)
            c.baselineGrainYOffsetPixels = (-0.8...0.9)

            // General smoothing.
            c.topSmoothing = 2

            return c
        }()

        RainForecastSurfaceView(
            minutes: model.nowcastMinutes,
            intensities: model.nowcastIntensities,
            certainties: model.nowcastCertainties,
            configuration: cfg
        )
        .background(bg)
    }

    private var isExt: Bool {
        WidgetWeaverRuntime.isWidgetExtension
    }
}
