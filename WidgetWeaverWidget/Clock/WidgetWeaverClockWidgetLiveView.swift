//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI
import WidgetKit

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        let isPlaceholder = redactionReasons.contains(.placeholder)
        let isPrivacy = redactionReasons.contains(.privacy)

        let showLive = !(isPlaceholder || isPrivacy)
        let handsOpacity: Double = showLive ? 1.0 : 0.85

        Group {
            if showLive {
                // Drive hands with an in-view 1Hz tick (budget-safe vs 1Hz WidgetKit timelines).
                // Angles are computed from the live time so the minute hand is not “seconds behind”.
                TimelineView(.periodic(from: entryDate, by: 1.0)) { context in
                    clock(now: context.date, handsOpacity: handsOpacity, isPrivacy: isPrivacy, showHeartbeat: true)
                }
            } else {
                // Static render for placeholder / privacy.
                clock(now: entryDate, handsOpacity: handsOpacity, isPrivacy: isPrivacy, showHeartbeat: false)
            }
        }
        .privacySensitive(isPrivacy)
        .widgetURL(URL(string: "widgetweaver://clock"))
    }

    @ViewBuilder
    private func clock(now: Date, handsOpacity: Double, isPrivacy: Bool, showHeartbeat: Bool) -> some View {
        let angles = WWClockAngles(date: now)

        ZStack(alignment: .bottomTrailing) {
            // Single stable tree: just update the angles.
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(angles.hour),
                minuteAngle: .degrees(angles.minute),
                secondAngle: .degrees(angles.second),
                showsSecondHand: true,
                showsHandShadows: true,
                showsGlows: true,
                showsCentreHub: true,
                handsOpacity: handsOpacity
            )

            // A tiny “heartbeat” keeps the host in a live-updating mode in more hosting paths.
            if showHeartbeat {
                WWClockWidgetHeartbeat(start: entryDate)
            }
        }
        .opacity(handsOpacity)
    }
}

// MARK: - Live angles (include seconds)

private struct WWClockAngles {
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

        // Tick-style angles (no reliance on font ligatures).
        self.second = sec * 6.0
        self.minute = (minuteInt + sec / 60.0) * 6.0
        self.hour = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
    }
}

// MARK: - Heartbeat

private struct WWClockWidgetHeartbeat: View {
    let start: Date

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .font(.system(size: 1))
            .foregroundStyle(Color.primary.opacity(0.001))
            .frame(width: 1, height: 1)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
