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
        // Reduce Motion is reported in the debug overlay, but does not currently gate seconds
        // while the mechanism is being proven reliable.
        let secondsEnabled = wantsSeconds && !isLowPower

        ZStack(alignment: .bottomTrailing) {
            if secondsEnabled {
                WidgetWeaverClockSecondHandProgressDrivenView(
                    palette: palette,
                    minuteAnchor: minuteAnchor,
                    showsGlows: WidgetWeaverClockMotionConfig.secondsShowsGlows,
                    showsHandShadows: WidgetWeaverClockMotionConfig.secondsShowsHandShadows
                )
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
                WidgetWeaverClockClockDebugOverlay(
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

// MARK: - Seconds via ProgressView(timerInterval:...)

private struct WidgetWeaverClockSecondHandProgressDrivenView: View {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date
    let showsGlows: Bool
    let showsHandShadows: Bool

    var body: some View {
        let start = minuteAnchor
        let end = minuteAnchor.addingTimeInterval(60.0)

        // The Home Screen host will animate time-driven primitives (like ProgressView(timerInterval:...))
        // while the widget is visible. This avoids 1 Hz WidgetKit timelines.
        ProgressView(timerInterval: start...end, countsDown: false)
            .progressViewStyle(
                WidgetWeaverClockSecondHandProgressStyle(
                    palette: palette,
                    minuteAnchor: minuteAnchor,
                    showsGlows: showsGlows,
                    showsHandShadows: showsHandShadows
                )
            )
    }
}

private struct WidgetWeaverClockSecondHandProgressStyle: ProgressViewStyle {
    let palette: WidgetWeaverClockPalette
    let minuteAnchor: Date
    let showsGlows: Bool
    let showsHandShadows: Bool

    func makeBody(configuration: Configuration) -> some View {
        let fracRaw = configuration.fractionCompleted ?? 0.0
        let frac = Self.clamp(fracRaw, min: 0.0, max: 1.0)

        // Discrete “tick” seconds (0...60). At 1.0, show 60 -> 360° (hand at 12).
        let tickSeconds = Int((frac * 60.0).rounded(.down))
        let tickSecondsClamped = max(0, min(60, tickSeconds))
        let secondAngleDegrees = Double(tickSecondsClamped) * 6.0

        let base = WWClockAngles(date: minuteAnchor)

        return ZStack(alignment: .bottomTrailing) {
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

            #if DEBUG
            if WidgetWeaverClockMotionConfig.debugOverlayEnabled {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("driver progress")
                        .opacity(0.85)

                    Text(String(format: "frac %.3f", frac))
                        .opacity(0.80)

                    Text("tickSec \(tickSecondsClamped)")
                        .opacity(0.80)

                    Text(String(format: "secDeg %.1f", secondAngleDegrees))
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
                .padding(6)
                .accessibilityHidden(true)
            }
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
// MARK: - Debug overlay (entry + timeline build counters)

private struct WidgetWeaverClockClockDebugOverlay: View {
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

        // This is only a coarse “what minute are we in” value.
        // Seconds motion is driven by ProgressView(timerInterval:...) above.
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
