//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RainForecastSurfaceConfiguration: Hashable {
    var noiseSeed: UInt64 = 0

    var baselineFractionFromTop: CGFloat = 0.84
    var topHeadroomFraction: CGFloat = 0.16
    var typicalPeakFraction: CGFloat = 0.52

    var robustMaxPercentile: Double = 0.93
    var intensityGamma: Double = 0.65

    var maxDenseSamples: Int = 256
    var baselineAntiClipInsetPixels: Double = 0.75

    var edgeEasingFraction: CGFloat = 0.10
    var edgeEasingPower: Double = 1.7

    var coreBodyColor: Color = Color(red: 0.00, green: 0.10, blue: 0.42)
    var coreTopColor: Color = Color(red: 0.12, green: 0.45, blue: 1.0)

    var coreMidColor: Color = Color(red: 0.03, green: 0.22, blue: 0.78)
    var coreBottomColor: Color = Color(red: 0.00, green: 0.05, blue: 0.18)

    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.62, green: 0.88, blue: 1.00)
    var rimInnerOpacity: Double = 0.30
    var rimInnerWidthPixels: Double = 1.05
    var rimOuterOpacity: Double = 0.12
    var rimOuterWidthPixels: Double = 5.2

    var glossEnabled: Bool = true
    var glossMaxOpacity: Double = 0.14
    var glossDepthPixels: ClosedRange<Double> = 9.0...14.0
    var glossSoftBlurPixels: Double = 0.6

    var glintEnabled: Bool = true
    var glintColor: Color = Color(red: 0.95, green: 0.99, blue: 1.0)
    var glintMaxOpacity: Double = 0.18
    var glintBlurPixels: Double = 1.0
    var glintMinHeightFraction: Double = 0.78
    var glintMaxCount: Int = 1

    // Fuzz: raster surface band (outside + inside).
    var fuzzEnabled: Bool = true
    var fuzzColor: Color = Color(red: 0.05, green: 0.32, blue: 1.00)
    var fuzzMaxOpacity: Double = 0.22
    var fuzzWidthFraction: CGFloat = 0.26
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 12.0...130.0
    var fuzzBaseDensity: Double = 0.86
    var fuzzLowHeightPower: Double = 2.8

    var fuzzUncertaintyFloor: Double = 0.18
    var fuzzUncertaintyExponent: Double = 2.0

    var fuzzMicroBlurPixels: Double = 0.0

    var fuzzRasterMaxPixels: Int = 110_000
    var fuzzEdgePower: Double = 0.65
    var fuzzClumpCellPixels: Double = 12.0
    var fuzzHazeStrength: Double = 0.72
    var fuzzSpeckStrength: Double = 1.0
    var fuzzInsideThreshold: UInt8 = 14

    // Surface-band controls (new).
    var fuzzInsideWidthFactor: Double = 0.68
    var fuzzInsideOpacityFactor: Double = 0.72
    var fuzzInsideSpeckleFraction: Double = 0.40

    // Ensures tapered ends stay fuzzy.
    var fuzzLowHeightBoost: Double = 0.85

    // Concentrates grain near the edge.
    var fuzzDistancePowerOutside: Double = 1.85
    var fuzzDistancePowerInside: Double = 1.55

    var baselineColor: Color = Color(red: 0.55, green: 0.75, blue: 1.0)
    var baselineLineOpacity: Double = 0.22
    var baselineEndFadeFraction: CGFloat = 0.040

    private static func colorKey(_ color: Color) -> UInt64 {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            let rr = UInt64(max(0, min(255, Int(round(r * 255.0)))))
            let gg = UInt64(max(0, min(255, Int(round(g * 255.0)))))
            let bb = UInt64(max(0, min(255, Int(round(b * 255.0)))))
            let aa = UInt64(max(0, min(255, Int(round(a * 255.0)))))
            return (rr << 24) | (gg << 16) | (bb << 8) | aa
        }
        #endif
        return 0
    }

    static func == (lhs: RainForecastSurfaceConfiguration, rhs: RainForecastSurfaceConfiguration) -> Bool {
        lhs.noiseSeed == rhs.noiseSeed
        && lhs.baselineFractionFromTop == rhs.baselineFractionFromTop
        && lhs.topHeadroomFraction == rhs.topHeadroomFraction
        && lhs.typicalPeakFraction == rhs.typicalPeakFraction
        && lhs.robustMaxPercentile == rhs.robustMaxPercentile
        && lhs.intensityGamma == rhs.intensityGamma
        && lhs.maxDenseSamples == rhs.maxDenseSamples
        && lhs.baselineAntiClipInsetPixels == rhs.baselineAntiClipInsetPixels
        && lhs.edgeEasingFraction == rhs.edgeEasingFraction
        && lhs.edgeEasingPower == rhs.edgeEasingPower
        && colorKey(lhs.coreBodyColor) == colorKey(rhs.coreBodyColor)
        && colorKey(lhs.coreTopColor) == colorKey(rhs.coreTopColor)
        && lhs.rimEnabled == rhs.rimEnabled
        && colorKey(lhs.rimColor) == colorKey(rhs.rimColor)
        && lhs.rimInnerOpacity == rhs.rimInnerOpacity
        && lhs.rimInnerWidthPixels == rhs.rimInnerWidthPixels
        && lhs.rimOuterOpacity == rhs.rimOuterOpacity
        && lhs.rimOuterWidthPixels == rhs.rimOuterWidthPixels
        && lhs.glossEnabled == rhs.glossEnabled
        && lhs.glossMaxOpacity == rhs.glossMaxOpacity
        && lhs.glossDepthPixels.lowerBound == rhs.glossDepthPixels.lowerBound
        && lhs.glossDepthPixels.upperBound == rhs.glossDepthPixels.upperBound
        && lhs.glossSoftBlurPixels == rhs.glossSoftBlurPixels
        && lhs.glintEnabled == rhs.glintEnabled
        && colorKey(lhs.glintColor) == colorKey(rhs.glintColor)
        && lhs.glintMaxOpacity == rhs.glintMaxOpacity
        && lhs.glintBlurPixels == rhs.glintBlurPixels
        && lhs.glintMinHeightFraction == rhs.glintMinHeightFraction
        && lhs.glintMaxCount == rhs.glintMaxCount
        && lhs.fuzzEnabled == rhs.fuzzEnabled
        && colorKey(lhs.fuzzColor) == colorKey(rhs.fuzzColor)
        && lhs.fuzzMaxOpacity == rhs.fuzzMaxOpacity
        && lhs.fuzzWidthFraction == rhs.fuzzWidthFraction
        && lhs.fuzzWidthPixelsClamp.lowerBound == rhs.fuzzWidthPixelsClamp.lowerBound
        && lhs.fuzzWidthPixelsClamp.upperBound == rhs.fuzzWidthPixelsClamp.upperBound
        && lhs.fuzzBaseDensity == rhs.fuzzBaseDensity
        && lhs.fuzzLowHeightPower == rhs.fuzzLowHeightPower
        && lhs.fuzzUncertaintyFloor == rhs.fuzzUncertaintyFloor
        && lhs.fuzzUncertaintyExponent == rhs.fuzzUncertaintyExponent
        && lhs.fuzzMicroBlurPixels == rhs.fuzzMicroBlurPixels
        && lhs.fuzzRasterMaxPixels == rhs.fuzzRasterMaxPixels
        && lhs.fuzzEdgePower == rhs.fuzzEdgePower
        && lhs.fuzzClumpCellPixels == rhs.fuzzClumpCellPixels
        && lhs.fuzzHazeStrength == rhs.fuzzHazeStrength
        && lhs.fuzzSpeckStrength == rhs.fuzzSpeckStrength
        && lhs.fuzzInsideWidthFactor == rhs.fuzzInsideWidthFactor
        && lhs.fuzzInsideOpacityFactor == rhs.fuzzInsideOpacityFactor
        && lhs.fuzzInsideSpeckleFraction == rhs.fuzzInsideSpeckleFraction
        && lhs.fuzzLowHeightBoost == rhs.fuzzLowHeightBoost
        && lhs.fuzzDistancePowerOutside == rhs.fuzzDistancePowerOutside
        && lhs.fuzzDistancePowerInside == rhs.fuzzDistancePowerInside
        && colorKey(lhs.baselineColor) == colorKey(rhs.baselineColor)
        && lhs.baselineLineOpacity == rhs.baselineLineOpacity
        && lhs.baselineEndFadeFraction == rhs.baselineEndFadeFraction
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(noiseSeed)

        hasher.combine(baselineFractionFromTop)
        hasher.combine(topHeadroomFraction)
        hasher.combine(typicalPeakFraction)
        hasher.combine(robustMaxPercentile)
        hasher.combine(intensityGamma)
        hasher.combine(maxDenseSamples)
        hasher.combine(baselineAntiClipInsetPixels)
        hasher.combine(edgeEasingFraction)
        hasher.combine(edgeEasingPower)

        hasher.combine(Self.colorKey(coreBodyColor))
        hasher.combine(Self.colorKey(coreTopColor))

        hasher.combine(rimEnabled)
        hasher.combine(Self.colorKey(rimColor))
        hasher.combine(rimInnerOpacity)
        hasher.combine(rimInnerWidthPixels)
        hasher.combine(rimOuterOpacity)
        hasher.combine(rimOuterWidthPixels)

        hasher.combine(glossEnabled)
        hasher.combine(glossMaxOpacity)
        hasher.combine(glossDepthPixels.lowerBound)
        hasher.combine(glossDepthPixels.upperBound)
        hasher.combine(glossSoftBlurPixels)

        hasher.combine(glintEnabled)
        hasher.combine(Self.colorKey(glintColor))
        hasher.combine(glintMaxOpacity)
        hasher.combine(glintBlurPixels)
        hasher.combine(glintMinHeightFraction)
        hasher.combine(glintMaxCount)

        hasher.combine(fuzzEnabled)
        hasher.combine(Self.colorKey(fuzzColor))
        hasher.combine(fuzzMaxOpacity)
        hasher.combine(fuzzWidthFraction)
        hasher.combine(fuzzWidthPixelsClamp.lowerBound)
        hasher.combine(fuzzWidthPixelsClamp.upperBound)
        hasher.combine(fuzzBaseDensity)
        hasher.combine(fuzzLowHeightPower)
        hasher.combine(fuzzUncertaintyFloor)
        hasher.combine(fuzzUncertaintyExponent)
        hasher.combine(fuzzMicroBlurPixels)
        hasher.combine(fuzzRasterMaxPixels)
        hasher.combine(fuzzEdgePower)
        hasher.combine(fuzzClumpCellPixels)
        hasher.combine(fuzzHazeStrength)
        hasher.combine(fuzzSpeckStrength)

        hasher.combine(fuzzInsideWidthFactor)
        hasher.combine(fuzzInsideOpacityFactor)
        hasher.combine(fuzzInsideSpeckleFraction)
        hasher.combine(fuzzLowHeightBoost)
        hasher.combine(fuzzDistancePowerOutside)
        hasher.combine(fuzzDistancePowerInside)

        hasher.combine(Self.colorKey(baselineColor))
        hasher.combine(baselineLineOpacity)
        hasher.combine(baselineEndFadeFraction)
    }
}

struct RainForecastSurfaceView: View {
    let intensities: [Double]
    let certainties: [Double]
    let configuration: RainForecastSurfaceConfiguration

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let renderer = RainForecastSurfaceRenderer(
                intensities: intensities,
                certainties: certainties,
                configuration: configuration,
                displayScale: displayScale
            )
            renderer.render(in: &context, size: size)
        }
    }
}
