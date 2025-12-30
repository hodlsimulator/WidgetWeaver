//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private struct WWClockSecondsMotion: Equatable {
    let wantsSweep: Bool
    let enabled: Bool
    let reasonShort: String
    let isLowPowerMode: Bool
    let reduceMotion: Bool
    let isPlaceholderRedacted: Bool
    let redactionReasonsDebug: String
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.displayScale) private var displayScale

    private static let secondsTipEpsilon: TimeInterval = 0.45

    var body: some View {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isPlaceholderRedacted = redactionReasons.contains(.placeholder)

        let motion = Self.computeMotion(
            tickMode: tickMode,
            isLowPowerMode: isLowPower,
            reduceMotion: reduceMotion,
            isPlaceholderRedacted: isPlaceholderRedacted,
            redactionReasons: redactionReasons
        )

        GeometryReader { proxy in
            let base = WWClockAngles(date: minuteAnchor)
            let dialDiameter = Self.dialDiameterAlignedToIconView(for: proxy.size, scale: displayScale)

            ZStack(alignment: .bottomLeading) {
                // Base clock remains timeline-driven (minuteAnchor only).
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(base.hour),
                    minuteAngle: .degrees(base.minute),
                    secondAngle: .degrees(0.0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    handsOpacity: 1.0
                )
                .animation(nil, value: minuteAnchor)

                // Seconds “hand” driven by a host-animated timer primitive.
                // NOTE: This is a “tip” (short moving arc/dot) rather than a full needle.
                if motion.enabled {
                    WWClockSecondsProgressTipHand(
                        minuteAnchor: minuteAnchor,
                        dialDiameter: dialDiameter,
                        colour: palette.accent,
                        epsilon: Self.secondsTipEpsilon
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }

                #if DEBUG
                WWClockDebugOverlay(
                    palette: palette,
                    entryDate: entryDate,
                    minuteAnchor: minuteAnchor,
                    tickMode: tickMode,
                    motion: motion,
                    dialDiameter: dialDiameter,
                    epsilon: Self.secondsTipEpsilon
                )
                .padding(6)
                .unredacted()
                #endif
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func computeMotion(
        tickMode: WidgetWeaverClockTickMode,
        isLowPowerMode: Bool,
        reduceMotion: Bool,
        isPlaceholderRedacted: Bool,
        redactionReasons: RedactionReasons
    ) -> WWClockSecondsMotion {
        let wantsSweep = (tickMode == .secondsSweep)

        let reasonsDebug: String = {
            var parts: [String] = []
            if redactionReasons.contains(.placeholder) { parts.append("placeholder") }
            if redactionReasons.contains(.privacy) { parts.append("privacy") }
            if redactionReasons.contains(.invalidated) { parts.append("invalidated") }
            if parts.isEmpty { return "none" }
            return parts.joined(separator: ",")
        }()

        if !wantsSweep {
            return WWClockSecondsMotion(
                wantsSweep: wantsSweep,
                enabled: false,
                reasonShort: "tickMode",
                isLowPowerMode: isLowPowerMode,
                reduceMotion: reduceMotion,
                isPlaceholderRedacted: isPlaceholderRedacted,
                redactionReasonsDebug: reasonsDebug
            )
        }

        if isLowPowerMode {
            return WWClockSecondsMotion(
                wantsSweep: wantsSweep,
                enabled: false,
                reasonShort: "LPM",
                isLowPowerMode: isLowPowerMode,
                reduceMotion: reduceMotion,
                isPlaceholderRedacted: isPlaceholderRedacted,
                redactionReasonsDebug: reasonsDebug
            )
        }

        if reduceMotion {
            return WWClockSecondsMotion(
                wantsSweep: wantsSweep,
                enabled: false,
                reasonShort: "RM",
                isLowPowerMode: isLowPowerMode,
                reduceMotion: reduceMotion,
                isPlaceholderRedacted: isPlaceholderRedacted,
                redactionReasonsDebug: reasonsDebug
            )
        }

        // Placeholder redaction means the host isn’t running a real timeline render.
        if isPlaceholderRedacted {
            return WWClockSecondsMotion(
                wantsSweep: wantsSweep,
                enabled: false,
                reasonShort: "placeholder",
                isLowPowerMode: isLowPowerMode,
                reduceMotion: reduceMotion,
                isPlaceholderRedacted: isPlaceholderRedacted,
                redactionReasonsDebug: reasonsDebug
            )
        }

        return WWClockSecondsMotion(
            wantsSweep: wantsSweep,
            enabled: true,
            reasonShort: "enabled",
            isLowPowerMode: isLowPowerMode,
            reduceMotion: reduceMotion,
            isPlaceholderRedacted: isPlaceholderRedacted,
            redactionReasonsDebug: reasonsDebug
        )
    }

    /// Matches the dial diameter computed inside `WidgetWeaverClockIconView` (2R),
    /// so the seconds ring/tip aligns with the face.
    private static func dialDiameterAlignedToIconView(for size: CGSize, scale: CGFloat) -> CGFloat {
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
        return R * 2.0
    }
}

// MARK: - Seconds driver: host-animated tip using ProgressView(timerInterval:)

private struct WWClockSecondsProgressTipHand: View {
    let minuteAnchor: Date
    let dialDiameter: CGFloat
    let colour: Color
    let epsilon: TimeInterval

    var body: some View {
        let start = minuteAnchor
        let end = minuteAnchor.addingTimeInterval(60.0)

        let lagStart = start.addingTimeInterval(epsilon)
        let lagEnd = end.addingTimeInterval(epsilon)

        ZStack {
            ProgressView(timerInterval: start...end, countsDown: false)
                .progressViewStyle(.circular)
                .tint(colour)
                .labelsHidden()

            ProgressView(timerInterval: lagStart...lagEnd, countsDown: false)
                .progressViewStyle(.circular)
                .tint(colour)
                .labelsHidden()
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .controlSize(.mini)
        .frame(width: dialDiameter, height: dialDiameter)
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
private struct WWClockDebugOverlay: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode
    let motion: WWClockSecondsMotion
    let dialDiameter: CGFloat
    let epsilon: TimeInterval

    var body: some View {
        let tickLabel = (tickMode == .secondsSweep) ? "sweep" : "minute"
        let secsLabel = motion.enabled ? "ON" : "OFF"

        VStack(alignment: .leading, spacing: 2) {
            Text("dbg \(tickLabel) secs \(secsLabel)")
            Text("why \(motion.reasonShort)  LPM:\(motion.isLowPowerMode ? 1 : 0) RM:\(motion.reduceMotion ? 1 : 0) ph:\(motion.isPlaceholderRedacted ? 1 : 0)")
            Text("red \(motion.redactionReasonsDebug)")
            Text("e \(fmt(entryDate))  a \(fmt(minuteAnchor))")
            Text("drv ProgressView(timerInterval) tip ε=\(String(format: "%.2fs", epsilon))")

            ProgressView(timerInterval: minuteAnchor...(minuteAnchor.addingTimeInterval(60.0)), countsDown: false)
                .progressViewStyle(.linear)
                .labelsHidden()
                .frame(width: 150, height: 4)
                .tint(palette.accent)

            WWClockSecondsProgressTipHand(
                minuteAnchor: minuteAnchor,
                dialDiameter: 18,
                colour: palette.accent,
                epsilon: epsilon
            )
            .frame(width: 18, height: 18)
            .opacity(motion.enabled ? 1.0 : 0.35)
        }
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .foregroundStyle(.white.opacity(0.92))
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(6)
        .background(.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private func fmt(_ d: Date) -> String {
        Self.df.string(from: d)
    }
}
#endif
