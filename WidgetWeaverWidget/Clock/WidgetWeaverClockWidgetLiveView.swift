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

            // README strategy #5:
            // - Hour/minute: minute-boundary timeline entries (stable, reliable).
            // - Seconds: budget-safe ticking via timer-style Text + ligature font (no 1 Hz timelines, no TimelineView).
            //
            // Important detail:
            // The bundled font only has ligatures for "0:00"..."0:59" (and "0:0"..."0:9").
            // The minute-boundary timeline keeps the timer in that domain by resetting `minuteAnchor` each minute.
            let minuteAnchor = Self.floorToMinute(entryDate)
            let base = WWClockBaseAngles(date: minuteAnchor)

            ZStack {
                // Base clock (no seconds in the main tree).
                // Centre hub is drawn after the seconds overlay so the seconds needle sits underneath it.
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

                // Seconds overlay: ticking needle driven by timer-style text glyph updates.
                WWClockSecondsLigatureOverlay(
                    palette: palette,
                    minuteAnchor: minuteAnchor,
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

// MARK: - Seconds overlay (ligature font)

private struct WWClockSecondsLigatureOverlay: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date
    let showLive: Bool
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(size: proxy.size, scale: displayScale)

            ZStack {
                if showLive {
                    // Use a timer-style date text so the system updates the glyphs every second.
                    // Important: the ligature font expects the displayed string to begin with "0:".
                    // In practice `Text(timerInterval:...)` can format with two-digit minutes ("00:SS"),
                    // which has no matching ligatures in the bundled font. `Text(date, style: .timer)`
                    // formats as "0:SS", which matches.
                    Text(minuteAnchor, style: .timer)
                        .font(WWClockSecondHandFont.font(size: layout.dialDiameter))
                        .foregroundStyle(palette.accent)
                        .frame(width: layout.dialDiameter, height: layout.dialDiameter)
                        .clipShape(Circle())
                        .opacity(handsOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else {
                    // Placeholder/privacy: deterministic static position (12 o'clock).
                    Text("0:00")
                        .font(WWClockSecondHandFont.font(size: layout.dialDiameter))
                        .foregroundStyle(palette.accent)
                        .frame(width: layout.dialDiameter, height: layout.dialDiameter)
                        .clipShape(Circle())
                        .opacity(handsOpacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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
