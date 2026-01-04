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
                Circle()
                    .fill(dotColour)
                    .frame(width: dotDiameter, height: dotDiameter)
                    .offset(y: -radius)
                    .rotationEffect(.degrees((Double(i) / Double(count)) * 360.0))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
