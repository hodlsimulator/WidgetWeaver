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

        let bevelOverlay = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.26), location: 0.00),
                .init(color: Color.clear, location: 0.52),
                .init(color: Color.black.opacity(0.22), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        ZStack {
            // Drop depth (small, so it reads embossed not floating).
            face
                .foregroundStyle(palette.numeralDark.opacity(0.55))
                .offset(x: px * 1.6, y: px * 1.9)
                .blur(radius: max(0, px * 0.45))
                .blendMode(.multiply)

            // Inner bevel: highlight + shade.
            face
                .foregroundStyle(palette.numeralInnerHighlight)
                .offset(x: -px * 1.1, y: -px * 1.2)
                .blur(radius: max(0, px * 0.40))
                .blendMode(.screen)

            face
                .foregroundStyle(palette.numeralInnerShade)
                .offset(x: px * 1.1, y: px * 1.2)
                .blur(radius: max(0, px * 0.45))
                .blendMode(.multiply)

            face
                .foregroundStyle(fill)
                .overlay(
                    face
                        .foregroundStyle(bevelOverlay)
                        .blendMode(.overlay)
                )

            // Specular streak (very subtle).
            face
                .foregroundStyle(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.0), location: 0.00),
                            .init(color: Color.white.opacity(0.14), location: 0.40),
                            .init(color: Color.white.opacity(0.0), location: 1.00)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.screen)
                .opacity(0.85)
        }
        .shadow(
            color: palette.numeralShadow,
            radius: max(px, fontSize * 0.05),
            x: 0,
            y: max(px, fontSize * 0.025)
        )
    }
}
