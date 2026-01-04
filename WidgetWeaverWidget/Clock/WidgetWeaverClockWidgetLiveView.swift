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

    private static let timerStartBiasSeconds: TimeInterval = 0.25

    /// Keeps the seconds hand moving even if the next WidgetKit minute entry arrives late.
    /// Requires the ligature font to support `1:SS` in addition to `0:SS`.
    private static let minuteSpilloverSeconds: TimeInterval = 59.0

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPrivacy = redactionReasons.contains(.privacy)
            let isPlaceholder = redactionReasons.contains(.placeholder)

            let handsOpacity: Double = isPrivacy ? 0.85 : 1.0
            let showSeconds = (tickMode == .secondsSweep)

            if isPlaceholder {
                // Keep placeholder rendering extremely cheap so a cold widget never shows as a black tile.
                WWClockPlaceholderView(palette: palette, handsOpacity: handsOpacity)
                    .widgetURL(URL(string: "widgetweaver://clock"))
            } else {
                // Seconds anchor:
                // - Use the entry minute so WidgetKit pre-rendering stays deterministic.
                // - Permit spillover so late minute delivery does not freeze the seconds hand.
                let secondsMinuteAnchor = Self.floorToMinute(entryDate)
                let timerStart = secondsMinuteAnchor.addingTimeInterval(-Self.timerStartBiasSeconds)
                let timerEnd = secondsMinuteAnchor.addingTimeInterval(60.0 + Self.minuteSpilloverSeconds)
                let timerRange = timerStart...timerEnd

                // Trigger font registration once per render pass (useful for logs).
                let fontOK = showSeconds ? WWClockSecondHandFont.isAvailable() : true

                let redactLabel: String = {
                    if isPlaceholder && isPrivacy { return "placeholder+privacy" }
                    if isPlaceholder { return "placeholder" }
                    if isPrivacy { return "privacy" }
                    return "none"
                }()

                // Lightweight render log (throttled).
                let _ = WWClockDebugLog.appendLazy(
                    category: "clock",
                    throttleID: "clockWidget.render",
                    minInterval: 30.0,
                    now: Date()
                ) {
                    let sysNow = Date()

                    let entryRef = Int(entryDate.timeIntervalSinceReferenceDate.rounded())
                    let wallRef = Int(sysNow.timeIntervalSinceReferenceDate.rounded())
                    let wallMinusEntry = Int((sysNow.timeIntervalSince(entryDate)).rounded())

                    let anchorRef = Int(secondsMinuteAnchor.timeIntervalSinceReferenceDate.rounded())
                    let startRef = Int(timerStart.timeIntervalSinceReferenceDate.rounded())
                    let endRef = Int(timerEnd.timeIntervalSinceReferenceDate.rounded())

                    let expectedSeconds = Calendar.autoupdatingCurrent.component(.second, from: sysNow)
                    let expectedString = String(format: "0:%02d", expectedSeconds)

                    return "render entryRef=\(entryRef) wallRef=\(wallRef) wall-entry=\(wallMinusEntry)s mode=\(tickMode) sec=\(showSeconds ? 1 : 0) redact=\(redactLabel) font=\(fontOK ? 1 : 0) rm=\(reduceMotion ? 1 : 0) anchorRef=\(anchorRef) rangeRef=\(startRef)...\(endRef) expected=\(expectedString)"
                }

                ZStack {
                    // Hour + minute hands:
                    // Driven by WidgetKit timeline entries (per-minute), with an optional
                    // linear sweep to the next minute boundary when displayed live.
                    WWClockAnimatedHandsDialView(
                        palette: palette,
                        startDate: entryDate,
                        handsOpacity: handsOpacity,
                        reduceMotion: reduceMotion
                    )

                    // Seconds hand glyph + hub overlay.
                    // Driven by `Text(timerInterval:)` and does not require frequent timeline reloads.
                    WWClockSecondsAndHubOverlay(
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
                        entryDate: entryDate,
                        minuteAnchor: secondsMinuteAnchor,
                        timerRange: timerRange,
                        showSeconds: showSeconds,
                        tickModeLabel: showSeconds ? "secondsSweep" : "minuteOnly"
                    )
                    .padding(6)
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

// MARK: - Cheap placeholder (prevents black tiles)

private struct WWClockPlaceholderView: View {
    let palette: WidgetWeaverClockPalette
    let handsOpacity: Double

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let dialSide = side * 0.82
            let radius = dialSide * 0.5

            let hourLength = radius * 0.56
            let hourWidth = max(2, radius * 0.10)

            let minuteLength = radius * 0.78
            let minuteWidth = max(2, radius * 0.075)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.dialCenter, location: 0.00),
                                .init(color: palette.dialMid, location: 0.65),
                                .init(color: palette.dialEdge, location: 1.00)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: radius
                        )
                    )
                    .frame(width: dialSide, height: dialSide)

                Capsule(style: .continuous)
                    .fill(palette.handMid.opacity(handsOpacity))
                    .frame(width: hourWidth, height: hourLength)
                    .offset(y: -hourLength * 0.5)
                    .rotationEffect(.degrees(310), anchor: .bottom)

                Capsule(style: .continuous)
                    .fill(palette.handLight.opacity(handsOpacity))
                    .frame(width: minuteWidth, height: minuteLength)
                    .offset(y: -minuteLength * 0.5)
                    .rotationEffect(.degrees(35), anchor: .bottom)

                Circle()
                    .fill(palette.hubBase.opacity(handsOpacity))
                    .frame(width: radius * 0.18, height: radius * 0.18)
                    .shadow(color: palette.hubShadow.opacity(0.55), radius: radius * 0.05, x: radius * 0.02, y: radius * 0.02)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Animated hour + minute hands (timeline driven, budget-safe)

