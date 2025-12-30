//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import SwiftUI
import WidgetKit
import UIKit
import Foundation

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode

    @Environment(\.redactionReasons) private var redactionReasons

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
            let isPlaceholder = redactionReasons.contains(.placeholder)
            let isPrivacy = redactionReasons.contains(.privacy)
            let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            let isReduceMotion = UIAccessibility.isReduceMotionEnabled

            // Seconds are only enabled for the sweep mode and when the system is not redacting.
            let secondsEnabled =
                (tickMode == .secondsSweep)
                && !isPlaceholder
                && !isPrivacy
                && !isLowPowerMode
                && !isReduceMotion

            let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

            // Base clock: draw hour + minute using the timeline’s minute anchor (cheap; updates once per minute).
            let baseAngles = WWClockBaseAngles(date: minuteAnchor)

            ZStack {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(baseAngles.hour),
                    minuteAngle: .degrees(baseAngles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)

                // Seconds overlay: driven by TimelineView, rendered as a normal needle.
                if secondsEnabled {
                    WWClockSecondsSweepOverlay(
                        startOfMinute: minuteAnchor,
                        colour: palette.accent
                    )
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Seconds sweep overlay

private struct WWClockSecondsSweepOverlay: View {
    let startOfMinute: Date
    let colour: Color

    var body: some View {
        // ProgressView(timerInterval:) does not provide a usable fractionCompleted to custom ProgressViewStyle
        // implementations, so TimelineView is used to compute the angle directly from time.
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startOfMinute)
            let clamped = max(0.0, min(elapsed, 60.0))

            // 0...60 seconds -> 0...360 degrees (allowing 360 avoids a backwards wrap at the top).
            let angle = Angle.degrees((clamped / 60.0) * 360.0)

            WWClockSecondHandNeedleView(
                angle: angle,
                colour: colour
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Needle drawing

private struct WWClockSecondHandNeedleView: View {
    let angle: Angle
    let colour: Color

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)

            // Tuned by eye for your watch-face proportions.
            let handLength = side * 0.46
            let handWidth = max(1.0, side * 0.0075)

            // Slightly extend past the hub so the join looks clean under the existing center cap.
            let hubOverlap = handWidth * 1.5

            ZStack {
                Capsule(style: .continuous)
                    .fill(colour)
                    .frame(width: handWidth, height: handLength + hubOverlap)
                    .offset(y: -(handLength / 2.0))
                    .rotationEffect(angle)
                    .shadow(
                        color: Color.black.opacity(0.22),
                        radius: max(0.5, handWidth * 0.35),
                        x: 0,
                        y: max(0.25, handWidth * 0.2)
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Base angles

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)

        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        // Degrees with 0 at 12 o’clock.
        self.minute = minuteInt * 6.0
        self.hour = (hour12 + (minuteInt / 60.0)) * 30.0
    }
}
