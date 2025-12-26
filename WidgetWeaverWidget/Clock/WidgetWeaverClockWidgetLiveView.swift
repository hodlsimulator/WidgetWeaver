//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    static let tickSeconds: TimeInterval = 1.0
    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Provided for deterministic WidgetKit pre-rendering; the live schedule re-syncs on appearance.
    let anchorDate: Date

    @State private var scheduleStart: Date

    init(palette: WidgetWeaverClockPalette, anchorDate: Date) {
        self.palette = palette
        self.anchorDate = anchorDate
        _scheduleStart = State(initialValue: Date())
    }

    var body: some View {
        TimelineView(.periodic(from: scheduleStart, by: WWClockWidgetLiveTuning.tickSeconds)) { context in
            let now = context.date
            let angles = WidgetWeaverClockAngles(now: now)

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
                        Text(now, format: .dateTime.hour().minute().second())
                        Text("LIVE .periodic(1s)")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.60))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                #endif
            }
        }
        .onAppear {
            let now = Date()
            if abs(now.timeIntervalSince(scheduleStart)) > 0.5 {
                scheduleStart = now
            }
        }
        .task {
            let now = Date()
            if abs(now.timeIntervalSince(scheduleStart)) > 0.5 {
                scheduleStart = now
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

        // Monotonic degrees so interpolation never runs backwards at wrap boundaries.
        secondDegrees = local * 6.0
        minuteDegrees = local * (360.0 / 3600.0)
        hourDegrees = local * (360.0 / 43200.0)
    }
}
