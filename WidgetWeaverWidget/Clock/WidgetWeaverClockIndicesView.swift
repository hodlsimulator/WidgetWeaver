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
                .init(color: palette.numeralMid, location: 0.58),
                .init(color: palette.numeralDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: radius * 2.0, height: radius * 2.0)

        ZStack {
            // Soft edge darkening so the numbers read as raised metal.
            face
                .foregroundStyle(palette.numeralDark.opacity(0.55))
                .blur(radius: max(px, bevel * 0.55))

            // Main metal face.
            metalField
                .mask(face)

            // Inner bevel: highlight (top-left).
            face
                .foregroundStyle(palette.numeralInnerHighlight)
                .offset(x: -bevel, y: -bevel)
                .blur(radius: bevelBlur)
                .blendMode(.screen)
                .mask(face)

            // Inner bevel: shade (bottom-right).
            face
                .foregroundStyle(palette.numeralInnerShade)
                .offset(x: bevel, y: bevel)
                .blur(radius: bevelBlur)
                .blendMode(.multiply)
                .mask(face)

            // Subtle specular sweep across the face.
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: Color.white.opacity(0.28), location: 0.00),
                    .init(color: Color.white.opacity(0.08), location: 0.42),
                    .init(color: Color.black.opacity(0.12), location: 1.00)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .mask(face)
            .blendMode(.overlay)
        }
        .shadow(
            color: palette.numeralShadow,
            radius: max(px, fontSize * 0.050),
            x: 0,
            y: max(px, fontSize * 0.030)
        )
    }
}
