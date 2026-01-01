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

            let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

            // README strategy #5:
            // - Minute hand should tick reliably from minute-boundary entries.
            // - Seconds hand should tick without 1Hz WidgetKit timelines.
            // Use the bundled second-hand ligature font driven by Text(timerInterval:...).
            let base = WWClockBaseAngles(date: entryDate)

            ZStack {
                // Base clock: hour + minute only (stable tree, no seconds animation).
                // Centre hub is drawn after the seconds needle so the needle sits "under" the hub.
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(base.hour),
                    minuteAngle: .degrees(base.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: false,
                    handsOpacity: handsOpacity
                )

                // Seconds needle + hub overlay, clipped to the dial circle.
                WWClockSecondsNeedleOverlay(
                    palette: palette,
                    minuteAnchor: entryDate,
                    showLive: !(isPlaceholder || isPrivacy),
                    handsOpacity: handsOpacity
                )
            }
            .privacySensitive(isPrivacy)
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
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

// MARK: - Seconds needle overlay (budget-safe ticking)

private struct WWClockSecondsNeedleOverlay: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date
    let showLive: Bool
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(size: proxy.size, scale: displayScale)

            ZStack {
                // This is the key trick:
                // - Text(timerInterval:) updates once per second in a widget-safe way.
                // - WWClockSecondHand-Regular.ttf has blank digits/colon, but "0:SS" ligatures map
                //   to pre-rotated second-hand glyphs (sec00 ... sec59).
                Group {
                    if showLive {
                        Text(timerInterval: minuteAnchor...Date.distantFuture, countsDown: false)
                    } else {
                        Text("0:00")
                    }
                }
                .font(WWClockSecondHandFont.font(size: layout.dialDiameter))
                .foregroundStyle(palette.accent)
                .frame(width: layout.dialDiameter, height: layout.dialDiameter)
                .clipShape(Circle())
                .opacity(handsOpacity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                // Draw hub last so the seconds needle sits underneath it visually.
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
        }
    }
}

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
