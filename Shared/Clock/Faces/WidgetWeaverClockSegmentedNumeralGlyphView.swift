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
/// Styling is intentionally fixed (metallic matte) to match the segmented mock
/// and remain consistent across colour schemes.
///
/// WidgetKit snapshots penalise soft blur/haze. Effects are clamped
/// and biased towards crisp bevel lines.
struct WidgetWeaverClockSegmentedNumeralGlyphView: View {
    let text: String
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let face = SegmentedNumeralBaseShape(text: text, fontSize: fontSize, scale: scale)

        // Matte metal fill (less sticker-white).
        let metalFill = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: WWClock.colour(0xE7EBF2, alpha: 0.92), location: 0.00),
                .init(color: WWClock.colour(0xC3CAD6, alpha: 0.90), location: 0.56),
                .init(color: WWClock.colour(0x7A879B, alpha: 0.92), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let specularOverlay = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.14), location: 0.00),
                .init(color: Color.white.opacity(0.00), location: 0.42),
                .init(color: Color.black.opacity(0.12), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let bevelBlur = max(0, px * 0.12)

        return ZStack {
            // Depth shadow so the glyph reads embossed into the segment surface.
            face
                .foregroundStyle(Color.black.opacity(0.38))
                .offset(x: px * 0.90, y: px * 1.05)
                .blur(radius: bevelBlur)
                .blendMode(.multiply)

            // Inner bevel: highlight then shade.
            face
                .foregroundStyle(Color.white.opacity(0.28))
                .offset(x: px * -0.85, y: px * -0.95)
                .blur(radius: bevelBlur)
                .blendMode(.screen)

            face
                .foregroundStyle(Color.black.opacity(0.22))
                .offset(x: px * 0.80, y: px * 0.86)
                .blur(radius: max(0, px * 0.14))
                .blendMode(.multiply)

            // Main metal fill.
            face
                .foregroundStyle(metalFill)

            // Subtle specular to keep the fill from reading flat.
            face
                .foregroundStyle(specularOverlay)
                .blendMode(.overlay)
                .opacity(0.55)
        }
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

            let fixedWidthBase = SegmentedNumeralTextMetrics.twoDigitWidth(fontSize: fontSize, scale: scale)
            let fixedWidth = WWClock.pixel(fixedWidthBase * SegmentedNumeralTextMetrics.twoDigitWidthSlackFactor, scale: scale)

            let kerningPx: CGFloat = 2.0
            let spacing = WWClock.pixel(-(kerningPx / max(scale, 1.0)), scale: scale)

            return AnyView(
                HStack(spacing: spacing) {
                    Text(left)
                        .font(font)
                        .monospacedDigit()
                        .segmentedNumeralWidth()

                    Text(right)
                        .font(font)
                        .monospacedDigit()
                        .segmentedNumeralWidth()
                }
                .fixedSize()
                .frame(width: fixedWidth, alignment: .center)
            )
        }

        return AnyView(
            Text(text)
                .font(font)
                .monospacedDigit()
                .segmentedNumeralWidth()
                .fixedSize()
        )
    }
}

private enum SegmentedNumeralTextMetrics {
    // Provides headroom for expanded-width numerals and the iOS < 17 fallback width scaling.
    static let twoDigitWidthSlackFactor: CGFloat = 1.12

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

private extension View {
    @ViewBuilder
    func segmentedNumeralWidth() -> some View {
        if #available(iOS 17.0, *) {
            self.fontWidth(.expanded)
        } else {
            self.scaleEffect(x: 1.06, y: 1.0, anchor: .center)
        }
    }
}
