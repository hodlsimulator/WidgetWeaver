//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import SwiftUI
import WidgetKit
import UIKit
import Foundation

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval

    @Environment(\.redactionReasons) private var redactionReasons

    init(
        palette: WidgetWeaverClockPalette,
        entryDate: Date,
        tickMode: WidgetWeaverClockTickMode,
        tickSeconds: TimeInterval
    ) {
        self.palette = palette
        self.entryDate = entryDate
        self.tickMode = tickMode
        self.tickSeconds = tickSeconds
    }

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPlaceholder = redactionReasons.contains(.placeholder)
            let isPrivacy = redactionReasons.contains(.privacy)
            let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            let isReduceMotion = UIAccessibility.isReduceMotionEnabled

            let secondsEnabled =
                (tickMode == .secondsSweep)
                && !isPlaceholder
                && !isPrivacy
                && !isLowPowerMode
                && !isReduceMotion

            let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

            let base = WWClockBaseAngles(date: entryDate)
            let sweep = WWClockMonotonicAngles(date: entryDate)

            let hourDeg = secondsEnabled ? sweep.hour : base.hour
            let minuteDeg = secondsEnabled ? sweep.minute : base.minute
            let secondDeg = secondsEnabled ? sweep.second : 0.0

            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(hourDeg),
                minuteAngle: .degrees(minuteDeg),
                secondAngle: .degrees(secondDeg),
                showsSecondHand: secondsEnabled,
                showsHandShadows: true,
                showsGlows: true,
                showsCentreHub: true,
                handsOpacity: handsOpacity
            )
            .privacySensitive(isPrivacy)
            .animation(
                secondsEnabled ? .linear(duration: max(1.0, tickSeconds)) : nil,
                value: secondDeg
            )
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Angles

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

private struct WWClockMonotonicAngles {
    let hour: Double
    let minute: Double
    let second: Double

    init(date: Date) {
        let tz = TimeZone.autoupdatingCurrent
        let local = date.timeIntervalSince1970 + TimeInterval(tz.secondsFromGMT(for: date))

        self.second = local * 6.0
        self.minute = local * (360.0 / 3600.0)
        self.hour = local * (360.0 / 43200.0)
    }
}
