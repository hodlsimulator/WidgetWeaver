//
//  WidgetWeaverClockSegmentedBezelDiagnosticsOverlayView.swift
//  WidgetWeaver
//
//  Created by . . on 1/31/26.
//

import SwiftUI

#if DEBUG
struct WidgetWeaverClockSegmentedBezelDiagnosticsOverlayView: View {
    let containerSide: CGFloat
    let rings: SegmentedBezelStyle.Rings

    let rimInnerRadius: CGFloat
    let baselineRimInnerRadius: CGFloat

    let segmentedOuterBoundaryRadius: CGFloat
    let gutterOuterRadius: CGFloat

    let gutterLock: SegmentedBezelStyle.GutterLock

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let lineW = WWClock.pixel(px, scale: scale)

        let rimD = rimInnerRadius * 2.0
        let ringD = segmentedOuterBoundaryRadius * 2.0
        let gutterD = gutterOuterRadius * 2.0

        let metrics = VStack(alignment: .leading, spacing: px * 2.0) {
            Text("Seg Bezel")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.92))

            Text("ringA: \(Int((rings.ringA / px).rounded()))px (+\(Int((rings.ringAExtra / px).rounded()))px)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.86))

            Text("ringC: \(Int((rings.ringC / px).rounded()))px (+\(Int((rings.ringCExtra / px).rounded()))px)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.86))

            Text("R: \(Int((rings.dialRadius / px).rounded()))px (baseline \(Int((rings.baselineDialRadius / px).rounded()))px)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.86))

            Text("gutter: \(Int((gutterLock.width / px).rounded()))px (baseline \(Int((gutterLock.baselineWidth / px).rounded()))px)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(gutterLock.didClampDueToBand ? Color.yellow.opacity(0.92) : Color.white.opacity(0.86))

            Text("band: \(Int((gutterLock.availableShelfBand / px).rounded()))px")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.72))
        }
        .padding(px * 4.0)
        .background(Color.black.opacity(0.38))
        .cornerRadius(px * 4.0)

        return ZStack(alignment: .topLeading) {
            // Rim→shelf step (rim inner edge).
            Circle()
                .stroke(Color.yellow.opacity(0.90), lineWidth: max(px, lineW))
                .frame(width: rimD, height: rimD)

            // Segmented ring outer boundary (style helper, bedOuter).
            Circle()
                .stroke(WWClock.colour(0xFF2D55, alpha: 0.92), lineWidth: max(px, lineW))
                .frame(width: ringD, height: ringD)

            // Gutter outer edge / shelf inner edge.
            Circle()
                .stroke(WWClock.colour(0x32D7FF, alpha: 0.92), lineWidth: max(px, lineW))
                .frame(width: gutterD, height: gutterD)

            metrics
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
