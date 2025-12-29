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
        let wantsSeconds = (tickMode == .secondsSweep)

        // IMPORTANT:
        // Low Power Mode forces minute-only.
        // Reduce Motion is reported in the debug overlay, but it does not currently gate seconds
        // while the seconds mechanism is being proven reliable.
        let secondsEnabled = wantsSeconds && !isLowPower

        ZStack(alignment: .bottomTrailing) {
            if secondsEnabled {
                WidgetWeaverClockSecondHandSweepView(
                    palette: palette,
                    minuteAnchor: minuteAnchor,
                    showsGlows: WidgetWeaverClockMotionConfig.secondsShowsGlows,
                    showsHandShadows: WidgetWeaverClockMotionConfig.secondsShowsHandShadows
                )
                // No .id(minuteAnchor...) here.
                // Restarting the sweep happens via onChange(of: minuteAnchor) inside the sweep view.
            } else {
                let angles = WWClockAngles(date: minuteAnchor)

                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(angles.hour),
                    minuteAngle: .degrees(angles.minute),
                    secondAngle: .degrees(0.0),
                    showsSecondHand: false,
                    showsHandShadows: WidgetWeaverClockMotionConfig.minuteShowsHandShadows,
                    showsGlows: WidgetWeaverClockMotionConfig.minuteShowsGlows,
                    handsOpacity: 1.0
                )
            }

            #if DEBUG
            if WidgetWeaverClockMotionConfig.debugOverlayEnabled {
                WidgetWeaverClockSweepDebugOverlay(
                    entryDate: entryDate,
                    minuteAnchor: minuteAnchor,
                    tickMode: tickMode,
                    secondsEnabled: secondsEnabled,
                    isLowPower: isLowPower,
                    reduceMotion: reduceMotion,
                    isPlaceholderRedacted: redactionReasons.contains(.placeholder)
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

// MARK: - Seconds sweep view

private struct WidgetWeaverClockSecondHandSweepView: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date
    let showsGlows: Bool
    let showsHandShadows: Bool

    @State private var secondAngleDegrees: Double = 0.0
    @State private var lastConfiguredAnchorRef: TimeInterval = -1.0

    var body: some View {
        let base = WWClockAngles(date: minuteAnchor)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: .degrees(base.hour),
            minuteAngle: .degrees(base.minute),
            secondAngle: .degrees(secondAngleDegrees),
            showsSecondHand: true,
            showsHandShadows: showsHandShadows,
            showsGlows: showsGlows,
            handsOpacity: 1.0
        )
        .onAppear {
            configureAndStartSweepIfNeeded(for: minuteAnchor)
        }
        .onChange(of: minuteAnchor) { _, newAnchor in
            configureAndStartSweepIfNeeded(for: newAnchor)
        }
    }

    private func configureAndStartSweepIfNeeded(for anchor: Date) {
        let anchorRef = anchor.timeIntervalSinceReferenceDate
        guard anchorRef != lastConfiguredAnchorRef else { return }
        lastConfiguredAnchorRef = anchorRef

        let now = Date()
        let nextMinute = anchor.addingTimeInterval(60.0)

        let rawSeconds = now.timeIntervalSince(anchor)
        let secondsIntoMinute = Self.clamp(rawSeconds, min: 0.0, max: 59.999)

        let remainingRaw = nextMinute.timeIntervalSince(now)
        let remaining = Self.clamp(remainingRaw, min: 0.0, max: 60.0)

        // Place the hand immediately (no animation), then start the sweep.
        var noAnim = Transaction()
        noAnim.animation = nil
        withTransaction(noAnim) {
            secondAngleDegrees = secondsIntoMinute * 6.0
        }

        // If the remaining time is effectively zero, snap to 12 and wait for the next minuteAnchor.
        guard remaining > 0.05 else {
            withTransaction(noAnim) {
                secondAngleDegrees = 360.0
            }
            return
        }

        // One linear sweep to 12 over the remainder of the minute.
        DispatchQueue.main.async {
            withAnimation(.linear(duration: remaining)) {
                secondAngleDegrees = 360.0
            }
        }
    }

    private static func clamp(_ x: Double, min a: Double, max b: Double) -> Double {
        if x < a { return a }
        if x > b { return b }
        return x
    }
}

// MARK: - Angle maths

private struct WWClockAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)

        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        // Stepped minute hand: exact minute.
        self.minute = minuteInt * 6.0

        // Hour hand moves in minute steps.
        self.hour = (hour12 + minuteInt / 60.0) * 30.0
    }
}

#if DEBUG
// MARK: - Debug overlay

private struct WidgetWeaverClockSweepDebugOverlay: View {
    let entryDate: Date
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode
    let secondsEnabled: Bool
    let isLowPower: Bool
    let reduceMotion: Bool
    let isPlaceholderRedacted: Bool

    var body: some View {
        let now = Date()
        let defaults = AppGroup.userDefaults
        let dayKey = Self.dayKey(for: now)

        let buildsToday = defaults.integer(forKey: "widgetweaver.clock.timelineBuild.count.\(dayKey)")
        let lastBuild = (defaults.object(forKey: "widgetweaver.clock.timelineBuild.last") as? Date) ?? .distantPast

        let modeText: String = {
            switch tickMode {
            case .minuteOnly: return "minute"
            case .secondsSweep: return "secondsSweep"
            }
        }()

        let secondsIntoMinute = Int(max(0, now.timeIntervalSince(minuteAnchor)).truncatingRemainder(dividingBy: 60.0))

        VStack(alignment: .trailing, spacing: 4) {
            Text("clock debug")
                .opacity(0.85)

            Text(isPlaceholderRedacted ? "redacted: placeholder" : "redacted: none")
                .opacity(0.80)

            Text(isLowPower ? "LPM on" : "LPM off")
                .opacity(0.80)

            Text(reduceMotion ? "reduceMotion on" : "reduceMotion off")
                .opacity(0.80)

            Text("mode \(modeText)")
                .opacity(0.80)

            Text(secondsEnabled ? "secondsEnabled true" : "secondsEnabled false")
                .opacity(0.80)

            Text("secInMin \(secondsIntoMinute)")
                .opacity(0.80)

            Text("entry \(entryDate, format: .dateTime.hour().minute().second())")
                .opacity(0.75)

            Text("anchor \(minuteAnchor, format: .dateTime.hour().minute().second())")
                .opacity(0.75)

            Text("lastBuild \(lastBuild, format: .dateTime.hour().minute().second())")
                .opacity(0.75)

            Text("buildsToday \(buildsToday)")
                .opacity(0.75)
        }
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .foregroundStyle(.primary.opacity(0.88))
        .padding(6)
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

    private static func dayKey(for date: Date) -> String {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.year, .month, .day], from: date)

        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0

        return String(format: "%04d%02d%02d", y, m, d)
    }
}
#endif
