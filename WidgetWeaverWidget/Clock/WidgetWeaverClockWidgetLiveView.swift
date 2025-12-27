//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    // Target cadence for the in-view heartbeat.
    // iOS may still coalesce updates (e.g. ~2s) depending on system conditions.
    static let heartbeatSeconds: TimeInterval = 1.0

    // Only animate for “small-ish” gaps; snap for large gaps.
    static let minAnimatableBeatSeconds: TimeInterval = 0.5
    static let maxAnimatableBeatSeconds: TimeInterval = 3.5

    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date

    @State private var targetDate: Date = Date()
    @State private var started: Bool = false

    var body: some View {
        TimelineView(.periodic(from: anchorDate, by: WWClockWidgetLiveTuning.heartbeatSeconds)) { context in
            let now = context.date
            let angles = WidgetWeaverClockAngles(now: targetDate)

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
                        Text("target: \(targetDate, format: .dateTime.hour().minute().second())")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.70))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                #endif
            }
            .onAppear {
                if !started {
                    started = true
                    targetDate = now
                }
            }
            .onChange(of: now) { oldNow, newNow in
                let dt = newNow.timeIntervalSince(oldNow)
                let animatable = dt >= WWClockWidgetLiveTuning.minAnimatableBeatSeconds
                    && dt <= WWClockWidgetLiveTuning.maxAnimatableBeatSeconds

                if animatable {
                    // Snap to the current tick baseline with no animation, then
                    // animate ahead by the observed beat interval.
                    withAnimation(.none) {
                        targetDate = newNow
                    }

                    DispatchQueue.main.async {
                        withAnimation(.linear(duration: dt)) {
                            targetDate = newNow.addingTimeInterval(dt)
                        }
                    }
                } else {
                    withAnimation(.none) {
                        targetDate = newNow
                    }
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

        secondDegrees = local * 6.0
        minuteDegrees = local * (360.0 / 3600.0)
        hourDegrees = local * (360.0 / 43200.0)
    }
}
