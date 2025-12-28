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
        ZStack {
            WidgetWeaverClockEmbossedNumeral(text: "12", palette: palette, fontSize: fontSize, scale: scale)
                .offset(x: 0, y: -radius)

            WidgetWeaverClockEmbossedNumeral(text: "3", palette: palette, fontSize: fontSize, scale: scale)
                .offset(x: radius, y: 0)

            WidgetWeaverClockEmbossedNumeral(text: "6", palette: palette, fontSize: fontSize, scale: scale)
                .offset(x: 0, y: radius)

            WidgetWeaverClockEmbossedNumeral(text: "9", palette: palette, fontSize: fontSize, scale: scale)
                .offset(x: -radius, y: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WidgetWeaverClockEmbossedNumeral: View {
    let text: String
    let palette: WidgetWeaverClockPalette
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        Text(text)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundColor(palette.numeralLight)
            .shadow(
                color: palette.numeralShadow,
                radius: max(px, fontSize * 0.040),
                x: px,
                y: px
            )
            .compositingGroup()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
