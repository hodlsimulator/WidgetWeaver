//
//  WidgetWeaverClockIndicesView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

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

    private let indices: [Int] = [1, 2, 4, 5, 7, 8, 10, 11]

    var body: some View {
        let px = WWClock.px(scale: scale)

        let shadowRadius = max(px, width * 0.09)
        let shadowOffset = max(px, width * 0.05)
        let corner = width * 0.18

        // Screen-space metal field so lighting direction is consistent.
        let metalField = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.batonBright, location: 0.00),
                .init(color: palette.batonMid, location: 0.55),
                .init(color: palette.batonDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: dialDiameter, height: dialDiameter)

        // Edge bevel field (light on upper-left, dark on lower-right).
        let edgeField = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.batonEdgeLight, location: 0.00),
                .init(color: Color.white.opacity(0.00), location: 0.40),
                .init(color: palette.batonEdgeDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: dialDiameter, height: dialDiameter)

        ZStack {
            ForEach(indices, id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0

                // Baton body (metal gradient masked to its shape)
                metalField
                    .mask(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .frame(width: width, height: length)
                            .rotationEffect(.degrees(degrees))
                            .offset(y: -centreRadius)
                    )
                    .overlay(
                        // Inner ridge highlight + underside shade for depth.
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.black.opacity(0.10), location: 0.00),
                                        .init(color: Color.white.opacity(0.40), location: 0.42),
                                        .init(color: Color.black.opacity(0.12), location: 1.00)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: width, height: length)
                            .rotationEffect(.degrees(degrees))
                            .offset(y: -centreRadius)
                            .blendMode(.overlay)
                    )
                    .overlay(
                        // Bevel edge stroke.
                        edgeField
                            .mask(
                                RoundedRectangle(cornerRadius: corner, style: .continuous)
                                    .stroke(lineWidth: max(px, width * 0.08))
                                    .frame(width: width, height: length)
                                    .rotationEffect(.degrees(degrees))
                                    .offset(y: -centreRadius)
                            )
                            .blendMode(.overlay)
                    )
                    .shadow(color: palette.batonShadow, radius: shadowRadius, x: shadowOffset, y: shadowOffset)

                // Blue cap at the outer tip
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
    let includesTopPip: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.14, style: .continuous)
        let indices: [Int] = includesTopPip ? [12, 3, 6, 9] : [3, 6, 9]

        ZStack {
            ForEach(indices, id: \.self) { i in
                let idx = i % 12
                let degrees = (Double(idx) / 12.0) * 360.0
                let isTop = (idx == 0)

                shape
                    .fill(pipColour.opacity(isTop ? 0.84 : 1.0))
                    .frame(width: isTop ? side * 0.92 : side, height: isTop ? side * 0.92 : side)
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
        let px = WWClock.px(scale: scale)

        ZStack {
            numeral("12", px: px)
                .offset(x: 0, y: -radius)

            numeral("3", px: px)
                .offset(x: radius, y: 0)

            numeral("6", px: px)
                .offset(x: 0, y: radius)

            numeral("9", px: px)
                .offset(x: -radius, y: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // If WidgetKit is applying placeholder redaction, force these to render normally.
        .unredacted()
    }

    @ViewBuilder
    private func numeral(_ text: String, px: CGFloat) -> some View {
        let face = Text(text)
            .font(.system(size: fontSize, weight: .semibold, design: .default))
            .fixedSize()

        // Bevel thickness needs to scale with the numeral size.
        // Using 1 px makes the emboss vanish at typical widget scales.
        let bevel = max(px, fontSize * 0.028)
        let bevelBlur = max(px, bevel * 0.65)

        // Use a single metal field for consistent lighting (top-left → bottom-right).
        let metalField = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.numeralLight, location: 0.00),
                .init(color: palette.numeralMid, location: 0.54),
                .init(color: palette.numeralDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        face
            .foregroundStyle(metalField)
            // Outer shadow to lift the numerals off the dial.
            .shadow(color: palette.numeralShadow, radius: bevelBlur * 0.95, x: bevel * 0.40, y: bevel * 0.55)
            // Emboss / inner bevel: highlight toward top-left.
            .overlay(
                face
                    .foregroundStyle(palette.numeralInnerHighlight)
                    .offset(x: -bevel * 0.45, y: -bevel * 0.45)
                    .blur(radius: bevelBlur)
                    .mask(face)
                    .blendMode(.screen)
            )
            // Emboss / inner bevel: shade toward bottom-right.
            .overlay(
                face
                    .foregroundStyle(palette.numeralInnerShade)
                    .offset(x: bevel * 0.45, y: bevel * 0.55)
                    .blur(radius: bevelBlur)
                    .mask(face)
                    .blendMode(.multiply)
            )
    }
}
