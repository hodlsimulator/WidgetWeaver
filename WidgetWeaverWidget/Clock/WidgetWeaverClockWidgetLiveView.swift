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

        let secondsEnabled =
            (tickMode == .secondsSweep)
            && !isPlaceholder
            && !isPrivacy

        let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0
        let interval = Self.updateInterval(tickMode: tickMode, tickSeconds: tickSeconds)

        TimelineView(.periodic(from: entryDate, by: interval)) { context in
            WidgetWeaverRenderClock.withNow(context.date) {
                let angles = WWClockMonotonicAngles(date: context.date)

                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(angles.hour),
                    minuteAngle: .degrees(angles.minute),
                    secondAngle: .degrees(angles.second),
                    showsSecondHand: secondsEnabled,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: true,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)
                .widgetURL(URL(string: "widgetweaver://clock"))
                .animation(secondsEnabled ? .linear(duration: interval) : nil, value: angles.second)
            }
        }
    }

    private static func updateInterval(
        tickMode: WidgetWeaverClockTickMode,
        tickSeconds: TimeInterval
    ) -> TimeInterval {
        switch tickMode {
        case .minuteOnly:
            return 60.0
        case .secondsSweep:
            let clamped = max(1.0, min(60.0, tickSeconds))
            return clamped
        }
    }
}

// MARK: - Monotonic angles

private struct WWClockMonotonicAngles {
    let hour: Double
    let minute: Double
    let second: Double

    init(date: Date) {
        let tzOffset = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let local = date.timeIntervalSince1970 + tzOffset

        self.second = local * 6.0
        self.minute = local * (360.0 / 3600.0)
        self.hour = local * (360.0 / 43200.0)
    }
}
