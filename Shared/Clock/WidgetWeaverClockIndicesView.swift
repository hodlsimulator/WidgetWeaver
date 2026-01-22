//
//  WidgetWeaverClockIndicesView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

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

        let metalField = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.batonBright, location: 0.00),
                .init(color: palette.batonMid, location: 0.50),
                .init(color: palette.batonDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: dialDiameter, height: dialDiameter)

        let edgeField = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.batonEdgeLight, location: 0.00),
                .init(color: Color.clear, location: 0.54),
                .init(color: palette.batonEdgeDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: dialDiameter, height: dialDiameter)

        ZStack {
            ForEach(hourIndices, id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0
                let corner = width * 0.18

                let batonMask = RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .frame(width: width, height: length)
                    .offset(y: -centreRadius)
                    .rotationEffect(.degrees(degrees))

                let batonStrokeMask = RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(lineWidth: max(px, width * 0.10))
                    .frame(width: width, height: length)
                    .offset(y: -centreRadius)
                    .rotationEffect(.degrees(degrees))

                metalField
                    .mask(batonMask)
                    .shadow(color: palette.batonShadow, radius: shadowRadius, x: shadowOffset, y: shadowOffset)

                edgeField
                    .mask(batonStrokeMask)

                RoundedRectangle(cornerRadius: corner * 0.85, style: .continuous)
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.black.opacity(0.12), location: 0.0),
                                .init(color: Color.white.opacity(0.40), location: 0.52),
                                .init(color: Color.black.opacity(0.14), location: 1.0)
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
        // A rounded-square reads closer to the iOS Clock icon than a perfect circle.
        let shape = RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)

        ZStack {
            ForEach([3, 6, 9], id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0

                shape
                    .fill(pipColour)
                    .frame(width: side, height: side)
                    .overlay(
                        shape
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: max(1, side * 0.10))
                            .blendMode(.overlay)
                    )
                    .shadow(color: Color.black.opacity(0.22), radius: max(1, side * 0.10), x: 0, y: max(1, side * 0.06))
                    .offset(y: -radius)
                    .rotationEffect(.degrees(degrees))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WidgetWeaverClockNumeralGlyphView: View {
    let palette: WidgetWeaverClockPalette
    let text: String
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let face = Text(text)
            .font(.system(size: fontSize, weight: .bold, design: .default))
            .fixedSize()

        let fill = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.numeralLight, location: 0.00),
                .init(color: palette.numeralMid, location: 0.56),
                .init(color: palette.numeralDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        return ZStack {
            // Small depth shadow so it reads embossed, not floating.
            face
                .foregroundStyle(palette.numeralDark.opacity(0.42))
                .offset(x: px * 1.2, y: px * 1.4)
                .blur(radius: max(0, px * 0.30))
                .blendMode(.multiply)

            // Inner bevel: highlight + shade.
            face
                .foregroundStyle(palette.numeralInnerHighlight)
                .offset(x: -px * 0.9, y: -px * 1.0)
                .blur(radius: max(0, px * 0.24))
                .blendMode(.screen)

            face
                .foregroundStyle(palette.numeralInnerShade)
                .offset(x: px * 0.9, y: px * 1.0)
                .blur(radius: max(0, px * 0.26))
                .blendMode(.multiply)

            // Main metal fill.
            face
                .foregroundStyle(fill)
        }
        .shadow(
            color: palette.numeralShadow,
            radius: max(px, fontSize * 0.045),
            x: 0,
            y: max(px, fontSize * 0.020)
        )
    }
}

struct WidgetWeaverClockNumeralsView: View {
    let palette: WidgetWeaverClockPalette
    let radius: CGFloat
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        ZStack {
            WidgetWeaverClockNumeralGlyphView(palette: palette, text: "12", fontSize: fontSize, scale: scale)
                .offset(x: 0, y: -radius)

            WidgetWeaverClockNumeralGlyphView(palette: palette, text: "3", fontSize: fontSize, scale: scale)
                .offset(x: radius, y: 0)

            WidgetWeaverClockNumeralGlyphView(palette: palette, text: "6", fontSize: fontSize, scale: scale)
                .offset(x: 0, y: radius)

            WidgetWeaverClockNumeralGlyphView(palette: palette, text: "9", fontSize: fontSize, scale: scale)
                .offset(x: -radius, y: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // If WidgetKit is applying placeholder redaction, force these to render normally.
        .unredacted()
    }
}

struct WidgetWeaverClockTwelveNumeralsView: View {
    let palette: WidgetWeaverClockPalette
    let radius: CGFloat
    let fontSize: CGFloat
    let scale: CGFloat

    private func text(for numeral: Int) -> String {
        numeral == 12 ? "12" : String(numeral)
    }

    private func offset(for numeral: Int) -> (x: CGFloat, y: CGFloat) {
        let stepDegrees = Double(numeral % 12) * 30.0
        let radians = stepDegrees * Double.pi / 180.0

        let x = radius * CGFloat(sin(radians))
        let y = -radius * CGFloat(cos(radians))

        return (x, y)
    }

    var body: some View {
        ZStack {
            ForEach(1..<13, id: \.self) { numeral in
                let p = offset(for: numeral)

                WidgetWeaverClockNumeralGlyphView(
                    palette: palette,
                    text: text(for: numeral),
                    fontSize: fontSize,
                    scale: scale
                )
                .offset(x: p.x, y: p.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // If WidgetKit is applying placeholder redaction, force these to render normally.
        .unredacted()
    }
}
