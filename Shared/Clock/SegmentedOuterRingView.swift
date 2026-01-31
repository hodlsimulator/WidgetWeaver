//
//  SegmentedOuterRingView.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import SwiftUI

struct SegmentedOuterRingView: View {
    let dialRadius: CGFloat
    let scale: CGFloat

    var body: some View {
        let style = SegmentedOuterRingStyle(dialRadius: dialRadius, scale: scale)

        Canvas { context, size in
            SegmentedOuterRingRenderer().render(
                into: &context,
                size: size,
                style: style,
                scale: scale
            )
        }
        .overlay {
            NumeralsView(
                dialRadius: dialRadius,
                numeralRadius: style.contentRadii.numeralRadius,
                scale: scale
            )
        }
        .frame(width: dialRadius * 2.0, height: dialRadius * 2.0)
        .accessibilityHidden(true)
    }
}

private struct NumeralsView: View {
    let dialRadius: CGFloat
    let numeralRadius: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let r = WWClock.pixel(numeralRadius, scale: scale)

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
                    WWClock.clamp(fontSizeBase * 1.02, min: fontSizeBase * 0.98, max: fontSizeBase * 1.06),
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
