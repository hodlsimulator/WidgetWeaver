//
//  SegmentedOuterRingView.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI

/// Segmented face outer ring (bed + blocks + numerals).
///
/// Step 9F.0b:
/// - This view is the sole outer ring draw path.
/// - A debug-only diagnostic (feature-flagged) can be enabled to prove the Canvas renderer
///   is active on the Home Screen widget.
struct SegmentedOuterRingView: View {
    let dialRadius: CGFloat
    let scale: CGFloat

    private let style: SegmentedOuterRingStyle
    private let renderer = SegmentedOuterRingRenderer()

    init(
        dialRadius: CGFloat,
        scale: CGFloat,
        style: SegmentedOuterRingStyle? = nil
    ) {
        self.dialRadius = dialRadius
        self.scale = scale
        self.style = style ?? SegmentedOuterRingStyle(dialRadius: dialRadius, scale: scale)
    }

    var body: some View {
        Canvas { context, size in
            renderer.render(into: &context, size: size, style: style, scale: scale)
        }
        .frame(width: dialRadius * 2.0, height: dialRadius * 2.0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .overlay(
            SegmentedOuterRingNumeralsView(
                dialRadius: dialRadius,
                innerRadius: style.radii.blockInner,
                thickness: style.radii.blockThickness,
                scale: scale
            )
        )
    }
}

private struct SegmentedOuterRingNumeralsView: View {
    let dialRadius: CGFloat
    let innerRadius: CGFloat
    let thickness: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Place numerals with a fixed inset from the block outer edge.
        // The inset is specified in physical pixels so it stays stable at 44/60.
        let numeralOuterInsetPx: CGFloat = 10.0
        let numeralOuterInset = WWClock.pixel(numeralOuterInsetPx / max(scale, 1.0), scale: scale)

        let placement = WWClock.pixel(max(px, thickness - numeralOuterInset), scale: scale)

        let r = WWClock.pixel(innerRadius + placement, scale: scale)

        let fontSizeBase = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.18, min: dialRadius * 0.16, max: dialRadius * 0.20),
            scale: scale
        )

        return ZStack {
            ForEach(0..<12, id: \.self) { idx in
                let numeral = idx == 0 ? 12 : idx
                let angle = Angle.degrees(Double(idx) * 30.0)

                // Optical nudges for better perceived centring.
                let xNudge: CGFloat = {
                    switch numeral {
                    case 12: return -px * 0.6
                    case 10: return -px * 0.3
                    case 11: return -px * 0.2
                    default: return 0.0
                    }
                }()

                let yNudge: CGFloat = {
                    switch numeral {
                    case 12: return -px * 0.6
                    case 6: return px * 0.5
                    default: return 0.0
                    }
                }()

                let fontSize = WWClock.pixel(
                    WWClock.clamp(fontSizeBase, min: fontSizeBase * 0.92, max: fontSizeBase * 1.02),
                    scale: scale
                )

                WidgetWeaverClockSegmentedNumeralGlyphView(
                    text: "\(numeral)",
                    fontSize: fontSize,
                    scale: scale
                )
                .offset(x: xNudge, y: yNudge)
                .position(
                    x: dialRadius + CGFloat(sin(angle.radians)) * r,
                    y: dialRadius - CGFloat(cos(angle.radians)) * r
                )
                .accessibilityHidden(true)
            }
        }
        .frame(width: dialRadius * 2.0, height: dialRadius * 2.0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
