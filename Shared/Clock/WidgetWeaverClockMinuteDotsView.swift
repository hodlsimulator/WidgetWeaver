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

/// Renders 60 tick marks (minor) with 12 major hour ticks.
///
/// Layout convention:
/// - `radius` represents the outer edge of each tick.
/// - Tick bodies extend inwards by their respective lengths.
struct WidgetWeaverClockMinuteTickMarksView: View {
    let palette: WidgetWeaverClockPalette
    let dialDiameter: CGFloat

    let radius: CGFloat

    let majorLength: CGFloat
    let minorLength: CGFloat

    let majorWidth: CGFloat
    let minorWidth: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)
        let t = WidgetWeaverClockFaceTokens.tickMarks

        let majorFill = palette.minuteDot.opacity(t.majorFillOpacity)
        let minorFill = palette.minuteDot.opacity(t.minorOpacity(dialDiameter: dialDiameter))

        let majorShadowRadius = max(px, majorWidth * 0.40)
        let majorShadowY = max(px, majorWidth * 0.18)

        let minorShadowRadius = max(px, minorWidth * 1.05)
        let minorShadowY = max(px, minorWidth * 0.70)

        ZStack {
            ForEach(0..<60, id: \.self) { idx in
                let isMajor = (idx % 5 == 0)
                let length = isMajor ? majorLength : minorLength
                let width = isMajor ? majorWidth : minorWidth

                let yOffset = -(radius - (length / 2.0))
                let corner = width * 0.40

                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(isMajor ? majorFill : minorFill)
                    .frame(width: width, height: length)
                    .shadow(
                        color: Color.black.opacity(isMajor ? t.majorShadowOpacity : t.minorShadowOpacity),
                        radius: isMajor ? majorShadowRadius : minorShadowRadius,
                        x: 0,
                        y: isMajor ? majorShadowY : minorShadowY
                    )
                    .offset(y: yOffset)
                    .rotationEffect(.degrees(Double(idx) * 6.0))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .drawingGroup()
    }
}
