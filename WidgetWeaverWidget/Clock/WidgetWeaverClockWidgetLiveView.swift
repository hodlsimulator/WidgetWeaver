//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

enum WidgetWeaverClockMotionConfig {
    /// Keep seconds mode cheap until proven stable on device.
    static let secondsShowsGlows: Bool = false
    static let secondsShowsHandShadows: Bool = false

    /// Minute mode can render the full look.
    static let minuteShowsGlows: Bool = true
    static let minuteShowsHandShadows: Bool = true

    #if DEBUG
    static let debugOverlayEnabled: Bool = true
    #else
    static let debugOverlayEnabled: Bool = false
    #endif
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.redactionReasons) private var redactionReasons

    @State private var secondHandTargetDegrees: Double = 0.0
    @State private var secondsDriverDebug: WWClockSecondsDriverDebugState = .empty

    var body: some View {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isPlaceholderRedacted = redactionReasons.contains(.placeholder)

        let eligibility = WWClockSecondsEligibility.evaluate(
            tickMode: tickMode,
            isLowPower: isLowPower,
            reduceMotion: reduceMotion,
            isPlaceholderRedacted: isPlaceholderRedacted
        )

        ZStack(alignment: .bottomTrailing) {
            if eligibility.enabled {
                WWClockSecondsSweepClock(
                    palette: palette,
                    minuteAnchor: minuteAnchor,
                    showsGlows: WidgetWeaverClockMotionConfig.secondsShowsGlows,
                    showsHandShadows: WidgetWeaverClockMotionConfig.secondsShowsHandShadows,
                    secondHandTargetDegrees: $secondHandTargetDegrees,
                    driverDebug: $secondsDriverDebug
                )
            } else {
                let base = WWClockAngles(date: minuteAnchor)

                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(base.hour),
                    minuteAngle: .degrees(base.minute),
                    secondAngle: .degrees(0.0),
                    showsSecondHand: false,
                    showsHandShadows: WidgetWeaverClockMotionConfig.minuteShowsHandShadows,
                    showsGlows: WidgetWeaverClockMotionConfig.minuteShowsGlows,
                    handsOpacity: 1.0
                )
                .animation(nil, value: minuteAnchor)
            }

            #if DEBUG
            if WidgetWeaverClockMotionConfig.debugOverlayEnabled {
                WidgetWeaverClockWidgetDebugOverlay(
                    entryDate: entryDate,
                    minuteAnchor: minuteAnchor,
                    tickMode: tickMode,
                    secondsEligibility: eligibility,
                    reduceMotion: reduceMotion,
                    isLowPower: isLowPower,
                    isPlaceholderRedacted: isPlaceholderRedacted,
                    driverDebug: secondsDriverDebug,
                    secondHandTargetDegrees: secondHandTargetDegrees
                )
                .padding(6)
                .unredacted()
            }
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Seconds sweep (per-minute CA segment + “heartbeat” primitives)

private struct WWClockSecondsSweepClock: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date
    let showsGlows: Bool
    let showsHandShadows: Bool

    @Binding var secondHandTargetDegrees: Double
    @Binding var driverDebug: WWClockSecondsDriverDebugState

    @State private var lastStartAnchor: Date = .distantPast
    @State private var lastStartWallNow: Date = .distantPast

    var body: some View {
        let base = WWClockAngles(date: minuteAnchor)

        ZStack {
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(base.hour),
                minuteAngle: .degrees(base.minute),
                secondAngle: .degrees(secondHandTargetDegrees),
                showsSecondHand: true,
                showsHandShadows: showsHandShadows,
                showsGlows: showsGlows,
                handsOpacity: 1.0
            )
            .animation(nil, value: minuteAnchor)

            // Timer-style heartbeat kept in the render graph.
            // This stays extremely cheap and helps keep widget hosting in a “live” mode.
            WWClockWidgetHeartbeat(start: Date())

            // Another time-driven primitive, present but visually negligible.
            // Uses a relative interval so it can animate even if minuteAnchor is treated as a frozen date.
            WWClockSecondsEngine(opacity: 0.02)
                .frame(width: 24, height: 6)
                .clipped()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            DispatchQueue.main.async {
                startOrResyncSweep(reason: "onAppear")
            }
        }
        .onChange(of: minuteAnchor) {
            DispatchQueue.main.async {
                startOrResyncSweep(reason: "onChange(minuteAnchor)")
            }
        }
        .task {
            // Some widget hosting paths can skip onAppear.
            DispatchQueue.main.async {
                startOrResyncSweep(reason: "task")
            }
        }
    }

    private func startOrResyncSweep(reason: String) {
        let now = Date()

        // Avoid immediate double-start (onAppear + task) producing a visible jump.
        if lastStartAnchor == minuteAnchor, now.timeIntervalSince(lastStartWallNow) < 0.15 {
            driverDebug.recordCall(reason: reason, skipped: true)
            return
        }

        lastStartAnchor = minuteAnchor
        lastStartWallNow = now

        // “Catch up” offset when returning to Home Screen after time away.
        let rawOffset = now.timeIntervalSince(minuteAnchor)
        let secondsIntoMinute = WWClockSecondsMath.clamp(rawOffset, min: 0.0, max: 59.999)

        let startAngle = secondsIntoMinute * 6.0
        let remaining = max(0.001, 60.0 - secondsIntoMinute)

        driverDebug.recordStart(
            reason: reason,
            wallNow: now,
            minuteAnchor: minuteAnchor,
            secondsIntoMinute: secondsIntoMinute,
            startAngleDegrees: startAngle,
            remainingSeconds: remaining
        )

        // Jump to correct in-minute position with no animation.
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            secondHandTargetDegrees = startAngle
        }

        // Single linear segment to 360° for the remainder of the minute.
        withAnimation(.linear(duration: remaining)) {
            secondHandTargetDegrees = 360.0
        }
    }
}

