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

        let majorOutset = max(px * 1.6, dotDiameter * 0.35)
        let majorRadius = WWClock.pixel(radius + majorOutset, scale: scale)
        let majorDiameter = WWClock.pixel(dotDiameter * 1.55, scale: scale)

        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let degrees = (Double(i) / Double(count)) * 360.0

                if quarterIndices.contains(i) {
                    ZStack {
                        Circle()
                            .fill(dotColour)

                        // Slight density boost without needing a separate palette colour.
                        Circle()
                            .fill(dotColour.opacity(0.35))
                    }
                    .frame(width: majorDiameter, height: majorDiameter)
                    .offset(y: -majorRadius)
                    .rotationEffect(.degrees(degrees))
                } else {
                    Circle()
                        .fill(dotColour)
                        .frame(width: dotDiameter, height: dotDiameter)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(degrees))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
