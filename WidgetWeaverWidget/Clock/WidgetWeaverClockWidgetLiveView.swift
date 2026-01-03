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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var baseDate: Date
    @State private var started: Bool = false

    @State private var minutePhase: Double = 0
    @State private var hourPhase: Double = 0

    private static let timerStartBiasSeconds: TimeInterval = 0.25

    /// Maximum safe spillover: the seconds-hand font only contains ligatures for `0:SS` and `1:SS`.
    /// Allowing almost a full extra minute keeps the seconds hand moving even if the next WidgetKit
    /// minute entry arrives late.
    private static let minuteSpilloverSeconds: TimeInterval = 59.0

    /// Minute-hand style:
    /// - `.tick` keeps the existing “quartz” behaviour (jumps once per minute),
    ///   but is driven by a compositor animation so it stays on-time even if the
    ///   WidgetKit minute-boundary entry is displayed late.
    /// - `.sweep` is continuous.
    private static let minuteHandStyle: WWClockHandStyle = .tick

    /// Hour hand stays smooth.
    private static let hourHandStyle: WWClockHandStyle = .sweep

    init(
        palette: WidgetWeaverClockPalette,
        entryDate: Date,
        tickMode: WidgetWeaverClockTickMode,
        tickSeconds: TimeInterval
    ) {
        self.palette = palette
        self.entryDate = entryDate
        self.tickMode = tickMode
        self.tickSeconds = tickSeconds

        let wallNow = Date()
        let initialBase = (entryDate > wallNow) ? entryDate : wallNow
        _baseDate = State(initialValue: initialBase)
    }

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPrivacy = redactionReasons.contains(.privacy)
            let isPlaceholder = redactionReasons.contains(.placeholder)

            let handsOpacity: Double = isPrivacy ? 0.85 : 1.0
            let showSeconds = (tickMode == .secondsSweep)

            // Seconds hand anchor:
            // - Use the timeline entry minute so WidgetKit pre-rendering stays deterministic.
            // - Permit a large spillover so late minute delivery does not freeze the hand.
            let secondsMinuteAnchor = Self.floorToMinute(entryDate)

            let timerStart = secondsMinuteAnchor.addingTimeInterval(-Self.timerStartBiasSeconds)
            let timerEnd = secondsMinuteAnchor.addingTimeInterval(60.0 + Self.minuteSpilloverSeconds)
            let timerRange = timerStart...timerEnd

            // Base angles for the non-animated fallback.
            let tickAnchor = Self.floorToMinute(entryDate)
            let tick = WWClockTickAngles(date: tickAnchor)

            // Animated hands are enabled in seconds mode.
            // The entire point is to stop depending on WidgetKit’s “minute boundary entry swap” timing,
            // which can be 1–2 seconds late on Home Screen.
            let animateHands = showSeconds

            let smoothBase = WWClockSmoothAngles(date: baseDate)
            let baseTime = WWClockBaseTime(date: baseDate)

            let animatedMinuteDeg: Double = {
                guard animateHands else { return tick.minute }

                switch Self.minuteHandStyle {
                case .sweep:
                    return smoothBase.minute + (minutePhase * 360.0)
                case .tick:
                    let elapsedSeconds = minutePhase * 3600.0
                    let totalSeconds = baseTime.secondsIntoHour + elapsedSeconds
                    let minuteIndex = floor(totalSeconds / 60.0)
                        .truncatingRemainder(dividingBy: 60.0)
                    return minuteIndex * 6.0
                }
            }()

            let animatedHourDeg: Double = {
                guard animateHands else { return tick.hour }

                switch Self.hourHandStyle {
                case .sweep:
                    return smoothBase.hour + (hourPhase * 360.0)
                case .tick:
                    // Not used (hour is kept smooth), but keep a deterministic implementation anyway.
                    // Tick the hour hand each minute.
                    let elapsedSeconds = hourPhase * 43200.0
                    let totalSeconds = baseTime.secondsIntoHalfDay + elapsedSeconds
                    let hourIndex = floor(totalSeconds / 3600.0)
                        .truncatingRemainder(dividingBy: 12.0)
                    let minuteIntoHour = floor(totalSeconds.truncatingRemainder(dividingBy: 3600.0) / 60.0)
                    return (hourIndex + minuteIntoHour / 60.0) * 30.0
                }
            }()

            let fontOK = WWClockSecondHandFont.isAvailable()

            let wallNow = Date()
            let expectedSeconds = Calendar.autoupdatingCurrent.component(.second, from: wallNow)
            let expectedString = String(format: "0:%02d", expectedSeconds)

            let redactLabel: String = {
                if isPlaceholder && isPrivacy { return "placeholder+privacy" }
                if isPlaceholder { return "placeholder" }
                if isPrivacy { return "privacy" }
                return "none"
            }()

            // IMPORTANT: side-effect call must be bound, otherwise @ViewBuilder tries to treat () as a View.
            let _ = WWClockDebugLog.appendLazy(
                category: "clock",
                throttleID: "clockWidget.render",
                minInterval: 30.0,
                now: wallNow
            ) {
                let entryRef = Int(entryDate.timeIntervalSinceReferenceDate.rounded())
                let wallRef = Int(wallNow.timeIntervalSinceReferenceDate.rounded())
                let baseRef = Int(baseDate.timeIntervalSinceReferenceDate.rounded())

                let anchorRef = Int(secondsMinuteAnchor.timeIntervalSinceReferenceDate.rounded())
                let startRef = Int(timerStart.timeIntervalSinceReferenceDate.rounded())
                let endRef = Int(timerEnd.timeIntervalSinceReferenceDate.rounded())

                let wallMinusEntry = Int((wallNow.timeIntervalSince(entryDate)).rounded())

                return "render entryRef=\(entryRef) wallRef=\(wallRef) wall-entry=\(wallMinusEntry)s mode=\(tickMode) sec=\(showSeconds ? 1 : 0) anim=\(animateHands ? 1 : 0) started=\(started ? 1 : 0) baseRef=\(baseRef) redact=\(redactLabel) font=\(fontOK ? 1 : 0) dt=\(dynamicTypeSize) rm=\(reduceMotion ? 1 : 0) anchorRef=\(anchorRef) rangeRef=\(startRef)...\(endRef) expected=\(expectedString)"
            }

            ZStack {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(animatedHourDeg),
                    minuteAngle: .degrees(animatedMinuteDeg),
                    secondAngle: .degrees(0.0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: false,
                    handsOpacity: handsOpacity
                )

                // Heartbeat:
                // A tiny timer-style Text keeps the widget host in a “live” rendering mode.
                // This helps compositor-backed repeatForever rotations keep running on the Home Screen.
                if animateHands {
                    WWClockWidgetHeartbeat(start: baseDate)
                }

                WWClockSecondsAndHubOverlay(
                    palette: palette,
                    showsSeconds: showSeconds,
                    timerRange: timerRange,
                    handsOpacity: handsOpacity
                )
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
            .onAppear {
                if animateHands {
                    DispatchQueue.main.async {
                        syncAndStartIfNeeded()
                    }
                }
            }
            .task {
                if animateHands {
                    DispatchQueue.main.async {
                        syncAndStartIfNeeded()
                    }
                }
            }
        }
    }

    private func syncAndStartIfNeeded() {
        let wallNow = Date()
        let anchoredNow = (wallNow > entryDate) ? wallNow : entryDate

        // Start once per view lifetime, but also re-sync if the anchor is stale.
        let shouldResync = (!started) || (abs(anchoredNow.timeIntervalSince(baseDate)) > 1.0)
        guard shouldResync else { return }

        started = true
        baseDate = anchoredNow

        withAnimation(.none) {
            minutePhase = 0
            hourPhase = 0
        }

        // CoreAnimation-backed infinite sweeps.
        withAnimation(.linear(duration: 3600.0).repeatForever(autoreverses: false)) {
            minutePhase = 1
        }
        withAnimation(.linear(duration: 43200.0).repeatForever(autoreverses: false)) {
            hourPhase = 1
        }
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

// MARK: - Heartbeat

private struct WWClockWidgetHeartbeat: View {
    let start: Date

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .font(.system(size: 1, weight: .regular, design: .monospaced))
            .monospacedDigit()
            .foregroundStyle(Color.primary.opacity(0.001))
            .frame(width: 1, height: 1, alignment: .center)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private enum WWClockHandStyle {
    case sweep
    case tick
}

// MARK: - Angle helpers

private struct WWClockTickAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let hour = Double(comps.hour ?? 0).truncatingRemainder(dividingBy: 12.0)
        let minute = Double(comps.minute ?? 0)

        self.minute = minute * 6.0
        self.hour = (hour + minute / 60.0) * 30.0
    }
}

