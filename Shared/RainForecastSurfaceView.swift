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

struct RainForecastSurfaceConfiguration: Hashable {
    // MARK: - Determinism

    /// Base seed (caller supplies start time / family / location mixing).
    /// Renderer further mixes in render size so patterns are stable per widget size.
    var noiseSeed: UInt64 = 0

    // MARK: - Geometry

    /// Baseline position as a fraction of chart height from the top.
    /// A higher value places the baseline lower (more vertical range above).
    var baselineFractionFromTop: CGFloat = 0.78

    /// Top headroom fraction of chart height (caps the absolute maximum height).
    var topHeadroomFraction: CGFloat = 0.14

    /// Typical peak height above baseline as a fraction of chart height.
    var typicalPeakFraction: CGFloat = 0.33

    /// Percentile used as the robust “max” for scaling.
    var robustMaxPercentile: Double = 0.93

    /// Gamma < 1 lifts mid-range values.
    var intensityGamma: Double = 0.65

    /// Dense sampling cap for silhouette creation (widget-safe).
    var maxDenseSamples: Int = 512

    /// Tail easing fraction (both ends) to prevent vertical cliffs when endpoints aren’t zero.
    var tailEasingFraction: CGFloat = 0.10

    /// Number of smoothing passes after resampling.
    var silhouetteSmoothingPasses: Int = 3

    /// Baseline inset in pixels to avoid clipping.
    var baselineAntiClipInsetPixels: Double = 0.75

    // MARK: - Raster (mask / fields)

    var rasterSupersample: CGFloat = 1.0
    var rasterMaxWidthPixels: Int = 720
    var rasterMaxHeightPixels: Int = 420
    var rasterMaxTotalPixels: Int = 240_000

    /// Mask threshold (0–255) used to define “inside” for field passes.
    var maskInsideThreshold: UInt8 = 16

    // MARK: - Core (opaque volume)

    var coreBodyColor: Color = Color(red: 0.02, green: 0.14, blue: 0.52)
    var coreTopColor: Color = Color(red: 0.12, green: 0.45, blue: 1.0)

    /// Kept for compatibility / theming, but not used for the core fill.
    var coreMidColor: Color = Color(red: 0.03, green: 0.22, blue: 0.78)

    /// Kept for compatibility / theming, but not used for the core fill.
    var coreBottomColor: Color = Color(red: 0.00, green: 0.05, blue: 0.18)

    // MARK: - Rim (wide bloom; no traced stroke)

    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.62, green: 0.88, blue: 1.00)

    /// Inner rim kept for compatibility; not used.
    var rimInnerOpacity: Double = 0.0
    var rimInnerWidthPixels: Double = 0.0

    /// Outer bloom (wide, low opacity).
    var rimOuterOpacity: Double = 0.06
    var rimOuterWidthPixels: Double = 14.0

    // MARK: - Inside lighting (subtle; surface-driven)

    var glossEnabled: Bool = true
    var glossMaxOpacity: Double = 0.10
    var glossDepthPixels: ClosedRange<Double> = 10.0...16.0
    var insideLightMinHeightPixels: Double = 3.0
    var glossSoftBlurPixels: Double = 0.0

    // MARK: - Glints (optional)

    var glintEnabled: Bool = false
    var glintColor: Color = Color(red: 0.95, green: 0.99, blue: 1.0)
    var glintMaxOpacity: Double = 0.10
    var glintBlurPixels: Double = 0.0
    var glintMinHeightFraction: Double = 0.78
    var glintMaxCount: Int = 1

    // MARK: - Fuzz (granular mist outside core)

    var fuzzEnabled: Bool = true
    var fuzzColor: Color = Color(red: 0.65, green: 0.90, blue: 1.0)
    var fuzzMaxOpacity: Double = 0.16

    /// Fuzz width as a fraction of chart height.
    var fuzzWidthFraction: CGFloat = 0.23

    /// Pixel clamp so fuzz stays consistent across very small/large chart sizes.
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 10.0...110.0

    /// Base density (turned into speckles via deterministic thresholding).
    var fuzzBaseDensity: Double = 0.92

    /// Higher values concentrate mist nearer the baseline.
    var fuzzLowHeightPower: Double = 1.9

    /// Keeps a visible envelope even when certainty is high.
    var fuzzUncertaintyFloor: Double = 0.45

    /// Renders fuzz at a reduced raster scale and upscales for a mistier read.
    var fuzzRenderScale: CGFloat = 0.72

    /// Low-frequency noise cell size in display pixels (clumps the mist).
    var fuzzFogCellPixels: Double = 18.0

    /// Hard cap for speckle population (deterministically thinned if exceeded).
    var fuzzSpeckleBudget: Int = 18_000

    // Kept for compatibility; not used.
    var fuzzMicroBlurPixels: Double = 0.0
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.5...1.2
    var fuzzMaxAttemptsPerColumn: Int = 24
    var fuzzMaxColumns: Int = 900

    // MARK: - Baseline

    var baselineColor: Color = Color(red: 0.48, green: 0.64, blue: 0.82)
    var baselineLineOpacity: Double = 0.14
    var baselineEndFadeFraction: CGFloat = 0.040
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
