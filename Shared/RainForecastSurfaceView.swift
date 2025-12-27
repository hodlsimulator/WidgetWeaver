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
    var baselineFractionFromTop: CGFloat = 0.84

    /// Top headroom fraction of chart height.
    var topHeadroomFraction: CGFloat = 0.16

    /// Typical peak height above baseline as a fraction of chart height.
    /// Robust max (percentile) maps to this height; larger values may rise further.
    var typicalPeakFraction: CGFloat = 0.52

    /// Percentile used as the robust “max” for scaling.
    var robustMaxPercentile: Double = 0.93

    /// Gamma < 1 lifts mid-range values (prevents thin strip).
    var intensityGamma: Double = 0.65

    /// Dense sampling cap for path building.
    /// Kept below ultra-high values to avoid widget render timeouts.
    var maxDenseSamples: Int = 256

    /// Baseline inset in pixels to avoid clipping.
    var baselineAntiClipInsetPixels: Double = 0.75

    /// Tail easing so the first/last portion tapers to the baseline even if endpoints are non-zero.
    var edgeEasingFraction: CGFloat = 0.10
    var edgeEasingPower: Double = 1.7

    // MARK: - Core (opaque volume)

    /// Core fill colour (solid; no vertical gradient fill).
    var coreBodyColor: Color = Color(red: 0.00, green: 0.10, blue: 0.42)

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
    var rimInnerOpacity: Double = 0.30
    var rimInnerWidthPixels: Double = 1.05

    /// Outer halo drawn outside the core.
    var rimOuterOpacity: Double = 0.12
    var rimOuterWidthPixels: Double = 5.2

    // MARK: - Gloss (inside-only)

    var glossEnabled: Bool = true
    var glossMaxOpacity: Double = 0.14
    var glossDepthPixels: ClosedRange<Double> = 9.0...14.0
    var glossSoftBlurPixels: Double = 0.6

    // MARK: - Glints (tiny, local maxima only)

    var glintEnabled: Bool = true
    var glintColor: Color = Color(red: 0.95, green: 0.99, blue: 1.0)
    var glintMaxOpacity: Double = 0.18
    var glintBlurPixels: Double = 1.0
    var glintMinHeightFraction: Double = 0.78
    var glintMaxCount: Int = 1

    // MARK: - Fuzz (granular speckle outside core)

    var fuzzEnabled: Bool = true

    /// Blue-only mist (avoid grey haze).
    var fuzzColor: Color = Color(red: 0.05, green: 0.32, blue: 1.00)

    var fuzzMaxOpacity: Double = 0.22

    /// fuzzWidth ≈ 18–28% of chart height
    var fuzzWidthFraction: CGFloat = 0.26

    /// Pixel clamp so fuzz stays consistent across very small/large chart sizes.
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 12.0...130.0

    /// Base density (converted into granular mist via deterministic dithering).
    var fuzzBaseDensity: Double = 0.86

    /// Stronger concentration near baseline / shoulders.
    var fuzzLowHeightPower: Double = 2.8

    /// Keeps a small envelope even when certainty is high.
    var fuzzUncertaintyFloor: Double = 0.18

    /// Optional micro-blur (< 1 px) for fuzz only. Kept at 0 for widget safety.
    var fuzzMicroBlurPixels: Double = 0.0

    /// Legacy knobs kept for compatibility (no longer drive the fuzz pipeline).
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.5...1.15
    var fuzzMaxAttemptsPerColumn: Int = 24
    var fuzzMaxColumns: Int = 900
    var fuzzSpeckleBudget: Int = 6500

    /// Hard cap on fuzz raster pixels (keeps widgets from timing out).
    var fuzzRasterMaxPixels: Int = 220_000

    /// Edge falloff curve (higher = tighter to surface).
    var fuzzEdgePower: Double = 0.65

    /// Clump cell size in pixels (at fuzz raster scale).
    var fuzzClumpCellPixels: Double = 12.0

    /// Relative strength of the continuous haze vs bright specks.
    var fuzzHazeStrength: Double = 0.72
    var fuzzSpeckStrength: Double = 1.0

    /// Inside threshold for the rasterised core mask (higher reduces edge bleed).
    var fuzzInsideThreshold: UInt8 = 14

    // MARK: - Baseline

    var baselineColor: Color = Color(red: 0.55, green: 0.75, blue: 1.0)
    var baselineLineOpacity: Double = 0.22
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
