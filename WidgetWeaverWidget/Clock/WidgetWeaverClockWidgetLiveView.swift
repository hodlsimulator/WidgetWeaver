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
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval

    init(
        face: WidgetWeaverClockFaceToken,
        palette: WidgetWeaverClockPalette,
        entryDate: Date,
        tickMode: WidgetWeaverClockTickMode,
        tickSeconds: TimeInterval
    ) {
        self.face = face
        self.palette = palette
        self.entryDate = entryDate
        self.tickMode = tickMode
        self.tickSeconds = tickSeconds
    }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lastWallSignatureSeconds: Int = Int.min
    @State private var lastLoggedMinuteRef: Int = Int.min
    @State private var significantTimeChangeToken: Int = 0
    @State private var lastClockJumpUptime: TimeInterval = -1.0

    // 2 hours forward range so Text(timerInterval:) never “runs out” while the widget is alive.
    static let secondsHandTimerWindowSeconds: TimeInterval = 2.0 * 60.0 * 60.0

    // For the minute-hand font, the GSUB mapping expects mm:ss relative to the hour anchor.
    // Keep a multi-hour window so the timer does not fall outside the interval on long-lived widgets.
    static let minuteHandTimerWindowSeconds: TimeInterval = 2.0 * 60.0 * 60.0

    // Bias start backwards slightly so hand glyph changes are never right on a boundary, avoiding
    // edge-case “missed tick” behaviour in some widget hosts.
    static let timerStartBiasSeconds: TimeInterval = 0.25

    // Render-proof label for debug logging.
    static let buildLabel: String = {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }()

    static func floorToMinute(_ date: Date) -> Date {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return cal.date(from: comps) ?? date
    }

    static func floorToHour(_ date: Date) -> Date {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: date)
        return cal.date(from: comps) ?? date
    }

    static func wallClockSignatureSeconds(now: Date, uptime: TimeInterval) -> Int {
        // If the wall clock is changed manually, Date() jumps but uptime remains monotonic.
        // Signature = wallSeconds - uptimeSeconds; a time jump changes this by a noticeable amount.
        let wallSeconds = now.timeIntervalSinceReferenceDate
        let sig = wallSeconds - uptime
        return Int(sig.rounded())
    }

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            WWClockRenderBody(
                face: face,
                palette: palette,
                tickMode: tickMode,
                tickSeconds: tickSeconds,
                displayScale: displayScale,
                redactionReasons: redactionReasons,
                reduceMotion: reduceMotion,
                lastWallSignatureSeconds: $lastWallSignatureSeconds,
                lastLoggedMinuteRef: $lastLoggedMinuteRef,
                significantTimeChangeToken: $significantTimeChangeToken,
                lastClockJumpUptime: $lastClockJumpUptime
            )
        }
    }
}

private struct WWClockRenderBody: View {
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval
    let displayScale: CGFloat
    let redactionReasons: RedactionReasons
    let reduceMotion: Bool

    @Binding var lastWallSignatureSeconds: Int
    @Binding var lastLoggedMinuteRef: Int
    @Binding var significantTimeChangeToken: Int
    @Binding var lastClockJumpUptime: TimeInterval

