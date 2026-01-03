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

            let wallNow = Date()
            let isPreRender = entryDate.timeIntervalSince(wallNow) > 5.0

            // Hour/minute hands:
            // Run compositor-backed sweeps so the minute hand is aligned to the real clock even if
            // WidgetKit swaps timeline entries slightly late.
            //
            // Reduce Motion is intentionally NOT used to disable this, because doing so reintroduces
            // the late “minute tick” behaviour.
            let liveHandsEnabled = showSeconds && !isPlaceholder && !isPreRender

            let tickAnchor = Self.floorToMinute(entryDate)
            let tick = WWClockTickAngles(date: tickAnchor)

            let smooth = WWClockSmoothAngles(date: baseDate)

            let minuteDeg = liveHandsEnabled ? (smooth.minute + (minutePhase * 360.0)) : tick.minute
            let hourDeg = liveHandsEnabled ? (smooth.hour + (hourPhase * 360.0)) : tick.hour

            let fontOK = WWClockSecondHandFont.isAvailable()
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
                let anchorRef = Int(secondsMinuteAnchor.timeIntervalSinceReferenceDate.rounded())
                let startRef = Int(timerStart.timeIntervalSinceReferenceDate.rounded())
                let endRef = Int(timerEnd.timeIntervalSinceReferenceDate.rounded())
                let wallMinusEntry = Int((wallNow.timeIntervalSince(entryDate)).rounded())

                return "render entryRef=\(entryRef) wallRef=\(wallRef) wall-entry=\(wallMinusEntry)s mode=\(tickMode) sec=\(showSeconds ? 1 : 0) liveHands=\(liveHandsEnabled ? 1 : 0) redact=\(redactLabel) font=\(fontOK ? 1 : 0) dt=\(dynamicTypeSize) rm=\(reduceMotion ? 1 : 0) anchorRef=\(anchorRef) rangeRef=\(startRef)...\(endRef) expected=\(expectedString)"
            }

            ZStack {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(hourDeg),
                    minuteAngle: .degrees(minuteDeg),
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
            .widgetURL(URL(string: "widgetweaver://clock"))
            .onAppear {
                if liveHandsEnabled {
                    DispatchQueue.main.async {
                        syncAndStartIfNeeded()
                    }
                }
            }
            .task {
                if liveHandsEnabled {
                    DispatchQueue.main.async {
                        syncAndStartIfNeeded()
                    }
                }
            }
        }
    }

    private func syncAndStartIfNeeded() {
        let now = Date()

        // Start once per view lifetime, but also re-sync if the anchor is stale.
        let shouldResync = (!started) || (abs(now.timeIntervalSince(baseDate)) > 1.0)
        guard shouldResync else { return }

        started = true
        baseDate = now

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

// MARK: - Tick angles (minute boundary)

private struct WWClockTickAngles {
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

// MARK: - Smooth angles (wall-clock sweep)

private struct WWClockSmoothAngles {
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

        self.minute = (minuteInt + sec / 60.0) * 6.0
        self.hour = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
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
