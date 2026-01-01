//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI
import WidgetKit

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPlaceholder = redactionReasons.contains(.placeholder)
            let isPrivacy = redactionReasons.contains(.privacy)

            let showLive = !(isPlaceholder || isPrivacy)
            let handsOpacity: Double = showLive ? 1.0 : 0.85

            // Hour/minute: minute-boundary provider timeline entries (stable, reliable).
            let minuteAnchor = Self.floorToMinute(entryDate)
            let base = WWClockBaseAngles(date: minuteAnchor)

            ZStack {
                // Base clock (no seconds in the main tree).
                // Centre hub is drawn in the overlay so the seconds needle sits underneath it.
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(base.hour),
                    minuteAngle: .degrees(base.minute),
                    secondAngle: .degrees(0.0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: false,
                    handsOpacity: handsOpacity
                )

                // Seconds + hub overlay:
                //
                // This is intentionally state-free. It avoids relying on `onAppear`, `.task`,
                // `TimelineView(.periodic)` or infinite SwiftUI animations, which can be skipped/paused
                // on some Home Screen hosting paths.
                //
                // Instead, the provider emits minute-boundary entries and this overlay requests a
                // finite CoreAnimation-backed rotation between successive entries.
                //
                // Key idea:
                // - For a given entry at time T, we draw the seconds hand at the *end* of the interval
                //   (T + tickSeconds) and attach an animation of duration tickSeconds keyed on entryDate.
                // - When the next entry arrives, SwiftUI animates from the previous target to the new
                //   target, producing continuous movement without any in-view timers.
                WWClockSecondsAndHubOverlay(
                    palette: palette,
                    entryDate: entryDate,
                    tickMode: tickMode,
                    tickSeconds: tickSeconds,
                    showLive: showLive,
                    handsOpacity: handsOpacity
                )
            }
            .privacySensitive(isPrivacy)
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

// MARK: - Minute-boundary angles (tick)

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

// MARK: - Seconds + hub overlay (finite animation)

private struct WWClockSecondsAndHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval
    let showLive: Bool
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(size: proxy.size, scale: displayScale)
            let R = layout.dialDiameter * 0.5

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

            ZStack {
                if tickMode == .secondsSweep {
                    if showLive {
                        WidgetWeaverClockSecondHandView(
                            colour: palette.accent,
                            width: secondWidth,
                            length: secondLength,
                            angle: .degrees(Self.secondDegreesTarget(date: entryDate, tickSeconds: tickSeconds)),
                            tipSide: secondTipSide,
                            scale: displayScale
                        )
                        .opacity(handsOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .animation(Self.secondsAnimation(tickSeconds: tickSeconds), value: entryDate)
                    } else {
                        // Placeholder/privacy: deterministic static position (12 o'clock).
                        WidgetWeaverClockSecondHandView(
                            colour: palette.accent,
                            width: secondWidth,
                            length: secondLength,
                            angle: .degrees(0.0),
                            tipSide: secondTipSide,
                            scale: displayScale
                        )
                        .opacity(handsOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }

                WidgetWeaverClockCentreHubView(
                    palette: palette,
                    baseRadius: layout.hubBaseRadius,
                    capRadius: layout.hubCapRadius,
                    scale: displayScale
                )
                .opacity(handsOpacity)
            }
            .frame(width: layout.dialDiameter, height: layout.dialDiameter)
            .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
            .clipShape(Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private static func secondsAnimation(tickSeconds: TimeInterval) -> Animation? {
        // `tickSeconds` is supplied by the provider as “time until the next entry”.
        // When it is 0 (a setup/anchor entry), do not animate.
        guard tickSeconds > 0.05 else { return nil }
        return .linear(duration: tickSeconds)
    }

    private static func secondDegreesTarget(date: Date, tickSeconds: TimeInterval) -> Double {
        // Use an unbounded angle so interpolation is always forward.
        // Each elapsed second adds 6 degrees.
        let baseDegrees = date.timeIntervalSinceReferenceDate * 6.0
        return baseDegrees + tickSeconds * 6.0
    }
}

// MARK: - Dial layout (matches WidgetWeaverClockIconView)

private struct WWClockDialLayout {
    let dialDiameter: CGFloat
    let hubBaseRadius: CGFloat
    let hubCapRadius: CGFloat

    init(size: CGSize, scale: CGFloat) {
        let s = min(size.width, size.height)

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
        self.dialDiameter = R * 2.0

        self.hubBaseRadius = WWClock.pixel(
            WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
            scale: scale
        )

        self.hubCapRadius = WWClock.pixel(
            WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
            scale: scale
        )
    }
}
