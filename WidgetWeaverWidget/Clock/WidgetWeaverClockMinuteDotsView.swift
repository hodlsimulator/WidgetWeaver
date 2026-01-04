//
//  WidgetWeaverClockMinuteDotsView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockMinuteDotsView: View {
    let count: Int
    let radius: CGFloat
    let dotDiameter: CGFloat
    let dotColour: Color
    let cardinalDotColour: Color
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Emphasise the quarter-hour dots behind 12/3/6/9.
        // These sit slightly further out so they replace the minor dot at the same angle.
        let quarterIndices: Set<Int> = {
            guard count > 0 else { return [] }
            let q1 = (count * 1) / 4
            let q2 = (count * 2) / 4
            let q3 = (count * 3) / 4
            return [0, q1, q2, q3]
        }()

        // Slightly larger + a tight glow so the 60-minute dots read closer to the mock.
        let minorDiameter = WWClock.pixel(dotDiameter * 1.10, scale: scale)
        let minorGlowBlur = max(px, minorDiameter * 0.26)

        // Cardinal dots use the accent colour and sit a touch further out so they replace the normal dot.
        let majorOutset = max(px * 1.6, dotDiameter * 0.40)
        let majorRadius = WWClock.pixel(radius + majorOutset, scale: scale)
        let majorDiameter = WWClock.pixel(dotDiameter * 1.60, scale: scale)
        let majorGlowBlur = max(px, majorDiameter * 0.34)

        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let degrees = (Double(i) / Double(count)) * 360.0

                if quarterIndices.contains(i) {
                    Circle()
                        .fill(cardinalDotColour)
                        .frame(width: majorDiameter, height: majorDiameter)
                        .shadow(color: cardinalDotColour.opacity(0.65), radius: majorGlowBlur, x: 0, y: 0)
                        .shadow(color: cardinalDotColour.opacity(0.22), radius: majorGlowBlur * 1.45, x: 0, y: 0)
                        .offset(y: -majorRadius)
                        .rotationEffect(.degrees(degrees))
                } else {
                    Circle()
                        .fill(dotColour)
                        .frame(width: minorDiameter, height: minorDiameter)
                        .shadow(color: dotColour.opacity(0.20), radius: minorGlowBlur, x: 0, y: 0)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(degrees))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
