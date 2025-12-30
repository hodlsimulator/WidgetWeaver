//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import SwiftUI
import WidgetKit
import Foundation

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        palette: WidgetWeaverClockPalette,
        entryDate: Date,
        minuteAnchor: Date,
        tickMode: WidgetWeaverClockTickMode
    ) {
        self.palette = palette
        self.entryDate = entryDate
        self.minuteAnchor = minuteAnchor
        self.tickMode = tickMode
    }

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let motion = computeMotion(
                tickMode: tickMode,
                redactionReasons: redactionReasons,
                isReduceMotion: reduceMotion
            )

            // Hour + minute are anchored to the entry’s minute anchor.
            // The widget only needs a fresh timeline entry once per minute.
            let baseAngles = WidgetWeaverClockBaseAngles(date: minuteAnchor)

            ZStack {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(baseAngles.hour),
                    minuteAngle: .degrees(baseAngles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    handsOpacity: motion.handsOpacity
                )
                .privacySensitive(motion.isPlaceholderRedacted || motion.isPrivacyRedacted)

                if motion.secondsEnabled {
                    WWClockSecondsDriver(
                        minuteAnchor: minuteAnchor,
                        palette: palette
                    )
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Seconds driver (ProgressView(timerInterval:) so it runs on the Home Screen)

private struct WWClockSecondsDriver: View {
    let minuteAnchor: Date
    let palette: WidgetWeaverClockPalette

    var body: some View {
        ProgressView(
            timerInterval: minuteAnchor...minuteAnchor.addingTimeInterval(60),
            countsDown: false
        )
        .labelsHidden()
        .progressViewStyle(WWClockSecondsProgressStyle(palette: palette))
        // Critical: make the driver fill the widget so the GeometryReader-based hand
        // draws at full clock size instead of the ProgressView’s tiny intrinsic size.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWClockSecondsProgressStyle: ProgressViewStyle {
    let palette: WidgetWeaverClockPalette

    func makeBody(configuration: Configuration) -> some View {
        let rawFraction = configuration.fractionCompleted ?? 0
        let fraction = min(max(rawFraction, 0), 1)

        // 0...1 over the minute -> 0...360° for the seconds hand.
        let secondAngle = Angle.degrees(fraction * 360.0)

        return WidgetWeaverClockSecondHandView(
            colour: palette.accent,
            width: 1.6,
            length: 0.90,
            angle: secondAngle,
            tipSide: 0.075,
            scale: 1.0
        )
    }
}

// MARK: - Motion gating

private struct WWClockMotion {
    let secondsEnabled: Bool
    let isPlaceholderRedacted: Bool
    let isPrivacyRedacted: Bool
    let isLowPowerMode: Bool
    let isReduceMotion: Bool
    let handsOpacity: Double
}

private func computeMotion(
    tickMode: WidgetWeaverClockTickMode,
    redactionReasons: RedactionReasons,
    isReduceMotion: Bool
) -> WWClockMotion {
    let isPlaceholder = redactionReasons.contains(.placeholder)
    let isPrivacy = redactionReasons.contains(.privacy)
    let lpm = ProcessInfo.processInfo.isLowPowerModeEnabled

    let wantsSweepSeconds = (tickMode == .secondsSweep)
    let secondsEnabled = wantsSweepSeconds && !isPlaceholder && !isPrivacy && !lpm && !isReduceMotion

    let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

    return WWClockMotion(
        secondsEnabled: secondsEnabled,
        isPlaceholderRedacted: isPlaceholder,
        isPrivacyRedacted: isPrivacy,
        isLowPowerMode: lpm,
        isReduceMotion: isReduceMotion,
        handsOpacity: handsOpacity
    )
}

// MARK: - Angle maths

private struct WidgetWeaverClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)

        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        self.minute = minuteInt * 6.0
        self.hour = (hour12 + minuteInt / 60.0) * 30.0
    }
}
