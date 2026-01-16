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
        let skipIndices: Set<Int> = {
            guard count >= 4 else { return [] }
            return [count / 4, count / 2, (count * 3) / 4]
        }()

        ZStack {
            ForEach(0..<count, id: \.self) { i in
                if !skipIndices.contains(i) {
                    let isTwelve = (i == 0)
                    let d = isTwelve ? (dotDiameter * 1.25) : dotDiameter

                    Circle()
                        .fill(dotColour)
                        .frame(width: d, height: d)
                        .offset(y: -radius)
                        .rotationEffect(.degrees((Double(i) / Double(count)) * 360.0))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
