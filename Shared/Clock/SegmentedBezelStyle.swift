//
//  SegmentedBezelStyle.swift
//  WidgetWeaver
//
//  Created by . . on 1/30/26.
//

import SwiftUI

/// Single source of truth for Segmented bezel geometry and materials.
///
/// Goals:
/// - Dial radius stays locked while the bezel reads chunkier (v3.3).
/// - Bezel-to-ring gutter width stays locked to the v3.2 baseline unless there is insufficient radial band.
/// - Thickness and gap policies are expressed in physical pixels.
struct SegmentedBezelStyle {

    // MARK: - Materials (v3.3 tone)

    /// Lighter, neutral gunmetal (target +10–18% luminance vs v3.2).
    static let bezelDark = WWClock.colour(0x07080A, alpha: 1.0)
    static let bezelMid = WWClock.colour(0x161B23, alpha: 1.0)
    static let bezelBright = WWClock.colour(0x323A44, alpha: 1.0)

    /// Narrow recessed channel before the segmented ring (kept neutral, no blue/green cast).
    static let gutterBase = WWClock.colour(0x05060A, alpha: 1.0)
    static let gutterHi = WWClock.colour(0x0C0F15, alpha: 1.0)

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

        /// Extra thickness applied to ring A (outer rim) in points.
        let ringAExtra: CGFloat
        /// Extra thickness applied to ring C (inner ridge) in points.
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

    /// Computes v3.3 rings by redistributing thickness while holding the baseline (v3.2) dial radius constant.
    ///
    /// Policy:
    /// - ringA +2px (target) and ringC +1px (target) at 44/60, only if ringB headroom permits.
    /// - ringB is reduced by the same amount so the dial radius remains unchanged.
    static func rings(outerRadius: CGFloat, scale: CGFloat) -> Rings {
        let px = WWClock.px(scale: scale)

        let metalThicknessRatio: CGFloat = 0.062
        let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

        // Baseline (v3.2) ring proportions.
        let baselineRingA = WWClock.pixel(
            WWClock.clamp(provisionalR * 0.020, min: px * 2.0, max: provisionalR * 0.030),
            scale: scale
        )

        let baselineRingC = WWClock.pixel(
            WWClock.clamp(provisionalR * 0.0095, min: px, max: provisionalR * 0.012),
            scale: scale
        )

        let minB = px
        let baselineRingB = WWClock.pixel(max(minB, outerRadius - provisionalR - baselineRingA - baselineRingC), scale: scale)

        let baselineDialRadius = outerRadius - baselineRingA - baselineRingB - baselineRingC

        // v3.3 chunk: take thickness from ringB (never below 1px).
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
    /// - `rimInnerRadius`: current rim inner edge (after ringA adjustments).
    /// - `baselineRimInnerRadius`: baseline rim inner edge (v3.2).
    /// - `segmentedOuterBoundaryRadius`: outer ring boundary (derived from the outer ring style helper).
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

        let minimumShelf = px

        let availableShelfBand = max(0.0, rimInnerRadius - segmentedOuterBoundaryRadius)

        var width = baselineWidth
        var didClampDueToBand = false

        if availableShelfBand <= (minWidth + minimumShelf) {
            let clamped = WWClock.pixel(min(minWidth, availableShelfBand), scale: scale)
            didClampDueToBand = clamped != width
            width = clamped
        } else {
            let maxAllowed = max(0.0, availableShelfBand - minimumShelf)
            if width > maxAllowed {
                width = WWClock.pixel(maxAllowed, scale: scale)
                didClampDueToBand = true
            }
        }

        width = max(0.0, WWClock.clamp(width, min: 0.0, max: maxWidth))

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

    // MARK: - Baseline gutter (v3.2)

    /// v3.2 gutter sizing logic used as the baseline for v3.3 "gap lock".
    ///
    /// Notes:
    /// - Gutter width is expressed in physical pixels (1–3px, target 2px).
    /// - Shelf coverage is biased so the metal shelf remains dominant.
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

    // MARK: - Debug validation

    #if DEBUG
    static func debugValidateGutterLock(
        containerSide: CGFloat,
        scale: CGFloat,
        gutter: GutterLock
    ) {
        let px = WWClock.px(scale: scale)
        let widthPx = Int((gutter.width / max(px, 0.0001)).rounded())
        let minPx = Int((gutter.minWidth / max(px, 0.0001)).rounded())
        let maxPx = Int((gutter.maxWidth / max(px, 0.0001)).rounded())
        let targetPx = Int((gutter.targetWidth / max(px, 0.0001)).rounded())

        if widthPx < minPx || widthPx > maxPx {
            print("[SegmentedBezel] gutterWidth out of bounds: width=\(widthPx)px, expected=[\(minPx)px..\((maxPx))px] (container=\(containerSide), scale=\(scale))")
        }

        if gutter.didClampDueToBand {
            let bandPx = Int((gutter.availableShelfBand / max(px, 0.0001)).rounded())
            print("[SegmentedBezel] gutterWidth clamped due to shelf band: width=\(widthPx)px (target=\(targetPx)px, band=\(bandPx)px, container=\(containerSide), scale=\(scale))")
        }
    }
    #endif
}
