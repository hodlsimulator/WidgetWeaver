//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import SwiftUI
import Foundation

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date
    let tickSeconds: TimeInterval

    var body: some View {
        let tick = max(0.5, tickSeconds)

        TimelineView(.periodic(from: anchorDate, by: tick)) { context in
            let angles = WWClockAngles(date: context.date)

            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: Angle.degrees(angles.hourDegrees),
                minuteAngle: Angle.degrees(angles.minuteDegrees),
                secondAngle: Angle.degrees(angles.secondDegrees),
                showsSecondHand: true,
                handsOpacity: 1.0
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(.linear(duration: tick), value: context.date)
        }
    }
}

private struct WWClockAngles {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(date: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let local = date.timeIntervalSince1970 + tz

        secondDegrees = local * WWClockAngularVelocity.secondDegPerSecond
        minuteDegrees = local * WWClockAngularVelocity.minuteDegPerSecond
        hourDegrees = local * WWClockAngularVelocity.hourDegPerSecond
    }
}

private enum WWClockAngularVelocity {
    static let secondDegPerSecond: Double = 360.0 / 60.0
    static let minuteDegPerSecond: Double = 360.0 / 3600.0
    static let hourDegPerSecond: Double = 360.0 / 43200.0
}
