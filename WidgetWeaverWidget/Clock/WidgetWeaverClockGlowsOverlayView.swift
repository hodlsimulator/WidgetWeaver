//
//  WidgetWeaverClockGlowsOverlayView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockGlowsOverlayView: View {
    let palette: WidgetWeaverClockPalette

    // Blue caps
    let hourCapCentreRadius: CGFloat
    let batonLength: CGFloat
    let batonWidth: CGFloat
    let capLength: CGFloat

    // Pips
    let pipSide: CGFloat
    let pipRadius: CGFloat

    // Minute edge emission glow
    let minuteAngle: Angle
    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    // Second hand terminal glow
    let secondAngle: Angle
    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat

    // Hub cut-out
    let hubCutoutRadius: CGFloat
    let scale: CGFloat

    private let hourIndices: [Int] = [1, 2, 4, 5, 7, 8, 10, 11]

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Tight glows only (single blur layer per element).
        let capGlowBlur = max(px, capLength * 0.18)
        let pipGlowBlur = max(px, pipSide * 0.20)

        let minuteGlowWidth = max(px, minuteWidth * 0.14)
        let minuteGlowBlur = max(px, minuteWidth * 0.20)

        let secondGlowBlur = max(px, secondWidth * 0.95)
        let secondTipGlowBlur = max(px, secondWidth * 1.05)

        ZStack {
            // Cap glows (one layer each, symmetric).
            ForEach(hourIndices, id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0
                RoundedRectangle(cornerRadius: batonWidth * 0.18, style: .continuous)
                    .fill(palette.accent.opacity(0.32))
                    .frame(width: batonWidth, height: capLength)
                    .offset(y: -(hourCapCentreRadius + (batonLength * 0.5) - (capLength * 0.5)))
                    .rotationEffect(.degrees(degrees))
                    .blur(radius: capGlowBlur)
                    .blendMode(.screen)
            }

            // Pip glows (tight, clipped by dial mask in the caller).
            ForEach([3, 6, 9], id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0
                RoundedRectangle(cornerRadius: pipSide * 0.14, style: .continuous)
                    .fill(palette.accent.opacity(0.26))
                    .frame(width: pipSide, height: pipSide)
                    .offset(y: -pipRadius)
                    .rotationEffect(.degrees(degrees))
                    .blur(radius: pipGlowBlur)
                    .blendMode(.screen)
            }

            // Minute-hand edge glow (one edge, ramping to tip; tight blur).
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.accent.opacity(0.00), location: 0.00),
                            .init(color: palette.accent.opacity(0.08), location: 0.55),
                            .init(color: palette.accent.opacity(0.34), location: 1.00)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: minuteGlowWidth, height: minuteLength)
                .offset(x: minuteWidth * 0.36, y: 0)
                .frame(width: minuteWidth, height: minuteLength)
                .rotationEffect(minuteAngle, anchor: .bottom)
                .offset(y: -minuteLength / 2.0)
                .blur(radius: minuteGlowBlur)
                .blendMode(.screen)

            // Second-hand glow (minimal).
            Rectangle()
                .fill(palette.accent.opacity(0.12))
                .frame(width: secondWidth, height: secondLength)
                .offset(y: -secondLength / 2.0)
                .rotationEffect(secondAngle)
                .blur(radius: secondGlowBlur)
                .blendMode(.screen)

            // Terminal square glow only.
            Rectangle()
                .fill(palette.accent.opacity(0.18))
                .frame(width: secondTipSide, height: secondTipSide)
                .offset(y: -secondLength)
                .rotationEffect(secondAngle)
                .blur(radius: secondTipGlowBlur)
                .blendMode(.screen)

            // Hub cut-out to prevent glow painting over centre hardware.
            Circle()
                .fill(Color.black)
                .frame(width: hubCutoutRadius * 2.0, height: hubCutoutRadius * 2.0)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
