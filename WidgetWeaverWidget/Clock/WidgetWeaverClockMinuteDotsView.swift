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
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let a = (Double(i) / Double(count)) * (Double.pi * 2.0)
                let x = CGFloat(sin(a)) * radius
                let y = -CGFloat(cos(a)) * radius

                Circle()
                    .fill(dotColour)
                    .frame(width: dotDiameter, height: dotDiameter)
                    .position(
                        x: WWClock.pixel((radius) + x, scale: scale),
                        y: WWClock.pixel((radius) + y, scale: scale)
                    )
            }
        }
        .frame(width: radius * 2.0, height: radius * 2.0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
