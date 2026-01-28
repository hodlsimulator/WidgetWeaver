//
//  WidgetWeaverClockSegmentedOuterRingBlocksView.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI

struct WidgetWeaverClockSegmentedOuterRingBlocksView: View {
    let dialRadius: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let radii = Self.ringRadii(dialRadius: dialRadius, scale: scale)

        let midRadius = max((radii.blockOuterRadius + radii.blockInnerRadius) * 0.5, 0.001)
        let gap = Self.segmentGap(dialRadius: dialRadius, scale: scale, midRadius: midRadius)

        let bedEdgeLine = WWClock.pixel(WWClock.clamp(radii.bedThickness * 0.10, min: px, max: px * 3.0), scale: scale)
        let blockEdgeLine = WWClock.pixel(WWClock.clamp(radii.blockThickness * 0.12, min: px, max: px * 3.0), scale: scale)
        let blockBorderLine = WWClock.pixel(WWClock.clamp(radii.blockThickness * 0.06, min: px, max: px * 2.0), scale: scale)

        let contactRadius = WWClock.pixel(WWClock.clamp(px * 1.0, min: px, max: px * 2.0), scale: scale)
        let contactOffset = WWClock.pixel(WWClock.clamp(px * 1.0, min: px, max: px * 2.0), scale: scale)

        let bedFill = LinearGradient(
            stops: [
                .init(color: WWClock.colour(0x131A24, alpha: 1.0), location: 0.0),
                .init(color: WWClock.colour(0x0A0D13, alpha: 1.0), location: 0.55),
                .init(color: WWClock.colour(0x030407, alpha: 1.0), location: 1.0),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let bedEdgeHighlight = LinearGradient(
            stops: [
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.10), location: 0.0),
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.45),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let bedEdgeShadow = LinearGradient(
            stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.55), location: 0.0),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.55),
            ],
            startPoint: .bottomTrailing,
            endPoint: .topLeading
        )

        let blockBaseFill = LinearGradient(
            stops: [
                .init(color: WWClock.colour(0x6C6C2A, alpha: 0.96), location: 0.0),
                .init(color: WWClock.colour(0x5A5A22, alpha: 0.96), location: 0.45),
                .init(color: WWClock.colour(0x3C3C12, alpha: 0.98), location: 1.0),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let blockChamferOverlay = LinearGradient(
            stops: [
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.16), location: 0.0),
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.30),
                .init(color: WWClock.colour(0x000000, alpha: 0.22), location: 1.0),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let blockEdgeHighlight = LinearGradient(
            stops: [
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.18), location: 0.0),
                .init(color: WWClock.colour(0xFFFFFF, alpha: 0.00), location: 0.65),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let blockEdgeShadow = LinearGradient(
            stops: [
                .init(color: WWClock.colour(0x000000, alpha: 0.55), location: 0.0),
                .init(color: WWClock.colour(0x000000, alpha: 0.00), location: 0.70),
            ],
            startPoint: .bottomTrailing,
            endPoint: .topLeading
        )

        let bedAnnulus = WWClockSegmentedAnnulus(innerRadius: radii.bedInnerRadius, outerRadius: radii.bedOuterRadius)
        let blockAnnulus = WWClockSegmentedAnnulus(innerRadius: radii.blockInnerRadius, outerRadius: radii.blockOuterRadius)

        return ZStack {
            // Ring bed visible in the gaps (dark recessed channel).
            bedAnnulus
                .fill(bedFill)
                .overlay(
                    bedAnnulus
                        .stroke(bedEdgeHighlight, lineWidth: bedEdgeLine)
                )
                .overlay(
                    bedAnnulus
                        .stroke(bedEdgeShadow, lineWidth: bedEdgeLine)
                )

            // 12 discrete blocks, each spanning 30° minus an angular gap.
            ForEach(0..<12, id: \.self) { idx in
                let startDeg = Double(idx) * 30.0
                let endDeg = startDeg + 30.0

                let sector = WWClockAnnularSectorShape(
                    innerRadius: radii.blockInnerRadius,
                    outerRadius: radii.blockOuterRadius,
                    startAngle: .degrees(startDeg),
                    endAngle: .degrees(endDeg),
                    angularGap: gap.angular
                )

                sector
                    .fill(blockBaseFill)
                    .overlay(sector.fill(blockChamferOverlay))
                    .overlay(
                        blockAnnulus
                            .stroke(blockEdgeHighlight, lineWidth: blockEdgeLine)
                            .mask(sector)
                    )
                    .overlay(
                        blockAnnulus
                            .stroke(blockEdgeShadow, lineWidth: blockEdgeLine)
                            .mask(sector)
                    )
                    // Border stroke clipped to the block so the air gap stays clean.
                    .overlay(
                        sector
                            .stroke(WWClock.colour(0x000000, alpha: 0.45), lineWidth: blockBorderLine)
                            .clipShape(sector)
                    )
                    // Per-block lift and contact shadow (light from top-left, shadow to bottom-right).
                    .compositingGroup()
                    .shadow(
                        color: WWClock.colour(0x000000, alpha: 0.55),
                        radius: contactRadius,
                        x: contactOffset,
                        y: contactOffset
                    )
                    .shadow(
                        color: WWClock.colour(0xFFFFFF, alpha: 0.10),
                        radius: contactRadius,
                        x: -contactOffset,
                        y: -contactOffset
                    )
            }
        }
    }
}

