//
//  SegmentedBezelStyle.swift
//  WidgetWeaver
//
//  Created by . . on 1/30/26.
//

import SwiftUI

/// Single source of truth for Segmented bezel geometry and materials.
///
/// Goals (v3.3):
/// - Bezel reads chunkier via ring redistribution while dial radius stays locked.
/// - Bezel→segmented-ring gutter width stays locked to the v3.2 baseline unless the shelf band is physically too thin.
/// - Physical pixel policies are applied first (clamps in px, not ratios).
struct SegmentedBezelStyle {

    // MARK: - Materials (v3.3 tone)

    /// Lighter, neutral gunmetal (+10–18% luminance vs v3.2).
    static let bezelDark: Color = WWClock.colour(0x07090C, alpha: 1.0)
    static let bezelMid: Color = WWClock.colour(0x171C25, alpha: 1.0)
    static let bezelBright: Color = WWClock.colour(0x343C47, alpha: 1.0)

    /// Narrow recessed channel before the segmented ring (neutral; no blue/green cast).
    static let gutterBase: Color = WWClock.colour(0x05060A, alpha: 1.0)
    static let gutterHi: Color = WWClock.colour(0x0C0F15, alpha: 1.0)

    // MARK: - Geometry

    struct Rings {
        let ringA: CGFloat
        let ringB: CGFloat
        let ringC: CGFloat
        let dialRadius: CGFloat

        let baselineRingA: CGFloat
        let baselineRingB: CGFloat
        let baselineRingC: CGFloat
        let baselineDialRadius: CGFloat

        let ringAExtra: CGFloat
        let ringCExtra: CGFloat
    }

    struct GutterLock {
        let width: CGFloat
        let baselineWidth: CGFloat
        let didClampDueToBand: Bool

        let availableShelfBand: CGFloat
        let minimumShelf: CGFloat

        let minWidth: CGFloat
        let targetWidth: CGFloat
        let maxWidth: CGFloat
    }

    /// Computes bezel rings by redistributing thickness while holding the baseline (v3.2) dial radius constant.
    ///
    /// Policy:
    /// - ringA (outer rim): +2px target at 44/60.
    /// - ringC (inner ridge): +1px target at 44/60.
    /// - ringB (body) reduced by the same amount so the dial radius does not move.
    static func rings(outerRadius: CGFloat, scale: CGFloat) -> Rings {
        let px = WWClock.px(scale: scale)

        let metalThicknessRatio: CGFloat = 0.062
        let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

        let baselineRingA = WWClock.pixel(
            WWClock.clamp(provisionalR * 0.020, min: px * 2.0, max: provisionalR * 0.030),
            scale: scale
        )

        let baselineRingC = WWClock.pixel(
            WWClock.clamp(provisionalR * 0.0095, min: px, max: provisionalR * 0.012),
            scale: scale
        )

        let minB = px
        let baselineRingB = WWClock.pixel(
            max(minB, outerRadius - provisionalR - baselineRingA - baselineRingC),
            scale: scale
        )

        let baselineDialRadius = outerRadius - baselineRingA - baselineRingB - baselineRingC

        // v3.3 chunkiness is taken from ringB headroom (never below 1px).
        let headroom = max(0.0, baselineRingB - minB)

        let ringCExtraTarget = WWClock.pixel(px * 1.0, scale: scale)
        let ringAExtraTarget = WWClock.pixel(px * 2.0, scale: scale)

        let ringCExtra = WWClock.pixel(min(headroom, ringCExtraTarget), scale: scale)
        let ringAExtra = WWClock.pixel(min(max(0.0, headroom - ringCExtra), ringAExtraTarget), scale: scale)

        let ringA = WWClock.pixel(baselineRingA + ringAExtra, scale: scale)
        let ringC = WWClock.pixel(baselineRingC + ringCExtra, scale: scale)
        let ringB = WWClock.pixel(max(minB, baselineRingB - ringAExtra - ringCExtra), scale: scale)

        let dialRadius = outerRadius - ringA - ringB - ringC

        return Rings(
            ringA: ringA,
            ringB: ringB,
            ringC: ringC,
            dialRadius: dialRadius,
            baselineRingA: baselineRingA,
            baselineRingB: baselineRingB,
            baselineRingC: baselineRingC,
            baselineDialRadius: baselineDialRadius,
            ringAExtra: ringAExtra,
            ringCExtra: ringCExtra
        )
    }