    var body: some View {
        let wallNow = Date()
        let uptimeNow = ProcessInfo.processInfo.systemUptime
        let wallSignatureSeconds = Self.wallClockSignatureSeconds(now: wallNow, uptime: uptimeNow)

        // Render clock (pinned to entryDate via WidgetWeaverRenderClock.withNow).
        let ctxNow = WidgetWeaverRenderClock.now

        let sysMinuteAnchor = WidgetWeaverClockWidgetLiveView.floorToMinute(wallNow)
        let ctxMinuteAnchor = WidgetWeaverClockWidgetLiveView.floorToMinute(ctxNow)
        let leadSeconds = ctxNow.timeIntervalSince(wallNow)

        // If the wall clock has jumped recently, treat the view as live even if the timeline entry
        // date is far ahead/behind (WidgetKit can be holding a stale entry after a manual time change).
        let recentlyJumped = (lastClockJumpUptime >= 0.0) && ((uptimeNow - lastClockJumpUptime) < (15.0 * 60.0))

        // Pre-render detection:
        // - far-future: ctxNow is way ahead of wallNow
        // - minute-boundary skew: ctxMinuteAnchor is ahead of sysMinuteAnchor
        let isPrerender = !recentlyJumped && ((leadSeconds > 5.0) || (ctxMinuteAnchor > sysMinuteAnchor))

        // Live: wallNow. Pre-render: ctxNow for deterministic snapshots.
        let renderNow: Date = isPrerender ? ctxNow : wallNow

        // Tick-style hour + minute hands: snap to the minute boundary.
        let handsNow = WidgetWeaverClockWidgetLiveView.floorToMinute(renderNow)

        let isPrivacy = redactionReasons.contains(.privacy)
        let isPlaceholder = redactionReasons.contains(.placeholder)

        let handsOpacity: Double = isPrivacy ? 0.85 : 1.0
        // The seconds hand is also used as a “live” rendering driver (via Text(timerInterval:)).
        // Some widget hosting paths can transiently apply placeholder redaction even on Home Screen.
        // Hiding the seconds hand in those moments makes the clock look frozen.
        let showSeconds = (tickMode == .secondsSweep)

        // Live minute-hand glyph:
        // - Disable for pre-render (must match entryDate snapshot)
        // - Keep enabled during placeholder redaction to avoid transient hand swapping
        //
        // Font selection:
        // - Icon face: prefer the Icon-specific thicker font, but fall back to the regular font
        //   if the Icon font is unavailable for any reason.
        // - Ceramic face: use the regular font (unchanged).
        let minuteGlyphFontAvailable: Bool = {
            if face == .icon {
                return WWClockMinuteHandIconFont.isAvailable() || WWClockMinuteHandFont.isAvailable()
            }
            return WWClockMinuteHandFont.isAvailable()
        }()

        let showsMinuteHandGlyph = (!isPrerender) && minuteGlyphFontAvailable

        let baseAngles = WWClockBaseAngles(date: handsNow)
        let hourAngle = Angle.degrees(baseAngles.hour)
        let minuteAngle = Angle.degrees(baseAngles.minute)

        // Seconds anchor:
        let secondsMinuteAnchor = handsNow
        let timerStart = secondsMinuteAnchor.addingTimeInterval(-WidgetWeaverClockWidgetLiveView.timerStartBiasSeconds)
        let timerEnd = secondsMinuteAnchor.addingTimeInterval(WidgetWeaverClockWidgetLiveView.secondsHandTimerWindowSeconds)
        let timerRange = timerStart...timerEnd

        // Minute-hand timer range (hour-anchored, multi-hour window).
        let minuteHourAnchor = WidgetWeaverClockWidgetLiveView.floorToHour(wallNow)
        let minuteTimerStart = minuteHourAnchor.addingTimeInterval(-WidgetWeaverClockWidgetLiveView.timerStartBiasSeconds)
        let minuteTimerEnd = minuteHourAnchor.addingTimeInterval(WidgetWeaverClockWidgetLiveView.minuteHandTimerWindowSeconds)
        let minuteTimerRange = minuteTimerStart...minuteTimerEnd

        // Wall-clock heartbeat: force a body refresh at minute granularity without relying on
        // WidgetKit delivering a new entry at exactly the minute boundary.
        let heartbeatRange = sysMinuteAnchor...sysMinuteAnchor.addingTimeInterval(60.0)

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
                "render build=\(WidgetWeaverClockWidgetLiveView.buildLabel) face=\(face.rawValue) ctxRef=\(ctxRef) wallRef=\(wallRef) leadMs=\(leadMs) live=\(isPrerender ? 0 : 1) handsRef=\(handsRef) handsHM=\(handsH):\(handsM) liveS=\(liveS) hDeg=\(hDeg) mDeg=\(mDeg) mode=\(tickMode) sec=\(showSeconds ? 1 : 0) minuteGlyph=\(showsMinuteHandGlyph ? 1 : 0) redact=\(redactLabel) rm=\(reduceMotion ? 1 : 0) balloon=\(balloon ? 1 : 0) lagMs=\(lagMs) sig=\(wallSignatureSeconds) jump=\(recentlyJumped ? 1 : 0)"
            }

