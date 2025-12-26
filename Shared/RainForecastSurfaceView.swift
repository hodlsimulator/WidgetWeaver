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

    // MARK: - Geometry (shape-agnostic)

    /// Baseline position as a fraction of chart height from the top.
    var baselineFractionFromTop: CGFloat = 0.596

    /// Top headroom fraction of chart height (caps the absolute maximum height).
    var topHeadroomFraction: CGFloat = 0.30

    /// Typical peak height above baseline as a fraction of chart height.
    var typicalPeakFraction: CGFloat = 0.195

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

    /// Supersampling factor for the offscreen mask/field raster.
    var rasterSupersample: CGFloat = 1.0

    /// Max raster width (in pixels) for mask/field passes.
    var rasterMaxWidthPixels: Int = 720

    /// Max raster height (in pixels) for mask/field passes.
    var rasterMaxHeightPixels: Int = 420

    /// Max total pixels (width * height) for mask/field passes.
    var rasterMaxTotalPixels: Int = 240_000

    /// Mask threshold (0–255) used to define “inside” for field passes.
    /// A small threshold prevents fuzz from leaking into the anti-aliased edge.
    var maskInsideThreshold: UInt8 = 16

    // MARK: - Core (opaque volume)

    /// Core fill colour (solid; no rect-aligned gradient fill).
    var coreBodyColor: Color = Color(red: 0.02, green: 0.14, blue: 0.52)

    /// Highlight colour used by inside lighting (surface-driven).
    var coreTopColor: Color = Color(red: 0.12, green: 0.45, blue: 1.0)

    /// Kept for compatibility / theming, but not used for the core fill.
    var coreMidColor: Color = Color(red: 0.03, green: 0.22, blue: 0.78)

    /// Kept for compatibility / theming, but not used for the core fill.
    var coreBottomColor: Color = Color(red: 0.00, green: 0.05, blue: 0.18)

    // MARK: - Rim (repurposed as optional wide bloom; no stroke tracing)

    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.62, green: 0.88, blue: 1.00)

    /// Inner rim kept for compatibility; not used (avoid traced line).
    var rimInnerOpacity: Double = 0.0
    var rimInnerWidthPixels: Double = 0.0

    /// Outer bloom (wide, low opacity).
    var rimOuterOpacity: Double = 0.06
    var rimOuterWidthPixels: Double = 14.0

    // MARK: - Inside lighting (replaces “gloss band”)

    var glossEnabled: Bool = true
    var glossMaxOpacity: Double = 0.12
    var glossDepthPixels: ClosedRange<Double> = 10.0...16.0

    /// Minimum surface height required before lighting sources are placed (in display pixels).
    var insideLightMinHeightPixels: Double = 3.0

    /// Kept for compatibility; not used.
    var glossSoftBlurPixels: Double = 0.0

    // MARK: - Glints (optional, subtle)

    var glintEnabled: Bool = false
    var glintColor: Color = Color(red: 0.95, green: 0.99, blue: 1.0)
    var glintMaxOpacity: Double = 0.10
    var glintBlurPixels: Double = 0.0
    var glintMinHeightFraction: Double = 0.78
    var glintMaxCount: Int = 1

    // MARK: - Fuzz (granular mist outside core)

    var fuzzEnabled: Bool = true
    var fuzzColor: Color = Color(red: 0.65, green: 0.90, blue: 1.0)
    var fuzzMaxOpacity: Double = 0.14

    /// fuzzWidth ≈ 10–22% of chart height.
    var fuzzWidthFraction: CGFloat = 0.20

    /// Pixel clamp so fuzz stays consistent across very small/large chart sizes.
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 10.0...90.0

    /// Base density (turned into speckles via deterministic thresholding).
    var fuzzBaseDensity: Double = 0.62

    /// Stronger concentration near baseline / shoulders.
    var fuzzLowHeightPower: Double = 2.6

    /// Keeps a small envelope even when certainty is high.
    var fuzzUncertaintyFloor: Double = 0.12

    /// Kept for compatibility; not used (speckles are grid-dithered).
    var fuzzMicroBlurPixels: Double = 0.0

    /// Kept for compatibility; not used (no circle spawning).
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.5...1.2

    /// Kept for compatibility; not used (grid-dithered).
    var fuzzMaxAttemptsPerColumn: Int = 24

    /// Kept for compatibility; not used (grid-dithered).
    var fuzzMaxColumns: Int = 900

    /// Hard cap for speckle population (deterministically thinned if exceeded).
    var fuzzSpeckleBudget: Int = 7_500

    // MARK: - Baseline

    var baselineColor: Color = Color(red: 0.48, green: 0.64, blue: 0.82)
    var baselineLineOpacity: Double = 0.18
    var baselineEndFadeFraction: CGFloat = 0.035
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