// MARK: - Geometry helpers

private extension WidgetWeaverClockSegmentedOuterRingBlocksView {
    struct RingRadii {
        let bedOuterRadius: CGFloat
        let bedInnerRadius: CGFloat
        let blockOuterRadius: CGFloat
        let blockInnerRadius: CGFloat

        var bedThickness: CGFloat { bedOuterRadius - bedInnerRadius }
        var blockThickness: CGFloat { blockOuterRadius - blockInnerRadius }
    }

    struct SegmentGap {
        let linear: CGFloat
        let angular: Angle
    }

    static func ringRadii(dialRadius: CGFloat, scale: CGFloat) -> RingRadii {
        let px = WWClock.px(scale: scale)

        let outerInset = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.010, min: px, max: dialRadius * 0.018),
            scale: scale
        )

        let bedOuter = dialRadius - outerInset

        let bedThickness = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.185, min: px * 7.0, max: dialRadius * 0.240),
            scale: scale
        )

        let bedInner = max(bedOuter - bedThickness, 0.0)

        // Small channel inset keeps the block edges crisp and leaves a visible bed around them.
        let channelInset = WWClock.pixel(
            WWClock.clamp(bedThickness * 0.11, min: px, max: bedThickness * 0.18),
            scale: scale
        )

        let blockOuter = max(bedOuter - channelInset, 0.0)
        let blockInner = max(bedInner + channelInset, 0.0)

        return RingRadii(
            bedOuterRadius: bedOuter,
            bedInnerRadius: bedInner,
            blockOuterRadius: blockOuter,
            blockInnerRadius: blockInner
        )
    }

    static func segmentGap(dialRadius: CGFloat, scale: CGFloat, midRadius: CGFloat) -> SegmentGap {
        // Gap is specified in pixels to remain readable at 44/60 without turning fat at larger sizes.
        let targetGapPxRaw = (dialRadius * scale * 0.045).rounded(.toNearestOrAwayFromZero)
        let gapPx = WWClock.clamp(targetGapPxRaw, min: 2.0, max: 6.0)

        let linear = gapPx / max(scale, 1.0)
        let angularRadians = Double(linear / max(midRadius, 0.001))

        return SegmentGap(
            linear: linear,
            angular: Angle.radians(angularRadians)
        )
    }
}

// MARK: - Shapes

private struct WWClockSegmentedAnnulus: Shape {
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY)

        p.addArc(center: c, radius: outerRadius, startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        p.addArc(center: c, radius: innerRadius, startAngle: .degrees(360), endAngle: .degrees(0), clockwise: true)
        p.closeSubpath()

        return p
    }
}
