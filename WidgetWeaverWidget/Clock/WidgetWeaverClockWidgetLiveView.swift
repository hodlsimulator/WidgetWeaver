//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    init(
        palette: WidgetWeaverClockPalette,
        entryDate: Date,
        minuteAnchor: Date,
        tickMode: WidgetWeaverClockTickMode
    ) {
        self.palette = palette
        self.entryDate = entryDate
        self.minuteAnchor = minuteAnchor
        self.tickMode = tickMode
    }

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let now = WidgetWeaverRenderClock.now

            let cal = Calendar.autoupdatingCurrent
            let hours = cal.component(.hour, from: minuteAnchor) % 12
            let minutes = cal.component(.minute, from: minuteAnchor)

            let hourAngle = Angle.degrees((Double(hours) + (Double(minutes) / 60.0)) * 30.0)
            let minuteAngle = Angle.degrees(Double(minutes) * 6.0)

            let motion = WWClockMotion(
                tickMode: tickMode,
                redactionReasons: redactionReasons,
                isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                isReduceMotionEnabled: reduceMotion
            )

            ZStack {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: hourAngle,
                    minuteAngle: minuteAngle,
                    secondAngle: .zero,
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    handsOpacity: motion.handsOpacity
                )

                if motion.secondsEnabled {
                    WWClockSecondsProgressSecondHandOverlay(
                        minuteAnchor: minuteAnchor,
                        palette: palette,
                        style: motion.secondsStyle,
                        scale: displayScale
                    )
                }
            }
            #if DEBUG
            .overlay(alignment: .bottomLeading) {
                WWClockDebugOverlay(
                    now: now,
                    minuteAnchor: minuteAnchor,
                    motion: motion,
                    redactionReasons: redactionReasons
                )
            }
            #endif
        }
    }
}

private struct WWClockMotion {
    enum SecondsStyle: String {
        case secondHandOnly = "secondHand"
        case secondHandPlusTip = "tip"
    }

    let secondsEnabled: Bool
    let secondsStyle: SecondsStyle
    let handsOpacity: Double
    let debugWhy: String

    init(
        tickMode: WidgetWeaverClockTickMode,
        redactionReasons: RedactionReasons,
        isLowPowerModeEnabled: Bool,
        isReduceMotionEnabled: Bool
    ) {
        let isPlaceholder = redactionReasons.contains(.placeholder)
        let isPrivacy = redactionReasons.contains(.privacy)

        let wantsSeconds = (tickMode == .secondsSweep)

        let enabled = wantsSeconds
            && (isPlaceholder == false)
            && (isPrivacy == false)
            && (isLowPowerModeEnabled == false)
            && (isReduceMotionEnabled == false)

        self.secondsEnabled = enabled
        self.secondsStyle = .secondHandPlusTip

        self.handsOpacity = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

        if isPlaceholder { self.debugWhy = "placeholder" }
        else if isPrivacy { self.debugWhy = "privacy" }
        else if isLowPowerModeEnabled { self.debugWhy = "low_power" }
        else if isReduceMotionEnabled { self.debugWhy = "reduce_motion" }
        else if wantsSeconds == false { self.debugWhy = "minuteOnly" }
        else { self.debugWhy = "enabled" }
    }
}

// MARK: - Seconds overlay driven by ProgressView(timerInterval:)

private struct WWClockSecondsProgressSecondHandOverlay: View {
    let minuteAnchor: Date
    let palette: WidgetWeaverClockPalette
    let style: WWClockMotion.SecondsStyle
    let scale: CGFloat

    private let epsilon: TimeInterval = 0.15

    private var interval: ClosedRange<Date> {
        let start = minuteAnchor
        let end = minuteAnchor.addingTimeInterval(60.0 - epsilon)
        return start...end
    }

    var body: some View {
        ProgressView(
            timerInterval: interval,
            countsDown: false
        )
        .labelsHidden()
        .progressViewStyle(
            WWClockSecondsProgressSecondHandStyle(
                palette: palette,
                style: style,
                scale: scale
            )
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWClockSecondsProgressSecondHandStyle: ProgressViewStyle {
    let palette: WidgetWeaverClockPalette
    let style: WWClockMotion.SecondsStyle
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        let rawFraction = configuration.fractionCompleted ?? 0
        let fraction = min(max(rawFraction, 0), 1)

        let secondAngle = Angle.degrees(fraction * 360.0)

        return ZStack {
            WidgetWeaverClockSecondHandView(
                colour: palette.accent,
                width: 1.6,
                length: 0.92,
                angle: secondAngle,
                tipSide: 0.08,
                scale: scale
            )

            if style == .secondHandPlusTip {
                WWClockSecondsProgressTipHand(
                    palette: palette,
                    fractionCompleted: fraction
                )
            }
        }
    }
}

private struct WWClockSecondsProgressTipHand: View {
    let palette: WidgetWeaverClockPalette
    let fractionCompleted: Double

    var body: some View {
        ZStack {
            ProgressView(value: fractionCompleted)
                .progressViewStyle(.circular)
                .tint(palette.accent)
                .controlSize(.mini)

            ProgressView(value: fractionCompleted)
                .progressViewStyle(.circular)
                .tint(Color.black)
                .controlSize(.mini)
                .scaleEffect(0.62)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .rotationEffect(.degrees(90))
        .scaleEffect(0.50)
        .offset(x: 74)
    }
}

#if DEBUG
private struct WWClockDebugOverlay: View {
    let now: Date
    let minuteAnchor: Date
    let motion: WWClockMotion
    let redactionReasons: RedactionReasons

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("dbg  sweep secs \(motion.secondsEnabled ? "ON" : "OFF")")
            Text("why  \(motion.debugWhy)")
            Text("red  \(redactionReasonsDescription)")
            Text("e \(now, format: .dateTime.hour().minute().second())  a \(minuteAnchor, format: .dateTime.hour().minute().second())")
            Text("drv  ProgressView(timerInterval)  \(motion.secondsStyle.rawValue)")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(Color.white.opacity(0.85))
        .padding(8)
        .background(.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(8)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var redactionReasonsDescription: String {
        var parts: [String] = []
        if redactionReasons.contains(.placeholder) { parts.append("placeholder") }
        if redactionReasons.contains(.privacy) { parts.append("privacy") }
        if parts.isEmpty { return "none" }
        return parts.joined(separator: ",")
    }
}
#endif
