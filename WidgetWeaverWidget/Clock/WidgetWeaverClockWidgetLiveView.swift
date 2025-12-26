//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    /// Must match the Home Screen clock widget timeline step.
    /// In WidgetWeaverHomeScreenClockWidget.swift this is 60 * 15.
    static let entryLifetimeSeconds: TimeInterval = 60.0 * 15.0

    static let showDebugOverlay: Bool = false
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// WidgetKit timeline entry date (deterministic anchor).
    let anchorDate: Date

    var body: some View {
        let interval = anchorDate...anchorDate.addingTimeInterval(WWClockWidgetLiveTuning.entryLifetimeSeconds)

        ProgressView(timerInterval: interval, countsDown: false)
            .progressViewStyle(
                WWClockWidgetLiveProgressStyle(
                    palette: palette,
                    anchorDate: anchorDate,
                    entryLifetimeSeconds: WWClockWidgetLiveTuning.entryLifetimeSeconds
                )
            )
            .accessibilityHidden(true)
    }
}

private struct WWClockWidgetLiveProgressStyle: ProgressViewStyle {
    let palette: WidgetWeaverClockPalette
    let anchorDate: Date
    let entryLifetimeSeconds: TimeInterval

    func makeBody(configuration: Configuration) -> some View {
        let rawFraction = configuration.fractionCompleted ?? 0.0
        let fraction = min(1.0, max(0.0, rawFraction))

        let now = anchorDate.addingTimeInterval(fraction * entryLifetimeSeconds)
        let degrees = WWClockHandDegrees(date: now)

        return ZStack(alignment: .bottomTrailing) {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(degrees.hourDegrees),
                minuteAngle: .degrees(degrees.minuteDegrees),
                secondAngle: .degrees(degrees.secondDegrees)
            )

            #if DEBUG
            if WWClockWidgetLiveTuning.showDebugOverlay {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(now, format: .dateTime.hour().minute().second())
                    Text(String(format: "f=%.4f", fraction))
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.70))
                .padding(6)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            #endif
        }
        .accessibilityHidden(true)
    }
}

private struct WWClockHandDegrees: Equatable {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(date: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let local = date.timeIntervalSince1970 + tz

        // Monotonic degrees avoid backwards interpolation at wrap boundaries.
        secondDegrees = local * 6.0
        minuteDegrees = local * (360.0 / 3600.0)
        hourDegrees = local * (360.0 / 43200.0)
    }
}
