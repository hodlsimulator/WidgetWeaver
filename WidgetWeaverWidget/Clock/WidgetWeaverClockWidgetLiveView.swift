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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isPlaceholder = redactionReasons.contains(.placeholder)
        let isPrivacy = redactionReasons.contains(.privacy)
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let wantsSeconds = (tickMode == .secondsSweep)

        // Prefer the CoreAnimation-based live clock only when motion is allowed.
        let liveEnabled =
            wantsSeconds
            && !isPlaceholder
            && !isPrivacy
            && !isLowPowerMode
            && !reduceMotion

        if liveEnabled {
            // Fully live (seconds + minute movement) without relying on WidgetKit timeline cadence.
            WidgetWeaverClockLiveView(palette: palette, startDate: entryDate)
                .privacySensitive(isPrivacy)
                .widgetURL(URL(string: "widgetweaver://clock"))
        } else {
            // Budget-safe static render (updates only when WidgetKit advances the timeline).
            WidgetWeaverRenderClock.withNow(entryDate) {
                let effective = WWClockTime.minuteAnchor(entryDate: entryDate)
                let angles = WWClockBaseAngles(date: effective)
                let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(angles.hour),
                    minuteAngle: .degrees(angles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: true,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)
                .widgetURL(URL(string: "widgetweaver://clock"))
            }
        }
    }
}

// MARK: - Helpers

private enum WWClockTime {
    static func minuteAnchor(entryDate: Date) -> Date {
        let systemNow = Date()

        // WidgetKit can pre-render ahead of time; if that happens, use a sane “now”.
        if entryDate > systemNow { return floorToMinute(systemNow) }

        // If the entry is stale, snap to the current minute.
        if systemNow.timeIntervalSince(entryDate) > 90.0 { return floorToMinute(systemNow) }

        // Otherwise use the entry date (minute-aligned in the timeline).
        return floorToMinute(entryDate)
    }

    static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        self.minute = minuteInt * 6.0
        self.hour = (hour12 + (minuteInt / 60.0)) * 30.0
    }
}
