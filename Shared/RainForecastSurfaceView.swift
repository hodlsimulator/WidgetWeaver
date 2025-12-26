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
    /// Renderer further mixes in render size so grain is stable per widget size.
    var noiseSeed: UInt64 = 0

    // MARK: - Geometry (shape-agnostic)

    /// Baseline position as a fraction of chart height from the top.
    /// The mock baseline sits well above the bottom, leaving empty space beneath.
    var baselineFractionFromTop: CGFloat = 0.596

    /// Top headroom fraction of chart height (≈ 25–40%).
    /// This caps the absolute maximum height (even for extreme intensities).
    var topHeadroomFraction: CGFloat = 0.30

    /// Typical peak height above baseline as a fraction of chart height (≈ 18–24%).
    /// Robust max (percentile) maps to this height; larger values may rise a bit further.
    var typicalPeakFraction: CGFloat = 0.195

    /// Percentile used as the robust “max” for scaling (≈ 90–95th of non-zero values).
    var robustMaxPercentile: Double = 0.93

    /// Gamma < 1 lifts mid-range values (prevents thin strip).
    var intensityGamma: Double = 0.65

    /// Dense sampling cap for path building.
    /// Kept below ultra-high values to avoid widget render timeouts.
    var maxDenseSamples: Int = 1024

    /// Baseline inset in pixels to avoid clipping.
    /// Mostly relevant if baseline is placed very near the edges.
    var baselineAntiClipInsetPixels: Double = 0.75

    // MARK: - Core (opaque volume)

    /// Core fill colour (solid; no vertical gradient fill).
    var coreBodyColor: Color = Color(red: 0.02, green: 0.14, blue: 0.52)

    /// Highlight colour used by the gloss band and rim.
    var coreTopColor: Color = Color(red: 0.12, green: 0.45, blue: 1.0)

    /// Kept for compatibility / theming, but not used for the core fill.
    var coreMidColor: Color = Color(red: 0.03, green: 0.22, blue: 0.78)

    /// Kept for compatibility / theming, but not used for the core fill.
    var coreBottomColor: Color = Color(red: 0.00, green: 0.05, blue: 0.18)

    // MARK: - Rim (crisp surface edge + subtle outer halo)

    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.62, green: 0.88, blue: 1.00)

    /// Inner rim drawn inside the core.
    var rimInnerOpacity: Double = 0.55
    var rimInnerWidthPixels: Double = 1.15

    /// Outer halo drawn outside the core.
    var rimOuterOpacity: Double = 0.14
    var rimOuterWidthPixels: Double = 5.5

    // MARK: - Gloss (inside-only)

    var glossEnabled: Bool = true
    var glossMaxOpacity: Double = 0.18
    var glossDepthPixels: ClosedRange<Double> = 8.0...14.0
    var glossSoftBlurPixels: Double = 0.6

    // MARK: - Glints (tiny, local maxima only)

    var glintEnabled: Bool = true
    var glintColor: Color = Color(red: 0.95, green: 0.99, blue: 1.0)
    var glintMaxOpacity: Double = 0.20
    var glintBlurPixels: Double = 1.0
    var glintMinHeightFraction: Double = 0.55
    var glintMaxCount: Int = 1

    // MARK: - Fuzz (granular speckle outside core)

    var fuzzEnabled: Bool = true
    var fuzzColor: Color = Color(red: 0.65, green: 0.90, blue: 1.0)
    var fuzzMaxOpacity: Double = 0.18

    /// fuzzWidth ≈ 10–22% of chart height
    var fuzzWidthFraction: CGFloat = 0.18

    /// Pixel clamp so fuzz stays consistent across very small/large chart sizes.
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 10.0...90.0

    /// Base density (turned into speckles via deterministic thresholding).
    var fuzzBaseDensity: Double = 0.55

    /// Stronger concentration near baseline / lower slopes.
    var fuzzLowHeightPower: Double = 2.4

    /// Keeps a small envelope even when certainty is high.
    var fuzzUncertaintyFloor: Double = 0.10

    /// Optional micro-blur (< 1 px) for fuzz only.
    /// Defaulted to 0 for widget safety; can be bumped slightly if needed.
    var fuzzMicroBlurPixels: Double = 0.0

    /// Speckle radius range in pixels (near-boundary).
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.5...1.2

    /// Upper bound on speckle attempts per column.
    var fuzzMaxAttemptsPerColumn: Int = 24

    /// Hard cap on how many fuzz columns are processed (stride is applied when denseCount is larger).
    var fuzzMaxColumns: Int = 900

    /// Hard cap on total speckle attempts for the entire render (keeps widgets from timing out).
    var fuzzSpeckleBudget: Int = 6500

    // MARK: - Baseline

    var baselineColor: Color = Color(red: 0.55, green: 0.75, blue: 1.0)
    var baselineLineOpacity: Double = 0.30
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
