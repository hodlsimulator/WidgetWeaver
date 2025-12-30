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
                    minuteAnchor: minuteAnchor
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
                    driverKind: eligibility.enabled ? "ProgressView heartbeat + per-minute sweep" : "static",
                    animatesSeconds: eligibility.enabled
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

// MARK: - Seconds driver (per-minute sweep, kicked off via task(id: minuteAnchor))

private struct WWClockSecondsSweepClock: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date

    @Environment(\.displayScale) private var displayScale

    @State private var sweepTimeSeconds: Double

    init(palette: WidgetWeaverClockPalette, minuteAnchor: Date) {
        self.palette = palette
        self.minuteAnchor = minuteAnchor

        // Start at “now” (clamped into this minute’s [anchor, anchor+60]) so the hand is correct immediately
        // even if the widget is first rendered mid-minute.
        let anchorSeconds = minuteAnchor.timeIntervalSinceReferenceDate
        let endSeconds = anchorSeconds + 60.0
        let nowSeconds = Date().timeIntervalSinceReferenceDate
        let startSeconds = min(max(nowSeconds, anchorSeconds), endSeconds)

        _sweepTimeSeconds = State(initialValue: startSeconds)
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = WWClockSecondHandMetrics(size: proxy.size, scale: displayScale)
            let base = WWClockAngles(date: minuteAnchor)

            let anchorSeconds = minuteAnchor.timeIntervalSinceReferenceDate
            let endSeconds = anchorSeconds + 60.0

            // Monotonic 0...60 within this minute; avoids modulo wrap artefacts.
            let secondsIntoMinute = WWClock.clamp(CGFloat(sweepTimeSeconds - anchorSeconds), min: 0.0, max: 60.0)
            let secondDegrees = Double(secondsIntoMinute) * 6.0

            ZStack {
                // Base clock: stable face + stepped hour/minute hands.
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(base.hour),
                    minuteAngle: .degrees(base.minute),
                    secondAngle: .degrees(0.0),
                    showsSecondHand: false,
                    showsHandShadows: WidgetWeaverClockMotionConfig.secondsShowsHandShadows,
                    showsGlows: WidgetWeaverClockMotionConfig.secondsShowsGlows,
                    handsOpacity: 1.0
                )
                .animation(nil, value: minuteAnchor)

                // The “keep-alive” driver the Home Screen host is willing to animate.
                // Keep it in the render graph with very low (non-zero) opacity.
                WWClockSecondsHeartbeatProgressView(minuteAnchor: minuteAnchor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(4)

                // Second hand itself: driven by sweepTimeSeconds animation (not by Date() ticking).
                WidgetWeaverClockSecondHandView(
                    colour: palette.accent,
                    width: metrics.secondWidth,
                    length: metrics.secondLength,
                    angle: .degrees(secondDegrees),
                    tipSide: metrics.secondTipSide,
                    scale: displayScale
                )
                .frame(width: metrics.dialDiameter, height: metrics.dialDiameter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: minuteAnchor) {
                await startOrResyncSweep(anchorSeconds: anchorSeconds, endSeconds: endSeconds)
            }
        }
    }

    @MainActor
    private func startOrResyncSweep(anchorSeconds: Double, endSeconds: Double) async {
        let nowSeconds = Date().timeIntervalSinceReferenceDate
        let startSeconds = min(max(nowSeconds, anchorSeconds), endSeconds)
        let remaining = max(0.05, endSeconds - startSeconds)

        // Hard-set without animation, then animate to end-of-minute.
        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            sweepTimeSeconds = startSeconds
        }

        withAnimation(.linear(duration: remaining)) {
            sweepTimeSeconds = endSeconds
        }
    }
}

private struct WWClockSecondsHeartbeatProgressView: View {
    let minuteAnchor: Date

