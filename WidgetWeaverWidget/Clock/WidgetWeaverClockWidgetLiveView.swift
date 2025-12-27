//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    // Lower-frequency heartbeat to reduce load while still sweeping smoothly.
    // The second hand crosses every second mark via linear interpolation.
    static let heartbeatSeconds: TimeInterval = 15.0

    // Only animate for reasonable gaps; snap for large gaps.
    static let minAnimatableBeatSeconds: TimeInterval = 0.5
    static let maxAnimatableBeatSeconds: TimeInterval = 45.0

    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date

    private let scheduleAnchor: Date

    @State private var targetDate: Date
    @State private var started: Bool = false

    init(palette: WidgetWeaverClockPalette, anchorDate: Date) {
        self.palette = palette
        self.anchorDate = anchorDate

        let now = Date()
        self.scheduleAnchor = (anchorDate > now) ? now : anchorDate

        _targetDate = State(initialValue: anchorDate)
    }

    var body: some View {
        TimelineView(.periodic(from: scheduleAnchor, by: WWClockWidgetLiveTuning.heartbeatSeconds)) { context in
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
                    primeSweep(from: now, duration: WWClockWidgetLiveTuning.heartbeatSeconds)
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

    private func primeSweep(from now: Date, duration: TimeInterval) {
        withAnimation(.none) {
            targetDate = now
        }

        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration)) {
                targetDate = now.addingTimeInterval(duration)
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

        hourDegrees = local * (360.0 / 43200.0)
        minuteDegrees = local * (360.0 / 3600.0)
        secondDegrees = local * 6.0
    }
}
