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
    fileprivate static let progressDriverWindowSeconds: TimeInterval = 4.0 * 3600.0

    fileprivate static var buildLabel: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    var body: some View {
        let progressRange = Self.progressDriverRange(anchor: entryDate)

        // IMPORTANT:
        // The clock rendering must be inside the time-driven ProgressView style, not an overlay.
        // An overlay closure is not guaranteed to be re-evaluated when the ProgressView's timer advances.
        // If the overlay doesn't re-run, hour/minute hands (and render logs) can stall and then "tick late".
        WidgetWeaverRenderClock.withNow(entryDate) {
            ProgressView(
                timerInterval: progressRange,
                countsDown: false,
                label: { EmptyView() },
                currentValueLabel: { EmptyView() }
            )
            .progressViewStyle(
                WWClockHeartbeatProgressStyle(
                    palette: palette,
                    entryDate: entryDate,
                    tickMode: tickMode,
                    tickSeconds: tickSeconds,
                    progressRange: progressRange
                )
            )
            .accessibilityHidden(true)
        }
    }

    fileprivate static func floorToHour(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 3600.0) * 3600.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }

    fileprivate static func progressDriverRange(anchor: Date) -> ClosedRange<Date> {
        let start = floorToHour(anchor)
        let end = start.addingTimeInterval(progressDriverWindowSeconds)
        return start...end
    }

    fileprivate static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

// MARK: - Heartbeat (ProgressViewStyle)

fileprivate struct WWClockHeartbeatProgressStyle: ProgressViewStyle {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval
    let progressRange: ClosedRange<Date>

    func makeBody(configuration: Configuration) -> some View {
        // fractionCompleted is the key signal that causes SwiftUI to re-evaluate as time advances.
        let frac = configuration.fractionCompleted ?? 0.0

        return WWClockHeartbeatBody(
            palette: palette,
            entryDate: entryDate,
            tickMode: tickMode,
            tickSeconds: tickSeconds,
            progressRange: progressRange,
            fractionCompleted: frac
        )
    }
}

