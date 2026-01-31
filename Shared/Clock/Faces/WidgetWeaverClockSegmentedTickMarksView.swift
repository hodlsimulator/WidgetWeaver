//
//  WidgetWeaverClockSegmentedTickMarksView.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI

/// Tick marks used by the Segmented clock face.
///
/// Renders a two-level hierarchy:
/// - Five-minute ticks (uniform across all 5-minute positions, including quarter-hours)
/// - One-minute ticks (thin / short)
///
/// Layout convention:
/// - `outerRadius` represents the outer edge of each tick.
/// - Tick bodies extend inwards by their respective lengths.
struct WidgetWeaverClockSegmentedTickMarksView: View {
    let palette: WidgetWeaverClockPalette

    let dialRadius: CGFloat
    let scale: CGFloat

    private struct Radii {
        let outerRadius: CGFloat
        let segmentInnerRadius: CGFloat
    }

    private func radii(dialRadius: CGFloat, scale: CGFloat) -> Radii {
        let px = WWClock.px(scale: scale)

        // Single source of truth: tick placement derives from the segmented ring style's px-clamped radii.
        let ringStyle = SegmentedOuterRingStyle(dialRadius: dialRadius, scale: scale)
        let segmentInnerRadius = ringStyle.radii.blockInner

        // Outer tick edge sits a fixed (px-clamped) clearance inside the segmented band.
        let tickOuterRadius = WWClock.pixel(max(px, ringStyle.contentRadii.ticksOuterRadius), scale: scale)

        return Radii(outerRadius: tickOuterRadius, segmentInnerRadius: segmentInnerRadius)
    }

    private func tickSizes(
        dialRadius: CGFloat,
        scale: CGFloat
    ) -> (
        fiveMinute: (len: CGFloat, w: CGFloat),
        minute: (len: CGFloat, w: CGFloat)
    ) {
        let px = WWClock.px(scale: scale)

        let minuteLength = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.044, min: px * 1.6, max: dialRadius * 0.065),
            scale: scale
        )

        // Five-minute ticks: blocky (short + thick). All ends remain square.
        let fiveLengthBase = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.064, min: px * 2.4, max: dialRadius * 0.085),
            scale: scale
        )

        let fiveLengthReductionPx: CGFloat = 8.0
        let fiveLengthReduction = WWClock.pixel(fiveLengthReductionPx / max(scale, 1.0), scale: scale)

        let fiveLength = WWClock.pixel(
            max(minuteLength + px, fiveLengthBase - fiveLengthReduction),
            scale: scale
        )

        let fiveWidth = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.018, min: px * 3.0, max: dialRadius * 0.023),
            scale: scale
        )

        let minuteWidth = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.0070, min: px, max: dialRadius * 0.012),
            scale: scale
        )

        return (
            fiveMinute: (len: fiveLength, w: fiveWidth),
            minute: (len: minuteLength, w: minuteWidth)
        )
    }

    var body: some View {
        let px = WWClock.px(scale: scale)
        let dialDiameter = dialRadius * 2.0

        let r = radii(dialRadius: dialRadius, scale: scale)
        let sizes = tickSizes(dialRadius: dialRadius, scale: scale)

        // Matte, off-white tick material (avoid a chrome read at 44/60).
        let tickFill = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: WWClock.colour(0xF1F3F6, alpha: 0.92), location: 0.00),
                .init(color: WWClock.colour(0xE2E7EF, alpha: 0.90), location: 0.56),
                .init(color: WWClock.colour(0xCCD5E2, alpha: 0.92), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Keeps the tick ring away from the dial occlusion ring and avoids touching the segmented ring.
        let ringSafeInset = WWClock.pixel(max(px, dialRadius * 0.006), scale: scale)
        let safeOuterRadius = WWClock.pixel(min(r.outerRadius, r.segmentInnerRadius - ringSafeInset), scale: scale)

        return ZStack {
            ForEach(0..<60, id: \.self) { idx in
                let isFiveMinute = (idx % 5 == 0)

                let length: CGFloat = isFiveMinute ? sizes.fiveMinute.len : sizes.minute.len
                let width: CGFloat = isFiveMinute ? sizes.fiveMinute.w : sizes.minute.w

                let opacity: Double = isFiveMinute ? 0.78 : 0.48

                let yOffset = WWClock.pixel(-(safeOuterRadius - (length / 2.0)), scale: scale)

                Rectangle()
                    .fill(tickFill)
                    .opacity(opacity)
                    .frame(width: width, height: length)
                    .offset(y: yOffset)
                    .rotationEffect(.degrees(Double(idx) * 6.0))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: dialDiameter, height: dialDiameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
