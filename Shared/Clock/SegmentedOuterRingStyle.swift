//
//  SegmentedOuterRingStyle.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI

/// Style and geometry for the Segmented face outer ring.
///
/// Single source of truth for:
/// - Radii (bed + blocks)
/// - Physical-pixel segment gap policy
/// - Chamfer geometry used by blocks
/// - Optional diagnostics used for lock validation
struct SegmentedOuterRingStyle {

    // MARK: - v3.4.2 regression locks

    private enum Locks {
        /// Physical pixel inset from `dialRadius` to the segmented bed outer boundary.
        ///
        /// This lock prevents outward drift; thickness adjustments are inward only.
        static let outerInsetPxLocked: CGFloat = 2.0

        /// v3.2 baseline block thickness measured at dial diameters 44/60, in physical pixels.
        static let baselineBlockThicknessPx44: CGFloat = 10.5
        static let baselineBlockThicknessPx60: CGFloat = 15.0

        /// Target thickness multiplier (+14%) with a clamp of +12–16%.
        static let blockThicknessMultiplier: CGFloat = 1.14
        static let blockThicknessMinMultiplier: CGFloat = 1.12
        static let blockThicknessMaxMultiplier: CGFloat = 1.16

        /// Bed-visible channels around blocks (physical pixels).
        static let outerChannelPxTarget: CGFloat = 2.0
        static let innerChannelPxTarget: CGFloat = 2.0
        static let channelPxMin: CGFloat = 1.0

        /// Segment air-gap policy (physical pixels).
        static let gapPxTarget: CGFloat = 3.0
        static let gapPxMin: CGFloat = 2.0
        static let gapPxMax: CGFloat = 3.0

        /// Tick ring clearance inside `blockInner` (physical pixels).
        static let ticksOuterClearancePxTarget: CGFloat = 3.0
        static let ticksOuterClearancePxMin: CGFloat = 2.0
        static let ticksOuterClearancePxMax: CGFloat = 4.0
    }

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

        /// Radius used for numeral centre points.
        let numeralRadius: CGFloat

