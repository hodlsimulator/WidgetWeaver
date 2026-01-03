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

    private static let timerStartBiasSeconds: TimeInterval = 0.25
    private static let minuteSpilloverSeconds: TimeInterval = 6.0

    /// How often (max) to re-evaluate minute/hour hands in seconds-sweep mode.
    /// This avoids relying on WidgetKit’s minute boundary delivery, which can be ~1–2s late.
    private static let liveHandsMinimumIntervalSeconds: TimeInterval = 0.25

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPrivacy = redactionReasons.contains(.privacy)
            let isPlaceholder = redactionReasons.contains(.placeholder)

            let handsOpacity: Double = isPrivacy ? 0.85 : 1.0
            let showSeconds = (tickMode == .secondsSweep)

            // Minute-only mode can remain budget-safe with a minute periodic tick.
            // Seconds-sweep mode uses an animation timeline (throttled) so the minute boundary is
            // observed promptly and the minute hand does not lag behind the live seconds hand.
            let scheduleStart = Self.floorToMinute(Date())

            Group {
                if showSeconds {
                    TimelineView(.animation(minimumInterval: Self.liveHandsMinimumIntervalSeconds, paused: false)) { timeline in
                        clockBody(
                            liveDate: timeline.date,
                            isPrivacy: isPrivacy,
                            isPlaceholder: isPlaceholder,
                            handsOpacity: handsOpacity,
                            showSeconds: showSeconds
                        )
                    }
                } else {
                    TimelineView(.periodic(from: scheduleStart, by: 60.0)) { timeline in
                        clockBody(
                            liveDate: timeline.date,
                            isPrivacy: isPrivacy,
                            isPlaceholder: isPlaceholder,
                            handsOpacity: handsOpacity,
                            showSeconds: showSeconds
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func clockBody(
        liveDate: Date,
        isPrivacy: Bool,
        isPlaceholder: Bool,
        handsOpacity: Double,
        showSeconds: Bool
    ) -> some View {
        // WidgetKit can pre-render future entries; never go earlier than the entry minute.
        let entryMinute = Self.floorToMinute(WidgetWeaverRenderClock.now)
        let liveMinute = Self.floorToMinute(liveDate)
        let minuteAnchor = Self.maxDate(entryMinute, liveMinute)

        let base = WWClockBaseAngles(date: minuteAnchor)

        // Seconds hand is driven by a time-aware SwiftUI timer text.
        // Allow a small spillover past the minute boundary so the hand can keep moving if a refresh
        // arrives slightly late (including across the hour).
        //
        // The ligature font maps both "0:SS" and "1:SS" to the same second-hand glyphs, so a short
        // "1:xx" spillover is safe and avoids freezing at 59.
        let timerStart = minuteAnchor.addingTimeInterval(-Self.timerStartBiasSeconds)
        let timerEnd = minuteAnchor.addingTimeInterval(60.0 + Self.minuteSpilloverSeconds)
        let timerRange = timerStart...timerEnd

        let minuteID = Int(minuteAnchor.timeIntervalSince1970 / 60.0)

        let wallNow = Date()
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
            let anchorRef = Int(minuteAnchor.timeIntervalSinceReferenceDate.rounded())
            let startRef = Int(timerStart.timeIntervalSinceReferenceDate.rounded())
            let endRef = Int(timerEnd.timeIntervalSinceReferenceDate.rounded())
            let wallMinusEntry = Int((wallNow.timeIntervalSince(entryDate)).rounded())

            return "render entryRef=\(entryRef) wallRef=\(wallRef) wall-entry=\(wallMinusEntry)s mode=\(tickMode) sec=\(showSeconds ? 1 : 0) redact=\(redactLabel) font=\(fontOK ? 1 : 0) dt=\(dynamicTypeSize) rm=\(reduceMotion ? 1 : 0) anchorRef=\(anchorRef) rangeRef=\(startRef)...\(endRef) expected=\(expectedString)"
        }

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
        .id(minuteID)
        .widgetURL(URL(string: "widgetweaver://clock"))
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }

    private static func maxDate(_ a: Date, _ b: Date) -> Date {
        (a > b) ? a : b
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