    /// Locks the bezel→ring gutter width to the v3.2 baseline and clamps only when the shelf band becomes too thin.
    ///
    /// Inputs:
    /// - `rimInnerRadius`: current rim inner edge (after ringA changes).
    /// - `baselineRimInnerRadius`: baseline rim inner edge (v3.2).
    /// - `segmentedOuterBoundaryRadius`: outer ring boundary derived from `SegmentedOuterRingStyle`.
    static func lockedGutter(
        rimInnerRadius: CGFloat,
        baselineRimInnerRadius: CGFloat,
        segmentedOuterBoundaryRadius: CGFloat,
        scale: CGFloat
    ) -> GutterLock {
        let px = WWClock.px(scale: scale)

        let minWidth = WWClock.pixel(px, scale: scale)
        let targetWidth = WWClock.pixel(px * 2.0, scale: scale)
        let maxWidth = WWClock.pixel(px * 3.0, scale: scale)

        let baselineWidth = gutterWidthV32(
            rimInnerRadius: baselineRimInnerRadius,
            segmentedOuterBoundaryRadius: segmentedOuterBoundaryRadius,
            scale: scale
        )

        let availableShelfBand = max(0.0, rimInnerRadius - segmentedOuterBoundaryRadius)
        let minimumShelf = px

        var width = baselineWidth
        var didClampDueToBand = false

        if availableShelfBand <= (minWidth + minimumShelf) {
            // Not enough band: clamp hard to the minimum edge policy.
            let clamped = WWClock.pixel(min(minWidth, availableShelfBand), scale: scale)
            didClampDueToBand = clamped != width
            width = clamped
        } else {
            // Preserve baseline unless it would crush the shelf.
            let maxAllowed = max(0.0, availableShelfBand - minimumShelf)
            if width > maxAllowed {
                width = WWClock.pixel(maxAllowed, scale: scale)
                didClampDueToBand = true
            }
        }

        // Safety clamp to the physical policy range.
        width = WWClock.pixel(WWClock.clamp(width, min: 0.0, max: maxWidth), scale: scale)

        return GutterLock(
            width: width,
            baselineWidth: baselineWidth,
            didClampDueToBand: didClampDueToBand,
            availableShelfBand: availableShelfBand,
            minimumShelf: minimumShelf,
            minWidth: minWidth,
            targetWidth: targetWidth,
            maxWidth: maxWidth
        )
    }

    // MARK: - Baseline (v3.2) gutter

    /// v3.2 gutter sizing logic used as the baseline for v3.3 "gap lock".
    private static func gutterWidthV32(
        rimInnerRadius: CGFloat,
        segmentedOuterBoundaryRadius: CGFloat,
        scale: CGFloat
    ) -> CGFloat {
        let px = WWClock.px(scale: scale)

        let rimInner = max(px, rimInnerRadius)
        let availableShelfBand = max(0.0, rimInner - segmentedOuterBoundaryRadius)

        let gutterMin = WWClock.pixel(px, scale: scale)
        let gutterTarget = WWClock.pixel(px * 2.0, scale: scale)
        let gutterMax = WWClock.pixel(px * 3.0, scale: scale)

        // Shelf coverage target: ~85–95% of the rim→ring band.
        let gutterMinByCoverage = availableShelfBand * 0.05
        let gutterMaxByCoverage = availableShelfBand * 0.15

        var minW = max(gutterMin, WWClock.pixel(gutterMinByCoverage, scale: scale))
        var maxW = min(gutterMax, WWClock.pixel(gutterMaxByCoverage, scale: scale))

        if maxW < minW {
            minW = gutterMin
            maxW = gutterMax
        }

        var w = gutterTarget
        w = WWClock.clamp(w, min: minW, max: maxW)
        w = WWClock.pixel(w, scale: scale)

        let minShelf = px
        if availableShelfBand <= (gutterMin + minShelf) {
            w = WWClock.pixel(min(gutterMin, availableShelfBand), scale: scale)
        } else {
            w = min(w, availableShelfBand - minShelf)
        }

        return max(0.0, w)
    }

    // MARK: - Debug guardrails

    #if DEBUG
    static func debugValidateGutterLock(
        containerSide: CGFloat,
        scale: CGFloat,
        gutter: GutterLock
    ) {
        let px = WWClock.px(scale: scale)

        func pxCount(_ value: CGFloat) -> Int {
            Int((value / max(px, 0.0001)).rounded())
        }

        let widthPx = pxCount(gutter.width)
        let minPx = pxCount(gutter.minWidth)
        let maxPx = pxCount(gutter.maxWidth)
        let targetPx = pxCount(gutter.targetWidth)

        if widthPx < minPx || widthPx > maxPx {
            print("[SegmentedBezel] gutterWidth out of bounds: width=\(widthPx)px, expected=[\(minPx)px..\((maxPx))px] (container=\(containerSide), scale=\(scale))")
        }

        if gutter.didClampDueToBand {
            let bandPx = pxCount(gutter.availableShelfBand)
            print("[SegmentedBezel] gutterWidth clamped due to shelf band: width=\(widthPx)px (target=\(targetPx)px, band=\(bandPx)px, container=\(containerSide), scale=\(scale))")
        }
    }
    #endif
}
