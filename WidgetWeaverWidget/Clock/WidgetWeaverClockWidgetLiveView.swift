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
    case timeDrivenPrimitives
    case burstTimelineHybrid
}

enum WidgetWeaverClockMotionConfig {
    static let implementation: WidgetWeaverClockMotionImplementation = .timeDrivenPrimitives

    /// While proving motion, keep rendering cheap.
    static let lightweightRendering: Bool = true

    /// Time window used by the ProgressView time driver.
    static let timeDriverWindowSeconds: TimeInterval = 60.0 * 60.0 * 24.0 // 24 hours

    static let burstSeconds: Int = 120
    static let burstMinSpacingSeconds: TimeInterval = 60.0 * 30.0
    static let burstMaxPerDay: Int = 8
    static let burstTimelineHorizonSeconds: TimeInterval = 60.0 * 60.0 * 6.0

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
                clock(at: date, showsSecondHand: showsSecondHand)
            }

        case .burstTimelineHybrid:
            clock(at: date, showsSecondHand: showsSecondHand)
        }
    }

    /// Attempts to tick by making the clock a pure function of a host-driven time primitive.
    ///
    /// Important: the interval start is anchored to the snapshot render time (Date()) to avoid
    /// “ENTRY is stale” effects while testing.
    private func timerDrivenClock(showsSecondHand: Bool) -> some View {
        let start = Self.floorToWholeSecond(Date())
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

    private static func floorToWholeSecond(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: floor(t))
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
        let fraction = Self.clamp01(rawFraction)
        let driverDate = intervalStart.addingTimeInterval(intervalSeconds * fraction)

        let angles = WWClockBaseAngles(date: driverDate)

        if lightweightRendering {
            return AnyView(
                WWClockUltraLightView(
                    hourAngleDegrees: angles.hour,
                    minuteAngleDegrees: angles.minute,
                    secondAngleDegrees: angles.second,
                    showsSecondHand: showsSecondHand
                )
            )
        }

        return AnyView(
            WidgetWeaverClockIconView(
                palette: palette,
                hourAngle: .degrees(angles.hour),
                minuteAngle: .degrees(angles.minute),
                secondAngle: .degrees(angles.second),
                showsSecondHand: showsSecondHand,
                showsHandShadows: true,
                showsGlows: true,
                handsOpacity: 1.0
            )
        )
    }

    @inline(__always)
    private static func clamp01(_ x: Double) -> Double {
        if x.isNaN || x.isInfinite { return 0.0 }
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }
}

// MARK: - Ultra-light ticking clock (diagnostic-friendly)

private struct WWClockUltraLightView: View {
    let hourAngleDegrees: Double
    let minuteAngleDegrees: Double
    let secondAngleDegrees: Double
    let showsSecondHand: Bool

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let centreDot = side * 0.06

            ZStack {
                Circle()
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: max(1.0, side * 0.035))

                hand(
                    width: max(1.0, side * 0.06),
                    length: side * 0.27,
                    angle: hourAngleDegrees,
                    opacity: 0.85
                )

                hand(
                    width: max(1.0, side * 0.045),
                    length: side * 0.38,
                    angle: minuteAngleDegrees,
                    opacity: 0.85
                )

                if showsSecondHand {
                    hand(
                        width: max(1.0, side * 0.02),
                        length: side * 0.42,
                        angle: secondAngleDegrees,
                        opacity: 0.75
                    )
                }

                Circle()
                    .fill(Color.primary.opacity(0.9))
                    .frame(width: centreDot, height: centreDot)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func hand(width: CGFloat, length: CGFloat, angle: Double, opacity: Double) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(opacity))
            .frame(width: width, height: length)
            .offset(y: -length / 2.0)
            .rotationEffect(.degrees(angle))
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

private struct WidgetWeaverClockMotionDebugOverlay: View {
    let entryDate: Date
    let anchorDate: Date
    let tickSeconds: TimeInterval

    var body: some View {
        let snapNow = Self.floorToWholeSecond(Date())
        let snapRange = snapNow...snapNow.addingTimeInterval(60.0)

        let entryRange = anchorDate...anchorDate.addingTimeInterval(60.0)

        let entryAge = snapNow.timeIntervalSince(entryDate)
        let entryAgeInt = Int(entryAge.rounded())

        VStack(alignment: .trailing, spacing: 4) {
            Text(WidgetWeaverClockMotionConfig.implementation == .timeDrivenPrimitives ? "mode time-driver" : "mode burst")
                .opacity(0.8)

            Text("entryAge \(entryAgeInt)s")
                .opacity(0.8)

            // Timer text anchored to SNAP (should visibly change if Text(timerInterval:) is supported)
            HStack(spacing: 6) {
                Text("SNAP")
                    .opacity(0.7)

                Text(timerInterval: snapRange, countsDown: false)
                    .monospacedDigit()
            }

            // Timer text anchored to ENTRY (reveals stale-entry behaviour)
            HStack(spacing: 6) {
                Text("ENTRY")
                    .opacity(0.7)

                Text(timerInterval: entryRange, countsDown: false)
                    .monospacedDigit()
            }

            // Standard progress bars
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 6) {
                    Text("SNAP bar")
                        .opacity(0.7)
                    ProgressView(timerInterval: snapRange, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.linear)
                        .frame(width: 86)
                }

                HStack(spacing: 6) {
                    Text("ENTRY bar")
                        .opacity(0.7)
                    ProgressView(timerInterval: entryRange, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.linear)
                        .frame(width: 86)
                }

                // Custom-style fraction readout: if this DOES NOT change while SNAP bar moves,
                // the host is animating the native bar without updating configuration.fractionCompleted.
                HStack(spacing: 6) {
                    Text("SNAP frac")
                        .opacity(0.7)
                    ProgressView(timerInterval: snapRange, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(WWDebugFractionProgressStyle())
                        .frame(width: 86, height: 12)
                }
            }

            Text("tick \(tickSeconds, format: .number.precision(.fractionLength(0)))s")
                .opacity(0.7)
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

    private static func floorToWholeSecond(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: floor(t))
    }
}

private struct WWDebugFractionProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        let raw = configuration.fractionCompleted ?? 0.0
        let f = Self.clamp01(raw)
        let pct = Int((f * 100.0).rounded())

        return GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let fillW = max(0.0, min(w, w * CGFloat(f)))

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)

                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: fillW, height: h)

                Text("\(pct)%")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .frame(width: w, height: h, alignment: .center)
            }
        }
    }

    @inline(__always)
    private static func clamp01(_ x: Double) -> Double {
        if x.isNaN || x.isInfinite { return 0.0 }
        if x <= 0.0 { return 0.0 }
        if x >= 1.0 { return 1.0 }
        return x
    }
}
#endif
