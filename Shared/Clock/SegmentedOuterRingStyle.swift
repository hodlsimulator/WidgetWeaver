//
//  SegmentedOuterRingStyle.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI

/// Style and geometry for the Segmented face outer ring.
///
/// This is the single source of truth for:
/// - Radii (bed + blocks)
/// - Physical-pixel separator gap policy
/// - Optional diagnostics used to validate the Canvas renderer path in WidgetKit
struct SegmentedOuterRingStyle {

    struct Radii {
        let bedOuter: CGFloat
        let bedInner: CGFloat
        let blockOuter: CGFloat
        let blockInner: CGFloat

        var bedThickness: CGFloat { bedOuter - bedInner }
        var blockThickness: CGFloat { blockOuter - blockInner }
        var blockMid: CGFloat { (blockOuter + blockInner) * 0.5 }
    }

    struct Gap {
        /// Gap width in physical pixels.
        let pixels: CGFloat
        /// Gap width in points.
        let linear: CGFloat
        /// Gap width in radians at the block mid radius.
        let angular: CGFloat

        /// Extra angular trimming (per edge) applied to protect the air gap from anti-aliasing bleed.
        ///
        /// The nominal gap is already defined in physical pixels. This trim is intentionally small and
        /// only exists to ensure the gap remains visibly "open" at 44/60 after edge AA.
        let edgeTrimAngular: CGFloat
    }

    struct BedLips {
        /// Line width used for the bed inner/outer lips.
        let lineWidth: CGFloat
        /// Highlight gradient used for lip strokes (direction is chosen per lip).
        let highlightGradient: Gradient
        /// Shadow gradient used for lip strokes (direction is chosen per lip).
        let shadowGradient: Gradient
    }

    struct Diagnostic {
        /// When enabled, alternate block fills and per-block markers are drawn.
        let enabled: Bool
        let markerColour: Color
        let markerRadius: CGFloat
    }

    let radii: Radii
    let gap: Gap

    let bedFillGradient: Gradient
    let bedLips: BedLips

    let blockFillEvenGradient: Gradient
    let blockFillOddGradient: Gradient

    let diagnostic: Diagnostic

    init(dialRadius: CGFloat, scale: CGFloat) {
        let px = WWClock.px(scale: scale)

        // Geometry mirrors the existing Segmented face tuning so overall proportions remain stable.
        let outerInset = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.010, min: px, max: dialRadius * 0.018),
            scale: scale
        )

        let bedOuter = WWClock.pixel(max(1.0, dialRadius - outerInset), scale: scale)

        let targetBedThickness = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.185, min: px * 6.0, max: dialRadius * 0.205),
            scale: scale
        )

        let bedInner = WWClock.pixel(max(px, bedOuter - targetBedThickness), scale: scale)
        let bedThickness = max(px, bedOuter - bedInner)

        // Channel inset keeps the bed visible around the blocks and through the gaps.
        let channelInset = WWClock.pixel(
            WWClock.clamp(bedThickness * 0.11, min: px, max: bedThickness * 0.18),
            scale: scale
        )

        let blockOuter = WWClock.pixel(max(px, bedOuter - channelInset), scale: scale)
        let blockInner = WWClock.pixel(max(px, bedInner + channelInset), scale: scale)

        self.radii = Radii(
            bedOuter: bedOuter,
            bedInner: bedInner,
            blockOuter: blockOuter,
            blockInner: blockInner
        )

        // Physical-pixel gap policy: keep separators readable at 44/60.
        let gapPixelsRaw = (dialRadius * scale * 0.045).rounded(.toNearestOrAwayFromZero)
        let gapPixels = WWClock.clamp(gapPixelsRaw, min: 2.0, max: 6.0)

        let gapPoints = WWClock.pixel(gapPixels / max(scale, 1.0), scale: scale)

        let midR = max(px, self.radii.blockMid)
        let gapAngular = max(0.0, gapPoints / midR)

        // A small additional trim protects the gap from appearing "filled" due to AA bleed at tiny sizes.
        // The trim is expressed in physical pixels so it stays consistent at 44/60.
        let edgeTrimPx: CGFloat = (gapPixels <= 3.0) ? 0.5 : 0.35
        let edgeTrimPoints = edgeTrimPx / max(scale, 1.0)
        let edgeTrimAngular = max(0.0, edgeTrimPoints / midR)

        self.gap = Gap(
            pixels: gapPixels,
            linear: gapPoints,
            angular: gapAngular,
            edgeTrimAngular: edgeTrimAngular
        )

        let diagnosticEnabled: Bool
        #if DEBUG
        diagnosticEnabled = WidgetWeaverFeatureFlags.segmentedRingDiagnosticsEnabled
        #else
        diagnosticEnabled = false
        #endif

        // Bed material (recessed channel).
        // Keep visible form in WidgetKit snapshots (avoid dead-black flattening).
        self.bedFillGradient = Gradient(stops: [
            .init(color: WWClock.colour(0x131A24, alpha: 1.0), location: 0.00),
            .init(color: WWClock.colour(0x0A0D13, alpha: 1.0), location: 0.55),
            .init(color: WWClock.colour(0x030407, alpha: 1.0), location: 1.00),
        ])

        let lipLineWidth = WWClock.pixel(
            WWClock.clamp(bedThickness * 0.10, min: px, max: px * 3.0),
            scale: scale
        )

        let lipHighlight = Gradient(stops: [
            .init(color: WWClock.colour(0xFFFFFF, alpha: 0.12), location: 0.00),
            .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.45),
        ])

        let lipShadow = Gradient(stops: [
            .init(color: WWClock.colour(0x000000, alpha: 0.55), location: 0.00),
            .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.55),
        ])

        self.bedLips = BedLips(
            lineWidth: lipLineWidth,
            highlightGradient: lipHighlight,
            shadowGradient: lipShadow
        )

        // Block fill gradients.
        // The odd gradient is only used when the diagnostic overlay is enabled.
        self.blockFillEvenGradient = Gradient(stops: [
            .init(color: WWClock.colour(0x6C6C2A, alpha: 0.98), location: 0.00),
            .init(color: WWClock.colour(0x5A5A22, alpha: 0.98), location: 0.48),
            .init(color: WWClock.colour(0x3C3C12, alpha: 0.99), location: 1.00),
        ])

        self.blockFillOddGradient = Gradient(stops: [
            .init(color: WWClock.colour(0x5F5F25, alpha: 0.98), location: 0.00),
            .init(color: WWClock.colour(0x4E4E1D, alpha: 0.98), location: 0.48),
            .init(color: WWClock.colour(0x33330F, alpha: 0.99), location: 1.00),
        ])

        // Diagnostic markers: a tiny, high-contrast dot at each segment centre.
        let markerRadiusPx = WWClock.clamp(gapPixels * 0.55, min: 1.4, max: 2.4)
        let markerRadius = WWClock.pixel(markerRadiusPx / max(scale, 1.0), scale: scale)

        self.diagnostic = Diagnostic(
            enabled: diagnosticEnabled,
            markerColour: WWClock.colour(0xFF2D55, alpha: 0.92),
            markerRadius: markerRadius
        )
    }
}
