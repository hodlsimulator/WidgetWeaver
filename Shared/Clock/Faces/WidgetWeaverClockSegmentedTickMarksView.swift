//
//  WidgetWeaverClockSegmentedTickMarksView.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI

/// Tick marks used by the Segmented clock face.
///
/// Renders a three-level hierarchy:
/// - Quarter-hour ticks (strongest)
/// - Five-minute ticks (medium)
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

        // Use the Segmented outer ring style as the single source of truth so tick placement stays aligned.
        let ringStyle = SegmentedOuterRingStyle(dialRadius: dialRadius, scale: scale)
        let segmentInnerRadius = ringStyle.radii.blockInner

        // Outer tick edge sits just inside the segmented ring's inner edge.
        let ringGap = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.030, min: px * 2.0, max: dialRadius * 0.040),
            scale: scale
        )

        let tickOuterRadius = WWClock.pixel(max(px, segmentInnerRadius - ringGap), scale: scale)

        return Radii(outerRadius: tickOuterRadius, segmentInnerRadius: segmentInnerRadius)
    }

    private func tickSizes(
        dialRadius: CGFloat,
        scale: CGFloat
    ) -> (
        quarter: (len: CGFloat, w: CGFloat),
        five: (len: CGFloat, w: CGFloat),
        minute: (len: CGFloat, w: CGFloat)
    ) {
        let px = WWClock.px(scale: scale)

        let quarterLength = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.086, min: px * 3.0, max: dialRadius * 0.105),
            scale: scale
        )

        let minuteLength = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.044, min: px * 1.6, max: dialRadius * 0.065),
            scale: scale
        )

        // Five-minute ticks: shorter (less intrusion) but thicker (more weight). All ends remain square.
        let fiveLengthBase = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.064, min: px * 2.4, max: dialRadius * 0.085),
            scale: scale
        )

        let fiveLengthReductionPx: CGFloat = 2.0
        let fiveLengthReduction = WWClock.pixel(fiveLengthReductionPx / max(scale, 1.0), scale: scale)

        let fiveLength = WWClock.pixel(
            max(minuteLength + px, fiveLengthBase - fiveLengthReduction),
            scale: scale
        )

        let quarterWidth = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.020, min: px * 2.0, max: dialRadius * 0.026),
            scale: scale
        )

        let fiveWidth = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.018, min: px * 2.0, max: dialRadius * 0.023),
            scale: scale
        )

        let minuteWidth = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.0070, min: px, max: dialRadius * 0.012),
            scale: scale
        )

        return (
            quarter: (len: quarterLength, w: quarterWidth),
            five: (len: fiveLength, w: fiveWidth),
            minute: (len: minuteLength, w: minuteWidth)
        )
    }

    var body: some View {
        let px = WWClock.px(scale: scale)
        let dialDiameter = dialRadius * 2.0

        let r = radii(dialRadius: dialRadius, scale: scale)
        let sizes = tickSizes(dialRadius: dialRadius, scale: scale)

        // Matte, off-white tick material to match the mock (avoid a chrome read at 44/60).
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

        ZStack {
            ForEach(0..<60, id: \.self) { idx in
                let isQuarter = (idx % 15 == 0)
                let isFive = (!isQuarter && idx % 5 == 0)

                let length: CGFloat = {
                    if isQuarter { return sizes.quarter.len }
                    if isFive { return sizes.five.len }
                    return sizes.minute.len
                }()

                let width: CGFloat = {
                    if isQuarter { return sizes.quarter.w }
                    if isFive { return sizes.five.w }
                    return sizes.minute.w
                }()

                // Slightly higher minute-tick opacity keeps the ring present in WidgetKit snapshots.
                let opacity: Double = {
                    if isQuarter { return 0.92 }
                    if isFive { return 0.78 }
                    return 0.62
                }()

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
