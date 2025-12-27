//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    // Must match the timeline step used by WidgetWeaverHomeScreenClockProvider.
    static let tickSeconds: TimeInterval = 2.0

    // Only animate when successive timeline entries arrive at the expected cadence.
    // If WidgetKit skips a beat (budget/throttling) it's better to snap than to
    // animate a huge jump.
    static let stepTolerance: TimeInterval = 0.35

    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date

    @State private var lastRenderNow: Date? = nil

    var body: some View {
        // NOTE:
        // Do not use `Date()` here expecting it to tick. Home Screen widgets are
        // generally static until the next timeline entry.
        //
        // WidgetWeaverRenderClock.withNow(entry.date) installs the timeline entry date
        // for the duration of the render pass, so `WidgetWeaverRenderClock.now` is
        // stable and advances exactly as the timeline advances.
        let now = WidgetWeaverRenderClock.now
        let angles = WidgetWeaverClockAngles(now: now)

        let shouldAnimate: Bool = {
            guard let lastRenderNow else { return false }
            let dt = now.timeIntervalSince(lastRenderNow)
            return abs(dt - WWClockWidgetLiveTuning.tickSeconds) <= WWClockWidgetLiveTuning.stepTolerance
        }()

        return ZStack(alignment: .bottomTrailing) {
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
                    Text("Δt: \(lastRenderNow.map { now.timeIntervalSince($0) } ?? -1)")
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
            transaction.animation = shouldAnimate ? .linear(duration: WWClockWidgetLiveTuning.tickSeconds) : nil
        }
        .onAppear {
            if lastRenderNow == nil {
                lastRenderNow = now
            }
        }
        .onChange(of: now) { _, newNow in
            lastRenderNow = newNow
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