fileprivate struct WWClockHeartbeatBody: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval
    let progressRange: ClosedRange<Date>
    let fractionCompleted: Double

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lastLoggedMinuteRef: Int = Int.min

    var body: some View {
        let clampedFrac = max(0.0, min(1.0, fractionCompleted))

        let start = progressRange.lowerBound
        let end = progressRange.upperBound
        let duration = max(0.001, end.timeIntervalSince(start))

        // A derived driver time from the progress fraction.
        // This is not used for correctness; it exists to prove the ProgressView is advancing.
        let driverNow = start.addingTimeInterval(clampedFrac * duration)
        let driverRefSec = Int(driverNow.timeIntervalSinceReferenceDate.rounded())

        // Real wall clock.
        let wallNow = Date()

        // Render clock (pinned to entry date while WidgetKit pre-renders).
        let ctxNow = WidgetWeaverRenderClock.now

        let sysMinuteAnchor = WidgetWeaverClockWidgetLiveView.floorToMinute(wallNow)
        let ctxMinuteAnchor = WidgetWeaverClockWidgetLiveView.floorToMinute(ctxNow)
        let leadSeconds = ctxNow.timeIntervalSince(wallNow)

        // Pre-render detection:
        // - far-future: ctxNow is way ahead of wallNow
        // - minute-boundary skew: ctxMinuteAnchor is ahead of sysMinuteAnchor
        let isPrerender = (leadSeconds > 5.0) || (ctxMinuteAnchor > sysMinuteAnchor)

        // Live: wall clock. Pre-render: entry date for deterministic snapshots.
        let renderNow: Date = isPrerender ? ctxNow : wallNow

        // Tick-style hour + minute hands: snap to the minute boundary.
        let handsNow = WidgetWeaverClockWidgetLiveView.floorToMinute(renderNow)

        let isPrivacy = redactionReasons.contains(.privacy)
        let isPlaceholder = redactionReasons.contains(.placeholder)

        let handsOpacity: Double = isPrivacy ? 0.85 : 1.0
        let showSeconds = (tickMode == .secondsSweep)

        let baseAngles = WWClockBaseAngles(date: handsNow)
        let hourAngle = Angle.degrees(baseAngles.hour)
        let minuteAngle = Angle.degrees(baseAngles.minute)

        // Seconds anchor:
        let secondsMinuteAnchor = handsNow
        let timerStart = secondsMinuteAnchor.addingTimeInterval(-WidgetWeaverClockWidgetLiveView.timerStartBiasSeconds)
        let timerEnd = secondsMinuteAnchor.addingTimeInterval(60.0 + WidgetWeaverClockWidgetLiveView.minuteSpilloverSeconds)
        let timerRange = timerStart...timerEnd

        // Render-path proof logging.
        let _ : Void = {
            guard WWClockDebugLog.isEnabled() else { return () }

            let balloon = WWClockDebugLog.isBallooningEnabled()

            let ctxRef = Int(ctxNow.timeIntervalSinceReferenceDate.rounded())
            let wallRef = Int(wallNow.timeIntervalSinceReferenceDate.rounded())
            let handsRef = Int(handsNow.timeIntervalSinceReferenceDate.rounded())

            let leadMs = Int((leadSeconds * 1000.0).rounded())
            let wallMinusDriverMs = Int(((wallNow.timeIntervalSince(driverNow)) * 1000.0).rounded())

            let cal = Calendar.autoupdatingCurrent
            let handsH = cal.component(.hour, from: handsNow)
            let handsM = cal.component(.minute, from: handsNow)
            let liveS = cal.component(.second, from: renderNow)

            let hDeg = Int(baseAngles.hour.rounded())
            let mDeg = Int(baseAngles.minute.rounded())

            let driverStartRef = Int(progressRange.lowerBound.timeIntervalSinceReferenceDate.rounded())
            let driverEndRef = Int(progressRange.upperBound.timeIntervalSinceReferenceDate.rounded())

            let redactLabel: String = {
                if isPlaceholder && isPrivacy { return "placeholder+privacy" }
                if isPlaceholder { return "placeholder" }
                if isPrivacy { return "privacy" }
                return "none"
            }()

            WWClockDebugLog.appendLazy(
                category: "clock",
                throttleID: balloon ? nil : "clockWidget.render",
                minInterval: balloon ? 0.0 : 15.0,
                now: wallNow
            ) {
                "render build=\(WidgetWeaverClockWidgetLiveView.buildLabel) ctxRef=\(ctxRef) wallRef=\(wallRef) leadMs=\(leadMs) live=\(isPrerender ? 0 : 1) handsRef=\(handsRef) handsHM=\(handsH):\(handsM) liveS=\(liveS) hDeg=\(hDeg) mDeg=\(mDeg) mode=\(tickMode) sec=\(showSeconds ? 1 : 0) redact=\(redactLabel) rm=\(reduceMotion ? 1 : 0) balloon=\(balloon ? 1 : 0) driverRef=\(driverStartRef)...\(driverEndRef) wall-driverMs=\(wallMinusDriverMs)"
            }

            return ()
        }()

        return ZStack {
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

            WWClockSecondsAndHubOverlay(
                palette: palette,
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
        .onChange(of: driverRefSec) { _, newDriverRef in
            // Prove the ProgressView heartbeat is actually advancing while the widget is live.
            guard WWClockDebugLog.isEnabled() else { return }

            let wallNow2 = Date()
            let ctxNow2 = WidgetWeaverRenderClock.now
            let sysMinuteAnchor2 = WidgetWeaverClockWidgetLiveView.floorToMinute(wallNow2)
            let ctxMinuteAnchor2 = WidgetWeaverClockWidgetLiveView.floorToMinute(ctxNow2)
            let leadSeconds2 = ctxNow2.timeIntervalSince(wallNow2)
            let isPrerender2 = (leadSeconds2 > 5.0) || (ctxMinuteAnchor2 > sysMinuteAnchor2)
            if isPrerender2 { return }

            let balloon = WWClockDebugLog.isBallooningEnabled()

            let leadMs2 = Int((leadSeconds2 * 1000.0).rounded())
            let cal = Calendar.autoupdatingCurrent
            let h = cal.component(.hour, from: wallNow2)
            let m = cal.component(.minute, from: wallNow2)
            let s = cal.component(.second, from: wallNow2)

            WWClockDebugLog.appendLazy(
                category: "clock",
                throttleID: balloon ? nil : "clockWidget.driverPulse",
                minInterval: balloon ? 0.0 : 10.0,
                now: wallNow2
            ) {
                "driverPulse build=\(WidgetWeaverClockWidgetLiveView.buildLabel) driverRef=\(newDriverRef) now=\(h):\(String(format: "%02d", m)):\(String(format: "%02d", s)) leadMs=\(leadMs2)"
            }
        }
        .onChange(of: handsNow) { _, newHands in
            // Minute tick proof logging.
            guard WWClockDebugLog.isEnabled() else { return }

            let handsRef = Int(newHands.timeIntervalSinceReferenceDate.rounded())
            if handsRef == lastLoggedMinuteRef { return }
            lastLoggedMinuteRef = handsRef

            let wallNow2 = Date()
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

            WWClockDebugLog.appendLazy(category: "clock", throttleID: nil, minInterval: 0, now: wallNow2) {
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
