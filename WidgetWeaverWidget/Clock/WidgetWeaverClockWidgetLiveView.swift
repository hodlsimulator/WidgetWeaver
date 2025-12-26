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

    // Keep this off unless investigating on-device behaviour.
    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// WidgetKit timeline entry date (stable anchor).
    let anchorDate: Date

    @State private var lastTick: Int? = nil

    var body: some View {
        let now = Date()
        let tick = Int(floor(now.timeIntervalSince1970))

        let tickDate = Date(timeIntervalSince1970: Double(tick))
        let angles = WidgetWeaverClockAngles(now: tickDate)

        let shouldAnimate: Bool = {
            guard let lastTick else { return false }
            return (tick - lastTick) == 1
        }()

        // System-updating time text.
        //
        // The intent is Widgy-like behaviour: updates while visible, pauses off-screen, catches up on return.
        // The actual clock drawing is attached to this dynamic view so it participates in the same update passes.
        let base = (anchorDate <= now) ? anchorDate : now
        return Text(timerInterval: base...Date.distantFuture, countsDown: false)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1, alignment: .topLeading)
            .clipped()
            .overlay {
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
                            Text("tick: \(tick)")
                            Text("last: \(lastTick.map(String.init) ?? "nil")")
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
                    if lastTick == nil {
                        lastTick = tick
                    }
                }
                .onChange(of: tick) { _, newTick in
                    lastTick = newTick
                }
            }
            .accessibilityHidden(true)
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
