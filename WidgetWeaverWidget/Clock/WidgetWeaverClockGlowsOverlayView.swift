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

    // Minute edge emission glow
    let minuteAngle: Angle
    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    // Second hand terminal glow
    let secondAngle: Angle
    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat

    let scale: CGFloat

    private let hourIndices: [Int] = [1, 2, 4, 5, 7, 8, 10, 11]

    var body: some View {
        let px = WWClock.px(scale: scale)

        // 5-minute bar cap glows (existing geometry; just slightly stronger + a tighter pass).
        let capGlowBlur = max(px, capLength * 0.20)
        let capGlowBlurTight = max(px, capLength * 0.12)

        // Minute hand edge emission glow (slightly stronger + a tighter pass for crispness).
        let minuteGlowWidth = max(px, minuteWidth * 0.14)
        let minuteGlowBlur = max(px, minuteWidth * 0.22)

        let minuteGlowWidthTight = max(px, minuteWidth * 0.10)
        let minuteGlowBlurTight = max(px, minuteWidth * 0.12)

        let secondGlowBlur = max(px, secondWidth * 0.95)
        let secondTipGlowBlur = max(px, secondWidth * 1.05)

        ZStack {
            ForEach(hourIndices, id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0

                RoundedRectangle(cornerRadius: batonWidth * 0.18, style: .continuous)
                    .fill(palette.accent.opacity(0.40))
                    .frame(width: batonWidth, height: capLength)
                    .offset(y: -(hourCapCentreRadius + (batonLength * 0.5) - (capLength * 0.5)))
                    .rotationEffect(.degrees(degrees))
                    .blur(radius: capGlowBlur)
                    .blendMode(.screen)

                RoundedRectangle(cornerRadius: batonWidth * 0.18, style: .continuous)
                    .fill(palette.accent.opacity(0.30))
                    .frame(width: batonWidth, height: capLength)
                    .offset(y: -(hourCapCentreRadius + (batonLength * 0.5) - (capLength * 0.5)))
                    .rotationEffect(.degrees(degrees))
                    .blur(radius: capGlowBlurTight)
                    .blendMode(.screen)
            }

            // Outer (soft) minute glow.
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.accent.opacity(0.00), location: 0.00),
                            .init(color: palette.accent.opacity(0.10), location: 0.55),
                            .init(color: palette.accent.opacity(0.40), location: 1.00)
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

            // Inner (tighter) minute glow to keep the edge crisp.
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.accent.opacity(0.00), location: 0.00),
                            .init(color: palette.accent.opacity(0.08), location: 0.55),
                            .init(color: palette.accent.opacity(0.32), location: 1.00)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: minuteGlowWidthTight, height: minuteLength)
                .offset(x: minuteWidth * 0.36, y: 0)
                .frame(width: minuteWidth, height: minuteLength)
                .rotationEffect(minuteAngle, anchor: .bottom)
                .offset(y: -minuteLength / 2.0)
                .blur(radius: minuteGlowBlurTight)
                .blendMode(.screen)

            Rectangle()
                .fill(palette.accent.opacity(0.12))
                .frame(width: secondWidth, height: secondLength)
                .offset(y: -secondLength / 2.0)
                .rotationEffect(secondAngle)
                .blur(radius: secondGlowBlur)
                .blendMode(.screen)

            Rectangle()
                .fill(palette.accent.opacity(0.18))
                .frame(width: secondTipSide, height: secondTipSide)
                .offset(y: -secondLength)
                .rotationEffect(secondAngle)
                .blur(radius: secondTipGlowBlur)
                .blendMode(.screen)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