private struct WWClockWidgetHeartbeat: View {
    let start: Date

    var body: some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false)
            .font(.system(size: 1))
            .foregroundStyle(Color.primary.opacity(0.001))
            .frame(width: 1, height: 1)
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct WWClockSecondsEngine: View {
    let opacity: Double

    var body: some View {
        let start = Date()
        let end = start.addingTimeInterval(60.0)

        ProgressView(timerInterval: start...end, countsDown: false)
            .progressViewStyle(.linear)
            .opacity(opacity)
            .accessibilityHidden(true)
    }
}

// MARK: - Eligibility

private struct WWClockSecondsEligibility: Equatable {
    let enabled: Bool
    let reason: String

    static func evaluate(
        tickMode: WidgetWeaverClockTickMode,
        isLowPower: Bool,
        reduceMotion: Bool,
        isPlaceholderRedacted: Bool
    ) -> WWClockSecondsEligibility {
        if tickMode == .minuteOnly {
            return WWClockSecondsEligibility(enabled: false, reason: "tickMode: minuteOnly")
        }
        if isLowPower {
            return WWClockSecondsEligibility(enabled: false, reason: "Low Power Mode")
        }
        if reduceMotion {
            return WWClockSecondsEligibility(enabled: false, reason: "Reduce Motion")
        }
        if isPlaceholderRedacted {
            return WWClockSecondsEligibility(enabled: false, reason: "preview/placeholder")
        }
        return WWClockSecondsEligibility(enabled: true, reason: "enabled")
    }
}

// MARK: - Debug state

private struct WWClockSecondsDriverDebugState: Equatable {
    var driverKind: String

    var lastStartReason: String
    var lastStartWallNow: Date
    var lastStartMinuteAnchor: Date
    var lastStartSecondsIntoMinute: Double
    var lastStartAngleDegrees: Double
    var lastStartRemainingSeconds: Double

    var restarts: Int
    var callCounts: WWClockSecondsDriverCallCounts
    var lastCallWasSkipped: Bool

    static let empty = WWClockSecondsDriverDebugState(
        driverKind: "CA sweep + heartbeat",
        lastStartReason: "inactive",
        lastStartWallNow: .distantPast,
        lastStartMinuteAnchor: .distantPast,
        lastStartSecondsIntoMinute: 0.0,
        lastStartAngleDegrees: 0.0,
        lastStartRemainingSeconds: 0.0,
        restarts: 0,
        callCounts: WWClockSecondsDriverCallCounts(),
        lastCallWasSkipped: true
    )

    mutating func recordStart(
        reason: String,
        wallNow: Date,
        minuteAnchor: Date,
        secondsIntoMinute: Double,
        startAngleDegrees: Double,
        remainingSeconds: Double
    ) {
        restarts += 1
        lastStartReason = reason
        lastStartWallNow = wallNow
        lastStartMinuteAnchor = minuteAnchor
        lastStartSecondsIntoMinute = secondsIntoMinute
        lastStartAngleDegrees = startAngleDegrees
        lastStartRemainingSeconds = remainingSeconds
        lastCallWasSkipped = false
        callCounts.bump(reason: reason)
    }

