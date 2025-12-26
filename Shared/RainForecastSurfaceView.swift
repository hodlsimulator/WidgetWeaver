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

    /// Top headroom fraction of chart height (≈ 6–10%).
    var topHeadroomFraction: CGFloat = 0.08

    /// Typical peak height above baseline as a fraction of chart height (≈ 55–65%).
    var typicalPeakFraction: CGFloat = 0.60

    /// Percentile used as the robust “max” for scaling (≈ 90–95th of non-zero values).
    var robustMaxPercentile: Double = 0.93

    /// Gamma < 1 lifts mid-range values (prevents thin strip).
    var intensityGamma: Double = 0.65

    /// Dense sampling cap for path building.
    /// Kept below ultra-high values to avoid widget render timeouts.
    var maxDenseSamples: Int = 1024

    /// Baseline inset in pixels to avoid clipping at the bottom edge.
    var baselineAntiClipInsetPixels: Double = 0.75

    // MARK: - Core (opaque volume)

    var coreTopColor: Color = Color(red: 0.12, green: 0.45, blue: 1.0)
    var coreMidColor: Color = Color(red: 0.03, green: 0.22, blue: 0.78)
    var coreBottomColor: Color = Color(red: 0.00, green: 0.05, blue: 0.18)

    // MARK: - Gloss (inside-only)

    var glossEnabled: Bool = true
    var glossMaxOpacity: Double = 0.18
    var glossDepthPixels: ClosedRange<Double> = 8.0...14.0
    var glossSoftBlurPixels: Double = 0.6

    // MARK: - Glints (tiny, local maxima only)

    var glintEnabled: Bool = true
    var glintColor: Color = Color(red: 0.95, green: 0.99, blue: 1.0)
    var glintMaxOpacity: Double = 0.28
    var glintBlurPixels: Double = 1.0
    var glintMinHeightFraction: Double = 0.55
    var glintMaxCount: Int = 2

    // MARK: - Fuzz (granular speckle outside core)

    var fuzzEnabled: Bool = true
    var fuzzColor: Color = Color(red: 0.65, green: 0.90, blue: 1.0)
    var fuzzMaxOpacity: Double = 0.18

    /// fuzzWidth ≈ 10–20% of chart height
    var fuzzWidthFraction: CGFloat = 0.16

    /// Pixel clamp so fuzz stays consistent across very small/large chart sizes.
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 10.0...90.0

    /// Base density (turned into speckles via deterministic thresholding).
    var fuzzBaseDensity: Double = 0.55

    /// Stronger concentration near baseline / lower slopes.
    var fuzzLowHeightPower: Double = 1.7

    /// Keeps a small envelope even when certainty is high.
    var fuzzUncertaintyFloor: Double = 0.10

    /// Optional micro-blur (< 1 px) for fuzz only.
    /// Defaulted to 0 for widget safety; can be bumped slightly if needed.
    var fuzzMicroBlurPixels: Double = 0.0

    /// Speckle radius range in pixels.
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
