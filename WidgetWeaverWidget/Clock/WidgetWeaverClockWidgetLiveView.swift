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

    /// The current WidgetKit timeline entry date (used as a fallback).
    let date: Date

    /// Anchor date (kept for compatibility / future use).
    let anchorDate: Date

    /// Desired on-screen tick interval while visible.
    let tickSeconds: TimeInterval

    var body: some View {
        let showsSecondHand = tickSeconds <= 1.0
        let effectiveTick = max(1.0, tickSeconds)

        TimelineView(.animation(minimumInterval: effectiveTick, paused: false)) { context in
            clock(at: context.date, showsSecondHand: showsSecondHand)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func clock(at now: Date, showsSecondHand: Bool) -> some View {
        let angles = WWClockBaseAngles(date: now)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: .degrees(angles.hour),
            minuteAngle: .degrees(angles.minute),
            secondAngle: .degrees(angles.second),
            showsSecondHand: showsSecondHand,
            handsOpacity: 1.0
        )
    }
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

        self.second = sec * 6.0
        self.minute = (minuteInt + sec / 60.0) * 6.0
        self.hour = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
    }
}
