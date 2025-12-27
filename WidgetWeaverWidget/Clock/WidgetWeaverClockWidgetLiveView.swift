//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    // Widgy-style: updates while visible, stops while off-screen, catches up instantly.
    // Lowering this reduces work but increases quantisation.
    static let minimumInterval: TimeInterval = 1.0 / 30.0

    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Kept for deterministic WidgetKit pre-rendering paths.
    /// The live driver uses TimelineView’s context date.
    let anchorDate: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: WWClockWidgetLiveTuning.minimumInterval, paused: false)) { context in
            let now = context.date
            let angles = WidgetWeaverClockAngles(now: now)

            ZStack(alignment: .bottomTrailing) {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(angles.hourDegrees),
                    minuteAngle: .degrees(angles.minuteDegrees),
                    secondAngle: .degrees(angles.secondDegrees)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                #if DEBUG
                if WWClockWidgetLiveTuning.showDebugOverlay {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(now, format: .dateTime.hour().minute().second())
                        Text(timerInterval: now...Date.distantFuture, countsDown: false)
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.70))
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

        // Monotonic degrees avoid wrap-backwards at boundaries.
        secondDegrees = local * 6.0
        minuteDegrees = local * (360.0 / 3600.0)
        hourDegrees = local * (360.0 / 43200.0)
    }
}
