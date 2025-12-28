//
//  WidgetWeaverClockIndicesView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI
import UIKit
import CoreText

struct WidgetWeaverClockHourIndicesView: View {
    let palette: WidgetWeaverClockPalette
    let dialDiameter: CGFloat
    let centreRadius: CGFloat
    let length: CGFloat
    let width: CGFloat
    let capLength: CGFloat
    let capColour: Color
    let scale: CGFloat

    private let hourIndices: [Int] = [1, 2, 4, 5, 7, 8, 10, 11]

    var body: some View {
        let px = WWClock.px(scale: scale)
        let shadowRadius = max(px, width * 0.040)
        let shadowOffset = max(px, width * 0.050)

        let metalField =
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: palette.batonBright, location: 0.00),
                    .init(color: palette.batonMid, location: 0.50),
                    .init(color: palette.batonDark, location: 1.00),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: dialDiameter, height: dialDiameter)

        let edgeField =
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: palette.batonEdgeLight, location: 0.00),
                    .init(color: Color.clear, location: 0.54),
                    .init(color: palette.batonEdgeDark, location: 1.00),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: dialDiameter, height: dialDiameter)

        ZStack {
            ForEach(hourIndices, id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0
                let corner = width * 0.18

                let batonMask =
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .frame(width: width, height: length)
                        .offset(y: -centreRadius)
                        .rotationEffect(.degrees(degrees))

                let batonStrokeMask =
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(lineWidth: max(px, width * 0.10))
                        .frame(width: width, height: length)
                        .offset(y: -centreRadius)
                        .rotationEffect(.degrees(degrees))

                metalField
                    .mask(batonMask)
                    .shadow(
                        color: palette.batonShadow,
                        radius: shadowRadius,
                        x: shadowOffset,
                        y: shadowOffset
                    )

                edgeField
                    .mask(batonStrokeMask)

                RoundedRectangle(cornerRadius: corner * 0.85, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.black.opacity(0.12), location: 0.0),
                                .init(color: Color.white.opacity(0.40), location: 0.52),
                                .init(color: Color.black.opacity(0.14), location: 1.0),
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.62, height: length * 0.94)
                    .offset(y: -centreRadius)
                    .rotationEffect(.degrees(degrees))
                    .blendMode(.overlay)

                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(capColour)
                    .frame(width: width, height: capLength)
                    .offset(y: -(centreRadius + (length * 0.5) - (capLength * 0.5)))
                    .rotationEffect(.degrees(degrees))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WidgetWeaverClockCardinalPipsView: View {
    let pipColour: Color
    let side: CGFloat
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.14, style: .continuous)

        ZStack {
            ForEach([3, 6, 9], id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0

                shape
                    .fill(pipColour)
                    .frame(width: side, height: side)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(degrees))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WidgetWeaverClockNumeralsView: View {
    let palette: WidgetWeaverClockPalette
    let radius: CGFloat
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        ZStack {
            WidgetWeaverClockVectorEmbossedNumeral(text: "12", palette: palette, fontSize: fontSize, scale: scale)
                .offset(x: 0, y: -radius)

            WidgetWeaverClockVectorEmbossedNumeral(text: "3", palette: palette, fontSize: fontSize, scale: scale)
                .offset(x: radius, y: 0)

            WidgetWeaverClockVectorEmbossedNumeral(text: "6", palette: palette, fontSize: fontSize, scale: scale)
                .offset(x: 0, y: radius)

            WidgetWeaverClockVectorEmbossedNumeral(text: "9", palette: palette, fontSize: fontSize, scale: scale)
                .offset(x: -radius, y: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Vector numerals (avoid Text/Image placeholder redaction)

private struct WidgetWeaverClockVectorEmbossedNumeral: View {
    let text: String
    let palette: WidgetWeaverClockPalette
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)
        let shadowRadius = max(px, fontSize * 0.040)

        let glyph = WWClockGlyphShape(text: text, fontSize: fontSize)

        ZStack {
            glyph
                .fill(palette.numeralInnerShade)
                .offset(x: px, y: px)

            glyph
                .fill(palette.numeralInnerHighlight)
                .offset(x: -px, y: -px)

            glyph
                .fill(palette.numeralLight)
        }
        .shadow(color: palette.numeralShadow, radius: shadowRadius, x: px, y: px)
        .frame(width: fontSize * 2.0, height: fontSize * 2.0)
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWClockGlyphShape: Shape {
    let text: String
    let fontSize: CGFloat

    func path(in rect: CGRect) -> Path {
        let ctFont = (UIFont.systemFont(ofSize: fontSize, weight: .semibold) as CTFont)

        let chars: [UniChar] = Array(text.utf16)
        guard !chars.isEmpty else { return Path() }

        var glyphs = Array(repeating: CGGlyph(), count: chars.count)
        let ok = CTFontGetGlyphsForCharacters(ctFont, chars, &glyphs, chars.count)
        guard ok else { return Path() }

        let raw = CGMutablePath()
        var x: CGFloat = 0

        for g in glyphs {
            if let gp = CTFontCreatePathForGlyph(ctFont, g, nil) {
                var t = CGAffineTransform(translationX: x, y: 0)
                raw.addPath(gp, transform: t)
            }

            var advance = CGSize.zero
            var gv = g
            CTFontGetAdvancesForGlyphs(ctFont, .horizontal, &gv, &advance, 1)
            x += advance.width
        }

        let bounds = raw.boundingBoxOfPath
        guard !bounds.isNull, !bounds.isEmpty else { return Path() }

        // Normalise to (0,0)
        var toOrigin = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        guard let normalised = raw.copy(using: &toOrigin) else { return Path() }

        // Flip Y into SwiftUI coordinate space: (x, y) -> (x, -y + H)
        var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
        guard let flipped = normalised.copy(using: &flip) else { return Path() }

        // Centre inside the provided rect
        let dx = rect.midX - (bounds.width / 2.0)
        let dy = rect.midY - (bounds.height / 2.0)

        var centre = CGAffineTransform(translationX: dx, y: dy)
        guard let centred = flipped.copy(using: &centre) else { return Path() }

        return Path(centred)
    }
}
