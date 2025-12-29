//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

enum WidgetWeaverClockMotionImplementation {
    case burstTimelineHybrid
}

enum WidgetWeaverClockMotionConfig {
    static let implementation: WidgetWeaverClockMotionImplementation = .burstTimelineHybrid
    static let lightweightSecondsRendering: Bool = true

    #if DEBUG
    static let debugOverlayEnabled: Bool = true
    #else
    static let debugOverlayEnabled: Bool = false
    #endif
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let date: Date
    let anchorDate: Date
    let tickSeconds: TimeInterval

    var body: some View {
        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isSeconds = (tickSeconds <= 1.0) && !isLowPower

        ZStack(alignment: .bottomTrailing) {
            if isSeconds && WidgetWeaverClockMotionConfig.lightweightSecondsRendering {
                WidgetWeaverClockSecondsLiteView(
                    palette: palette,
                    date: date,
                    showsSecondHand: true
                )
            } else {
                let angles = WWClockBaseAngles(date: date)

                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(angles.hour),
                    minuteAngle: .degrees(angles.minute),
                    secondAngle: .degrees(angles.second),
                    showsSecondHand: isSeconds,
                    showsHandShadows: !isSeconds,
                    showsGlows: !isSeconds,
                    handsOpacity: 1.0
                )
            }

            #if DEBUG
            if WidgetWeaverClockMotionConfig.debugOverlayEnabled {
                WidgetWeaverClockHybridDebugOverlay(
                    entryDate: date,
                    tickSeconds: tickSeconds
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

private struct WidgetWeaverClockSecondsLiteView: View {
    let palette: WidgetWeaverClockPalette
    let date: Date
    let showsSecondHand: Bool

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let angles = WWClockBaseAngles(date: date)

        return GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let ring = WWClock.pixel(max(1.0, side * 0.045), scale: displayScale)

            let hourLen = side * 0.22
            let minLen = side * 0.32
            let secLen = side * 0.36

            let hourW = WWClock.pixel(max(1.0, side * 0.060), scale: displayScale)
            let minW = WWClock.pixel(max(1.0, side * 0.045), scale: displayScale)
            let secW = WWClock.pixel(max(1.0, side * 0.016), scale: displayScale)

            let hub = WWClock.pixel(max(2.0, side * 0.085), scale: displayScale)

            ZStack {
                Circle()
                    .fill(palette.dialEdge)

                Circle()
                    .strokeBorder(palette.separatorRing.opacity(0.55), lineWidth: ring)

                hand(
                    colour: palette.handMid.opacity(0.95),
                    width: hourW,
                    length: hourLen,
                    angleDegrees: angles.hour
                )

                hand(
                    colour: palette.handLight.opacity(0.95),
                    width: minW,
                    length: minLen,
                    angleDegrees: angles.minute
                )

                if showsSecondHand {
                    hand(
                        colour: palette.accent.opacity(0.95),
                        width: secW,
                        length: secLen,
                        angleDegrees: angles.second
                    )
                }

                Circle()
                    .fill(palette.hubBase.opacity(0.95))
                    .frame(width: hub, height: hub)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func hand(colour: Color, width: CGFloat, length: CGFloat, angleDegrees: Double) -> some View {
        Rectangle()
            .fill(colour)
            .frame(width: width, height: length)
            .offset(y: -length / 2.0)
            .rotationEffect(.degrees(angleDegrees))
    }
}

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
private struct WidgetWeaverClockHybridDebugOverlay: View {
    let entryDate: Date
    let tickSeconds: TimeInterval

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        let now = Date()
        let isPlaceholderRedacted = redactionReasons.contains(.placeholder)

        let isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let isSeconds = (tickSeconds <= 1.0) && !isLowPower

        let cal = Calendar.autoupdatingCurrent
        let s = cal.component(.second, from: entryDate)

        let defaults = AppGroup.userDefaults
        let dayKey = Self.dayKey(for: now)

        let sessionUntil = (defaults.object(forKey: "widgetweaver.clock.session.until") as? Date) ?? .distantPast
        let sessionActive = sessionUntil > now
        let sessionLeft = max(0, Int(sessionUntil.timeIntervalSince(now).rounded(.down)))

        let buildsToday = defaults.integer(forKey: "widgetweaver.clock.timelineBuild.count.\(dayKey)")
        let sessionsToday = defaults.integer(forKey: "widgetweaver.clock.session.count.\(dayKey)")

        VStack(alignment: .trailing, spacing: 4) {
            Text("clock debug")
                .opacity(0.85)

            Text(isPlaceholderRedacted ? "redacted: placeholder" : "redacted: none")
                .opacity(0.80)

            Text(isLowPower ? "LPM on" : "LPM off")
                .opacity(0.80)

            Text(isSeconds ? "mode: seconds" : "mode: minute")
                .opacity(0.80)

            Text("tickSeconds \(Int(tickSeconds.rounded()))")
                .opacity(0.80)

            Text("entrySec \(String(format: "%02d", s))")
                .opacity(0.80)

            Text(sessionActive ? "session active" : "session inactive")
                .opacity(0.80)

            Text("sessionLeft \(sessionLeft)s")
                .opacity(0.80)

            Text("buildsToday \(buildsToday)")
                .opacity(0.75)

            Text("sessionsToday \(sessionsToday)")
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
