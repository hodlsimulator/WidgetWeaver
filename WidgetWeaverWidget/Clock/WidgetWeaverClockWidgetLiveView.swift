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
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let intervalStart: Date
    let intervalEnd: Date

    @State private var hourDegrees: Double
    @State private var minuteDegrees: Double
    @State private var secondDegrees: Double

    @State private var lastSignature: IntervalSignature

    init(palette: WidgetWeaverClockPalette, intervalStart: Date, intervalEnd: Date) {
        self.palette = palette
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd

        let initialAngles = WWClockMonotonicAngles(date: intervalStart)
        _hourDegrees = State(initialValue: initialAngles.hourDegrees)
        _minuteDegrees = State(initialValue: initialAngles.minuteDegrees)
        _secondDegrees = State(initialValue: initialAngles.secondDegrees)

        _lastSignature = State(initialValue: IntervalSignature(start: intervalStart, end: intervalEnd))
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
            startOrResyncAnimationIfNeeded()
        }
        .onChange(of: intervalStart) { _, _ in
            startOrResyncAnimationIfNeeded()
        }
        .onChange(of: intervalEnd) { _, _ in
            startOrResyncAnimationIfNeeded()
        }
    }

    private func startOrResyncAnimationIfNeeded() {
        let signature = IntervalSignature(start: intervalStart, end: intervalEnd)
        if signature != lastSignature {
            lastSignature = signature
        }

        guard intervalEnd > intervalStart else {
            let snap = WWClockMonotonicAngles(date: intervalStart)
            withAnimation(.none) {
                hourDegrees = snap.hourDegrees
                minuteDegrees = snap.minuteDegrees
                secondDegrees = snap.secondDegrees
            }
            return
        }

        let now = Date()

        if now < intervalStart {
            let snap = WWClockMonotonicAngles(date: intervalStart)
            withAnimation(.none) {
                hourDegrees = snap.hourDegrees
                minuteDegrees = snap.minuteDegrees
                secondDegrees = snap.secondDegrees
            }
            return
        }

        if now >= intervalEnd {
            let snap = WWClockMonotonicAngles(date: intervalEnd)
            withAnimation(.none) {
                hourDegrees = snap.hourDegrees
                minuteDegrees = snap.minuteDegrees
                secondDegrees = snap.secondDegrees
            }
            return
        }

        let remaining = intervalEnd.timeIntervalSince(now)
        let duration = max(WWClockWidgetLiveTuning.minimumAnimationSeconds, remaining)

        let fromAngles = WWClockMonotonicAngles(date: now)
        let toAngles = WWClockMonotonicAngles(date: intervalEnd)

        withAnimation(.none) {
            hourDegrees = fromAngles.hourDegrees
            minuteDegrees = fromAngles.minuteDegrees
            secondDegrees = fromAngles.secondDegrees
        }

        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration)) {
                hourDegrees = toAngles.hourDegrees
                minuteDegrees = toAngles.minuteDegrees
                secondDegrees = toAngles.secondDegrees
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
