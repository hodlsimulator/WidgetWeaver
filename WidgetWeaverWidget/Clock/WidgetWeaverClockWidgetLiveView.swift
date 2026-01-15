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

    fileprivate static let timerStartBiasSeconds: TimeInterval = 0.25
    fileprivate static let minuteSpilloverSeconds: TimeInterval = 59.0

    // Must match Scripts/generate_minute_hand_font.py WINDOW_HOURS.
    fileprivate static let minuteHandTimerWindowSeconds: TimeInterval = 4.0 * 3600.0

    fileprivate static var buildLabel: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            WWClockEveryMinuteRoot(
                palette: palette,
                entryDate: entryDate,
                tickMode: tickMode,
                tickSeconds: tickSeconds
            )
        }
    }

    fileprivate static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }

    fileprivate static func floorToHour(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 3600.0) * 3600.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

// MARK: - Live driver (every minute)

fileprivate struct WWClockEveryMinuteRoot: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval

    var body: some View {
        // In widgets, SwiftUI time-driven primitives can advance without WidgetKit delivering
        // a new timeline entry. TimelineView is a low-cost driver that can re-evaluate the
        // hour/minute hands at minute granularity.
        TimelineView(.everyMinute) { timelineCtx in
            WWClockRenderBody(
                palette: palette,
                entryDate: entryDate,
                tickMode: tickMode,
                tickSeconds: tickSeconds,
                timelineNow: timelineCtx.date
            )
        }
    }
}

// MARK: - Render body

fileprivate struct WWClockRenderBody: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval
    let timelineNow: Date

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lastLoggedMinuteRef: Int = Int.min

    var body: some View {
        // Wall clock.
        let wallNow = Date()

        // Render clock (pinned to entryDate via WidgetWeaverRenderClock.withNow).
        let ctxNow = WidgetWeaverRenderClock.now

        let sysMinuteAnchor = WidgetWeaverClockWidgetLiveView.floorToMinute(wallNow)
        let ctxMinuteAnchor = WidgetWeaverClockWidgetLiveView.floorToMinute(ctxNow)
        let leadSeconds = ctxNow.timeIntervalSince(wallNow)

        // Pre-render detection:
        // - far-future: ctxNow is way ahead of wallNow
        // - minute-boundary skew: ctxMinuteAnchor is ahead of sysMinuteAnchor
        let isPrerender = (leadSeconds > 5.0) || (ctxMinuteAnchor > sysMinuteAnchor)

        // Live: TimelineView date (should tick every minute). Pre-render: ctxNow for deterministic snapshots.
        let renderNow: Date = isPrerender ? ctxNow : timelineNow

        // Tick-style hour + minute hands: snap to the minute boundary.
        let handsNow = WidgetWeaverClockWidgetLiveView.floorToMinute(renderNow)

        let isPrivacy = redactionReasons.contains(.privacy)
        let isPlaceholder = redactionReasons.contains(.placeholder)

        let handsOpacity: Double = isPrivacy ? 0.85 : 1.0
        let showSeconds = (tickMode == .secondsSweep)

        // Live minute-hand glyph:
        // - Disable for pre-render (must match entryDate snapshot)
        // - Disable for placeholder
        let showsMinuteHandGlyph = (!isPrerender) && (!isPlaceholder)

        let baseAngles = WWClockBaseAngles(date: handsNow)
        let hourAngle = Angle.degrees(baseAngles.hour)
        let minuteAngle = Angle.degrees(baseAngles.minute)

        // Seconds anchor:
        let secondsMinuteAnchor = handsNow
        let timerStart = secondsMinuteAnchor.addingTimeInterval(-WidgetWeaverClockWidgetLiveView.timerStartBiasSeconds)
        let timerEnd = secondsMinuteAnchor.addingTimeInterval(60.0 + WidgetWeaverClockWidgetLiveView.minuteSpilloverSeconds)
        let timerRange = timerStart...timerEnd

        // Minute-hand timer range (hour-anchored, multi-hour window).
        let minuteHourAnchor = WidgetWeaverClockWidgetLiveView.floorToHour(wallNow)
        let minuteTimerStart = minuteHourAnchor.addingTimeInterval(-WidgetWeaverClockWidgetLiveView.timerStartBiasSeconds)
        let minuteTimerEnd = minuteHourAnchor.addingTimeInterval(WidgetWeaverClockWidgetLiveView.minuteHandTimerWindowSeconds)
        let minuteTimerRange = minuteTimerStart...minuteTimerEnd

        // Render-path proof logging (sync to survive widget process teardown).
        let _ : Void = {
            guard WWClockDebugLog.isEnabled() else { return () }

            let balloon = WWClockDebugLog.isBallooningEnabled()

            let ctxRef = Int(ctxNow.timeIntervalSinceReferenceDate.rounded())
            let wallRef = Int(wallNow.timeIntervalSinceReferenceDate.rounded())
            let handsRef = Int(handsNow.timeIntervalSinceReferenceDate.rounded())

            let leadMs = Int((leadSeconds * 1000.0).rounded())

            let cal = Calendar.autoupdatingCurrent
            let handsH = cal.component(.hour, from: handsNow)
            let handsM = cal.component(.minute, from: handsNow)
            let liveS = cal.component(.second, from: wallNow)

            let hDeg = Int(baseAngles.hour.rounded())
            let mDeg = Int(baseAngles.minute.rounded())

            let redactLabel: String = {
                if isPlaceholder && isPrivacy { return "placeholder+privacy" }
                if isPlaceholder { return "placeholder" }
                if isPrivacy { return "privacy" }
                return "none"
            }()

            // How late was this render relative to the minute boundary?
            let lagMs = Int((wallNow.timeIntervalSince(handsNow) * 1000.0).rounded())

            WWClockDebugLog.appendLazySync(
                category: "clock",
                throttleID: balloon ? nil : "clockWidget.render",
                minInterval: balloon ? 0.0 : 15.0,
                now: wallNow
            ) {
                "render build=\(WidgetWeaverClockWidgetLiveView.buildLabel) ctxRef=\(ctxRef) wallRef=\(wallRef) leadMs=\(leadMs) live=\(isPrerender ? 0 : 1) handsRef=\(handsRef) handsHM=\(handsH):\(handsM) liveS=\(liveS) hDeg=\(hDeg) mDeg=\(mDeg) mode=\(tickMode) sec=\(showSeconds ? 1 : 0) minuteGlyph=\(showsMinuteHandGlyph ? 1 : 0) redact=\(redactLabel) rm=\(reduceMotion ? 1 : 0) balloon=\(balloon ? 1 : 0) lagMs=\(lagMs)"
            }

            return ()
        }()

        ZStack {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: .degrees(0),
                showsSecondHand: false,
                showsMinuteHand: !showsMinuteHandGlyph,
                showsHandShadows: false,
                showsGlows: false,
                showsCentreHub: false,
                handsOpacity: handsOpacity
            )
            .id(handsNow)
            .transition(.identity)
            .transaction { transaction in
                transaction.animation = nil
            }

            WWClockSecondsAndHubOverlay(
                palette: palette,
                showsMinuteHand: showsMinuteHandGlyph,
                minuteTimerRange: minuteTimerRange,
                showsSeconds: showSeconds,
                timerRange: timerRange,
                handsOpacity: handsOpacity
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "widgetweaver://clock"))
        .overlay(alignment: .bottomTrailing) {
            if WWClockDebugLog.isEnabled() {
                WWClockWidgetDebugBadge(
                    entryDate: renderNow,
                    minuteAnchor: secondsMinuteAnchor,
                    timerRange: timerRange,
                    showSeconds: showSeconds,
                    tickModeLabel: showSeconds ? "secondsSweep" : "minuteOnly"
                )
                .padding(6)
            }
        }
        .onChange(of: handsNow) { _, newHands in
            // Minute tick proof logging.
            guard WWClockDebugLog.isEnabled() else { return }

            let handsRef = Int(newHands.timeIntervalSinceReferenceDate.rounded())
            if handsRef == lastLoggedMinuteRef { return }
            lastLoggedMinuteRef = handsRef

            let wallNow2 = Date()

            // Skip minuteTick logs for pre-render passes.
            let ctxNow2 = WidgetWeaverRenderClock.now
            let sysMinuteAnchor2 = WidgetWeaverClockWidgetLiveView.floorToMinute(wallNow2)
            let ctxMinuteAnchor2 = WidgetWeaverClockWidgetLiveView.floorToMinute(ctxNow2)
            let leadSeconds2 = ctxNow2.timeIntervalSince(wallNow2)
            let isPrerender2 = (leadSeconds2 > 5.0) || (ctxMinuteAnchor2 > sysMinuteAnchor2)
            if isPrerender2 { return }

            let lagMs = Int((wallNow2.timeIntervalSince(newHands) * 1000.0).rounded())
            let ok = (abs(lagMs) <= 250) ? 1 : 0

            let cal = Calendar.autoupdatingCurrent
            let h = cal.component(.hour, from: newHands)
            let m = cal.component(.minute, from: newHands)

            WWClockDebugLog.appendLazySync(category: "clock", throttleID: nil, minInterval: 0, now: wallNow2) {
                "minuteTick build=\(WidgetWeaverClockWidgetLiveView.buildLabel) hm=\(h):\(String(format: "%02d", m)) handsRef=\(handsRef) lagMs=\(lagMs) ok=\(ok)"
            }
        }
    }
}

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = secondInt + (nano / 1_000_000_000.0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        self.hour = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
        self.minute = (minuteInt + sec / 60.0) * 6.0
    }
}

