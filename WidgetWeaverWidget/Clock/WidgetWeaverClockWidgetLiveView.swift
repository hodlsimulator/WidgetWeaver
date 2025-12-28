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

    /// The active timeline entry date.
    let date: Date

    /// A stable anchor for the current timeline.
    ///
    /// Hand angles are computed as unbounded (monotonic) values from this anchor to avoid wrap/jitter
    /// at second/minute boundaries.
    let anchorDate: Date

    /// Expected spacing between timeline entries.
    ///
    /// Used as the animation duration so CoreAnimation can sweep the hands smoothly between entries.
    let tickSeconds: TimeInterval

    var body: some View {
        let base = WWClockBaseAngles(date: anchorDate)
        let dt = date.timeIntervalSince(anchorDate)

        let hourAngle = Angle.degrees(base.hour + dt * WWClockAngularVelocity.hourDegPerSecond)
        let minuteAngle = Angle.degrees(base.minute + dt * WWClockAngularVelocity.minuteDegPerSecond)
        let secondAngle = Angle.degrees(base.second + dt * WWClockAngularVelocity.secondDegPerSecond)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: hourAngle,
            minuteAngle: minuteAngle,
            secondAngle: secondAngle,
            showsSecondHand: true,
            handsOpacity: 1.0
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .animation(.linear(duration: max(0.0, tickSeconds)), value: date)
    }
}

private enum WWClockAngularVelocity {
    static let secondDegPerSecond: Double = 360.0 / 60.0
    static let minuteDegPerSecond: Double = 360.0 / 3600.0
    static let hourDegPerSecond: Double = 360.0 / 43200.0
}

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double
    let second: Double

    init(date: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let local = date.timeIntervalSince1970 + tz

        let sec = local.truncatingRemainder(dividingBy: 60.0)
        let minTotal = (local / 60.0).truncatingRemainder(dividingBy: 60.0)
        let hourTotal = (local / 3600.0).truncatingRemainder(dividingBy: 12.0)

        second = sec * 6.0
        minute = (minTotal + sec / 60.0) * 6.0
        hour = (hourTotal + minTotal / 60.0 + sec / 3600.0) * 30.0
    }
}
