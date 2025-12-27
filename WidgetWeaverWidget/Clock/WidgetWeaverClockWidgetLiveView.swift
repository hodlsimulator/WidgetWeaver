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
    static let minimumAnimationSeconds: TimeInterval = 0.05

    // Snap only when drift is obvious. These are screen-angle thresholds (mod 360).
    // Second hand: 6° per second. Minute hand: 0.1° per second. Hour hand: ~0.00833° per second.
    static let snapSecondDegrees: Double = 9.0    // ~1.5s
    static let snapMinuteDegrees: Double = 2.0    // ~20s
    static let snapHourDegrees: Double = 0.75     // ~90min
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let intervalStart: Date
    let intervalEnd: Date

    @State private var hourDegrees: Double
    @State private var minuteDegrees: Double
    @State private var secondDegrees: Double

    init(palette: WidgetWeaverClockPalette, intervalStart: Date, intervalEnd: Date) {
        self.palette = palette
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd

        let initialAngles = WWClockMonotonicAngles(date: intervalStart)
        _hourDegrees = State(initialValue: initialAngles.hourDegrees)
        _minuteDegrees = State(initialValue: initialAngles.minuteDegrees)
        _secondDegrees = State(initialValue: initialAngles.secondDegrees)
    }

    private var signature: IntervalSignature {
        IntervalSignature(start: intervalStart, end: intervalEnd)
    }

    private var segmentSeconds: TimeInterval {
        let dt = intervalEnd.timeIntervalSince(intervalStart)
        if dt.isFinite && dt > 0 { return dt }
        return 2.0
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(hourDegrees),
                minuteAngle: .degrees(minuteDegrees),
                secondAngle: .degrees(secondDegrees)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if DEBUG
            if WWClockWidgetLiveTuning.showDebugOverlay {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Date(), format: .dateTime.hour().minute().second())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary.opacity(0.75))

                    Text("start: \(intervalStart, format: .dateTime.hour().minute().second())")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary.opacity(0.60))

                    Text("end:   \(intervalEnd, format: .dateTime.hour().minute().second())")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary.opacity(0.60))
                }
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            #endif
        }
        .onAppear {
            startOrResyncAnimation()
        }
        .onChange(of: signature) { _, _ in
            startOrResyncAnimation()
        }
    }

    private func startOrResyncAnimation() {
        let step = max(WWClockWidgetLiveTuning.minimumAnimationSeconds, segmentSeconds)

        // Treat each new timeline entry as a trigger, but base the sweep on wall time.
        // This keeps the clock moving even if WidgetKit delivers entries slightly late.
        let now = Date()
        let end = now.addingTimeInterval(step)

        let expectedNow = WWClockMonotonicAngles(date: now)
        let target = WWClockMonotonicAngles(date: end)

        let driftSecond = abs(WWClockAngleMath.shortestDeltaDegrees(current: secondDegrees, target: expectedNow.secondDegrees))
        let driftMinute = abs(WWClockAngleMath.shortestDeltaDegrees(current: minuteDegrees, target: expectedNow.minuteDegrees))
        let driftHour = abs(WWClockAngleMath.shortestDeltaDegrees(current: hourDegrees, target: expectedNow.hourDegrees))

        let shouldSnap =
            driftSecond > WWClockWidgetLiveTuning.snapSecondDegrees ||
            driftMinute > WWClockWidgetLiveTuning.snapMinuteDegrees ||
            driftHour > WWClockWidgetLiveTuning.snapHourDegrees

        if shouldSnap {
            withAnimation(.none) {
                hourDegrees = expectedNow.hourDegrees
                minuteDegrees = expectedNow.minuteDegrees
                secondDegrees = expectedNow.secondDegrees
            }
        }

        DispatchQueue.main.async {
            withAnimation(.linear(duration: step)) {
                hourDegrees = target.hourDegrees
                minuteDegrees = target.minuteDegrees
                secondDegrees = target.secondDegrees
            }
        }
    }
}

private struct IntervalSignature: Equatable {
    let start: Date
    let end: Date
}

private struct WWClockMonotonicAngles {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(date: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let localSeconds = date.timeIntervalSince1970 + tz

        secondDegrees = localSeconds * 6.0
        minuteDegrees = localSeconds * (360.0 / 3600.0)
        hourDegrees = localSeconds * (360.0 / 43200.0)
    }
}

private enum WWClockAngleMath {
    static func shortestDeltaDegrees(current: Double, target: Double) -> Double {
        var d = (target - current).truncatingRemainder(dividingBy: 360.0)
        if d >= 180.0 { d -= 360.0 }
        if d < -180.0 { d += 360.0 }
        return d
    }
}
