//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI
import WidgetKit
#if canImport(UIKit)
import UIKit
#endif

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval

    @Environment(\.redactionReasons) private var redactionReasons

    var body: some View {
        let isPlaceholder = redactionReasons.contains(.placeholder)
        let isPrivacy = redactionReasons.contains(.privacy)

        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        let isReduceMotion: Bool = {
            #if canImport(UIKit)
            return UIAccessibility.isReduceMotionEnabled
            #else
            return false
            #endif
        }()

        let secondsEnabled =
            (tickMode == .secondsSweep)
            && !isPlaceholder
            && !isPrivacy
            && !isLowPowerMode
            && !isReduceMotion

        let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0
        let interval = Self.updateInterval(tickMode: tickMode, tickSeconds: tickSeconds)

        TimelineView(.periodic(from: entryDate, by: interval)) { context in
            WidgetWeaverRenderClock.withNow(context.date) {
                let angles = WWClockMonotonicAngles(date: context.date)

                ZStack(alignment: .bottomTrailing) {
                    WidgetWeaverClockIconView(
                        palette: palette,
                        hourAngle: .degrees(angles.hour),
                        minuteAngle: .degrees(angles.minute),
                        secondAngle: .degrees(angles.second),
                        showsSecondHand: secondsEnabled,
                        showsHandShadows: true,
                        showsGlows: true,
                        showsCentreHub: true,
                        handsOpacity: handsOpacity
                    )
                    .privacySensitive(isPrivacy)
                    .widgetURL(URL(string: "widgetweaver://clock"))
                    .animation(secondsEnabled ? .linear(duration: interval) : nil, value: angles.second)

                    // Time-based Text keeps the widget host in a live rendering mode on some Home Screen paths.
                    WWClockWidgetHeartbeat(start: Date())
                }
            }
        }
    }

    private static func updateInterval(
        tickMode: WidgetWeaverClockTickMode,
        tickSeconds: TimeInterval
    ) -> TimeInterval {
        switch tickMode {
        case .minuteOnly:
            return 60.0
        case .secondsSweep:
            let clamped = max(1.0, min(60.0, tickSeconds))
            return clamped
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

// MARK: - Angles

private struct WWClockMonotonicAngles {
    let hour: Double
    let minute: Double
    let second: Double

    init(date: Date) {
        // Local “wall-clock seconds” (epoch + GMT offset) preserves DST jumps correctly.
        let tz = TimeZone.autoupdatingCurrent
        let local = date.timeIntervalSince1970 + TimeInterval(tz.secondsFromGMT(for: date))

        // Keep magnitudes small so SwiftUI transform quantisation does not erase per-second deltas.
        // A 7-day cycle avoids daily wrap and stays comfortably within float precision.
        let secondsPerCycle: Double = 86_400.0 * 7.0
        let t = Self.positiveRemainder(local, secondsPerCycle)

        self.second = t * 6.0
        self.minute = t * (360.0 / 3_600.0)
        self.hour = t * (360.0 / 43_200.0)
    }

    private static func positiveRemainder(_ value: Double, _ modulus: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: modulus)
        return (r >= 0) ? r : (r + modulus)
    }
}
