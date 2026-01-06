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

    /// Home Screen widgets are not guaranteed to flip timeline entries exactly at their scheduled
    /// dates. When that happens, hour/minute hands that only update on entry boundaries can appear
    /// to “tick late”.
    ///
    /// Using a `TimelineView` provides an internal, lightweight per-second invalidation mechanism
    /// that keeps the hands in sync with wall-clock time even if WidgetKit delays swapping entries.
    private static let handsUpdateIntervalSeconds: TimeInterval = 1.0

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPrivacy = redactionReasons.contains(.privacy)
            let isPlaceholder = redactionReasons.contains(.placeholder)

            // `WidgetWeaverRenderClock.now` is the entry date pinned for the current render pass.
            // This must remain stable in pre-rendered snapshots.
            let ctxNow = WidgetWeaverRenderClock.now
            let scheduleStart = Self.floorToSecond(ctxNow)

            // Respect redaction previews by keeping them deterministic and static.
            let allowLiveUpdates = !(isPlaceholder || isPrivacy)

            let includeSecondsInHands = (tickMode == .secondsSweep) && !reduceMotion
            let showSeconds = (tickMode == .secondsSweep) && !reduceMotion

            let handsOpacity: Double = isPrivacy ? 0.85 : 1.0

            if allowLiveUpdates {
                TimelineView(.periodic(from: scheduleStart, by: Self.handsUpdateIntervalSeconds)) { timelineContext in
                    let wallNow = Date()
                    let scheduledNow = timelineContext.date

                    // When WidgetKit pre-renders a future entry, `Date()` is ahead/behind the entry.
                    // Freeze to the entry time until wall-clock catches up.
                    let frozen = wallNow < ctxNow
                    let renderNow = frozen ? ctxNow : min(scheduledNow, wallNow)

                    self.clockContent(
                        ctxNow: ctxNow,
                        renderNow: renderNow,
                        wallNow: wallNow,
                        scheduledNow: scheduledNow,
                        frozen: frozen,
                        handsOpacity: handsOpacity,
                        showSeconds: showSeconds,
                        includeSecondsInHands: includeSecondsInHands,
                        isPlaceholder: isPlaceholder,
                        isPrivacy: isPrivacy
                    )
                }
            } else {
                let wallNow = Date()

                self.clockContent(
                    ctxNow: ctxNow,
                    renderNow: ctxNow,
                    wallNow: wallNow,
                    scheduledNow: nil,
                    frozen: true,
                    handsOpacity: handsOpacity,
                    showSeconds: showSeconds,
                    includeSecondsInHands: includeSecondsInHands,
                    isPlaceholder: isPlaceholder,
                    isPrivacy: isPrivacy
                )
            }
        }
    }

    @ViewBuilder
    private func clockContent(
        ctxNow: Date,
        renderNow: Date,
        wallNow: Date,
        scheduledNow: Date?,
        frozen: Bool,
        handsOpacity: Double,
        showSeconds: Bool,
        includeSecondsInHands: Bool,
        isPlaceholder: Bool,
        isPrivacy: Bool
    ) -> some View {
        let baseAngles = WWClockBaseAngles(date: renderNow, includeSeconds: includeSecondsInHands)
        let hourAngle = Angle.degrees(baseAngles.hour)
        let minuteAngle = Angle.degrees(baseAngles.minute)

        // Seconds anchor:
        // - Re-anchor every minute to avoid leaving the supported glyph range.
        // - Permit spillover so late minute delivery does not freeze the seconds hand.
        let secondsMinuteAnchor = Self.floorToMinute(renderNow)
        let timerStart = secondsMinuteAnchor.addingTimeInterval(-Self.timerStartBiasSeconds)
        let timerEnd = secondsMinuteAnchor.addingTimeInterval(60.0 + Self.minuteSpilloverSeconds)
        let timerRange = timerStart...timerEnd

        // Trigger font registration once per render pass (useful for logs).
        let fontOK = showSeconds ? WWClockSecondHandFont.isAvailable() : true

        // Lightweight render log (throttled).
        let _ = WWClockDebugLog.appendLazy(
            category: "clock",
            throttleID: "clockWidget.render",
            minInterval: 30.0,
            now: wallNow
        ) {
            let cal = Calendar.autoupdatingCurrent

            let ctxRef = Int(ctxNow.timeIntervalSinceReferenceDate.rounded())
            let wallRef = Int(wallNow.timeIntervalSinceReferenceDate.rounded())
            let schedRef = Int((scheduledNow ?? wallNow).timeIntervalSinceReferenceDate.rounded())
            let renderRef = Int(renderNow.timeIntervalSinceReferenceDate.rounded())

            let leadSeconds = ctxNow.timeIntervalSince(wallNow)
            let leadMs = Int((leadSeconds * 1000.0).rounded())

            let wallMinusRender = Int((wallNow.timeIntervalSince(renderNow)).rounded())

            let entryH = cal.component(.hour, from: renderNow)
            let entryM = cal.component(.minute, from: renderNow)
            let entryS = cal.component(.second, from: renderNow)

            let minuteBoundary = abs(renderNow.timeIntervalSince(secondsMinuteAnchor)) < 0.001

            let hDeg = Int(baseAngles.hour.rounded())
            let mDeg = Int(baseAngles.minute.rounded())

            let anchorRef = Int(secondsMinuteAnchor.timeIntervalSinceReferenceDate.rounded())
            let startRef = Int(timerStart.timeIntervalSinceReferenceDate.rounded())
            let endRef = Int(timerEnd.timeIntervalSinceReferenceDate.rounded())

            let expectedSeconds = cal.component(.second, from: wallNow)
            let expectedString = String(format: "0:%02d", expectedSeconds)

            let redactLabel: String = {
                if isPlaceholder && isPrivacy { return "placeholder+privacy" }
                if isPlaceholder { return "placeholder" }
                if isPrivacy { return "privacy" }
                return "none"
            }()

            let live = frozen ? 0 : 1

            return "render ctxRef=\(ctxRef) wallRef=\(wallRef) schedRef=\(schedRef) leadMs=\(leadMs) live=\(live) frozen=\(frozen ? 1 : 0) entryRef=\(renderRef) wall-entry=\(wallMinusRender)s entryHMS=\(entryH):\(entryM):\(entryS) onMinute=\(minuteBoundary ? 1 : 0) hDeg=\(hDeg) mDeg=\(mDeg) mode=\(tickMode) sec=\(showSeconds ? 1 : 0) redact=\(redactLabel) font=\(fontOK ? 1 : 0) rm=\(reduceMotion ? 1 : 0) anchorRef=\(anchorRef) rangeRef=\(startRef)...\(endRef) expected=\(expectedString)"
        }

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
            .id(secondsMinuteAnchor)
            .transition(.identity)
            .transaction { transaction in
                transaction.animation = nil
            }

            // Seconds hand glyph + hub overlay.
            // Driven by `Text(timerInterval:)`.
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
                entryDate: renderNow,
                minuteAnchor: secondsMinuteAnchor,
                timerRange: timerRange,
                showSeconds: showSeconds,
                tickModeLabel: showSeconds ? "secondsSweep" : "minuteOnly"
            )
            .padding(6)
        }
        #endif
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }

    private static func floorToSecond(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t)
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date, includeSeconds: Bool) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = includeSeconds ? (secondInt + (nano / 1_000_000_000.0)) : 0.0
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