    var body: some View {
        // Important details:
        // - Non-zero opacity (0.0 risks pruning / snapshot optimisation).
        // - Small & cheap.
        // - No custom ProgressViewStyle.
        ProgressView(
            timerInterval: minuteAnchor...(minuteAnchor.addingTimeInterval(60.0)),
            countsDown: false
        )
        .progressViewStyle(.linear)
        .frame(width: 44, height: 3)
        .opacity(0.02)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Metrics / math

private struct WWClockSecondHandMetrics: Equatable {
    let dialDiameter: CGFloat
    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat
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
        dialDiameter = R * 2.0

        secondLength = WWClock.pixel(
            WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
            scale: scale
        )
        secondWidth = WWClock.pixel(
            WWClock.clamp(R * 0.006, min: R * 0.004, max: R * 0.007),
            scale: scale
        )
        secondTipSide = WWClock.pixel(
            WWClock.clamp(R * 0.014, min: R * 0.012, max: R * 0.016),
            scale: scale
        )

        hubBaseRadius = WWClock.pixel(
            WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
            scale: scale
        )
        hubCapRadius = WWClock.pixel(
            WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
            scale: scale
        )
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

// MARK: - Base angles (minute-stepped)

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
// MARK: - Debug overlay (compact + includes visible ProgressView driver)

private struct WidgetWeaverClockWidgetDebugOverlay: View {
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode
    let secondsEligibility: WWClockSecondsEligibility
    let reduceMotion: Bool
    let isLowPower: Bool
    let isPlaceholderRedacted: Bool

    let driverKind: String
    let animatesSeconds: Bool

    var body: some View {
        let modeText: String = {
            switch tickMode {
            case .minuteOnly: return "minute"
            case .secondsSweep: return "sweep"
            }
        }()

        let secsText = secondsEligibility.enabled ? "ON" : "OFF"
        let anchorText: String = minuteAnchor.formatted(.dateTime.hour().minute().second())

        let reasonShort: String = {
            let s = secondsEligibility.reason
            if s.count <= 22 { return s }
            return String(s.prefix(22)) + "…"
        }()

        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("dbg \(modeText) secs \(secsText)")
                    .opacity(0.95)

                Spacer(minLength: 6)

                WWClockDebugProbeDot(minuteAnchor: minuteAnchor, isActive: animatesSeconds)
            }

            Text("why \(reasonShort)")
                .opacity(0.86)

            Text("anch \(anchorText)")
                .opacity(0.82)

            // Visible driver probe: if this bar doesn’t move, the host isn’t animating timerInterval primitives.
            ProgressView(
                timerInterval: minuteAnchor...(minuteAnchor.addingTimeInterval(60.0)),
                countsDown: false
            )
            .progressViewStyle(.linear)
            .frame(width: 108, height: 4)
            .opacity(animatesSeconds ? 0.95 : 0.35)

            Text("drv \(driverKind)")
                .opacity(0.78)

            Text("pwr LPM:\(isLowPower ? "1" : "0") RM:\(reduceMotion ? "1" : "0") red:\(isPlaceholderRedacted ? "1" : "0")")
                .opacity(0.72)
        }
        .font(.system(size: 7, weight: .regular, design: .monospaced))
        .dynamicTypeSize(.xSmall)
        .lineLimit(1)
        .minimumScaleFactor(0.65)
        .frame(maxWidth: 150, alignment: .leading)
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

private struct WWClockDebugProbeDot: View {
    let minuteAnchor: Date
    let isActive: Bool

    @State private var probeTimeSeconds: Double

    init(minuteAnchor: Date, isActive: Bool) {
        self.minuteAnchor = minuteAnchor
        self.isActive = isActive

        let anchorSeconds = minuteAnchor.timeIntervalSinceReferenceDate
        let endSeconds = anchorSeconds + 60.0
        let nowSeconds = Date().timeIntervalSinceReferenceDate
        let startSeconds = min(max(nowSeconds, anchorSeconds), endSeconds)

        _probeTimeSeconds = State(initialValue: startSeconds)
    }

    var body: some View {
        let anchorSeconds = minuteAnchor.timeIntervalSinceReferenceDate
        let endSeconds = anchorSeconds + 60.0

        let secs = WWClock.clamp(CGFloat(probeTimeSeconds - anchorSeconds), min: 0.0, max: 60.0)
        let degrees = Double(secs) * 6.0

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 10, height: 10)

            Circle()
                .fill(Color.white.opacity(0.90))
                .frame(width: 3, height: 3)
                .offset(y: -5)
                .rotationEffect(.degrees(degrees))
        }
        .opacity(isActive ? 1.0 : 0.35)
        .task(id: minuteAnchor) {
            await startOrResyncProbe(anchorSeconds: anchorSeconds, endSeconds: endSeconds)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @MainActor
    private func startOrResyncProbe(anchorSeconds: Double, endSeconds: Double) async {
        guard isActive else { return }

        let nowSeconds = Date().timeIntervalSinceReferenceDate
        let startSeconds = min(max(nowSeconds, anchorSeconds), endSeconds)
        let remaining = max(0.05, endSeconds - startSeconds)

        var t = Transaction()
        t.animation = nil
        withTransaction(t) {
            probeTimeSeconds = startSeconds
        }

        withAnimation(.linear(duration: remaining)) {
            probeTimeSeconds = endSeconds
        }
    }
}
#endif
