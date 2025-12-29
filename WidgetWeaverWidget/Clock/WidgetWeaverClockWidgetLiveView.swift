//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

// MARK: - Motion configuration

enum WidgetWeaverClockMotionImplementation {
    /// Seconds are delivered only by timeline entries (burst + minute fallback).
    case burstTimelineHybrid
}

enum WidgetWeaverClockMotionConfig {
    /// Shipping path (time-driven primitives are not viable on this device/OS state).
    static let implementation: WidgetWeaverClockMotionImplementation = .burstTimelineHybrid

    /// Keep seconds renders cheap.
    static let lightweightDuringSeconds: Bool = true

    /// 1 Hz burst length for each burst timeline.
    static let burstSeconds: Int = 120

    /// When chaining bursts, WidgetKit is asked for a new timeline at burst end.
    ///
    /// This is the only remaining lever to approximate “ticks while visible”.
    #if DEBUG
    static let burstChainingEnabled: Bool = true
    #else
    static let burstChainingEnabled: Bool = true
    #endif

    /// Hard cap for how long chained bursts are allowed to continue.
    static let burstSessionMaxSeconds: TimeInterval = 60.0 * 30.0 // 30 minutes

    /// Hard cap for sessions per local day.
    static let burstSessionMaxPerDay: Int = 2

    /// Minimum spacing between session starts.
    static let burstSessionMinSpacingSeconds: TimeInterval = 60.0 * 60.0 * 4.0 // 4 hours

    /// Minute timeline horizon (used outside bursts, and after bursts).
    /// Keep this modest to avoid very large timelines.
    static let minuteHorizonSeconds: TimeInterval = 60.0 * 60.0 * 2.0 // 2 hours

    /// Keep timelines bounded to avoid silent failures on device.
    static let maxTimelineEntries: Int = 240

    #if DEBUG
    static let debugOverlayEnabled: Bool = true
    #else
    static let debugOverlayEnabled: Bool = false
    #endif
}

// MARK: - Widget clock view

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let date: Date
    let anchorDate: Date
    let tickSeconds: TimeInterval

    var body: some View {
        let showsSecondHand = tickSeconds <= 1.0
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let lightweight = (WidgetWeaverClockMotionConfig.lightweightDuringSeconds && showsSecondHand) || isLowPower

        ZStack(alignment: .bottomTrailing) {
            let angles = WWClockBaseAngles(date: date)

            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(angles.hour),
                minuteAngle: .degrees(angles.minute),
                secondAngle: .degrees(angles.second),
                showsSecondHand: showsSecondHand && !isLowPower,
                showsHandShadows: !lightweight,
                showsGlows: !lightweight,
                handsOpacity: 1.0
            )

            #if DEBUG
            if WidgetWeaverClockMotionConfig.debugOverlayEnabled {
                WidgetWeaverClockHybridDebugOverlay(
                    entryDate: date,
                    tickSeconds: tickSeconds
                )
                .padding(6)
            }
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Angle maths

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double
    let second: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)
        let secondInt = Double(comps.second ?? 0)
        let nano = Double(comps.nanosecond ?? 0)

        let sec = secondInt + (nano / 1_000_000_000.0)
        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        self.second = sec * 6.0
        self.minute = (minuteInt + sec / 60.0) * 6.0
        self.hour = (hour12 + minuteInt / 60.0 + sec / 3600.0) * 30.0
    }
}

#if DEBUG
// MARK: - Debug overlay

private struct WidgetWeaverClockHybridDebugOverlay: View {
    let entryDate: Date
    let tickSeconds: TimeInterval

    var body: some View {
        let defaults = AppGroup.userDefaults
        let now = Date()
        let dayKey = Self.dayKey(for: now)

        let timelineCount = defaults.integer(forKey: "widgetweaver.clock.timelineBuild.count.\(dayKey)")
        let sessionCount = defaults.integer(forKey: "widgetweaver.clock.session.count.\(dayKey)")

        let lastTimelineBuild = (defaults.object(forKey: "widgetweaver.clock.timelineBuild.last") as? Date) ?? .distantPast
        let sessionUntil = (defaults.object(forKey: "widgetweaver.clock.session.until") as? Date) ?? .distantPast
        let sessionRemaining = max(0, Int(sessionUntil.timeIntervalSince(now).rounded(.down)))

        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isSeconds = tickSeconds <= 1.0

        VStack(alignment: .trailing, spacing: 4) {
            Text("mode burst-hybrid")
                .opacity(0.85)

            Text(isLowPower ? "LPM on" : "LPM off")
                .opacity(0.75)

            Text(isSeconds ? "ticks: seconds" : "ticks: minute")
                .opacity(0.75)

            Text("entry \(entryDate, format: .dateTime.hour().minute().second())")
                .opacity(0.75)

            Text("lastBuild \(lastTimelineBuild, format: .dateTime.hour().minute().second())")
                .opacity(0.75)

            Text("buildsToday \(timelineCount)")
                .opacity(0.75)

            Text("sessionsToday \(sessionCount)")
                .opacity(0.75)

            if sessionUntil > now {
                Text("sessionLeft \(sessionRemaining)s")
                    .opacity(0.85)
            } else {
                Text("sessionLeft 0s")
                    .opacity(0.75)
            }
        }
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .foregroundStyle(.primary.opacity(0.86))
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
