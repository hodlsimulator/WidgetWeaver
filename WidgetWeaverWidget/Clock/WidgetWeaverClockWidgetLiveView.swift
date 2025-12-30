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
    let isRedacted: Bool
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
        let motion = Self.computeMotion(
            tickMode: tickMode,
            isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            reduceMotion: reduceMotion,
            isRedacted: !redactionReasons.isEmpty
        )

        GeometryReader { proxy in
            let base = WWClockAngles(date: minuteAnchor)
            let dialDiameter = Self.dialDiameter(for: proxy.size, scale: displayScale)

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

                // Seconds “hand” driven by the same host mechanism as ProgressView(timerInterval:).
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
        isRedacted: Bool
    ) -> WWClockSecondsMotion {
        let wantsSweep = (tickMode == .secondsSweep)

        if !wantsSweep {
            return WWClockSecondsMotion(
                wantsSweep: wantsSweep,
                enabled: false,
                reasonShort: "tickMode",
                isLowPowerMode: isLowPowerMode,
                reduceMotion: reduceMotion,
                isRedacted: isRedacted
            )
        }

        if isLowPowerMode {
            return WWClockSecondsMotion(
                wantsSweep: wantsSweep,
                enabled: false,
                reasonShort: "LPM",
                isLowPowerMode: isLowPowerMode,
                reduceMotion: reduceMotion,
                isRedacted: isRedacted
            )
        }

        if reduceMotion {
            return WWClockSecondsMotion(
                wantsSweep: wantsSweep,
                enabled: false,
                reasonShort: "RM",
                isLowPowerMode: isLowPowerMode,
                reduceMotion: reduceMotion,
                isRedacted: isRedacted
            )
        }

        if isRedacted {
            return WWClockSecondsMotion(
                wantsSweep: wantsSweep,
                enabled: false,
                reasonShort: "redact",
                isLowPowerMode: isLowPowerMode,
                reduceMotion: reduceMotion,
                isRedacted: isRedacted
            )
        }

        return WWClockSecondsMotion(
            wantsSweep: wantsSweep,
            enabled: true,
            reasonShort: "enabled",
            isLowPowerMode: isLowPowerMode,
            reduceMotion: reduceMotion,
            isRedacted: isRedacted
        )
    }

    private static func dialDiameter(for size: CGSize, scale: CGFloat) -> CGFloat {
        // Keep this aligned with the clock’s rendered dial scale.
        // The previous clock view uses ~0.925 of the shortest side.
        let s = min(size.width, size.height)
        return WWClock.pixel(s * 0.925, scale: scale)
    }
}

// MARK: - Seconds driver: host-animated tip using ProgressView(timerInterval:)

/// Creates a moving “tip” by subtracting a slightly delayed circular progress from the leading one.
/// This is host-driven (like your moving linear progress bar) and does not require SwiftUI to tick.
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

            ProgressView(timerInterval: lagStart...lagEnd, countsDown: false)
                .progressViewStyle(.circular)
                .tint(colour)
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
// MARK: - Debug overlay

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
            Text("why \(motion.reasonShort)  LPM:\(motion.isLowPowerMode ? 1 : 0) RM:\(motion.reduceMotion ? 1 : 0) red:\(motion.isRedacted ? 1 : 0)")
            Text("e \(fmt(entryDate))  a \(fmt(minuteAnchor))")
            Text("drv ProgressView(timerInterval) tip ε=\(String(format: "%.2fs", epsilon))")

            // Known-good moving probe (your screenshot already proved this animates).
            ProgressView(timerInterval: minuteAnchor...(minuteAnchor.addingTimeInterval(60.0)), countsDown: false)
                .progressViewStyle(.linear)
                .frame(width: 140, height: 4)
                .tint(palette.accent)

            // Small circular probe: should move if circular timer progress is animated.
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
