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
        let _ = (tickMode, tickSeconds)

        let isPlaceholder = redactionReasons.contains(.placeholder)
        let isPrivacy = redactionReasons.contains(.privacy)
        let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

        // Widgets are rendered as snapshots. Anything “live” must be represented via timeline entries.
        // This view therefore renders purely from entryDate.
        WidgetWeaverRenderClock.withNow(entryDate) {
            let angles = WWClockAngles(date: entryDate)

            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(angles.hour),
                minuteAngle: .degrees(angles.minute),
                secondAngle: .degrees(angles.second),
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

        self.second = sec * 6.0
        self.minute = (minuteInt + sec / 60.0) * 6.0
        self.hour = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
    }
}
