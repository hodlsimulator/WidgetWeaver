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
                // Static clock face + hour/minute hands.
                // When the seconds overlay is enabled, the centre hub is drawn above it in a separate layer.
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(baseAngles.hour),
                    minuteAngle: .degrees(baseAngles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: !secondsEnabled,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: !secondsEnabled,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)

                if secondsEnabled {
                    ZStack {
                        WWClockSecondHandLigatureOverlay(
                            palette: palette,
                            startOfMinute: minuteAnchor,
                            handsOpacity: handsOpacity
                        )

                        // Centre hub in its own layer so it stays crisp above the ticking overlay.
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

// MARK: - Seconds hand overlay (budget-safe, widget-safe)

private struct WWClockSecondHandLigatureOverlay: View {
    let palette: WidgetWeaverClockPalette
    let startOfMinute: Date
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            // Match the dial sizing used by WidgetWeaverClockIconView.
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
            let dialDiameter = R * 2.0

            // End at +59s to avoid ever reaching a “1:00” string.
            let endOfMinute = startOfMinute.addingTimeInterval(59.0)

            // The custom font maps the timer string “0:SS” to a ligature glyph (sec00...sec59)
            // which draws the second hand at that second.
            Text(timerInterval: startOfMinute...endOfMinute, countsDown: false)
                .environment(\.locale, Self.posixLocale)
                .font(WWClockSecondHandFont.font(size: dialDiameter))
                .foregroundStyle(palette.accent)
                .frame(width: dialDiameter, height: dialDiameter, alignment: .center)
                .clipShape(Circle())
                .opacity(handsOpacity)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
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
