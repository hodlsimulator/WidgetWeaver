//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Exists to keep your call sites stable; not required for `.animation` schedule.
    let anchorDate: Date

    var body: some View {
        TimelineView(.animation) { context in
            let now = context.date
            let angles = WidgetWeaverClockAngles(now: now)

            ZStack(alignment: .bottomTrailing) {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(angles.hourDegrees),
                    minuteAngle: .degrees(angles.minuteDegrees),
                    secondAngle: .degrees(angles.secondDegrees)
                )

                #if DEBUG
                if WWClockWidgetLiveTuning.showDebugOverlay {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(now, format: .dateTime.hour().minute().second())
                        Text("LIVE .animation")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.55))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                #endif
            }
        }
    }
}

private struct WidgetWeaverClockAngles {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(now: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: now))
        let local = now.timeIntervalSince1970 + tz

        // Monotonic degrees keep interpolation direction stable across wrap boundaries.
        secondDegrees = local * 6.0
        minuteDegrees = local * (360.0 / 3600.0)
        hourDegrees = local * (360.0 / 43200.0)
    }
}
