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

    var body: some View {
        TimelineView(.animation) { context in
            let angles = WWClockMonotonicAngles(date: context.date)

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
        }
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