            return ()
        }()

        let wallSignatureChanged = (wallSignatureSeconds != lastWallSignatureSeconds)

        ZStack {
            // Heartbeat driver: ensures the body is re-evaluated while the widget is on screen.
            if !isPrerender {
                WWClockSecondsDriverText(timerRange: heartbeatRange)
                    .id("hb-\(sysMinuteAnchor.timeIntervalSinceReferenceDate)")
            }

            WidgetWeaverClockFaceView(
                face: face,
                palette: palette,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: .degrees(0),
                showsSecondHand: false,
                showsMinuteHand: !showsMinuteHandGlyph,
                showsHandShadows: false,
                showsGlows: false,
                showsCentreHub: false
            )
            .opacity(handsOpacity)

            WWClockSecondsAndHubOverlay(
                face: face,
                palette: palette,
                showsMinuteHand: showsMinuteHandGlyph,
                minuteTimerRange: minuteTimerRange,
                showsSeconds: showSeconds,
                timerRange: timerRange,
                handsOpacity: handsOpacity,
                refreshToken: significantTimeChangeToken
            )
        }
        .onAppear {
            // Initialise signature.
            lastWallSignatureSeconds = wallSignatureSeconds
        }
        .onChange(of: wallSignatureChanged) { _, changed in
            guard changed else { return }

            let now = Date()
            let prev = lastWallSignatureSeconds
            lastWallSignatureSeconds = wallSignatureSeconds

            // Record a jump time so pre-render detection can relax briefly.
            lastClockJumpUptime = ProcessInfo.processInfo.systemUptime

            // Force rebuild of glyph views on a significant wall clock jump.
            significantTimeChangeToken &+= 1

            if WWClockDebugLog.isEnabled() {
                WWClockDebugLog.appendLazySync(category: "clock", throttleID: nil, minInterval: 0.0, now: now) {
                    "clockJump build=\(WidgetWeaverClockWidgetLiveView.buildLabel) prevSig=\(prev) newSig=\(wallSignatureSeconds) delta=\(wallSignatureSeconds - prev)"
                }
            }
        }
        .onChange(of: sysMinuteAnchor) { _, newMinuteAnchor in
            // Some widget hosts do not re-evaluate exactly on the boundary; this is a belt-and-braces check.
            let minuteRef = Int(newMinuteAnchor.timeIntervalSinceReferenceDate.rounded())
            guard minuteRef != lastLoggedMinuteRef else { return }
            lastLoggedMinuteRef = minuteRef

            guard WWClockDebugLog.isEnabled() else { return }

            let now = Date()
            let balloon = WWClockDebugLog.isBallooningEnabled()

            let ctxNow2 = WidgetWeaverRenderClock.now
            let wallNow2 = now
            let leadSeconds2 = ctxNow2.timeIntervalSince(wallNow2)

            let sysMinuteAnchor2 = WidgetWeaverClockWidgetLiveView.floorToMinute(wallNow2)
            let ctxMinuteAnchor2 = WidgetWeaverClockWidgetLiveView.floorToMinute(ctxNow2)
            let isPrerender2 = (leadSeconds2 > 5.0) || (ctxMinuteAnchor2 > sysMinuteAnchor2)

            let cal = Calendar.autoupdatingCurrent
            let h = cal.component(.hour, from: newMinuteAnchor)
            let m = cal.component(.minute, from: newMinuteAnchor)

            let lagMs = Int((wallNow2.timeIntervalSince(newMinuteAnchor) * 1000.0).rounded())

            let ok = (!isPrerender2) ? 1 : 0

            WWClockDebugLog.appendLazySync(
                category: "clock",
                throttleID: balloon ? nil : "clockWidget.minute",
                minInterval: balloon ? 0.0 : 60.0,
                now: now
            ) {
                "minuteTick build=\(WidgetWeaverClockWidgetLiveView.buildLabel) hm=\(h):\(String(format: "%02d", m)) handsRef=\(minuteRef) lagMs=\(lagMs) ok=\(ok)"
            }
        }
    }

    static func wallClockSignatureSeconds(now: Date, uptime: TimeInterval) -> Int {
        WidgetWeaverClockWidgetLiveView.wallClockSignatureSeconds(now: now, uptime: uptime)
    }
}

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hourInt = Double((comps.hour ?? 0) % 12)
        let minuteInt = Double(comps.minute ?? 0)
        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        // Hour: includes minute contribution (minute tick style).
        let hourValue = hourInt + (minuteInt / 60.0)
        hour = hourValue * 30.0

        // Minute: tick (snapped to minute boundary by caller).
        minute = minuteInt * 6.0
    }
}

private struct WWClockSecondsDriverText: View {
    let timerRange: ClosedRange<Date>

    var body: some View {
        Text(timerInterval: timerRange, countsDown: false)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .font(.system(size: 8, weight: .regular, design: .monospaced))
            .foregroundStyle(Color.clear)
            .unredacted()
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 1, maxHeight: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}

private struct WWClockDynamicHandID: Hashable {
    let anchorRef: Int
    let refreshToken: Int
    let kind: Int

    init(anchorRef: Int, refreshToken: Int, kind: Int) {
        self.anchorRef = anchorRef
        self.refreshToken = refreshToken
        self.kind = kind
    }
}

private struct WWClockSecondsAndHubOverlay: View {
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette

    let showsMinuteHand: Bool
    let minuteTimerRange: ClosedRange<Date>

    let showsSeconds: Bool
    let timerRange: ClosedRange<Date>

    let handsOpacity: Double
    let refreshToken: Int

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(face: face, size: proxy.size, scale: displayScale)

            let dialDiameter = layout.dialDiameter
            let hubBaseRadius = layout.hubBaseRadius
            let hubCapRadius = layout.hubCapRadius

