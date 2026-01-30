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

        // Baseline tuning (acts as the "current capture" reference for the thickness boost).
        let baselineBedThickness = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.185, min: px * 6.0, max: dialRadius * 0.205),
            scale: scale
        )

        let baselineChannelInset = WWClock.pixel(
            WWClock.clamp(baselineBedThickness * 0.085, min: px, max: baselineBedThickness * 0.155),
            scale: scale
        )

        let baselineBlockThickness = max(px, baselineBedThickness - (baselineChannelInset * 2.0))

        // Channel policy (BOLD v2): fixed physical pixels so the bed stays visible around blocks at 44/60.
        // Targets: 2px outer + 2px inner (minimum 1px each).
        let minChannelPx: CGFloat = 1.0
        let targetOuterChannelPx: CGFloat = 2.0
        let targetInnerChannelPx: CGFloat = 2.0

        let minChannel = minChannelPx / max(scale, 1.0)
        let outerChannel = max(minChannel, targetOuterChannelPx / max(scale, 1.0))
        let innerChannel = max(minChannel, targetInnerChannelPx / max(scale, 1.0))

        // Block thickness boost: +18–22% vs baseline (use 20% midpoint).
        let desiredBlockThickness = WWClock.pixel(max(px, baselineBlockThickness * 1.20), scale: scale)

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

        // Physical-pixel gap policy:
        // - Widget sizes (44/60) must show an obviously open "air" cut where the bed is visible.
        // - Express the gap in physical pixels so it stays stable across device scales.
        let gapPixels: CGFloat = WWClock.clamp(4.0, min: 3.0, max: 4.0)
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
        let dialDiameter = dialRadius * 2.0
        let t = WWClock.clamp((dialDiameter - 44.0) / (60.0 - 44.0), min: 0.0, max: 1.0)

        let chamferPixelsRaw = 2.0 + (t * 1.0)
        let chamferPixels = WWClock.clamp(chamferPixelsRaw.rounded(.toNearestOrAwayFromZero), min: 2.0, max: 3.0)
        let chamferPoints = chamferPixels / max(scale, 1.0)

        self.chamfer = Chamfer(
            pixels: chamferPixels,
            depth: chamferPoints
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
            WWClock.clamp(self.radii.bedThickness * 0.075, min: px, max: px * 2.0),
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
        // BOLD v2: keep this low so gaps read as open air (no divider read).
        let occlusionAlpha: Double = 0.06

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

        // Block fill gradients (slightly darker / less saturated for mock parity).
        // The odd gradient is only used when the diagnostic overlay is enabled.
        self.blockFillEvenGradient = Gradient(stops: [
            .init(color: WWClock.colour(0x515121, alpha: 0.98), location: 0.00),
            .init(color: WWClock.colour(0x404018, alpha: 0.98), location: 0.48),
            .init(color: WWClock.colour(0x2A2A0D, alpha: 0.99), location: 1.00),
        ])

        self.blockFillOddGradient = Gradient(stops: [
            .init(color: WWClock.colour(0x4A4A1E, alpha: 0.98), location: 0.00),
            .init(color: WWClock.colour(0x3A3A16, alpha: 0.98), location: 0.48),
            .init(color: WWClock.colour(0x25250B, alpha: 0.99), location: 1.00),
        ])

        // Block bevel shading (no blur): overlays + tight edge accents.
        let rimStrokeWidth = WWClock.pixel(2.0 / max(scale, 1.0), scale: scale)
        let edgeStrokeWidth = WWClock.pixel(1.0 / max(scale, 1.0), scale: scale)

        // Radial/chamfer edge accents are shifted further inside the block to keep gaps clean.
        let radialEdgeInsetPx: CGFloat = 1.10
        let radialEdgeInset = radialEdgeInsetPx / max(scale, 1.0)

        let radialEdgeEndInsetPx: CGFloat = 1.10
        let radialEdgeEndInset = radialEdgeEndInsetPx / max(scale, 1.0)

        self.blockBevel = BlockBevel(
            highlightOverlayGradient: Gradient(stops: [
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.16), location: 0.00),
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.34),
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