private struct WWClockBaseTime {
    let secondsIntoHour: Double
    let secondsIntoHalfDay: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        let minute = Double(comps.minute ?? 0)
        let second = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = second + nano / 1_000_000_000.0

        self.secondsIntoHour = (minute * 60.0) + sec
        self.secondsIntoHalfDay = (hour12 * 3600.0) + (minute * 60.0) + sec
    }
}

private struct WWClockSmoothAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour = Double(comps.hour ?? 0).truncatingRemainder(dividingBy: 12.0)
        let minute = Double(comps.minute ?? 0)
        let second = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = second + nano / 1_000_000_000.0
        let minuteValue = minute + sec / 60.0
        let hourValue = hour + minuteValue / 60.0

        self.minute = minuteValue * 6.0
        self.hour = hourValue * 30.0
    }
}

// MARK: - Seconds overlay + hub

private struct WWClockSecondsAndHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let showsSeconds: Bool
    let timerRange: ClosedRange<Date>
    let handsOpacity: Double

    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        ZStack {
            if showsSeconds {
                WWClockSecondHandGlyphView(timerRange: timerRange)
                    .transition(.opacity)
            }

            WWClockCentreHubOverlay(palette: palette)
                .opacity(handsOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct WWClockSecondHandGlyphView: View {
    let timerRange: ClosedRange<Date>

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let fontSize = s * 0.92

            Text(timerInterval: timerRange, countsDown: false)
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .font(WWClockSecondHandFont.font(size: fontSize))
                .minimumScaleFactor(0.01)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .compositingGroup()
        .opacity(0.98)
    }
}

private struct WWClockCentreHubOverlay: View {
    let palette: WidgetWeaverClockPalette

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let outerDiameter = WWClock.pixel(s * 0.925, scale: displayScale)
            let outerRadius = outerDiameter * 0.5

            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            let ringA = WWClock.pixel(provisionalR * 0.010, scale: displayScale)
            let ringC = WWClock.pixel(
                WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
                scale: displayScale
            )
            let minB = WWClock.px(scale: displayScale)
            let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: displayScale)

            let R = outerRadius - ringA - ringB - ringC

            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
                scale: displayScale
            )
            let hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: displayScale
            )

            WidgetWeaverClockCentreHubView(
                palette: palette,
                baseRadius: hubBaseRadius,
                capRadius: hubCapRadius,
                scale: displayScale
            )
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}
