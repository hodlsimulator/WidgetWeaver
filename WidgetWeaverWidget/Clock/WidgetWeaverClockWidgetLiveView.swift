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

            let secondsEnabled =
                (tickMode == .secondsSweep)
                && !isPlaceholder
                && !isPrivacy
                && !isLowPowerMode
                && !isReduceMotion

            let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

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

                if secondsEnabled {
                    WWClockSecondHandHostDrivenOverlay(
                        palette: palette,
                        startOfMinute: minuteAnchor,
                        handsOpacity: handsOpacity
                    )
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Host-driven seconds overlay

private struct WWClockSecondHandHostDrivenOverlay: View {
    let palette: WidgetWeaverClockPalette
    let startOfMinute: Date
    let handsOpacity: Double

    var body: some View {
        let endOfMinute = startOfMinute.addingTimeInterval(60.0)

        // The ProgressView itself is the host-driven “tick source”.
        // The second hand angle is derived from wall clock time relative to startOfMinute.
        ProgressView(timerInterval: startOfMinute...endOfMinute, countsDown: false)
            .progressViewStyle(.linear)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(0.001)
            .overlay {
                WWClockSecondHandOnlyView(
                    palette: palette,
                    startOfMinute: startOfMinute
                )
                .opacity(handsOpacity)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct WWClockSecondHandOnlyView: View {
    let palette: WidgetWeaverClockPalette
    let startOfMinute: Date

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let now = Date()
            let elapsed = now.timeIntervalSince(startOfMinute)
            let clamped = max(0.0, min(elapsed, 59.999))
            let angle = Angle.degrees((clamped / 60.0) * 360.0)

            let s = min(proxy.size.width, proxy.size.height)

            // Mirror the second-hand geometry used by WidgetWeaverClockIconView
            let outerDiameter = WWClock.pixel(s * 0.925, scale: displayScale)
            let outerRadius = outerDiameter * 0.5

            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            let ringA = WWClock.pixel(provisionalR * 0.010, scale: displayScale)
            let ringC = WWClock.pixel(
                WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
                scale: displayScale
            )
            let minB = WWClock.px(scale: displayScale)
            let ringB = WWClock.pixel(
                max(minB, outerRadius - provisionalR - ringA - ringC),
                scale: displayScale
            )

            let R = outerRadius - ringA - ringB - ringC

            let secondLength = WWClock.pixel(
                WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
                scale: displayScale
            )
            let secondWidth = WWClock.pixel(
                WWClock.clamp(R * 0.006, min: R * 0.004, max: R * 0.007),
                scale: displayScale
            )
            let secondTipSide = WWClock.pixel(
                WWClock.clamp(R * 0.014, min: R * 0.012, max: R * 0.016),
                scale: displayScale
            )

            WidgetWeaverClockSecondHandView(
                colour: palette.accent,
                width: secondWidth,
                length: secondLength,
                angle: angle,
                tipSide: secondTipSide,
                scale: displayScale
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Base angles (minute-anchored)

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        self.minute = minuteInt * 6.0
        self.hour = (hour12 + (minuteInt / 60.0)) * 30.0
    }
}
