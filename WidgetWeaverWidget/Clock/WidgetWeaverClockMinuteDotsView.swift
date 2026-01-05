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

        // Keep these minute dots distinct from the major pips at 3 / 6 / 9.
        // With 60 dots and index 0 at 12:
        // - 3 o’clock = 15
        // - 6 o’clock = 30
        // - 9 o’clock = 45
        // Index 0 (12) must remain a normal minute dot.
        let skipIndices: Set<Int> = (count == 60) ? [15, 30, 45] : []

        // Slightly larger dots to read closer to the mock, while staying crisp on pixel grids.
        let finalDotDiameter = WWClock.pixel(dotDiameter * 1.10, scale: scale)
        let shadowRadius = max(px, finalDotDiameter * 0.12)
        let shadowOffset = max(px, finalDotDiameter * 0.06)

        ZStack {
            ForEach(0..<count, id: \.self) { i in
                if !skipIndices.contains(i) {
                    Circle()
                        .fill(dotColour)
                        .frame(width: finalDotDiameter, height: finalDotDiameter)
                        .shadow(
                            color: Color.black.opacity(0.18),
                            radius: shadowRadius,
                            x: 0,
                            y: shadowOffset
                        )
                        .offset(y: -radius)
                        .rotationEffect(.degrees((Double(i) / Double(count)) * 360.0))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