private struct WWClockAnimatedHandsDialView: View {
    let palette: WidgetWeaverClockPalette

    /// WidgetKit entry date (deterministic for pre-rendered snapshots).
    ///
    /// When actually displayed, the view uses `Date()` to avoid “late by 1–2s” minute jumps.
    let startDate: Date

    let handsOpacity: Double
    let reduceMotion: Bool

    @State private var hourDegrees: Double
    @State private var minuteDegrees: Double

    init(
        palette: WidgetWeaverClockPalette,
        startDate: Date,
        handsOpacity: Double,
        reduceMotion: Bool
    ) {
        self.palette = palette
        self.startDate = startDate
        self.handsOpacity = handsOpacity
        self.reduceMotion = reduceMotion

        let base = WWClockBaseAngles(date: startDate)
        _hourDegrees = State(initialValue: base.hour)
        _minuteDegrees = State(initialValue: base.minute)
    }

    var body: some View {
        let hourAngle = Angle.degrees(hourDegrees)
        let minuteAngle = Angle.degrees(minuteDegrees)

        // Glows + hand shadows are intentionally disabled here to keep widget rendering fast
        // and to avoid cold-start “black tile” behaviour.
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
        .onAppear {
            DispatchQueue.main.async {
                updateHands(reason: "appear")
            }
        }
        .task {
            DispatchQueue.main.async {
                updateHands(reason: "task")
            }
        }
        .onChange(of: startDate) { _, _ in
            DispatchQueue.main.async {
                updateHands(reason: "entryChange")
            }
        }
    }

    private func updateHands(reason: String) {
        let wallNow = Date()

        // When WidgetKit pre-renders future entries, stick to `startDate` and do not animate.
        let isPrerender = startDate.timeIntervalSince(wallNow) > 0.25

        let renderStartDate = isPrerender ? startDate : wallNow
        let nextBoundary = Self.nextMinuteBoundary(after: renderStartDate)

        var duration = nextBoundary.timeIntervalSince(renderStartDate)
        if duration.isNaN || duration.isInfinite { duration = 0.0 }
        duration = max(0.0, duration)

        let startAngles = WWClockBaseAngles(date: renderStartDate)
        let endAnglesRaw = WWClockBaseAngles(date: nextBoundary)

        var endHour = endAnglesRaw.hour
        var endMinute = endAnglesRaw.minute

        // Unwrap across 360° so the hands always move forward.
        if endHour <= startAngles.hour { endHour += 360.0 }
        if endMinute <= startAngles.minute { endMinute += 360.0 }

        withAnimation(.none) {
            hourDegrees = startAngles.hour
            minuteDegrees = startAngles.minute
        }

        if (!reduceMotion) && (!isPrerender) && duration > 0.05 {
            withAnimation(.linear(duration: duration)) {
                hourDegrees = endHour
                minuteDegrees = endMinute
            }
        }

        WWClockDebugLog.appendLazy(
            category: "clock",
            throttleID: "clock.hands.timeline",
            minInterval: 20.0,
            now: wallNow
        ) {
            let entryRef = Int(startDate.timeIntervalSinceReferenceDate.rounded())
            let wallRef = Int(wallNow.timeIntervalSinceReferenceDate.rounded())
            let startRef = Int(renderStartDate.timeIntervalSinceReferenceDate.rounded())
            let nextRef = Int(nextBoundary.timeIntervalSinceReferenceDate.rounded())

            let wallMinusEntry = Int((wallNow.timeIntervalSince(startDate)).rounded())
            let durMs = Int((duration * 1000.0).rounded())

            let h0 = Int(startAngles.hour.rounded())
            let h1 = Int(endHour.rounded())
            let m0 = Int(startAngles.minute.rounded())
            let m1 = Int(endMinute.rounded())

            return "hands.timeline reason=\(reason) entryRef=\(entryRef) wallRef=\(wallRef) wall-entry=\(wallMinusEntry)s prerender=\(isPrerender ? 1 : 0) rm=\(reduceMotion ? 1 : 0) startRef=\(startRef) nextRef=\(nextRef) durMs=\(durMs) h=\(h0)→\(h1) m=\(m0)→\(m1)"
        }
    }

    private static func nextMinuteBoundary(after date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        let minuteAnchor = Date(timeIntervalSinceReferenceDate: floored)
        return minuteAnchor.addingTimeInterval(60.0)
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

        // Hour hand: 360° per 12 hours.
        self.hour = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0

        // Minute hand: 360° per hour.
        self.minute = (minuteInt + sec / 60.0) * 6.0
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
