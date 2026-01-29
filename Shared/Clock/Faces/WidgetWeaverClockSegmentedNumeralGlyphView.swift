//
//  WidgetWeaverClockSegmentedNumeralGlyphView.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Numeral glyph used by the Segmented clock face.
///
/// The styling is intentionally fixed (silver metal) to match the segmented mock
/// and remain consistent across colour schemes.
struct WidgetWeaverClockSegmentedNumeralGlyphView: View {
    let text: String
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let face = SegmentedNumeralBaseShape(text: text, fontSize: fontSize, scale: scale)

        let metalFill = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: WWClock.colour(0xF3F7FF, alpha: 0.95), location: 0.00),
                .init(color: WWClock.colour(0xC7D4E6, alpha: 0.92), location: 0.56),
                .init(color: WWClock.colour(0x7B8AA5, alpha: 0.94), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let specularOverlay = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.24), location: 0.00),
                .init(color: Color.white.opacity(0.00), location: 0.40),
                .init(color: Color.black.opacity(0.18), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return ZStack {
            // Depth shadow so the glyph reads embossed into the segment surface.
            face
                .foregroundStyle(Color.black.opacity(0.44))
                .offset(x: px * 0.95, y: px * 1.10)
                .blur(radius: max(0, px * 0.22))
                .blendMode(.multiply)

            // Inner bevel: highlight then shade.
            face
                .foregroundStyle(Color.white.opacity(0.34))
                .offset(x: px * -0.95, y: px * -1.05)
                .blur(radius: max(0, px * 0.22))
                .blendMode(.screen)

            face
                .foregroundStyle(Color.black.opacity(0.26))
                .offset(x: px * 0.90, y: px * 0.95)
                .blur(radius: max(0, px * 0.24))
                .blendMode(.multiply)

            // Main metal fill.
            face
                .foregroundStyle(metalFill)

            // Subtle specular to keep the fill from reading flat at mid sizes.
            face
                .foregroundStyle(specularOverlay)
                .blendMode(.overlay)
                .opacity(0.72)
        }
        .shadow(
            color: Color.black.opacity(0.16),
            radius: max(px, fontSize * 0.024),
            x: 0,
            y: max(0, fontSize * 0.010)
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SegmentedNumeralBaseShape: View {
    let text: String
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        let font = Font.system(size: fontSize, weight: .heavy, design: .default)

        // Tighten internal spacing for 10/11/12 while keeping the overall width stable.
        let isTwoDigitTightened = (text == "10" || text == "11" || text == "12")

        if isTwoDigitTightened, text.count == 2 {
            let digits = Array(text)
            let left = String(digits[0])
            let right = String(digits[1])

            let fixedWidth = SegmentedNumeralTextMetrics.twoDigitWidth(fontSize: fontSize, scale: scale)

            let kerningPx: CGFloat = 2.0
            let spacing = WWClock.pixel(-(kerningPx / max(scale, 1.0)), scale: scale)

            return AnyView(
                HStack(spacing: spacing) {
                    Text(left)
                        .font(font)
                        .monospacedDigit()

                    Text(right)
                        .font(font)
                        .monospacedDigit()
                }
                .fixedSize()
                .frame(width: fixedWidth, alignment: .center)
            )
        }

        return AnyView(
            Text(text)
                .font(font)
                .monospacedDigit()
                .fixedSize()
        )
    }
}

private enum SegmentedNumeralTextMetrics {
    static func twoDigitWidth(fontSize: CGFloat, scale: CGFloat) -> CGFloat {
        #if canImport(UIKit)
        let uiFont = UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .heavy)
        let width = ("00" as NSString).size(withAttributes: [.font: uiFont]).width
        return WWClock.pixel(width, scale: scale)
        #else
        return WWClock.pixel(fontSize * 1.20, scale: scale)
        #endif
    }
}
