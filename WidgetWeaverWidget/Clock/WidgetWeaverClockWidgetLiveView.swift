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

    /// Used as a stable phase anchor for `.periodic` scheduling.
    let anchorDate: Date

    @State private var lastTick: Int? = nil
    @State private var lastSecondDegrees: Double? = nil

    var body: some View {
        TimelineView(.periodic(from: anchorDate, by: 1.0)) { context in
            let now = context.date
            let tick = Int(now.timeIntervalSince1970)

            let angles = WidgetWeaverClockAngles(now: now)

            let shouldAnimate: Bool = {
                guard let lastTick, let lastSecondDegrees else { return false }
                guard tick == lastTick + 1 else { return false }

                // Expected delta is ~6 degrees per second.
                // Large deltas usually mean the widget was paused off-screen or a timezone/DST jump occurred.
                let delta = abs(angles.secondDegrees - lastSecondDegrees)
                return delta < 20.0
            }()

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
                        Text("LIVE .periodic(1s)")
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary.opacity(0.55))
                    .padding(6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                #endif
            }
            .transaction { transaction in
                transaction.animation = shouldAnimate ? .linear(duration: 1.0) : nil
            }
            .onAppear {
                if lastTick == nil {
                    lastTick = tick
                    lastSecondDegrees = angles.secondDegrees
                }
            }
            .onChange(of: tick) { _, newTick in
                lastTick = newTick

                // Recompute at the quantised second boundary to keep the comparison stable.
                let d = Date(timeIntervalSince1970: Double(newTick))
                let a = WidgetWeaverClockAngles(now: d)
                lastSecondDegrees = a.secondDegrees
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
