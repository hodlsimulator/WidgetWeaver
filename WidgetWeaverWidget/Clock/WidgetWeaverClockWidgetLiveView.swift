//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetAnimationLimits {
    // WidgetKit clamps animations to ~2 seconds max.
    // Keeping this explicit avoids “looks fine in preview, frozen on Home Screen”.
    static let maxDurationSeconds: TimeInterval = 2.0
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let intervalStart: Date
    let intervalEnd: Date

    private var stepSeconds: TimeInterval {
        let dt = intervalEnd.timeIntervalSince(intervalStart)
        if dt.isFinite == false { return 2.0 }
        return max(0.05, min(WWClockWidgetAnimationLimits.maxDurationSeconds, dt))
    }

    var body: some View {
        let angles = WWClockMonotonicAngles(date: intervalStart)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: .degrees(angles.hourDegrees),
            minuteAngle: .degrees(angles.minuteDegrees),
            secondAngle: .degrees(angles.secondDegrees),
            showsSecondHand: true,
            handsOpacity: 1.0
        )
        // The only “driver” is timeline entry changes.
        // When intervalStart changes, angles change, and WidgetKit animates the transition.
        .animation(.linear(duration: stepSeconds), value: angles.secondDegrees)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
