//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    // The Home Screen widget host may coalesce “heartbeat” updates.
    // The code treats any small-ish interval as animatable and snaps on large gaps.
    static let minAnimatableBeatSeconds: TimeInterval = 0.5
    static let maxAnimatableBeatSeconds: TimeInterval = 3.0

    // Kept non-zero so the view stays in the hierarchy and drives invalidations.
    static let heartbeatOpacity: Double = 0.01

    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date

    @State private var lastBeatDate: Date? = nil
    @State private var lastTick: Int? = nil

    var body: some View {
        let now = Date()
        let base = (anchorDate <= now) ? anchorDate : now

        // This tick value is only used to detect a “new second” render pass.
        let tick = Int(floor(now.timeIntervalSince1970))

        // Observed time between heartbeat-driven view evaluations.
        let observedBeat: TimeInterval = {
            guard let lastBeatDate else { return 0 }
            return now.timeIntervalSince(lastBeatDate)
        }()

        let isAnimatableBeat: Bool = {
            guard lastBeatDate != nil else { return false }
            return observedBeat >= WWClockWidgetLiveTuning.minAnimatableBeatSeconds
                && observedBeat <= WWClockWidgetLiveTuning.maxAnimatableBeatSeconds
        }()

        // Animation duration uses the observed beat so motion stays continuous
        // even if iOS only invalidates every ~2 seconds.
        let duration: TimeInterval = isAnimatableBeat ? observedBeat : 0

        // Look ahead by the same duration so the hand reaches the correct position
        // when the animation ends (instead of lagging behind real time).
        let targetDate: Date = isAnimatableBeat ? now.addingTimeInterval(duration) : now
        let angles = WidgetWeaverClockAngles(now: targetDate)

        return ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(angles.hourDegrees),
                minuteAngle: .degrees(angles.minuteDegrees),
                secondAngle: .degrees(angles.secondDegrees)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Heartbeat: time-aware Text that updates without WidgetKit timeline reloads.
            Text(timerInterval: base...Date.distantFuture, countsDown: false)
                .font(.system(size: 1, weight: .regular, design: .monospaced))
                .foregroundStyle(Color.white.opacity(WWClockWidgetLiveTuning.heartbeatOpacity))
                .frame(width: 1, height: 1, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            #if DEBUG
            if WWClockWidgetLiveTuning.showDebugOverlay {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(now, format: .dateTime.hour().minute().second())
                    Text("tick: \(tick)")
                    Text("beat: \(String(format: "%.2f", observedBeat))s")
                    Text("lastTick: \(lastTick.map(String.init) ?? "nil")")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.70))
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            #endif
        }
        .transaction { transaction in
            transaction.animation = isAnimatableBeat ? .linear(duration: duration) : nil
        }
        .onAppear {
            if lastTick == nil { lastTick = tick }
            if lastBeatDate == nil { lastBeatDate = now }
        }
        .onChange(of: tick) { _, newTick in
            lastTick = newTick
            lastBeatDate = now
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
