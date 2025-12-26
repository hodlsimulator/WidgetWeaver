//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    // Home Screen widget hosts often coalesce “1 second” schedules.
    // A 2-second cadence tends to produce continuous motion without long stalls.
    static let tickSeconds: TimeInterval = 2.0

    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Deterministic anchor provided by WidgetKit (timeline entry date).
    /// Used as the periodic schedule anchor so WidgetKit pre-rendering stays stable.
    let anchorDate: Date

    var body: some View {
        TimelineView(.periodic(from: anchorDate, by: WWClockWidgetLiveTuning.tickSeconds)) { context in
            let angles = WidgetWeaverClockAngles(now: context.date)

            ZStack(alignment: .bottomTrailing) {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(angles.hourDegrees),
                    minuteAngle: .degrees(angles.minuteDegrees),
                    secondAngle: .degrees(angles.secondDegrees)
                )
                .animation(.linear(duration: WWClockWidgetLiveTuning.tickSeconds), value: angles.secondDegrees)

                #if DEBUG
                if WWClockWidgetLiveTuning.showDebugOverlay {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.date, format: .dateTime.hour().minute().second())
                        Text("CLK TLV")
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

        // Monotonic degrees avoid backwards interpolation at wrap boundaries.
        secondDegrees = local * 6.0
        minuteDegrees = local * (360.0 / 3600.0)
        hourDegrees = local * (360.0 / 43200.0)
    }
}