            let minuteAnchorRef = Int(minuteTimerRange.lowerBound.timeIntervalSinceReferenceDate.rounded())
            let secondAnchorRef = Int(timerRange.lowerBound.timeIntervalSinceReferenceDate.rounded())

            let minuteID = WWClockDynamicHandID(anchorRef: minuteAnchorRef, refreshToken: refreshToken, kind: 1)
            let secondID = WWClockDynamicHandID(anchorRef: secondAnchorRef, refreshToken: refreshToken, kind: 2)

            let secondHandColour: Color = {
                switch face {
                case .icon:
                    return palette.iconSecondHand
                case .segmented:
                    return WWClock.colour(0xE5D05A, alpha: 1.0)
                case .ceramic:
                    return palette.accent
                }
            }()

            ZStack {
                if showsMinuteHand {
                    WWClockMinuteHandGlyphView(
                        face: face,
                        palette: palette,
                        timerRange: minuteTimerRange,
                        diameter: dialDiameter
                    )
                    .id(minuteID)
                    .opacity(handsOpacity)
                }

                if showsSeconds {
                    WWClockSecondHandGlyphView(
                        palette: palette,
                        colour: secondHandColour,
                        timerRange: timerRange,
                        diameter: dialDiameter
                    )
                    .id(secondID)
                    .opacity(handsOpacity)
                }

                Group {
                    if face == .segmented {
                        WidgetWeaverClockSegmentedCentreHubView(
                            palette: palette,
                            baseRadius: hubBaseRadius,
                            capRadius: hubCapRadius,
                            scale: displayScale
                        )
                    } else {
                        WidgetWeaverClockCentreHubView(
                            palette: palette,
                            baseRadius: hubBaseRadius,
                            capRadius: hubCapRadius,
                            scale: displayScale
                        )
                    }
                }
                .opacity(handsOpacity)
            }
            .frame(width: dialDiameter, height: dialDiameter, alignment: .center)
            .clipShape(Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct WWClockMinuteHandGlyphView: View {
    let face: WidgetWeaverClockFaceToken
    let palette: WidgetWeaverClockPalette
    let timerRange: ClosedRange<Date>
    let diameter: CGFloat

    private func glyphFont() -> Font {
        if face == .icon, WWClockMinuteHandIconFont.isAvailable() {
            return WWClockMinuteHandIconFont.font(size: diameter)
        }
        return WWClockMinuteHandFont.font(size: diameter)
    }

    private func glyph() -> some View {
        Text(timerInterval: timerRange, countsDown: false)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .font(glyphFont())
            .unredacted()
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(width: diameter, height: diameter, alignment: .center)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { transaction in
                transaction.animation = nil
            }
    }

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

        ZStack {
            // Edge stroke approximation:
            // Draw the glyph in edge colour, then inset the fill slightly.
            glyph()
                .foregroundStyle(palette.handEdge)

            metalField
                .mask(
                    glyph()
                        .foregroundStyle(Color.white)
                        .scaleEffect(0.94, anchor: .center)
                )
        }
        .frame(width: diameter, height: diameter, alignment: .center)
    }
}

private struct WWClockSecondHandGlyphView: View {
    let palette: WidgetWeaverClockPalette
    let colour: Color
    let timerRange: ClosedRange<Date>
    let diameter: CGFloat

    var body: some View {
        Text(timerInterval: timerRange, countsDown: false)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .font(WWClockSecondHandFont.font(size: diameter))
            .foregroundStyle(colour)
            .unredacted()
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .frame(width: diameter, height: diameter, alignment: .center)
            .shadow(color: palette.handShadow, radius: diameter * 0.012, x: 0, y: diameter * 0.006)
            .shadow(color: colour.opacity(0.35), radius: diameter * 0.018, x: 0, y: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transaction { transaction in
                transaction.animation = nil
            }
    }
}

private struct WWClockDialLayout {
    let dialDiameter: CGFloat
    let hubBaseRadius: CGFloat
    let hubCapRadius: CGFloat

    init(face: WidgetWeaverClockFaceToken, size: CGSize, scale: CGFloat) {
        let s = min(size.width, size.height)

        let outerDiameter = WWClock.outerBezelDiameter(containerSide: s, scale: scale)
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

        switch face {
        case .icon:
            hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.034, min: R * 0.030, max: R * 0.040),
                scale: scale
            )

            hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: scale
            )

        case .ceramic:
            hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
                scale: scale
            )

            hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: scale
            )

        case .segmented:
            let base = WWClock.pixel(
                WWClock.clamp(R * 0.085, min: R * 0.070, max: R * 0.095),
                scale: scale
            )

            hubBaseRadius = base

            hubCapRadius = WWClock.pixel(
                WWClock.clamp(base * 0.50, min: base * 0.42, max: base * 0.58),
                scale: scale
            )
        }
    }
}
