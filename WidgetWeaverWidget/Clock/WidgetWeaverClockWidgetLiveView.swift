//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    // This is only a requested schedule; Home Screen can coalesce/throttle.
    static let scheduleStepSeconds: TimeInterval = 2.0

    // Clamp animation duration so it never becomes a tiny blip or an excessively long sweep.
    static let minAnimSeconds: TimeInterval = 0.25
    static let maxAnimSeconds: TimeInterval = 90.0

    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Timeline entry date from WidgetKit.
    /// Used as a stable anchor for the periodic schedule.
    let anchorDate: Date

    @State private var lastContextDate: Date?

    var body: some View {
        SwiftUI.TimelineView(
            PeriodicTimelineSchedule(from: anchorDate, by: WWClockWidgetLiveTuning.scheduleStepSeconds)
        ) { context in
            let now = context.date

            let dtRaw: TimeInterval = {
                guard let last = lastContextDate else { return WWClockWidgetLiveTuning.scheduleStepSeconds }
                return now.timeIntervalSince(last)
            }()

            let animSeconds = max(
                WWClockWidgetLiveTuning.minAnimSeconds,
                min(WWClockWidgetLiveTuning.maxAnimSeconds, dtRaw)
            )

            let angles = WidgetWeaverClockAngles(now: now)

            ZStack(alignment: .bottomTrailing) {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(angles.hourDegrees),
                    minuteAngle: .degrees(angles.minuteDegrees),
                    secondAngle: .degrees(angles.secondDegrees)
                )
                // Animate across whatever delta the host actually delivered.
                .animation(.linear(duration: animSeconds), value: angles.secondDegrees)

                #if DEBUG
                if WWClockWidgetLiveTuning.showDebugOverlay {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(now, format: .dateTime.hour().minute().second())
                        Text(String(format: "dt=%.2fs", dtRaw))
                        Text(String(format: "anim=%.2fs", animSeconds))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.55))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                #endif
            }
            .onAppear {
                DispatchQueue.main.async {
                    lastContextDate = now
                }
            }
            .onChange(of: now) { _, newNow in
                DispatchQueue.main.async {
                    lastContextDate = newNow
                }
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
