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

    /// Keeps the seconds hand moving even if the next minute-boundary refresh arrives late.
    /// Requires the ligature font to support `1:SS` in addition to `0:SS`.
    private static let minuteSpilloverSeconds: TimeInterval = 59.0

    var body: some View {
        // WidgetKit can apply timeline entries slightly late.
        // A time-aware ProgressView acts as a lightweight “heartbeat” so hour/minute hands can
        // stay aligned to wall-clock time without requesting high-frequency widget timeline reloads.
        let progressRange = Self.progressDriverRange(anchor: entryDate)

        WidgetWeaverRenderClock.withNow(entryDate) {
            ProgressView(
                timerInterval: progressRange,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(.linear)
            .accessibilityHidden(true)
            // Keep the progress view practically invisible while still allowing it to drive updates.
            .opacity(0.001)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                let sysNow = Date()
                let ctxNow = WidgetWeaverRenderClock.now

                // WidgetKit can render a widget entry ahead-of-time.
                // In those cases, `Date()` reflects wall-clock time, but the render pass should use
                // the entry date. Keep pre-render deterministic by preferring `ctxNow`.
                let sysMinuteAnchor = Self.floorToMinute(sysNow)
                let ctxMinuteAnchor = Self.floorToMinute(ctxNow)
                let leadSeconds = ctxNow.timeIntervalSince(sysNow)

                // Two distinct pre-render cases must be handled:
                // 1) Far-future pre-render: ctxNow is many seconds/minutes ahead of sysNow.
                // 2) Near minute-boundary pre-render: ctxNow can be just past the next minute while sysNow is
                //    still in the previous minute (skew can be ~100–200ms). In that case, using sysNow
                //    produces a snapshot that is effectively “one minute behind” for the entry being rendered.
                let isPrerender = (leadSeconds > 5.0) || (ctxMinuteAnchor > sysMinuteAnchor)

                // Use wall-clock time when live, but fall back to the entry date when pre-rendering.
                let liveNow: Date = isPrerender ? ctxNow : sysNow

                // Tick-style hour + minute hands: snap to the minute boundary so the hands do not drift
                // between updates.
                let handsNow = Self.floorToMinute(liveNow)

                let isPrivacy = redactionReasons.contains(.privacy)
                let isPlaceholder = redactionReasons.contains(.placeholder)

                let handsOpacity: Double = isPrivacy ? 0.85 : 1.0
                let showSeconds = (tickMode == .secondsSweep)

                let baseAngles = WWClockBaseAngles(date: handsNow)
                let hourAngle = Angle.degrees(baseAngles.hour)
                let minuteAngle = Angle.degrees(baseAngles.minute)

                // Seconds anchor:
                // - Use the render minute so WidgetKit pre-rendering stays deterministic.
                // - Permit spillover so a late refresh does not freeze the seconds hand.
                let secondsMinuteAnchor = handsNow
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
                    now: sysNow
                ) {
                    let cal = Calendar.autoupdatingCurrent

                    let ctxRef = Int(ctxNow.timeIntervalSinceReferenceDate.rounded())
                    let sysRef = Int(sysNow.timeIntervalSinceReferenceDate.rounded())
                    let handsRef = Int(handsNow.timeIntervalSinceReferenceDate.rounded())

                    let ctxMinusSys = Int((ctxNow.timeIntervalSince(sysNow)).rounded())
                    let leadMs = Int((leadSeconds * 1000.0).rounded())

                    let handsH = cal.component(.hour, from: handsNow)
                    let handsM = cal.component(.minute, from: handsNow)

                    let liveS = cal.component(.second, from: liveNow)

                    let liveOnMinute = abs(liveNow.timeIntervalSince(secondsMinuteAnchor)) < 0.001

                    let hDeg = Int(baseAngles.hour.rounded())
                    let mDeg = Int(baseAngles.minute.rounded())

                    let driverStartRef = Int(progressRange.lowerBound.timeIntervalSinceReferenceDate.rounded())
                    let driverEndRef = Int(progressRange.upperBound.timeIntervalSinceReferenceDate.rounded())

                    let anchorRef = Int(secondsMinuteAnchor.timeIntervalSinceReferenceDate.rounded())
                    let startRef = Int(timerStart.timeIntervalSinceReferenceDate.rounded())
                    let endRef = Int(timerEnd.timeIntervalSinceReferenceDate.rounded())

                    let expectedSeconds = cal.component(.second, from: sysNow)
                    let expectedString = String(format: "0:%02d", expectedSeconds)

                    let redactLabel: String = {
                        if isPlaceholder && isPrivacy { return "placeholder+privacy" }
                        if isPlaceholder { return "placeholder" }
                        if isPrivacy { return "privacy" }
                        return "none"
                    }()

                    return "render ctxRef=\(ctxRef) sysRef=\(sysRef) ctx-sys=\(ctxMinusSys)s leadMs=\(leadMs) live=\(isPrerender ? 0 : 1) handsRef=\(handsRef) handsHM=\(handsH):\(handsM) liveS=\(liveS) onMinute=\(liveOnMinute ? 1 : 0) hDeg=\(hDeg) mDeg=\(mDeg) mode=\(tickMode) sec=\(showSeconds ? 1 : 0) redact=\(redactLabel) font=\(fontOK ? 1 : 0) rm=\(reduceMotion ? 1 : 0) driverRef=\(driverStartRef)...\(driverEndRef) anchorRef=\(anchorRef) rangeRef=\(startRef)...\(endRef) expected=\(expectedString)"
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
                    .id(handsNow)
                    .transition(.identity)
                    .transaction { transaction in
                        transaction.animation = nil
                    }

                    // Seconds hand glyph + hub overlay.
                    // Driven by `Text(timerInterval:)` and does not require frequent widget timeline reloads.
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
                        entryDate: liveNow,
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

    private static let progressDriverWindowSeconds: TimeInterval = 4.0 * 3600.0

    private static func floorToHour(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 3600.0) * 3600.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }

    private static func progressDriverRange(anchor: Date) -> ClosedRange<Date> {
        let start = floorToHour(anchor)
        let end = start.addingTimeInterval(progressDriverWindowSeconds)
        return start...end
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
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
