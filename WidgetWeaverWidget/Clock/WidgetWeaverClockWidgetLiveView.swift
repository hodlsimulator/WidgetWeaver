//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    /// Lower values are smoother but cost more CPU if the host actually allows live updates.
    /// 1/20 ≈ 20fps is a decent compromise for a sweeping second hand.
    static let minimumInterval: TimeInterval = 1.0 / 20.0

    /// DEBUG overlay for validating whether the host is actually advancing time.
    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// Deterministic anchor provided by WidgetKit (timeline entry date).
    /// This is used as “t=0” so WidgetKit pre-rendering stays stable.
    let anchorDate: Date

    @State private var initialContextDate: Date?

    var body: some View {
        TimelineView(.animation(minimumInterval: WWClockWidgetLiveTuning.minimumInterval, paused: false)) { context in
            let base = initialContextDate ?? context.date

            // Capture the first context date asynchronously to avoid "Modifying state during view update".
            if initialContextDate == nil {
                DispatchQueue.main.async {
                    if initialContextDate == nil {
                        initialContextDate = context.date
                    }
                }
            }

            // Map the animation timeline onto the entry’s anchor date.
            let elapsed = context.date.timeIntervalSince(base)
            let effectiveNow = anchorDate.addingTimeInterval(elapsed)

            let angles = WidgetWeaverClockAngles(now: effectiveNow)

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
                        Text(effectiveNow, format: .dateTime.hour().minute().second())
                        Text("CLK TLV anim")
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
        .onChange(of: anchorDate) { _ in
            // Reset the anchor mapping if WidgetKit switches to a new entry.
            initialContextDate = nil
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
