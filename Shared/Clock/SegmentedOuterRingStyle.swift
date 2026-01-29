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

    /// Subtle darkening in the bed channels adjacent to the blocks.
    ///
    /// The occlusion is rendered onto the bed (under the blocks) so it only shows through the gaps.
    /// This avoids per-segment blur shadows while still giving the blocks a "seated" feel.
    struct BedContactOcclusion {
        /// Darkening band in the outer channel (between `blockOuter` and `bedOuter`).
        let outerBandGradient: Gradient
        /// Darkening band in the inner channel (between `bedInner` and `blockInner`).
        let innerBandGradient: Gradient
    }

    /// Block bevel tokens (screen-space lighting: highlight top-left, shade bottom-right).
    struct BlockBevel {
        /// Highlight overlay (screen blend).
        let highlightOverlayGradient: Gradient
        /// Shadow overlay (multiply blend).
        let shadowOverlayGradient: Gradient

        /// Perimeter rim highlight (screen blend). Drawn as a clipped stroke so it remains inside the block.
        let perimeterHighlightGradient: Gradient
        /// Perimeter rim shadow (multiply blend). Drawn as a clipped stroke so it remains inside the block.
        let perimeterShadowGradient: Gradient

        /// Stroke width used for the perimeter rim strokes. This is the actual stroke width; clipping
        /// leaves approximately half of it inside the block.
        let perimeterRimStrokeWidth: CGFloat

        /// Stroke width for the outer arc highlight accent (drawn inside the block).
        let outerEdgeLineWidth: CGFloat
        /// Stroke width for the inner arc shadow accent (drawn inside the block).
        let innerEdgeLineWidth: CGFloat

        /// Stroke width for radial edge bevel accents (drawn inside the block).
        let radialEdgeStrokeWidth: CGFloat

        /// Inset from the inner/outer arcs for radial edge accents (points).
        let radialEdgeEndInset: CGFloat

        /// Inset towards the block interior for radial edge accents (points).
        let radialEdgeInset: CGFloat

        /// Colour used for the lit radial edge accent (screen blend).
        let radialEdgeHighlightColour: Color

        /// Colour used for the shaded radial edge accent (multiply blend).
        let radialEdgeShadowColour: Color
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
    let bedContactOcclusion: BedContactOcclusion

    let blockFillEvenGradient: Gradient
    let blockFillOddGradient: Gradient
    let blockBevel: BlockBevel

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
            WWClock.clamp(bedThickness * 0.085, min: px, max: bedThickness * 0.155),
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

        // Physical-pixel gap policy:
        // - Widget sizes (44/60) must show an obviously open "air" cut where the bed is visible.
        // - Express the gap in physical pixels so it stays stable across device scales.
        //
        // Rule: keep at least 1 pt of gap in the current render context, clamped to 2–3 px.
        let minGapPoints: CGFloat = 1.0
        let desiredGapPx = (minGapPoints * max(scale, 1.0)).rounded(.up)
        let gapPixels = WWClock.clamp(desiredGapPx, min: 2.0, max: 3.0)

        let gapPoints = WWClock.pixel(gapPixels / max(scale, 1.0), scale: scale)

        let midR = max(px, self.radii.blockMid)
        let gapAngular = max(0.0, gapPoints / midR)

        // Additional trim protects the air gap from AA closure. Keep this minimal to avoid a divider read.
        // Expressed in physical pixels per edge.
        let edgeTrimPx: CGFloat = (gapPixels <= 2.0) ? 0.12 : 0.10
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
            WWClock.clamp(bedThickness * 0.075, min: px, max: px * 2.0),
            scale: scale
        )

        let lipHighlight = Gradient(stops: [
            .init(color: WWClock.colour(0xFFFFFF, alpha: 0.08), location: 0.00),
            .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.30),
        ])

        let lipShadow = Gradient(stops: [
            .init(color: WWClock.colour(0x000000, alpha: 0.40), location: 0.00),
            .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.34),
        ])

        self.bedLips = BedLips(
            lineWidth: lipLineWidth,
            highlightGradient: lipHighlight,
            shadowGradient: lipShadow
        )

        // Bed contact occlusion (under the blocks; shows only through gaps).
        let occlusionAlpha: Double = {
            // Keep the bed visible through the air gaps without turning them into dark dividers.
            let a = 0.16 - Double(gapPixels - 2.0) * 0.04
            return Double(WWClock.clamp(CGFloat(a), min: 0.10, max: 0.16))
        }()

        self.bedContactOcclusion = BedContactOcclusion(
            outerBandGradient: Gradient(stops: [
                .init(color: WWClock.colour(0x000000, alpha: occlusionAlpha), location: 0.00),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 1.00),
            ]),
            innerBandGradient: Gradient(stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.00),
                .init(color: WWClock.colour(0x000000, alpha: occlusionAlpha), location: 1.00),
            ])
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

        // Block bevel shading (no blur): overlays + tight edge accents.
        let rimStrokeWidth = WWClock.pixel(2.0 / max(scale, 1.0), scale: scale)
        let edgeStrokeWidth = WWClock.pixel(1.0 / max(scale, 1.0), scale: scale)

        // Radial edge accents are inset using sub-pixel values (not rounded), so the accent never lands
        // directly in the air gap even when the clip mask is antialiased.
        let radialEdgeInsetPx: CGFloat = (gapPixels <= 2.0) ? 0.52 : 0.44
        let radialEdgeInset = radialEdgeInsetPx / max(scale, 1.0)

        let radialEdgeEndInsetPx: CGFloat = 0.85
        let radialEdgeEndInset = radialEdgeEndInsetPx / max(scale, 1.0)

        self.blockBevel = BlockBevel(
            highlightOverlayGradient: Gradient(stops: [
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.18), location: 0.00),
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.36),
            ]),
            shadowOverlayGradient: Gradient(stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.22), location: 0.00),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.58),
            ]),
            perimeterHighlightGradient: Gradient(stops: [
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.18), location: 0.00),
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.68),
            ]),
            perimeterShadowGradient: Gradient(stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.36), location: 0.00),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.72),
            ]),
            perimeterRimStrokeWidth: max(px, rimStrokeWidth),
            outerEdgeLineWidth: max(px, edgeStrokeWidth),
            innerEdgeLineWidth: max(px, edgeStrokeWidth),
            radialEdgeStrokeWidth: max(px, edgeStrokeWidth),
            radialEdgeEndInset: radialEdgeEndInset,
            radialEdgeInset: radialEdgeInset,
            radialEdgeHighlightColour: WWClock.colour(0xFFFFFF, alpha: 0.12),
            radialEdgeShadowColour: WWClock.colour(0x000000, alpha: 0.20)
        )

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
