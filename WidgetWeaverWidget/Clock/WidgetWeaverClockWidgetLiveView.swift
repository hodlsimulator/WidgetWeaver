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

    @State private var animationGeneration: Int = 0

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
        animationGeneration &+= 1
        let gen = animationGeneration

        guard intervalEnd > intervalStart else {
            let snap = WWClockMonotonicAngles(date: intervalStart)
            withAnimation(.none) {
                hourDegrees = snap.hourDegrees
                minuteDegrees = snap.minuteDegrees
                secondDegrees = snap.secondDegrees
            }
            return
        }

        runOneSecondSteppedSweep(generation: gen)
    }

    private func runOneSecondSteppedSweep(generation gen: Int) {
        guard gen == animationGeneration else { return }

        let wallNow = Date()
        let clampedNow = min(max(wallNow, intervalStart), intervalEnd)

        guard clampedNow < intervalEnd else {
            let snap = WWClockMonotonicAngles(date: intervalEnd)
            withAnimation(.none) {
                hourDegrees = snap.hourDegrees
                minuteDegrees = snap.minuteDegrees
                secondDegrees = snap.secondDegrees
            }
            return
        }

        let nextWholeSecond = Date(timeIntervalSince1970: ceil(clampedNow.timeIntervalSince1970))
        let target = min(max(nextWholeSecond, clampedNow.addingTimeInterval(WWClockWidgetLiveTuning.minimumAnimationSeconds)), intervalEnd)

        let duration = max(WWClockWidgetLiveTuning.minimumAnimationSeconds, target.timeIntervalSince(clampedNow))

        let fromAngles = WWClockMonotonicAngles(date: clampedNow)
        let toAngles = WWClockMonotonicAngles(date: target)

        withAnimation(.none) {
            hourDegrees = fromAngles.hourDegrees
            minuteDegrees = fromAngles.minuteDegrees
            secondDegrees = fromAngles.secondDegrees
        }

        DispatchQueue.main.async {
            guard gen == animationGeneration else { return }

            withAnimation(.linear(duration: duration)) {
                hourDegrees = toAngles.hourDegrees
                minuteDegrees = toAngles.minuteDegrees
                secondDegrees = toAngles.secondDegrees
            }

            let delay = max(WWClockWidgetLiveTuning.minimumAnimationSeconds, duration)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                runOneSecondSteppedSweep(generation: gen)
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
