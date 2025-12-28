//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    private static let tickSeconds: TimeInterval = 2.0

    var body: some View {
        let now = WidgetWeaverRenderClock.now
        let angles = WWClockMonotonicAngles(date: now)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: .degrees(angles.hourDegrees),
            minuteAngle: .degrees(angles.minuteDegrees),
            secondAngle: .degrees(angles.secondDegrees),
            showsSecondHand: true,
            handsOpacity: 1.0
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Animate between WidgetKit timeline entries.
        .animation(.linear(duration: Self.tickSeconds), value: now.timeIntervalSinceReferenceDate)
    }
}

private struct WWClockMonotonicAngles {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(date: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let localSeconds = date.timeIntervalSince1970 + tz

        secondDegrees = localSeconds * 6.0
        minuteDegrees = localSeconds * (360.0 / 3600.0)
        hourDegrees = localSeconds * (360.0 / 43200.0)
    }
}
