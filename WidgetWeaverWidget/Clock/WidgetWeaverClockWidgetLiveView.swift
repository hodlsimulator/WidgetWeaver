//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

// MARK: - Motion configuration

/// Implementation choices for the Home Screen clock motion experiments.
enum WidgetWeaverClockMotionImplementation {
    /// Prefer widget-host time-driven primitives (budget-safe when supported by the host).
    case timeDrivenPrimitives

    /// Use a short, tightly capped 1 Hz WidgetKit burst, then minute-level entries.
    case burstTimelineHybrid
}

/// Shared switches and constants for the clock motion experiments.
///
/// Keep values here deterministic and easy to adjust during on-device testing.
enum WidgetWeaverClockMotionConfig {
    /// Single switch: choose the motion implementation.
    static let implementation: WidgetWeaverClockMotionImplementation = .timeDrivenPrimitives

    /// While proving motion, keep rendering cheap (disable glows and heavy shadows).
    static let lightweightRendering: Bool = true

    /// Time window used by the ProgressView time driver.
    /// This must stay ahead of any sparse WidgetKit timeline refresh.
    static let timeDriverWindowSeconds: TimeInterval = 60.0 * 60.0 * 24.0 // 24 hours

    /// Hybrid burst window length (seconds).
    static let burstSeconds: Int = 120

    /// Minimum spacing between bursts (seconds).
    static let burstMinSpacingSeconds: TimeInterval = 60.0 * 30.0 // 30 minutes

    /// Hard cap for bursts per local calendar day.
    static let burstMaxPerDay: Int = 8

    /// Horizon covered by minute-level entries in hybrid burst mode.
    static let burstTimelineHorizonSeconds: TimeInterval = 60.0 * 60.0 * 6.0 // 6 hours

    #if DEBUG
    /// Debug overlay for verifying time-driven primitive refresh behaviour.
    static let debugOverlayEnabled: Bool = true
    #else
    static let debugOverlayEnabled: Bool = false
    #endif
}

// MARK: - Widget clock view

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    /// The current WidgetKit timeline entry date.
    let date: Date

    /// Anchor date (kept for compatibility / future use).
    let anchorDate: Date

    /// Desired tick interval indicated by the timeline strategy.
    /// - <= 1.0: seconds visible
    /// - > 1.0: minute-level (or slower) display
    let tickSeconds: TimeInterval

    var body: some View {
        let showsSecondHand = tickSeconds <= 1.0

        ZStack(alignment: .bottomTrailing) {
            clockBody(showsSecondHand: showsSecondHand)

            #if DEBUG
            if WidgetWeaverClockMotionConfig.debugOverlayEnabled {
                WidgetWeaverClockMotionDebugOverlay(
                    entryDate: date,
                    anchorDate: anchorDate,
                    tickSeconds: tickSeconds
                )
                .padding(6)
            }
            #endif
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func clockBody(showsSecondHand: Bool) -> some View {
        switch WidgetWeaverClockMotionConfig.implementation {
        case .timeDrivenPrimitives:
            if showsSecondHand, !ProcessInfo.processInfo.isLowPowerModeEnabled {
                timerDrivenClock(showsSecondHand: true)
            } else {
                // Low Power Mode (or minute-only): rely on timeline entries.
                clock(at: date, showsSecondHand: showsSecondHand)
            }

        case .burstTimelineHybrid:
            // In hybrid burst mode, the timeline entries are authoritative.
            clock(at: date, showsSecondHand: showsSecondHand)
        }
    }

    private func timerDrivenClock(showsSecondHand: Bool) -> some View {
        let start = date
        let end = start.addingTimeInterval(WidgetWeaverClockMotionConfig.timeDriverWindowSeconds)
        let interval: ClosedRange<Date> = start...end

        return ProgressView(timerInterval: interval, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(
            WWClockTimerDrivenProgressStyle(
                palette: palette,
                intervalStart: start,
                intervalSeconds: WidgetWeaverClockMotionConfig.timeDriverWindowSeconds,
                showsSecondHand: showsSecondHand,
                lightweightRendering: WidgetWeaverClockMotionConfig.lightweightRendering
            )
        )
    }

    @ViewBuilder
    private func clock(at now: Date, showsSecondHand: Bool) -> some View {
        let angles = WWClockBaseAngles(date: now)

        WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: .degrees(angles.hour),
            minuteAngle: .degrees(angles.minute),
            secondAngle: .degrees(angles.second),
            showsSecondHand: showsSecondHand,
            showsHandShadows: !WidgetWeaverClockMotionConfig.lightweightRendering,
            showsGlows: !WidgetWeaverClockMotionConfig.lightweightRendering,
            handsOpacity: 1.0
        )
    }
}

// MARK: - Timer-driven progress style

private struct WWClockTimerDrivenProgressStyle: ProgressViewStyle {
    let palette: WidgetWeaverClockPalette
    let intervalStart: Date
    let intervalSeconds: TimeInterval
    let showsSecondHand: Bool
    let lightweightRendering: Bool

    func makeBody(configuration: Configuration) -> some View {
        let rawFraction = configuration.fractionCompleted ?? 0.0
        let fraction = WWClockTimerDrivenProgressStyle.clamp01(rawFraction)
        let driverDate = intervalStart.addingTimeInterval(intervalSeconds * fraction)

        let angles = WWClockBaseAngles(date: driverDate)

        return WidgetWeaverClockIconView(
            palette: palette,
            hourAngle: .degrees(angles.hour),
            minuteAngle: .degrees(angles.minute),
            secondAngle: .degrees(angles.second),
            showsSecondHand: showsSecondHand,
            showsHandShadows: !lightweightRendering,
            showsGlows: !lightweightRendering,
            handsOpacity: 1.0
        )
        .accessibilityHidden(true)
    }

    @inline(__always)
    private static func clamp01(_ x: Double) -> Double {
        if x.isNaN || x.isInfinite { return 0.0 }
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
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
// MARK: - Motion debug overlay

private struct WidgetWeaverClockMotionDebugOverlay: View {
    let entryDate: Date
    let anchorDate: Date
    let tickSeconds: TimeInterval

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Text("timer")
                    .opacity(0.7)

                // Visible timer-based primitive (not derived from Date()).
                Text(timerInterval: anchorDate...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
            }

            // Visible ProgressView(timerInterval:) primitive.
            ProgressView(timerInterval: anchorDate...anchorDate.addingTimeInterval(60.0), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .frame(width: 72)

            Text("entry \(entryDate, format: .dateTime.hour().minute().second())")
                .opacity(0.7)

            Text("tick \(tickSeconds, format: .number.precision(.fractionLength(0)))s")
                .opacity(0.7)

            Text(WidgetWeaverClockMotionConfig.implementation == .timeDrivenPrimitives ? "mode time-driver" : "mode burst")
                .opacity(0.7)
        }
        .font(.system(size: 9, weight: .regular, design: .monospaced))
        .foregroundStyle(.primary.opacity(0.85))
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
}
#endif
