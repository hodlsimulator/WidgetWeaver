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
                // Draw the static clock face + hour/minute hands.
                // When the ticking seconds overlay is enabled, the centre hub is drawn in its own
                // layer so it stays crisp.
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
                    ZStack {
                        WWClockSecondHandTickingOverlay(
                            palette: palette,
                            startOfMinute: minuteAnchor,
                            handsOpacity: handsOpacity
                        )

                        // Centre hub in its own layer (avoids being rasterised along with the seconds overlay).
                        GeometryReader { proxy in
                            let s = min(proxy.size.width, proxy.size.height)
                            let outerDiameter = WWClock.pixel(s * 0.925, scale: displayScale)
                            let outerRadius = outerDiameter * 0.5

                            let metalThicknessRatio: CGFloat = 0.062
                            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

                            let ringA = WWClock.pixel(provisionalR * 0.010, scale: displayScale)
                            let ringC = WWClock.pixel(
                                WWClock.clamp(
                                    provisionalR * 0.0095,
                                    min: provisionalR * 0.008,
                                    max: provisionalR * 0.012
                                ),
                                scale: displayScale
                            )
                            let minB = WWClock.px(scale: displayScale)
                            let ringB = WWClock.pixel(
                                max(minB, outerRadius - provisionalR - ringA - ringC),
                                scale: displayScale
                            )

                            let R = outerRadius - ringA - ringB - ringC

                            let hubBaseRadius = WWClock.pixel(
                                WWClock.clamp(
                                    R * 0.095,
                                    min: R * 0.080,
                                    max: R * 0.110
                                ),
                                scale: displayScale
                            )
                            let hubCapRadius = WWClock.pixel(
                                WWClock.clamp(
                                    R * 0.065,
                                    min: R * 0.055,
                                    max: R * 0.075
                                ),
                                scale: displayScale
                            )

                            WidgetWeaverClockCentreHubView(
                                palette: palette,
                                baseRadius: hubBaseRadius,
                                capRadius: hubCapRadius,
                                scale: displayScale
                            )
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .opacity(handsOpacity)
                        }
                    }
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Seconds hand overlay (budget-safe)

private struct WWClockSecondHandTickingOverlay: View {
    let palette: WidgetWeaverClockPalette
    let startOfMinute: Date
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            // Mirror the sizing logic from WidgetWeaverClockIconView so the second hand matches.
            let outerDiameter = WWClock.pixel(s * 0.925, scale: displayScale)
            let outerRadius = outerDiameter * 0.5

            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            let ringA = WWClock.pixel(provisionalR * 0.010, scale: displayScale)
            let ringC = WWClock.pixel(
                WWClock.clamp(
                    provisionalR * 0.0095,
                    min: provisionalR * 0.008,
                    max: provisionalR * 0.012
                ),
                scale: displayScale
            )
            let minB = WWClock.px(scale: displayScale)
            let ringB = WWClock.pixel(
                max(minB, outerRadius - provisionalR - ringA - ringC),
                scale: displayScale
            )

            let R = outerRadius - ringA - ringB - ringC

            let secondLength = WWClock.pixel(
                WWClock.clamp(
                    R * 0.90,
                    min: R * 0.86,
                    max: R * 0.92
                ),
                scale: displayScale
            )
            let secondWidth = WWClock.pixel(
                WWClock.clamp(
                    R * 0.006,
                    min: R * 0.004,
                    max: R * 0.007
                ),
                scale: displayScale
            )
            let secondTipSide = WWClock.pixel(
                WWClock.clamp(
                    R * 0.014,
                    min: R * 0.012,
                    max: R * 0.016
                ),
                scale: displayScale
            )

            TimelineView(.periodic(from: startOfMinute, by: 1.0)) { context in
                let tick = WWClockSecondTick.secondIndex(for: context.date)
                let angle = Angle.degrees(Double(tick) * 6.0)

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
            // Avoid implicit cross-fades between seconds.
            .transaction { transaction in
                transaction.animation = nil
            }
            .opacity(handsOpacity)
            .overlay(
                WWClockSecondsHeartbeat(start: startOfMinute),
                alignment: .bottomTrailing
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private enum WWClockSecondTick {
    @inline(__always)
    static func secondIndex(for date: Date) -> Int {
        // Seconds-of-minute are timezone-agnostic.
        let t = date.timeIntervalSinceReferenceDate
        var s = Int(floor(t)) % 60
        if s < 0 { s += 60 }
        return s
    }
}

private struct WWClockSecondsHeartbeat: View {
    let start: Date

    var body: some View {
        // Heartbeat:
        // A tiny timer-style Text keeps the widget host in a “live” rendering mode.
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .font(.system(size: 1))
            .foregroundStyle(Color.primary.opacity(0.001))
            .frame(width: 1, height: 1)
            .clipped()
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
