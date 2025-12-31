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
    @Environment(\.displayScale) private var displayScale

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
                // Hour + minute are minute-boundary timeline-driven.
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(baseAngles.hour),
                    minuteAngle: .degrees(baseAngles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: !secondsEnabled,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)

                if secondsEnabled {
                    // Lightweight, host-animated seconds indicator (keeps the widget stable).
                    WWClockSecondsRingOverlay(
                        palette: palette,
                        startOfMinute: minuteAnchor,
                        scale: displayScale,
                        opacity: handsOpacity
                    )

                    // Hub drawn once on top.
                    WWClockCentreHubOverlay(palette: palette, scale: displayScale)
                        .opacity(handsOpacity)
                        .privacySensitive(isPrivacy)
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Seconds indicator (host-animated, widget-safe)

private struct WWClockSecondsRingOverlay: View {
    let palette: WidgetWeaverClockPalette
    let startOfMinute: Date
    let scale: CGFloat
    let opacity: Double

    var body: some View {
        let endOfMinute = startOfMinute.addingTimeInterval(60.0)

        return GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            let outerDiameter = WWClock.pixel(s * 0.925, scale: scale)
            let outerRadius = outerDiameter * 0.5

            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            let ringA = WWClock.pixel(provisionalR * 0.010, scale: scale)
            let ringC = WWClock.pixel(
                WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
                scale: scale
            )
            let minB = WWClock.px(scale: scale)
            let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: scale)

            let R = outerRadius - ringA - ringB - ringC

            let secondLength = WWClock.pixel(
                WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
                scale: scale
            )

            let diameter = secondLength * 2.0

            ProgressView(timerInterval: startOfMinute...endOfMinute, countsDown: false)
                .progressViewStyle(.circular)
                .tint(palette.accent)
                .frame(width: diameter, height: diameter)
                .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
                .opacity(opacity * 0.55)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Centre hub (drawn once on top)

private struct WWClockCentreHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let scale: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            let outerDiameter = WWClock.pixel(s * 0.925, scale: scale)
            let outerRadius = outerDiameter * 0.5

            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            let ringA = WWClock.pixel(provisionalR * 0.010, scale: scale)
            let ringC = WWClock.pixel(
                WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
                scale: scale
            )
            let minB = WWClock.px(scale: scale)
            let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: scale)

            let R = outerRadius - ringA - ringB - ringC

            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
                scale: scale
            )
            let hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: scale
            )

            WidgetWeaverClockCentreHubView(
                palette: palette,
                baseRadius: hubBaseRadius,
                capRadius: hubCapRadius,
                scale: scale
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
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