private struct WWClockSecondsAndHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let showsMinuteHand: Bool
    let minuteTimerRange: ClosedRange<Date>

    let showsSeconds: Bool
    let timerRange: ClosedRange<Date>
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(size: proxy.size, scale: displayScale)

            ZStack {
                if showsMinuteHand {
                    WWClockMinuteHandGlyphView(
                        palette: palette,
                        timerRange: minuteTimerRange,
                        diameter: layout.dialDiameter
                    )
                    .opacity(handsOpacity)
                }

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

private struct WWClockMinuteHandGlyphView: View {
    let palette: WidgetWeaverClockPalette
    let timerRange: ClosedRange<Date>
    let diameter: CGFloat

    var body: some View {
        let metalField = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.handLight, location: 0.00),
                .init(color: palette.handMid, location: 0.52),
                .init(color: palette.handDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: diameter, height: diameter)

        let glyph = Text(timerInterval: timerRange, countsDown: false)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .font(WWClockMinuteHandFont.font(size: diameter))
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(width: diameter, height: diameter, alignment: .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)

        ZStack {
            // Edge stroke approximation:
            // Draw the glyph in edge colour, then inset the fill slightly.
            glyph
                .foregroundStyle(palette.handEdge)

            metalField
                .mask(
                    glyph
                        .foregroundStyle(Color.white)
                        .scaleEffect(0.94, anchor: .center)
                )
        }
        .frame(width: diameter, height: diameter, alignment: .center)
    }
}

private struct WWClockSecondHandGlyphView: View {
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
