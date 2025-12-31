//
//  RainForecastSurfaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/23/25.
//
//  SwiftUI view for the nowcast “rain surface” chart.
//  Keeps the background pure black and delegates all rendering to RainForecastSurfaceRenderer.
//

import SwiftUI

struct RainForecastSurfaceView: View {

    @Environment(\.displayScale) private var displayScale
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.wwThumbnailRenderingEnabled) private var thumbnailRenderingEnabled
    @Environment(\.wwLowGraphicsBudget) private var lowGraphicsBudget

    private let intensities: [Double]
    private let certainties: [Double]
    private let configuration: RainForecastSurfaceConfiguration

    init(
        intensities: [Double],
        certainties: [Double] = [],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties = certainties
        self.configuration = configuration
    }

    init(
        intensities: [Double],
        certainties: [Double?],
        configuration: RainForecastSurfaceConfiguration = RainForecastSurfaceConfiguration()
    ) {
        self.intensities = intensities
        self.certainties = certainties.map { $0 ?? 0.0 }
        self.configuration = configuration
    }

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)

            var ctx = context
            ctx.fill(Path(rect), with: .color(.black))

            var cfg = configuration
            cfg.applyWidgetPlaceholderBudgetGuardrails(
                isLowBudget: isLowBudgetRender,
                displayScale: displayScale,
                size: size
            )

            let renderer = RainForecastSurfaceRenderer(
                intensities: intensities,
                certainties: certainties,
                configuration: cfg
            )

            renderer.render(in: &ctx, rect: rect, displayScale: displayScale)
        }
        .background(Color.black)
    }

    private var isLowBudgetRender: Bool {
        if redactionReasons.contains(.placeholder) { return true }
        if !thumbnailRenderingEnabled { return true }
        if lowGraphicsBudget { return true }
        return false
    }
}

// MARK: - Configuration

struct RainForecastSurfaceConfiguration {

    // Layout
    var baselineFractionFromTop: Double = 0.68
    var topHeadroomFraction: Double = 0.07
    var typicalPeakFraction: Double = 0.72

    // End easing (makes tails feel “soft” instead of cut off)
    var edgeEasingFraction: Double = 0.03
    var edgeEasingPower: Double = 1.90

    // Intensity -> height mapping
    var intensityReferenceMaxMMPerHour: Double = 6.0
    var robustMaxPercentile: Double = 0.92
    var intensityGamma: Double = 1.20

    // Core shading
    var coreBodyColor: Color = Color(red: 0.12, green: 0.43, blue: 0.98).opacity(0.78)
    var coreTopColor: Color = Color(red: 0.40, green: 0.86, blue: 1.00).opacity(0.94)
    var coreTopMix: Double = 0.62
    var coreFadeFraction: Double = 0.15

    // Fuzz / uncertainty styling (primary visual)
    var fuzzEnabled: Bool = true
    var canEnableFuzz: Bool = true
    var fuzzColor: Color = Color.white
    var fuzzMaxOpacity: Double = 0.42
    var fuzzWidthFraction: Double = 0.040
    var fuzzWidthPixelsClamp: ClosedRange<Double> = 2.0...24.0
    var fuzzDensity: Double = 1.45

    // Chance -> fuzz mapping
    var fuzzChanceThreshold: Double = 0.60
    var fuzzChanceTransition: Double = 0.24
    var fuzzChanceExponent: Double = 1.35
    var fuzzChanceFloor: Double = 0.24
    var fuzzChanceMinStrength: Double = 0.08

    // Fuzz emphasis around ends / base
    var fuzzTailMinutes: Double = 7.0
    var fuzzLowHeightPower: Double = 1.7
    var fuzzLowHeightBoost: Double = 1.55

    // Optional haze (kept low by default to avoid lifting the black background)
    var fuzzHazeStrength: Double = 0.12
    var fuzzHazeBlurFractionOfBand: Double = 0.26
    var fuzzHazeStrokeWidthFactor: Double = 1.10
    var fuzzInsideHazeStrokeWidthFactor: Double = 0.55

    // Inside speckles (legacy knobs retained)
    var fuzzInsideWidthFactor: Double = 0.62
    var fuzzInsideOpacityFactor: Double = 0.88

    // Particle speckles (legacy knobs retained; texture fuzz path ignores these)
    var fuzzSpeckStrength: Double = 1.35
    var fuzzSpeckleBudget: Int = 7800
    var fuzzSpeckleRadiusPixels: ClosedRange<Double> = 0.30...2.0
    var fuzzInsideSpeckleFraction: Double = 0.55

    // Distance distributions (legacy knobs retained)
    var fuzzDistancePowerOutside: Double = 1.10
    var fuzzDistancePowerInside: Double = 0.75
    var fuzzAlongTangentJitter: Double = 0.35

    // Edge suppression window (prevents peppering far-away dry baseline)
    var fuzzSlopeReferenceBandFraction: Double = 0.25
    var fuzzEdgeWindowPx: Double = 12.0

    // NEW: Texture-based fuzz (WidgetKit-safe, “dissipation” look)
    var fuzzTextureEnabled: Bool = true
    var fuzzTextureTilePixels: Int = 256
    var fuzzTextureGradientStops: Int = 28
    var fuzzTextureInnerBandMultiplier: Double = 1.35
    var fuzzTextureOuterBandMultiplier: Double = 2.60
    var fuzzTextureInnerOpacityMultiplier: Double = 0.85
    var fuzzTextureOuterOpacityMultiplier: Double = 0.45

    // Outer dust (outside the core body)
    var fuzzOuterDustEnabled: Bool = true
    var fuzzOuterDustEnabledInAppExtension: Bool = false
    var fuzzOuterDustPassCount: Int = 3
    var fuzzOuterDustPassCountInAppExtension: Int = 2

