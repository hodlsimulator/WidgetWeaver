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

        // Quarter-hour dots at 12/3/6/9.
        // These replace the minor dot at the same index (so there is only one dot per angle).
        let quarterIndices: Set<Int> = {
            guard count > 0 else { return [] }
            let q1 = (count * 1) / 4
            let q2 = (count * 2) / 4
            let q3 = (count * 3) / 4
            return [0, q1, q2, q3]
        }()

        // Slight prominence bump for the minute dots (subtle, closer to the mock).
        let minorDiameter = WWClock.pixel(dotDiameter * 1.10, scale: scale)
        let minorGlowBlur = max(px, minorDiameter * 0.22)

        // Quarter-hour dots: keep a single dot (no duplicate), but avoid any “major” top marker.
        // These stay the same size as the other minute dots, with only a small density boost.
        let majorDiameter = minorDiameter
        let majorGlowBlur = minorGlowBlur

        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let degrees = (Double(i) / Double(count)) * 360.0

                if quarterIndices.contains(i) {
                    ZStack {
                        Circle()
                            .fill(dotColour)

                        // Slight density boost without introducing a second marker.
                        Circle()
                            .fill(dotColour.opacity(0.30))
                    }
                    .frame(width: majorDiameter, height: majorDiameter)
                    .shadow(color: dotColour.opacity(0.18), radius: majorGlowBlur, x: 0, y: 0)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(degrees))
                } else {
                    Circle()
                        .fill(dotColour)
                        .frame(width: minorDiameter, height: minorDiameter)
                        .shadow(color: dotColour.opacity(0.14), radius: minorGlowBlur, x: 0, y: 0)
                        .offset(y: -radius)
                        .rotationEffect(.degrees(degrees))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
