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

    /// Desired tick interval for on-screen updates.
    ///
    /// When `<= 1`, the widget uses an in-view periodic TimelineView at 1 Hz (WidgetKit timeline remains sparse).
    /// When `> 1`, the view animates between WidgetKit timeline entries.
    let tickSeconds: TimeInterval

    var body: some View {
        let wantsOneHz = (tickSeconds <= 1.0)

        if wantsOneHz {
            TimelineView(.periodic(from: date, by: 1.0)) { context in
                clock(at: context.date)
                    .animation(.linear(duration: 1.0), value: context.date)
            }
        } else {
            clock(at: date)
                .animation(.linear(duration: max(0.0, tickSeconds)), value: date)
        }
    }

    @ViewBuilder
    private func clock(at now: Date) -> some View {
        let base = WWClockBaseAngles(date: anchorDate)
        let dt = now.timeIntervalSince(anchorDate)

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
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = secondInt + (nano / 1_000_000_000.0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        second = sec * 6.0
        minute = (minuteInt + sec / 60.0) * 6.0
        hour = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
    }
}
