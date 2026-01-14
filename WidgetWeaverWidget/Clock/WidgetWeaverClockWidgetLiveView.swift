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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lastLoggedMinuteRef: Int = Int.min

    private static let timerStartBiasSeconds: TimeInterval = 0.25
    private static let minuteSpilloverSeconds: TimeInterval = 59.0

    var body: some View {
        let scheduleStart = Self.floorToMinute(Date())

        WidgetWeaverRenderClock.withNow(entryDate) {
            TimelineView(.periodic(from: scheduleStart, by: 60.0)) { timeline in
                let sysNow = timeline.date
                let ctxNow = WidgetWeaverRenderClock.now

                let sysMinuteAnchor = Self.floorToMinute(sysNow)
                let ctxMinuteAnchor = Self.floorToMinute(ctxNow)
                let leadSeconds = ctxNow.timeIntervalSince(sysNow)

                // Pre-render detection:
                // - far-future: ctxNow is way ahead of sysNow
                // - minute-boundary skew: ctxMinuteAnchor is ahead of sysMinuteAnchor
                let isPrerender = (leadSeconds > 5.0) || (ctxMinuteAnchor > sysMinuteAnchor)

                let effectiveNow: Date = isPrerender ? ctxNow : sysNow
                let handsNow = Self.floorToMinute(effectiveNow)

                let isPrivacy = redactionReasons.contains(.privacy)
                let handsOpacity: Double = isPrivacy ? 0.85 : 1.0
                let showSeconds = (tickMode == .secondsSweep)

                let angles = _WWClockWidgetBaseAngles(date: handsNow)
                let hourAngle = Angle.degrees(angles.hourDeg)
                let minuteAngle = Angle.degrees(angles.minuteDeg)

                // Seconds glyph anchor (minute) + spillover window
                let secondsMinuteAnchor = handsNow
                let timerStart = secondsMinuteAnchor.addingTimeInterval(-Self.timerStartBiasSeconds)
                let timerEnd = secondsMinuteAnchor.addingTimeInterval(60.0 + Self.minuteSpilloverSeconds)
                let timerRange = timerStart...timerEnd

                // Ensure font registration happens when seconds are on.
                let _ = showSeconds ? WWClockSecondHandFont.isAvailable() : true

                let minuteID = Int(handsNow.timeIntervalSince1970 / 60.0)

                ZStack {
                    WidgetWeaverClockIconView(
                        palette: palette,
                        hourAngle: hourAngle,
                        minuteAngle: minuteAngle,
                        secondAngle: .degrees(0),
                        showsSecondHand: false,
                        showsHandShadows: false,
                        showsGlows: false,
                        showsCentreHub: false,
                        handsOpacity: handsOpacity
                    )
                    .id(minuteID)
                    .transition(.identity)
                    .transaction { transaction in
                        transaction.animation = nil
                    }

                    _WWClockWidgetSecondsAndHubOverlay(
                        palette: palette,
                        showsSeconds: showSeconds,
                        timerRange: timerRange,
                        handsOpacity: handsOpacity
                    )
                }
                .widgetURL(URL(string: "widgetweaver://clock"))
                #if DEBUG
                .overlay(alignment: .bottomTrailing) {
                    WWClockWidgetDebugBadge(
                        entryDate: effectiveNow,
                        minuteAnchor: secondsMinuteAnchor,
                        timerRange: timerRange,
                        showSeconds: showSeconds,
                        tickModeLabel: showSeconds ? "secondsSweep" : "minuteOnly"
                    )
                    .padding(6)
                }
                #endif
                #if DEBUG
                .onChange(of: handsNow) { _, newHands in
                    if isPrerender { return }

                    let newRef = Int(newHands.timeIntervalSinceReferenceDate.rounded())
                    if newRef == lastLoggedMinuteRef { return }
                    lastLoggedMinuteRef = newRef

                    let tickNow = Date()
                    let lagMs = Int((tickNow.timeIntervalSince(newHands) * 1000.0).rounded())
                    let ok = (abs(lagMs) <= 250) ? 1 : 0

                    let leadMs = Int((leadSeconds * 1000.0).rounded())

                    WWClockDebugLog.appendLazy(category: "clock", throttleID: nil, minInterval: 0, now: tickNow) {
                        let cal = Calendar.autoupdatingCurrent
                        let h = cal.component(.hour, from: newHands)
                        let m = cal.component(.minute, from: newHands)
                        return "minuteTick hm=\(h):\(String(format: "%02d", m)) handsRef=\(newRef) lagMs=\(lagMs) ok=\(ok) leadMs=\(leadMs) rm=\(reduceMotion ? 1 : 0)"
                    }
                }
                #endif
            }
        }
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

private struct _WWClockWidgetBaseAngles {
    let hourDeg: Double
    let minuteDeg: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = secondInt + (nano / 1_000_000_000.0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        hourDeg = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
        minuteDeg = (minuteInt + sec / 60.0) * 6.0
    }
}

private struct _WWClockWidgetSecondsAndHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let showsSeconds: Bool
    let timerRange: ClosedRange<Date>
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = _WWClockWidgetDialLayout(size: proxy.size, scale: displayScale)

            ZStack {
                if showsSeconds {
                    _WWClockWidgetSecondHandGlyphView(
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

private struct _WWClockWidgetSecondHandGlyphView: View {
    let palette: WidgetWeaverClockPalette
    let timerRange: ClosedRange<Date>
    let diameter: CGFloat

    var body: some View {
        Text(timerInterval: timerRange, countsDown: false)
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
    }
}

private struct _WWClockWidgetDialLayout {
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
        dialDiameter = R * 2.0

        hubBaseRadius = WWClock.pixel(
            WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
            scale: scale
        )

        hubCapRadius = WWClock.pixel(
            WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
            scale: scale
        )
    }
}
