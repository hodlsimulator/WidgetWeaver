//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  SwiftUI wrapper for the procedural nowcast surface renderer.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RainForecastSurfaceConfiguration: Hashable {
    // MARK: - Determinism

    var noiseSeed: UInt64 = 0

    // MARK: - Geometry (shape-agnostic)

    var baselineFractionFromTop: CGFloat = 0.84
    var topHeadroomFraction: CGFloat = 0.16
    var typicalPeakFraction: CGFloat = 0.52

    var robustMaxPercentile: Double = 0.93
    var intensityGamma: Double = 0.65

    var maxDenseSamples: Int = 256

    var baselineAntiClipInsetPixels: Double = 0.75

    var edgeEasingFraction: CGFloat = 0.10
    var edgeEasingPower: Double = 1.7

    // MARK: - Core (opaque volume)

    var coreBodyColor: Color = Color(red: 0.00, green: 0.10, blue: 0.42)
    var coreTopColor: Color = Color(red: 0.12, green: 0.45, blue: 1.0)

    var coreMidColor: Color = Color(red: 0.03, green: 0.22, blue: 0.78)
    var coreBottomColor: Color = Color(red: 0.00, green: 0.05, blue: 0.18)

    // MARK: - Rim

    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.62, green: 0.88, blue: 1.00)
    var rimInnerOpacity: Double = 0.30
    var rimInnerWidthPixels: Double = 1.05
    var rimOuterOpacity: Double = 0.12
    var rimOuterWidthPixels: Double = 5.2

    // MARK: - Gloss (inside-only)

    var glossEnabled: Bool = true
    var glossMaxOpacity: Double = 0.14
    var glossDepthPixels: ClosedRange<Double> = 9.0...14.0
    var glossSoftBlurPixels: Double = 0.6

    // MARK: - Glints

    var glintEnabled: Bool = true
    var glintColor: Color = Color(red: 0.95, green: 0.99, blue: 1.0)
    var glintMaxOpacity: Double = 0.18
    var glintBlurPixels: Double = 1.0
    var glintMinHeightFraction: Double = 0.78
    var glintMaxCount: Int = 1

    // MARK: - Fuzz (granular speckle outside core)

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
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.5...1.15
    var fuzzMaxAttemptsPerColumn: Int = 24
    var fuzzMaxColumns: Int = 900
    var fuzzSpeckleBudget: Int = 6500

    var fuzzRasterMaxPixels: Int = 110_000
    var fuzzEdgePower: Double = 0.65
    var fuzzClumpCellPixels: Double = 12.0
    var fuzzHazeStrength: Double = 0.72
    var fuzzSpeckStrength: Double = 1.0
    var fuzzInsideThreshold: UInt8 = 14

    // MARK: - Baseline

    var baselineColor: Color = Color(red: 0.55, green: 0.75, blue: 1.0)
    var baselineLineOpacity: Double = 0.22
    var baselineEndFadeFraction: CGFloat = 0.040

    // MARK: - Hashable

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
        && colorKey(lhs.coreMidColor) == colorKey(rhs.coreMidColor)
        && colorKey(lhs.coreBottomColor) == colorKey(rhs.coreBottomColor)
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
        && lhs.fuzzRasterMaxPixels == rhs.fuzzRasterMaxPixels
        && lhs.fuzzEdgePower == rhs.fuzzEdgePower
        && lhs.fuzzClumpCellPixels == rhs.fuzzClumpCellPixels
        && lhs.fuzzHazeStrength == rhs.fuzzHazeStrength
        && lhs.fuzzSpeckStrength == rhs.fuzzSpeckStrength
        && lhs.fuzzInsideThreshold == rhs.fuzzInsideThreshold
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
        hasher.combine(Self.colorKey(coreMidColor))
        hasher.combine(Self.colorKey(coreBottomColor))

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
        hasher.combine(fuzzRasterMaxPixels)
        hasher.combine(fuzzEdgePower)
        hasher.combine(fuzzClumpCellPixels)
        hasher.combine(fuzzHazeStrength)
        hasher.combine(fuzzSpeckStrength)
        hasher.combine(fuzzInsideThreshold)

        hasher.combine(Self.colorKey(baselineColor))
        hasher.combine(baselineLineOpacity)
        hasher.combine(baselineEndFadeFraction)
    }

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
//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  SwiftUI wrapper for the procedural nowcast surface renderer.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct RainForecastSurfaceConfiguration: Hashable {
    // MARK: - Determinism

    var noiseSeed: UInt64 = 0

    // MARK: - Geometry (shape-agnostic)

    var baselineFractionFromTop: CGFloat = 0.84
    var topHeadroomFraction: CGFloat = 0.16
    var typicalPeakFraction: CGFloat = 0.52

    var robustMaxPercentile: Double = 0.93
    var intensityGamma: Double = 0.65

    var maxDenseSamples: Int = 256

    var baselineAntiClipInsetPixels: Double = 0.75

    var edgeEasingFraction: CGFloat = 0.10
    var edgeEasingPower: Double = 1.7

    // MARK: - Core (opaque volume)

    var coreBodyColor: Color = Color(red: 0.00, green: 0.10, blue: 0.42)
    var coreTopColor: Color = Color(red: 0.12, green: 0.45, blue: 1.0)

    var coreMidColor: Color = Color(red: 0.03, green: 0.22, blue: 0.78)
    var coreBottomColor: Color = Color(red: 0.00, green: 0.05, blue: 0.18)

    // MARK: - Rim

    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.62, green: 0.88, blue: 1.00)
    var rimInnerOpacity: Double = 0.30
    var rimInnerWidthPixels: Double = 1.05
    var rimOuterOpacity: Double = 0.12
    var rimOuterWidthPixels: Double = 5.2

    // MARK: - Gloss (inside-only)

    var glossEnabled: Bool = true
    var glossMaxOpacity: Double = 0.14
    var glossDepthPixels: ClosedRange<Double> = 9.0...14.0
    var glossSoftBlurPixels: Double = 0.6

    // MARK: - Glints

    var glintEnabled: Bool = true
    var glintColor: Color = Color(red: 0.95, green: 0.99, blue: 1.0)
    var glintMaxOpacity: Double = 0.18
    var glintBlurPixels: Double = 1.0
    var glintMinHeightFraction: Double = 0.78
    var glintMaxCount: Int = 1

    // MARK: - Fuzz (granular speckle outside core)

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
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.5...1.15
    var fuzzMaxAttemptsPerColumn: Int = 24
    var fuzzMaxColumns: Int = 900
    var fuzzSpeckleBudget: Int = 6500

    var fuzzRasterMaxPixels: Int = 110_000
    var fuzzEdgePower: Double = 0.65
    var fuzzClumpCellPixels: Double = 12.0
    var fuzzHazeStrength: Double = 0.72
    var fuzzSpeckStrength: Double = 1.0
    var fuzzInsideThreshold: UInt8 = 14

    // MARK: - Baseline

    var baselineColor: Color = Color(red: 0.55, green: 0.75, blue: 1.0)
    var baselineLineOpacity: Double = 0.22
    var baselineEndFadeFraction: CGFloat = 0.040

    // MARK: - Hashable

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
        && colorKey(lhs.coreMidColor) == colorKey(rhs.coreMidColor)
        && colorKey(lhs.coreBottomColor) == colorKey(rhs.coreBottomColor)
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
        && lhs.fuzzRasterMaxPixels == rhs.fuzzRasterMaxPixels
        && lhs.fuzzEdgePower == rhs.fuzzEdgePower
        && lhs.fuzzClumpCellPixels == rhs.fuzzClumpCellPixels
        && lhs.fuzzHazeStrength == rhs.fuzzHazeStrength
        && lhs.fuzzSpeckStrength == rhs.fuzzSpeckStrength
        && lhs.fuzzInsideThreshold == rhs.fuzzInsideThreshold
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
        hasher.combine(Self.colorKey(coreMidColor))
        hasher.combine(Self.colorKey(coreBottomColor))

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
        hasher.combine(fuzzRasterMaxPixels)
        hasher.combine(fuzzEdgePower)
        hasher.combine(fuzzClumpCellPixels)
        hasher.combine(fuzzHazeStrength)
        hasher.combine(fuzzSpeckStrength)
        hasher.combine(fuzzInsideThreshold)

        hasher.combine(Self.colorKey(baselineColor))
        hasher.combine(baselineLineOpacity)
        hasher.combine(baselineEndFadeFraction)
    }

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
