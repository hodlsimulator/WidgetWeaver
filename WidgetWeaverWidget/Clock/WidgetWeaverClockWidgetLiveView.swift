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
                // When the host-driven seconds overlay is enabled, the centre hub is drawn in its own
                // layer so it stays crisp while the seconds matte animates.
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
                        WWClockSecondHandHostDrivenOverlay(
                            palette: palette,
                            startOfMinute: minuteAnchor,
                            handsOpacity: handsOpacity
                        )

                        // Centre hub in its own layer (avoids being blurred/rasterised along with the matte).
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

// MARK: - Host-driven seconds hand overlay

private struct WWClockSecondHandHostDrivenOverlay: View {
    let palette: WidgetWeaverClockPalette
    let startOfMinute: Date
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let endOfMinute = startOfMinute.addingTimeInterval(60.0)

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

            // Important:
            // Avoid `.mask(...)` here. On Home Screen hosting paths the mask subtree can get cached,
            // freezing the ProgressView(timerInterval:) at its initial state (tick stuck at 12).
            //
            // Instead, cut the needle stack down to the wedge by subtracting an "outside matte":
            // outside matte = solid fill minus wedge. Apply it with `.destinationOut` inside a
            // compositing group so it only affects the needle layer.
            ZStack {
                ZStack {
                    ZStack {
                        ForEach(0..<60, id: \.self) { tick in
                            let angle = Angle.degrees(Double(tick) * 6.0)
                            WidgetWeaverClockSecondHandView(
                                colour: palette.accent,
                                width: secondWidth,
                                length: secondLength,
                                angle: angle,
                                tipSide: secondTipSide,
                                scale: displayScale
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .opacity(handsOpacity)

                    WWClockSecondHandOutsideWedgeMatte(
                        startOfMinute: startOfMinute,
                        endOfMinute: endOfMinute,
                        dialDiameter: outerDiameter,
                        windowSeconds: 1.0
                    )
                    .blendMode(.destinationOut)
                }
                .compositingGroup()
                .frame(width: proxy.size.width, height: proxy.size.height)

                WWClockSecondsHeartbeat(start: startOfMinute)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomTrailing)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct WWClockSecondsHeartbeat: View {
    let start: Date

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .font(.system(size: 1))
            .foregroundStyle(Color.primary.opacity(0.001))
            .frame(width: 1, height: 1)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct WWClockSecondHandOutsideWedgeMatte: View {
    let startOfMinute: Date
    let endOfMinute: Date
    let dialDiameter: CGFloat
    let windowSeconds: TimeInterval

    var body: some View {
        ZStack {
            Color.white

            WWClockSecondHandWedgeMask(
                startOfMinute: startOfMinute,
                endOfMinute: endOfMinute,
                dialDiameter: dialDiameter,
                windowSeconds: windowSeconds
            )
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WWClockSecondHandWedgeMask: View {
    let startOfMinute: Date
    let endOfMinute: Date
    let dialDiameter: CGFloat
    let windowSeconds: TimeInterval

    // Rendering the ProgressView very small then scaling up makes the stroke thick enough
    // that the resulting wedge reaches through the centre (useful as a mask).
    //
    // The view expands its layout bounds to the dial size before compositing, otherwise
    // the scaled ProgressView is clipped to its tiny (unscaled) layout box.
    private let baseDiameter: CGFloat = 2.0

    var body: some View {
        let scale = dialDiameter / baseDiameter

        let behindStart = startOfMinute.addingTimeInterval(windowSeconds)
        let behindEnd = endOfMinute.addingTimeInterval(windowSeconds)

        ZStack {
            ProgressView(timerInterval: startOfMinute...endOfMinute, countsDown: false)
                .progressViewStyle(.circular)
                .tint(Color.white)
                .frame(width: baseDiameter, height: baseDiameter)
                .scaleEffect(scale)
                .frame(width: dialDiameter, height: dialDiameter)

            ProgressView(timerInterval: behindStart...behindEnd, countsDown: false)
                .progressViewStyle(.circular)
                .tint(Color.white)
                .frame(width: baseDiameter, height: baseDiameter)
                .scaleEffect(scale)
                .frame(width: dialDiameter, height: dialDiameter)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
