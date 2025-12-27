//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetSweepTuning {
    // The render host can re-render late or skip entries. Large jumps are handled by snapping.
    static let contiguousToleranceSeconds: TimeInterval = 6.0

    // Degrees-of-error threshold for deciding whether a snap-to-start is required.
    // Second-hand velocity is 6 degrees/second.
    static let maxSnapErrorDegrees: Double = 36.0

    // Guardrails for the long-running linear sweep.
    static let minAnimatableDurationSeconds: TimeInterval = 5.0
    static let maxAnimatableDurationSeconds: TimeInterval = 60.0 * 60.0 * 2.0

    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let nextDate: Date

    @State private var hourDegrees: Double
    @State private var minuteDegrees: Double
    @State private var secondDegrees: Double

    @State private var started: Bool = false
    @State private var lastEntryDate: Date? = nil
    @State private var lastTargetDate: Date? = nil

    init(palette: WidgetWeaverClockPalette, entryDate: Date, nextDate: Date) {
        self.palette = palette
        self.entryDate = entryDate
        self.nextDate = nextDate

        let startAngles = WidgetWeaverClockMonotonicAngles(date: entryDate)
        _hourDegrees = State(initialValue: startAngles.hourDegrees)
        _minuteDegrees = State(initialValue: startAngles.minuteDegrees)
        _secondDegrees = State(initialValue: startAngles.secondDegrees)
    }

    var body: some View {
        let hourAngle = Angle.degrees(hourDegrees)
        let minuteAngle = Angle.degrees(minuteDegrees)
        let secondAngle = Angle.degrees(secondDegrees)

        ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: secondAngle
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            #if DEBUG
            if WWClockWidgetSweepTuning.showDebugOverlay {
                let duration = nextDate.timeIntervalSince(entryDate)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("entry: \(entryDate, format: .dateTime.hour().minute().second())")
                    Text("next:  \(nextDate, format: .dateTime.hour().minute().second())")
                    Text("dt: \(duration, format: .number.precision(.fractionLength(3)))")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.70))
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            #endif
        }
        .task(id: entryDate) {
            await MainActor.run {
                applyEntryAndStartSweep()
            }
        }
    }

    @MainActor
    private func applyEntryAndStartSweep() {
        let startAngles = WidgetWeaverClockMonotonicAngles(date: entryDate)
        let endAngles = WidgetWeaverClockMonotonicAngles(date: nextDate)

        let duration = nextDate.timeIntervalSince(entryDate)
        let animatableDuration = duration >= WWClockWidgetSweepTuning.minAnimatableDurationSeconds
            && duration <= WWClockWidgetSweepTuning.maxAnimatableDurationSeconds

        var shouldSnapToStart = !started

        if let lastEntryDate, let lastTargetDate {
            let expectedDt = lastTargetDate.timeIntervalSince(lastEntryDate)
            let actualDt = entryDate.timeIntervalSince(lastEntryDate)

            let contiguous = abs(actualDt - expectedDt) <= WWClockWidgetSweepTuning.contiguousToleranceSeconds

            if contiguous {
                let errH = abs(hourDegrees - startAngles.hourDegrees)
                let errM = abs(minuteDegrees - startAngles.minuteDegrees)
                let errS = abs(secondDegrees - startAngles.secondDegrees)
                let worst = max(errH, max(errM, errS))

                shouldSnapToStart = worst > WWClockWidgetSweepTuning.maxSnapErrorDegrees
            } else {
                shouldSnapToStart = true
            }
        }

        if shouldSnapToStart {
            withAnimation(.none) {
                hourDegrees = startAngles.hourDegrees
                minuteDegrees = startAngles.minuteDegrees
                secondDegrees = startAngles.secondDegrees
            }
        }

        guard animatableDuration else {
            started = true
            self.lastEntryDate = entryDate
            self.lastTargetDate = nextDate
            return
        }

        // Starting on the next runloop tick yields a stable “from” state for CoreAnimation.
        DispatchQueue.main.async {
            withAnimation(.linear(duration: duration)) {
                hourDegrees = endAngles.hourDegrees
                minuteDegrees = endAngles.minuteDegrees
                secondDegrees = endAngles.secondDegrees
            }
        }

        started = true
        lastEntryDate = entryDate
        lastTargetDate = nextDate
    }
}

private struct WidgetWeaverClockMonotonicAngles {
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