    // Legacy knobs (kept for compatibility with existing code; renderer ignores these for now)
    var fuzzErodeEnabled: Bool = true
    var fuzzErodeStrength: Double = 1.05
    var fuzzErodeBlurFractionOfBand: Double = 0.06
    var fuzzErodeStrokeWidthFactor: Double = 0.56
    var fuzzErodeEdgePower: Double = 1.35
    var fuzzErodeRimInsetPixels: Double = 1.0

    // Gloss / glint (optional; not required for mockup match)
    var glossEnabled: Bool = false
    var glossMaxOpacity: Double = 0.10
    var glossHeightPower: Double = 1.20

    var glintEnabled: Bool = false
    var glintCount: Int = 10
    var glintMaxOpacity: Double = 0.18
    var glintRadiusPixels: ClosedRange<Double> = 0.7...2.2

    // Rim
    var rimEnabled: Bool = true
    var rimColor: Color = Color(red: 0.55, green: 0.95, blue: 1.00)
    var rimOpacity: Double = 0.18
    var rimWidthPixels: Double = 1.0

    // Legacy/compat knobs referenced by WidgetWeaverWeatherTemplateNowcastChart.swift
    var rimInnerOpacity: Double = 0.10
    var rimInnerWidthPixels: Double = 1.0
    var rimOuterOpacity: Double = 0.06
    var rimOuterWidthPixels: Double = 2.0

    // Baseline
    var baselineEnabled: Bool = true
    var baselineColor: Color = Color.white
    var baselineLineOpacity: Double = 0.05
    var baselineWidthPixels: Double = 1.0
    var baselineOffsetPixels: Double = 0.0
    var baselineEndFadeFraction: Double = 0.20

    // Renderer internals / budgets
    var sourceMinuteCount: Int = 60
    var maxDenseSamples: Int = 900

    // Deterministic noise
    var noiseSeed: UInt64 = 0xF00D_F00D_CAFE_BEEF
}

// MARK: - Budget guardrails (WidgetKit placeholder / previews)

private extension RainForecastSurfaceConfiguration {

    mutating func applyWidgetPlaceholderBudgetGuardrails(
        isLowBudget: Bool,
        displayScale: CGFloat,
        size: CGSize
    ) {
        let ds = (displayScale.isFinite && displayScale > 0) ? displayScale : 1.0

        // Hard clamps that should hold in all contexts.
        maxDenseSamples = max(120, min(maxDenseSamples, 900))

        let hardMaxSpeckles: Int = 9000
        fuzzSpeckleBudget = max(0, min(fuzzSpeckleBudget, hardMaxSpeckles))

        // Clamp fuzz width pixels to sane values so it can't explode with a large preview rect.
        let minW = max(0.0, min(fuzzWidthPixelsClamp.lowerBound, fuzzWidthPixelsClamp.upperBound))
        let maxW = max(minW, fuzzWidthPixelsClamp.upperBound)
        fuzzWidthPixelsClamp = minW...maxW

        // Ensure no negative widths/opacities.
        fuzzMaxOpacity = max(0.0, min(fuzzMaxOpacity, 1.0))
        rimInnerOpacity = max(0.0, min(rimInnerOpacity, 1.0))
        rimOuterOpacity = max(0.0, min(rimOuterOpacity, 1.0))
        baselineLineOpacity = max(0.0, min(baselineLineOpacity, 1.0))

        // Texture fuzz clamps.
        fuzzTextureTilePixels = max(32, min(fuzzTextureTilePixels, 512))
        fuzzTextureGradientStops = max(8, min(fuzzTextureGradientStops, 64))
        fuzzTextureInnerBandMultiplier = max(0.1, min(fuzzTextureInnerBandMultiplier, 6.0))
        fuzzTextureOuterBandMultiplier = max(0.1, min(fuzzTextureOuterBandMultiplier, 8.0))
        fuzzTextureInnerOpacityMultiplier = max(0.0, min(fuzzTextureInnerOpacityMultiplier, 2.0))
        fuzzTextureOuterOpacityMultiplier = max(0.0, min(fuzzTextureOuterOpacityMultiplier, 2.0))

        fuzzOuterDustPassCount = max(0, min(fuzzOuterDustPassCount, 4))
        fuzzOuterDustPassCountInAppExtension = max(0, min(fuzzOuterDustPassCountInAppExtension, 4))

        // WidgetKit placeholder / preview rendering is very budget constrained.
        // Degrade visuals by removing extras first.
        guard isLowBudget else { return }

        // 1) Remove optional highlights.
        glossEnabled = false
        glintEnabled = false

        // 2) Remove any haze/blur paths that can trigger expensive rasterisation.
        fuzzHazeStrength = 0.0
        fuzzHazeBlurFractionOfBand = 0.0

        // 3) Clamp work proportional to width.
        let wPx = max(1.0, Double(size.width * ds))
        let conservativeDense = max(120, min(Int(wPx * 0.6), 260))
        maxDenseSamples = min(maxDenseSamples, conservativeDense)

        // 4) Reduce particle knobs (legacy; texture path ignores, but keep sane).
        fuzzSpeckleBudget = min(fuzzSpeckleBudget, 650)
        fuzzDensity = min(fuzzDensity, 0.85)
        fuzzInsideSpeckleFraction = min(fuzzInsideSpeckleFraction, 0.25)
        fuzzAlongTangentJitter = min(fuzzAlongTangentJitter, 0.35)

        // 5) Final degrade: disable fuzz entirely for placeholder/previews.
        canEnableFuzz = false
    }
}
