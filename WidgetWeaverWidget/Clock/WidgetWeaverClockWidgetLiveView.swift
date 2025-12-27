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
    static let heartbeatOpacity: Double = 0.01
    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date

    @State private var lastTick: Int? = nil

    var body: some View {
        let now = Date()
        let base = (anchorDate <= now) ? anchorDate : now

        let tick = Int(floor(now.timeIntervalSince1970))
        let tickDate = Date(timeIntervalSince1970: Double(tick))
        let angles = WidgetWeaverClockAngles(now: tickDate)

        let shouldAnimate: Bool = {
            guard let lastTick else { return false }
            return (tick - lastTick) == 1
        }()

        return ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(angles.hourDegrees),
                minuteAngle: .degrees(angles.minuteDegrees),
                secondAngle: .degrees(angles.secondDegrees)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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
