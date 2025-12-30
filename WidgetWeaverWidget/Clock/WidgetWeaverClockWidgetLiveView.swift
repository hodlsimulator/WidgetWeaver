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
                WWClockSecondsPerMinuteImplicitAnimationClock(
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
                    driverKind: eligibility.enabled ? "Implicit per-minute anim(timeSeconds)" : "static",
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

// MARK: - Seconds driver: implicit animation from minuteAnchor -> minuteAnchor+60

private struct WWClockSecondsPerMinuteImplicitAnimationClock: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let metrics = WWClockSecondHandMetrics(size: proxy.size, scale: displayScale)
            let base = WWClockAngles(date: minuteAnchor)

            let anchorSeconds = minuteAnchor.timeIntervalSinceReferenceDate

            ZStack {
                // Base clock: static face + stepped hour/minute hands.
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

                // Second hand:
                // - No TimelineView, no timers, no onAppear/task dependence.
                // - Animate an animatable "timeSeconds" scalar from (minuteAnchor) -> (minuteAnchor+60).
                // - Angle is derived from the animated scalar, producing a continuous sweep.
                WWClockSecondHandTimeSweepLayer(
                    palette: palette,
                    metrics: metrics,
                    anchorSeconds: anchorSeconds,
                    scale: displayScale
                )
                .animation(.linear(duration: 60.0), value: minuteAnchor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct WWClockSecondHandTimeSweepLayer: View {
    let palette: WidgetWeaverClockPalette
    let metrics: WWClockSecondHandMetrics
    let anchorSeconds: Double
    let scale: CGFloat

    var body: some View {
        WidgetWeaverClockSecondHandView(
            colour: palette.accent,
            width: metrics.secondWidth,
            length: metrics.secondLength,
            angle: .degrees(0.0),
            tipSide: metrics.secondTipSide,
            scale: scale
        )
        .modifier(
            WWClockSecondHandTimeSecondsRotationModifier(timeSeconds: anchorSeconds)
        )
        .frame(width: metrics.dialDiameter, height: metrics.dialDiameter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Animates `timeSeconds` (seconds since reference date) linearly between minute anchors.
/// The second hand angle is derived from the animated intermediate values, yielding a sweep.
/// Strict concurrency fix: this modifier’s protocol witnesses are `nonisolated`.
private struct WWClockSecondHandTimeSecondsRotationModifier: AnimatableModifier {

    // With default main-actor isolation enabled, this stored value would otherwise be main-actor isolated,
    // which breaks the Animatable conformance under strict concurrency checking.
    nonisolated(unsafe) var timeSeconds: Double

    nonisolated var animatableData: Double {
        get { timeSeconds }
        set { timeSeconds = newValue }
    }

    nonisolated func body(content: Content) -> some View {
        let secondsIntoMinute = timeSeconds - floor(timeSeconds / 60.0) * 60.0
        let degrees = secondsIntoMinute * 6.0
        return content.rotationEffect(.degrees(degrees))
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
// MARK: - Debug overlay (does not rely on Date() ticking)

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

        let entryText: String = entryDate.formatted(.dateTime.hour().minute().second())
        let anchorText: String = minuteAnchor.formatted(.dateTime.hour().minute().second())

        let reasonShort: String = {
            let s = secondsEligibility.reason
            if s.count <= 24 { return s }
            return String(s.prefix(24)) + "…"
        }()

        let probeAnchorSeconds = minuteAnchor.timeIntervalSinceReferenceDate

        VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 10, height: 10)

                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 3, height: 3)
                        .offset(y: -5)
                        .modifier(WWClockSecondHandTimeSecondsRotationModifier(timeSeconds: probeAnchorSeconds))
                        .animation(.linear(duration: 60.0), value: minuteAnchor)
                }
                .opacity(animatesSeconds ? 1.0 : 0.35)

                Text("dbg \(modeText) secs \(secsText)")
                    .opacity(0.92)
            }

            Text("why \(reasonShort)")
                .opacity(0.86)

            Text("e \(entryText) a \(anchorText)")
                .opacity(0.82)

            Text("drv \(driverKind)")
                .opacity(0.80)

            Text("pwr LPM:\(isLowPower ? "1" : "0") RM:\(reduceMotion ? "1" : "0") red:\(isPlaceholderRedacted ? "1" : "0")")
                .opacity(0.76)
        }
        .font(.system(size: 7, weight: .regular, design: .monospaced))
        .dynamicTypeSize(.xSmall)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: 165, alignment: .trailing)
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
#endif