        /// Outer radius of tick marks (outer edge), clamped in physical pixels inside `blockInner`.
        let ticksOuterRadius: CGFloat
    }

    struct Gap {
        /// Gap width in physical pixels.
        let pixels: CGFloat
        /// Gap width in points.
        let linear: CGFloat
        /// Gap width in radians at the block mid radius.
        let angular: CGFloat

        /// Extra angular trimming applied per edge.
        let edgeTrimAngular: CGFloat
    }

    struct Chamfer {
        /// Chamfer depth in physical pixels.
        let pixels: CGFloat
        /// Chamfer depth in points.
        let depth: CGFloat
    }

    struct BedLips {
        let lineWidth: CGFloat
        let highlightGradient: Gradient
        let shadowGradient: Gradient
    }

    /// Subtle darkening in the bed channels adjacent to the blocks.
    ///
    /// The occlusion is rendered onto the bed (under the blocks) so it only shows through the gaps.
    struct BedContactOcclusion {
        let outerBandGradient: Gradient
        let innerBandGradient: Gradient
    }

    struct BlockBevel {
        let highlightOverlayGradient: Gradient
        let shadowOverlayGradient: Gradient

        let perimeterHighlightGradient: Gradient
        let perimeterShadowGradient: Gradient

        let perimeterRimStrokeWidth: CGFloat

        let outerEdgeLineWidth: CGFloat
        let innerEdgeLineWidth: CGFloat

        let radialEdgeStrokeWidth: CGFloat
        let radialEdgeEndInset: CGFloat
        let radialEdgeInset: CGFloat

        let radialEdgeHighlightColour: Color
        let radialEdgeShadowColour: Color
    }

    struct Diagnostic {
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

        // Pixel-lock dial radius before deriving ring geometry.
        let dialRadiusLocked = WWClock.pixel(max(px, dialRadius), scale: scale)

        // Segmented outer boundary lock: bedOuter must not drift outward.
        let outerInset = WWClock.pixel(Locks.outerInsetPxLocked * px, scale: scale)
        let bedOuter = WWClock.pixel(max(px, dialRadiusLocked - outerInset), scale: scale)

        // Dial size normalisation for 44/60 tuning.
        let dialDiameter = dialRadiusLocked * 2.0
        let t = WWClock.clamp((dialDiameter - 44.0) / (60.0 - 44.0), min: 0.0, max: 1.0)

        // Block thickness targeting (physical pixels) derived from v3.2 baseline.
        let baselineBlockThicknessPx = Locks.baselineBlockThicknessPx44
            + (t * (Locks.baselineBlockThicknessPx60 - Locks.baselineBlockThicknessPx44))

        let desiredBlockThicknessPx = baselineBlockThicknessPx * Locks.blockThicknessMultiplier
        let minTargetBlockThicknessPx = baselineBlockThicknessPx * Locks.blockThicknessMinMultiplier
        let maxTargetBlockThicknessPx = baselineBlockThicknessPx * Locks.blockThicknessMaxMultiplier

        let minTargetIntPx = ceil(minTargetBlockThicknessPx)
        let maxTargetIntPx = floor(maxTargetBlockThicknessPx)

        var targetBlockThicknessPx = desiredBlockThicknessPx.rounded(.toNearestOrAwayFromZero)

        if minTargetIntPx <= maxTargetIntPx {
            targetBlockThicknessPx = WWClock.clamp(targetBlockThicknessPx, min: minTargetIntPx, max: maxTargetIntPx)
        } else {
            // When 12–16% contains no integer pixel value, prefer thickness over thinning.
            targetBlockThicknessPx = minTargetIntPx
        }

        targetBlockThicknessPx = max(0.0, targetBlockThicknessPx)
        let targetBlockThickness = WWClock.pixel(targetBlockThicknessPx * px, scale: scale)

        // Channel policy (physical pixels): 2px outer + 2px inner preferred (min 1px each).
        let minChannel = WWClock.pixel(Locks.channelPxMin * px, scale: scale)
        let outerChannel = WWClock.pixel(max(minChannel, Locks.outerChannelPxTarget * px), scale: scale)
        let innerChannel = WWClock.pixel(max(minChannel, Locks.innerChannelPxTarget * px), scale: scale)

        // Bed thickness is channels + target thickness, applied inward-only.
        let desiredBedThicknessRaw = targetBlockThickness + outerChannel + innerChannel
        let maxBedThickness = max(px, bedOuter - px)
        let bedThickness = WWClock.pixel(min(desiredBedThicknessRaw, maxBedThickness), scale: scale)

        let bedInner = WWClock.pixel(max(px, bedOuter - bedThickness), scale: scale)

        var blockOuter = WWClock.pixel(max(px, bedOuter - outerChannel), scale: scale)
        var blockInner = WWClock.pixel(max(px, bedInner + innerChannel), scale: scale)

        // Minimum viable block thickness protection for unusually small containers.
        if blockOuter <= blockInner {
            blockOuter = WWClock.pixel(max(px, bedOuter - minChannel), scale: scale)
            blockInner = WWClock.pixel(max(px, bedInner + minChannel), scale: scale)
        }

        let radii = Radii(
            bedOuter: bedOuter,
            bedInner: bedInner,
            blockOuter: blockOuter,
            blockInner: blockInner
        )
        self.radii = radii

        // Content radii: numerals + ticks move inward together when band thickens.
        let blockBandMidRadius = WWClock.pixel(radii.blockMid, scale: scale)

        let ticksOuterClearancePx = WWClock.clamp(
            Locks.ticksOuterClearancePxTarget,
            min: Locks.ticksOuterClearancePxMin,
            max: Locks.ticksOuterClearancePxMax
        )
        let ticksOuterClearance = WWClock.pixel(ticksOuterClearancePx * px, scale: scale)

        let ticksOuterRadius = WWClock.pixel(
            max(px, radii.blockInner - ticksOuterClearance),
            scale: scale
        )

        self.contentRadii = ContentRadii(
            blockBandMidRadius: blockBandMidRadius,
            numeralRadius: blockBandMidRadius,
            ticksOuterRadius: ticksOuterRadius
        )

        // Segment gap policy (physical pixels).
        let gapPixels: CGFloat = WWClock.clamp(Locks.gapPxTarget, min: Locks.gapPxMin, max: Locks.gapPxMax)
        let gapPoints = gapPixels * px

        let midR = max(px, blockBandMidRadius)
        let gapAngular = max(0.0, gapPoints / midR)

        // BOLD v2: geometry defines the gap; keep trim at zero.
        let edgeTrimAngular: CGFloat = 0.0

        self.gap = Gap(
            pixels: gapPixels,
            linear: gapPoints,
            angular: gapAngular,
            edgeTrimAngular: edgeTrimAngular
        )

        // Chamfer depth: 2px at 44, 3px at 60.
        let chamferPixelsRaw = 2.0 + (t * 1.0)
        let chamferPixels = WWClock.clamp(chamferPixelsRaw.rounded(.toNearestOrAwayFromZero), min: 2.0, max: 3.0)
        let chamferPoints = chamferPixels * px

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

        #if DEBUG
        SegmentedOuterRingStyle.debugValidateLocks(
            dialRadiusLocked: dialRadiusLocked,
            radii: radii,
            targetOuterInsetPx: Locks.outerInsetPxLocked,
            targetBlockThicknessPx: targetBlockThicknessPx,
            diagnosticsEnabled: diagnosticEnabled,
            scale: scale
        )
        #endif

        // Bed material (recessed channel).
        self.bedFillGradient = Gradient(stops: [
            .init(color: WWClock.colour(0x131A24, alpha: 1.0), location: 0.00),
            .init(color: WWClock.colour(0x0A0D13, alpha: 1.0), location: 0.55),
            .init(color: WWClock.colour(0x030407, alpha: 1.0), location: 1.00),
        ])

        let lipLineWidth = WWClock.pixel(
            WWClock.clamp(radii.bedThickness * 0.075, min: px, max: px * 2.0),
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

        // Bed contact occlusion (under blocks; shows only through gaps).
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

        // Block fills.
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
        let rimStrokeWidth = WWClock.pixel(2.0 * px, scale: scale)
        let edgeStrokeWidth = WWClock.pixel(1.0 * px, scale: scale)

        let radialEdgeInsetPx: CGFloat = 1.10
        let radialEdgeInset = radialEdgeInsetPx * px

        let radialEdgeEndInsetPx: CGFloat = 1.10
        let radialEdgeEndInset = radialEdgeEndInsetPx * px

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

        // Diagnostic markers.
        let markerRadiusPx = WWClock.clamp(gapPixels * 0.55, min: 1.4, max: 2.4)
        let markerRadius = WWClock.pixel(markerRadiusPx * px, scale: scale)

        self.diagnostic = Diagnostic(
            enabled: diagnosticEnabled,
            segmentMarkerColour: WWClock.colour(0xFF2D55, alpha: 0.92),
            gapMarkerColour: WWClock.colour(0x32D7FF, alpha: 0.92),
            markerRadius: markerRadius
        )
    }

    #if DEBUG
    private static func debugValidateLocks(
        dialRadiusLocked: CGFloat,
        radii: Radii,
        targetOuterInsetPx: CGFloat,
        targetBlockThicknessPx: CGFloat,
        diagnosticsEnabled: Bool,
        scale: CGFloat
    ) {
        guard scale > 0 else { return }

        let px = WWClock.px(scale: scale)

        let outerInsetPxMeasured = ((dialRadiusLocked - radii.bedOuter) / px).rounded(.toNearestOrAwayFromZero)
        let blockThicknessPxMeasured = ((radii.blockOuter - radii.blockInner) / px).rounded(.toNearestOrAwayFromZero)

        let bedOuterPx = (radii.bedOuter / px).rounded(.toNearestOrAwayFromZero)
        let bedInnerPx = (radii.bedInner / px).rounded(.toNearestOrAwayFromZero)
        let outerChannelPx = ((radii.bedOuter - radii.blockOuter) / px).rounded(.toNearestOrAwayFromZero)
        let innerChannelPx = ((radii.blockInner - radii.bedInner) / px).rounded(.toNearestOrAwayFromZero)

        let outerLockOK = abs(outerInsetPxMeasured - targetOuterInsetPx) <= 0.1
        let thicknessOK = blockThicknessPxMeasured + 0.01 >= targetBlockThicknessPx

        // Non-fatal gates: print-only to avoid widget extension crashes in DEBUG.
        let shouldPrint = diagnosticsEnabled || !outerLockOK || !thicknessOK
        guard shouldPrint else { return }

        let status = (outerLockOK && thicknessOK) ? "OK" : "FAIL"

        print(
            "[SegmentedRing locks \(status)] " +
            "dialR=\(dialRadiusLocked) " +
            "outerInsetPx=\(outerInsetPxMeasured) target=\(targetOuterInsetPx) " +
            "blockThicknessPx=\(blockThicknessPxMeasured) target>=\(targetBlockThicknessPx) " +
            "bedOuterPx=\(bedOuterPx) bedInnerPx=\(bedInnerPx) " +
            "outerChannelPx=\(outerChannelPx) innerChannelPx=\(innerChannelPx)"
        )
    }
    #endif
}

extension SegmentedOuterRingStyle {
    /// Read-only helper used by the Segmented bezel so the bezel→ring gutter stays locked
    /// to the outer ring geometry in both WidgetKit and in-app rendering.
    static func segmentedOuterBoundaryRadius(dialRadius: CGFloat, scale: CGFloat) -> CGFloat {
        SegmentedOuterRingStyle(dialRadius: dialRadius, scale: scale).radii.bedOuter
    }
}
