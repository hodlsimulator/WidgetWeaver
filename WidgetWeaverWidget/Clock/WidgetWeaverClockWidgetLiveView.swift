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

            // Seconds hand:
            // - Always draw a fallback needle at 12 o'clock via WidgetWeaverClockIconView.
            // - In live, non-redacted renders, try to draw the time-aware seconds glyph on top.
            //
            // This avoids the “no seconds hand at all” failure mode if the glyph path fails to render.
            let showSecondsHand = (tickMode == .secondsSweep)
            let showLiveSecondsGlyph = showSecondsHand && showLive

            ZStack {
                // Base clock (hour + minute + fallback seconds at 12).
                // The centre hub is drawn in the overlay so the seconds needle sits underneath it.
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(base.hour),
                    minuteAngle: .degrees(base.minute),
                    secondAngle: .degrees(0.0),
                    showsSecondHand: showSecondsHand,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: false,
                    handsOpacity: handsOpacity
                )

                WWClockSecondsAndHubOverlay(
                    palette: palette,
                    minuteAnchor: minuteAnchor,
                    showLiveSecondsHand: showLiveSecondsGlyph,
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

// MARK: - Seconds + hub overlay (time-aware seconds hand)

private struct WWClockSecondsAndHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date
    let showLiveSecondsHand: Bool
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(size: proxy.size, scale: displayScale)

            ZStack {
                if showLiveSecondsHand {
                    WWClockSecondHandGlyphView(
                        palette: palette,
                        minuteAnchor: minuteAnchor,
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
    let minuteAnchor: Date
    let diameter: CGFloat

    // A timer range capped to < 60 seconds ensures the formatted output remains within the minute.
    private var timerRange: ClosedRange<Date> {
        let end = minuteAnchor.addingTimeInterval(59.999)
        return minuteAnchor...end
    }

    var body: some View {
        ZStack {
            Text(timerInterval: timerRange, countsDown: false)
                // Force ASCII digits + ':' so OpenType `liga` substitution stays stable.
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .font(WWClockSecondHandFont.font(size: diameter))
                .foregroundStyle(palette.accent)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(width: diameter, height: diameter, alignment: .center)
                .shadow(color: palette.handShadow, radius: diameter * 0.012, x: 0, y: diameter * 0.006)
                .shadow(color: palette.accent.opacity(0.35), radius: diameter * 0.018, x: 0, y: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            #if DEBUG
            // Debug: show the exact timer string the system is producing.
            // This makes it obvious whether it is "0:05", "00:05", etc.
            Text(timerInterval: timerRange, countsDown: false)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .font(.system(
                    size: max(CGFloat(10.0), diameter * 0.08),
                    weight: .regular,
                    design: .monospaced
                ))
                .foregroundStyle(Color.red.opacity(0.85))
                .frame(width: diameter, height: diameter, alignment: .bottom)
                .padding(.bottom, max(CGFloat(6.0), diameter * 0.06))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            #endif
        }
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
