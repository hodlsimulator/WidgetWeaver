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

    // Avoids the “00 → 02” style boundary glitch.
    private static let timerStartBiasSeconds: TimeInterval = 0.25

    // Keep some spillover so the timer doesn’t go blank if the next minute entry is delivered a bit late.
    private static let minuteSpilloverSeconds: TimeInterval = 6.0

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPrivacy = redactionReasons.contains(.privacy)
            let handsOpacity: Double = isPrivacy ? 0.85 : 1.0

            // Hour/minute can follow the entry minute (what you already had).
            let entryMinuteAnchor = Self.floorToMinute(entryDate)
            let base = WWClockBaseAngles(date: entryMinuteAnchor)

            // Seconds should render even if the host chooses to redact (a clock isn’t sensitive).
            let showSeconds = (tickMode == .secondsSweep)

            // IMPORTANT: compute seconds timer off “render time” rather than entryDate,
            // so a stale timeline entry can’t push the timer range out of sync on a specific device.
            let renderNow = Date()
            let secondMinuteAnchor = Self.floorToMinute(renderNow)

            let timerStart = secondMinuteAnchor.addingTimeInterval(-Self.timerStartBiasSeconds)
            let timerEnd = secondMinuteAnchor.addingTimeInterval(60.0 + Self.minuteSpilloverSeconds)
            let timerRange = timerStart...timerEnd

            ZStack {
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

                WWClockSecondsAndHubOverlay(
                    palette: palette,
                    showsSeconds: showSeconds,
                    timerRange: timerRange,
                    handsOpacity: handsOpacity
                )
            }
            .overlay(alignment: .bottomLeading) {
                WWClockWidgetDebugBadge(
                    entryDate: entryDate,
                    minuteAnchor: secondMinuteAnchor,
                    timerRange: timerRange,
                    showSeconds: showSeconds,
                    tickModeLabel: String(describing: tickMode)
                )
                .padding(6)
            }
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

// MARK: - Seconds + hub overlay (time-aware seconds hand)

private struct WWClockSecondsAndHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let showsSeconds: Bool
    let timerRange: ClosedRange<Date>
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(size: proxy.size, scale: displayScale)

            ZStack {
                if showsSeconds {
                    WWClockSecondHandGlyphView(
                        palette: palette,
                        timerRange: timerRange,
                        diameter: layout.dialDiameter
                    )
                    .opacity(handsOpacity)
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
}

private struct WWClockSecondHandGlyphView: View {
    let palette: WidgetWeaverClockPalette
    let timerRange: ClosedRange<Date>
    let diameter: CGFloat

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        // If the host is rendering a placeholder state, the timer output can be replaced.
        // In that case, show a stable test string that maps to a known ligature.
        let usesPlaceholder = redactionReasons.contains(.placeholder)

        Group {
            if usesPlaceholder {
                Text("0:00")
            } else {
                Text(timerInterval: timerRange, countsDown: false)
            }
        }
        .environment(\.locale, Locale(identifier: "en_US_POSIX"))
        .font(WWClockSecondHandFont.font(size: diameter))
        .dynamicTypeSize(.medium)
        .foregroundStyle(palette.accent)
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .frame(width: diameter, height: diameter, alignment: .center)
        .shadow(color: palette.handShadow, radius: diameter * 0.012, x: 0, y: diameter * 0.006)
        .shadow(color: palette.accent.opacity(0.35), radius: diameter * 0.018, x: 0, y: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
