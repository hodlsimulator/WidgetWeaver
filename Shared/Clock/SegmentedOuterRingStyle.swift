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
/// - Chamfer geometry used by the outer blocks
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

    struct ContentRadii {
        /// Midline of the block band, used for numeral placement.
        let blockBandMidRadius: CGFloat

        /// Radius used to place numeral centre points.
        let numeralRadius: CGFloat

        /// Outer radius of the tick marks (outer edge), clamped in physical pixels inside `blockInner`.
        let ticksOuterRadius: CGFloat
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
        /// For the BOLD v2 geometry this is intentionally near-zero; the gap must be encoded in the
        /// block geometry itself (not "faked" by trimming).
        let edgeTrimAngular: CGFloat
    }

    struct Chamfer {
        /// Chamfer depth in physical pixels.
        let pixels: CGFloat
        /// Chamfer depth in points.
        let depth: CGFloat
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

        /// Perimeter rim highlight (screen blend).
        let perimeterHighlightGradient: Gradient
        /// Perimeter rim shadow (multiply blend).
        let perimeterShadowGradient: Gradient

        /// Stroke width used for the perimeter rim strokes.
        let perimeterRimStrokeWidth: CGFloat

        /// Stroke width for the outer arc highlight accent (drawn inside the block).
        let outerEdgeLineWidth: CGFloat
        /// Stroke width for the inner arc shadow accent (drawn inside the block).
        let innerEdgeLineWidth: CGFloat

        /// Stroke width for chamfer/radial edge bevel accents (drawn inside the block).
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
        /// When enabled, per-block markers are drawn.
        let enabled: Bool
        let segmentMarkerColour: Color
        let gapMarkerColour: Color
        let markerRadius: CGFloat
    }

    let radii: Radii
    let contentRadii: ContentRadii
    let gap: Gap
    let chamfer: Chamfer

    let bedFillGradient: Gradient
    let bedLips: BedLips
    let bedContactOcclusion: BedContactOcclusion

    let blockFillEvenGradient: Gradient
    let blockFillOddGradient: Gradient
    let blockBevel: BlockBevel

    let diagnostic: Diagnostic

    init(dialRadius: CGFloat, scale: CGFloat) {
        let px = WWClock.px(scale: scale)

        // Geometry mirrors the existing Segmented face conventions so overall proportions remain stable.
        let outerInset = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.010, min: px, max: dialRadius * 0.018),
            scale: scale
        )

        let bedOuter = WWClock.pixel(max(1.0, dialRadius - outerInset), scale: scale)

        // Dial size normalisation for 44/60 tuning.
        let dialDiameter = dialRadius * 2.0
        let t = WWClock.clamp((dialDiameter - 44.0) / (60.0 - 44.0), min: 0.0, max: 1.0)

        // Block thickness targeting (physical pixels).
        //
        // Previous values (12px/17px) render as a thin trim line. The mock requires a materially thicker
        // band with the added thickness coming from the inner edge moving inward (towards centre).
        //
        // These targets are ~2.7x thicker than the prior band and are applied inward-only via bedInner.
        let blockThicknessPx44: CGFloat = 32.0
        let blockThicknessPx60: CGFloat = 46.0

        let blockThicknessPxRaw = blockThicknessPx44 + (t * (blockThicknessPx60 - blockThicknessPx44))
        let blockThicknessPx = WWClock.clamp(
            blockThicknessPxRaw.rounded(.toNearestOrAwayFromZero),
            min: blockThicknessPx44,
            max: blockThicknessPx60
        )

        // Channel policy (BOLD v2): fixed physical pixels so the bed stays visible around blocks at 44/60.
        // Targets: 2px outer + 2px inner (minimum 1px each).
        let minChannelPx: CGFloat = 1.0
        let targetOuterChannelPx: CGFloat = 2.0
        let targetInnerChannelPx: CGFloat = 2.0

        let minChannel = minChannelPx / max(scale, 1.0)
        let outerChannel = max(minChannel, targetOuterChannelPx / max(scale, 1.0))
        let innerChannel = max(minChannel, targetInnerChannelPx / max(scale, 1.0))

        let desiredBlockThickness = WWClock.pixel(blockThicknessPx / max(scale, 1.0), scale: scale)

        let desiredBedThicknessRaw = desiredBlockThickness + outerChannel + innerChannel
        let maxBedThickness = max(px, bedOuter - px)
        let bedThickness = WWClock.pixel(min(desiredBedThicknessRaw, maxBedThickness), scale: scale)

        let bedInner = WWClock.pixel(max(px, bedOuter - bedThickness), scale: scale)

        var blockOuter = WWClock.pixel(max(px, bedOuter - outerChannel), scale: scale)
        var blockInner = WWClock.pixel(max(px, bedInner + innerChannel), scale: scale)

        // Enforce minimum viable block thickness if the container is unusually small.
        if blockOuter <= blockInner {
            let fallbackChannel = WWClock.pixel(minChannel, scale: scale)
            blockOuter = WWClock.pixel(max(px, bedOuter - fallbackChannel), scale: scale)
            blockInner = WWClock.pixel(max(px, bedInner + fallbackChannel), scale: scale)
        }

        self.radii = Radii(
            bedOuter: bedOuter,
            bedInner: bedInner,
            blockOuter: blockOuter,
            blockInner: blockInner
        )

        // Content radii: numerals + tick ring move inward together when ring thickness changes.
        let blockBandMidRadius = WWClock.pixel(self.radii.blockMid, scale: scale)

        // Tick ring outer edge clearance from the segmented ring inner boundary (physical pixels).
        let ticksOuterClearanceBasePx: CGFloat = WWClock.clamp(3.0, min: 2.0, max: 4.0)
        // 15B1: shift the tick ring inward (uniform translation), without changing tick lengths.
        let ticksOuterShiftPx: CGFloat = WWClock.clamp(3.0, min: 2.0, max: 4.0)
        let ticksOuterClearancePx: CGFloat = ticksOuterClearanceBasePx + ticksOuterShiftPx
        let ticksOuterClearance = WWClock.pixel(ticksOuterClearancePx / max(scale, 1.0), scale: scale)

        let ticksOuterRadius = WWClock.pixel(
            max(px, self.radii.blockInner - ticksOuterClearance),
            scale: scale
        )

        self.contentRadii = ContentRadii(
            blockBandMidRadius: blockBandMidRadius,
            numeralRadius: blockBandMidRadius,
            ticksOuterRadius: ticksOuterRadius
        )

        // Physical-pixel gap policy:
        // - Target 3px at 44/60 so gaps read as open-air cuts without looking loose.
        // - Clamp to [2px..3px] and only go outside the range if a future renderer change requires it.
        let gapPixels: CGFloat = WWClock.clamp(3.0, min: 2.0, max: 3.0)
        let gapPoints = gapPixels / max(scale, 1.0)

        let midR = max(px, self.radii.blockMid)
        let gapAngular = max(0.0, gapPoints / midR)

        // For BOLD v2 the geometry itself defines the gap. Keep trim near-zero.
        let edgeTrimPx: CGFloat = 0.0
        let edgeTrimPoints = edgeTrimPx / max(scale, 1.0)
        let edgeTrimAngular = max(0.0, edgeTrimPoints / midR)

        self.gap = Gap(
            pixels: gapPixels,
            linear: gapPoints,
            angular: gapAngular,
            edgeTrimAngular: edgeTrimAngular
        )

        // Chamfer depth (scale-aware clamp):
        // - 2px at a 44pt dial diameter
        // - 3px at a 60pt dial diameter
        let chamferPixelsRaw = 2.0 + (t * 1.0)
        let chamferPixels = WWClock.clamp(chamferPixelsRaw.rounded(.toNearestOrAwayFromZero), min: 2.0, max: 3.0)
        let chamferPoints = chamferPixels / max(scale, 1.0)

        self.chamfer = Chamfer(
            pixels: chamferPixels,
            depth: chamferPoints
        )

        let diagnosticEnabled: Bool
        #if DEBUG
        diagnosticEnabled = false
        #else
        diagnosticEnabled = false
        #endif

        // Bed fill: dark neutral (not green), with a slight highlight on the top-left.
        self.bedFillGradient = Gradient(stops: [
            .init(color: WWClock.colour(0x0E1116, alpha: 1.00), location: 0.00),
            .init(color: WWClock.colour(0x0C0F13, alpha: 1.00), location: 0.44),
            .init(color: WWClock.colour(0x080A0D, alpha: 1.00), location: 1.00)
        ])

        // Bed lips: tight strokes to create crisp bed boundaries (no blur haze).
        let lipW = WWClock.pixel(WWClock.clamp(px * 1.2, min: px, max: px * 2.0), scale: scale)

        self.bedLips = BedLips(
            lineWidth: lipW,
            highlightGradient: Gradient(stops: [
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.12), location: 0.00),
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.55),
            ]),
            shadowGradient: Gradient(stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.26), location: 0.00),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.70),
            ])
        )

        // Contact occlusion: mild radial darkening in the bed channels.
        self.bedContactOcclusion = BedContactOcclusion(
            outerBandGradient: Gradient(stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.30), location: 0.00),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 1.00),
            ]),
            innerBandGradient: Gradient(stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.30), location: 0.00),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 1.00),
            ])
        )

        // Block fills: olive metal (even/odd subtle alternation).
        self.blockFillEvenGradient = Gradient(stops: [
            .init(color: WWClock.colour(0x6B6A2D, alpha: 1.00), location: 0.00),
            .init(color: WWClock.colour(0x4F4D1F, alpha: 1.00), location: 0.52),
            .init(color: WWClock.colour(0x343312, alpha: 1.00), location: 1.00),
        ])

        self.blockFillOddGradient = Gradient(stops: [
            .init(color: WWClock.colour(0x67662A, alpha: 1.00), location: 0.00),
            .init(color: WWClock.colour(0x4A481C, alpha: 1.00), location: 0.52),
            .init(color: WWClock.colour(0x313010, alpha: 1.00), location: 1.00),
        ])

        // Bevel parameters are tuned to avoid haze and rely on crisp strokes/overlays.
        let rimStrokeWidth = WWClock.pixel(WWClock.clamp(px * 1.6, min: px, max: px * 2.0), scale: scale)
        let edgeStrokeWidth = WWClock.pixel(WWClock.clamp(px * 1.2, min: px, max: px * 1.6), scale: scale)

        let radialEdgeInset = WWClock.pixel(WWClock.clamp(chamferPoints * 0.70, min: px, max: chamferPoints), scale: scale)
        let radialEdgeEndInset = WWClock.pixel(WWClock.clamp(px * 1.2, min: px, max: px * 2.0), scale: scale)

        self.blockBevel = BlockBevel(
            highlightOverlayGradient: Gradient(stops: [
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.18), location: 0.00),
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.56),
            ]),
            shadowOverlayGradient: Gradient(stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.20), location: 0.00),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.58),
            ]),
            perimeterHighlightGradient: Gradient(stops: [
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.16), location: 0.00),
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.70),
            ]),
            perimeterShadowGradient: Gradient(stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.32), location: 0.00),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.74),
            ]),
            perimeterRimStrokeWidth: max(px, rimStrokeWidth),
            outerEdgeLineWidth: max(px, edgeStrokeWidth),
            innerEdgeLineWidth: max(px, edgeStrokeWidth),
            radialEdgeStrokeWidth: max(px, edgeStrokeWidth),
            radialEdgeEndInset: radialEdgeEndInset,
            radialEdgeInset: radialEdgeInset,
            radialEdgeHighlightColour: WWClock.colour(0xFFFFFF, alpha: 0.06),
            radialEdgeShadowColour: WWClock.colour(0x000000, alpha: 0.10)
        )

        // Diagnostic markers: segment centres and gap centres.
        let markerRadiusPx = WWClock.clamp(gapPixels * 0.55, min: 1.4, max: 2.4)
        let markerRadius = WWClock.pixel(markerRadiusPx / max(scale, 1.0), scale: scale)

        self.diagnostic = Diagnostic(
            enabled: diagnosticEnabled,
            segmentMarkerColour: WWClock.colour(0xFF2D55, alpha: 0.92),
            gapMarkerColour: WWClock.colour(0x32D7FF, alpha: 0.92),
            markerRadius: markerRadius
        )
    }
}

extension SegmentedOuterRingStyle {
    /// Read-only helper used by the Segmented bezel so the bezel→ring gutter stays locked
    /// to the outer ring geometry in both WidgetKit and in-app rendering.
    static func segmentedOuterBoundaryRadius(dialRadius: CGFloat, scale: CGFloat) -> CGFloat {
        SegmentedOuterRingStyle(dialRadius: dialRadius, scale: scale).radii.bedOuter
    }
}