    mutating func recordCall(reason: String, skipped: Bool) {
        lastStartReason = reason
        lastCallWasSkipped = skipped
        callCounts.bump(reason: reason)
    }
}

private struct WWClockSecondsDriverCallCounts: Equatable {
    var onAppear: Int = 0
    var task: Int = 0
    var onChange: Int = 0
    var other: Int = 0

    mutating func bump(reason: String) {
        if reason.hasPrefix("onAppear") {
            onAppear += 1
            return
        }
        if reason.hasPrefix("task") {
            task += 1
            return
        }
        if reason.hasPrefix("onChange") {
            onChange += 1
            return
        }
        other += 1
    }
}

// MARK: - Maths

private enum WWClockSecondsMath {
    static func clamp(_ x: Double, min a: Double, max b: Double) -> Double {
        if x < a { return a }
        if x > b { return b }
        return x
    }
}

// MARK: - Angles (minute-stepped base hands)

private struct WWClockAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        minute = minuteInt * 6.0
        hour = (hour12 + minuteInt / 60.0) * 30.0
    }
}

#if DEBUG
// MARK: - Debug overlay (compact; always fits in systemSmall)

private struct WidgetWeaverClockWidgetDebugOverlay: View {
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode
    let secondsEligibility: WWClockSecondsEligibility
    let reduceMotion: Bool
    let isLowPower: Bool
    let isPlaceholderRedacted: Bool
    let driverDebug: WWClockSecondsDriverDebugState
    let secondHandTargetDegrees: Double

    var body: some View {
        let modeText: String = {
            switch tickMode {
            case .minuteOnly: return "minute"
            case .secondsSweep: return "sweep"
            }
        }()

        let secsText = secondsEligibility.enabled ? "ON" : "OFF"
        let startedText = driverDebug.restarts > 0 ? "on" : "off"

        let reasonShort: String = {
            let s = secondsEligibility.reason
            if s.count <= 26 { return s }
            return String(s.prefix(26)) + "…"
        }()

        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                Text("dbg \(modeText) secs \(secsText)")
                    .opacity(0.92)

                Spacer(minLength: 6)

                WWClockDebugEngineStrip()
                    .accessibilityHidden(true)

                WWClockDebugSweepMarker(targetDegrees: secondHandTargetDegrees)
                    .frame(width: 12, height: 12)
                    .opacity(0.92)
                    .accessibilityHidden(true)
            }

            Text("why \(reasonShort)")
                .opacity(0.86)

            Text("anch \(minuteAnchor, format: .dateTime.hour().minute().second())")
                .opacity(0.82)

            Text("pwr LPM:\(isLowPower ? "1" : "0") RM:\(reduceMotion ? "1" : "0") red:\(isPlaceholderRedacted ? "1" : "0")")
                .opacity(0.78)

            Text("drv \(startedText) r\(driverDebug.restarts) ap\(driverDebug.callCounts.onAppear) t\(driverDebug.callCounts.task) c\(driverDebug.callCounts.onChange)")
                .opacity(0.76)

            Text(String(format: "off %.2fs start %.0f° rem %.2fs", driverDebug.lastStartSecondsIntoMinute, driverDebug.lastStartAngleDegrees, driverDebug.lastStartRemainingSeconds))
                .opacity(0.74)
        }
        .font(.system(size: 7, weight: .regular, design: .monospaced))
        .dynamicTypeSize(.xSmall)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: 150, alignment: .trailing)
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

private struct WWClockDebugEngineStrip: View {
    var body: some View {
        let start = Date()
        let end = start.addingTimeInterval(60.0)

        ProgressView(timerInterval: start...end, countsDown: false)
            .progressViewStyle(.linear)
            .tint(Color.white.opacity(0.90))
            .frame(width: 46, height: 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.16))
            )
            .clipShape(Capsule(style: .continuous))
            .opacity(0.95)
    }
}

private struct WWClockDebugSweepMarker: View {
    let targetDegrees: Double

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)

            Rectangle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 1.1, height: 5.8)
                .offset(y: -2.9)
                .rotationEffect(.degrees(targetDegrees), anchor: .center)

            Circle()
                .fill(Color.white.opacity(0.75))
                .frame(width: 2.4, height: 2.4)
        }
    }
}
#endif
