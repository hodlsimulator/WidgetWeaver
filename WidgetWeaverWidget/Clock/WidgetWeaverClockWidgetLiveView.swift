//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit

private enum WWClockDebugStorage {
    static let overlayEnabledKey = "widgetweaver.clock.debug.overlay.enabled"
    static let lastRenderTSKey = "widgetweaver.clock.widget.render.last.ts"
    static let lastRenderInfoKey = "widgetweaver.clock.widget.render.info"
    static let fontOKKey = "widgetweaver.clock.font.ok"
    static let renderThrottleTSKey = "widgetweaver.clock.widget.render.throttle.ts"

    static func isOverlayEnabled() -> Bool {
        AppGroup.userDefaults.bool(forKey: overlayEnabledKey)
    }

    static func recordRender(info: String, fontOK: Bool) {
        let defaults = AppGroup.userDefaults
        if !defaults.bool(forKey: overlayEnabledKey) {
            return
        }

        let now = Date().timeIntervalSince1970
        let last = defaults.double(forKey: renderThrottleTSKey)
        if (now - last) < 20.0 {
            return
        }

        defaults.set(now, forKey: renderThrottleTSKey)
        defaults.set(now, forKey: lastRenderTSKey)
        defaults.set(info, forKey: lastRenderInfoKey)
        defaults.set(fontOK, forKey: fontOKKey)
        defaults.synchronize()
    }
}

private enum WWClockSecondHandTimerConfig {
    static let minuteSpilloverSeconds: TimeInterval = 6.0
    static let timerStartBiasSeconds: TimeInterval = 0.25
    static let pauseAtSeconds: TimeInterval = 59.0
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPrivacy = redactionReasons.contains(.privacy)
            let debugOverlayEnabled = WWClockDebugStorage.isOverlayEnabled()

            let minuteAnchor = Self.floorToMinute(entryDate)
            let base = WWClockBaseAngles(date: minuteAnchor)

            let showSeconds = (tickMode == .secondsSweep)

            let timerStart = minuteAnchor.addingTimeInterval(-WWClockSecondHandTimerConfig.timerStartBiasSeconds)
            let timerEnd = minuteAnchor.addingTimeInterval(60.0 + WWClockSecondHandTimerConfig.minuteSpilloverSeconds)
            let timerRange = timerStart...timerEnd

            let pauseTime = minuteAnchor.addingTimeInterval(WWClockSecondHandTimerConfig.pauseAtSeconds)

            let _ = WWClockSecondHandFont.font(size: 12)
            let fontOK = UIFont(name: WWClockSecondHandFont.postScriptName, size: 12) != nil

            let info =
                "privacy=\(isPrivacy ? 1 : 0) " +
                "sec=\(showSeconds ? 1 : 0) " +
                "font=\(fontOK ? 1 : 0) " +
                "rm=\(reduceMotion ? 1 : 0) " +
                "dt=\(String(describing: dynamicTypeSize)) " +
                "entry=\(Int(entryDate.timeIntervalSinceReferenceDate))"

            let _ = WWClockDebugStorage.recordRender(info: info, fontOK: fontOK)

            let handsOpacity: Double = isPrivacy ? 0.85 : 1.0

            ZStack {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(base.hour),
                    minuteAngle: .degrees(base.minute),
                    secondAngle: .degrees(0.0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: false,
                    handsOpacity: handsOpacity
                )

                WWClockSecondsAndHubOverlay(
                    palette: palette,
                    timerRange: timerRange,
                    pauseTime: pauseTime,
                    showsSeconds: showSeconds,
                    handsOpacity: handsOpacity,
                    fontOK: fontOK
                )
            }
            .overlay(alignment: .topLeading) {
                if debugOverlayEnabled {
                    WWClockWidgetDebugOverlay(
                        timerRange: timerRange,
                        isPrivacy: isPrivacy,
                        showSeconds: showSeconds,
                        fontOK: fontOK,
                        reduceMotion: reduceMotion,
                        dynamicTypeSize: dynamicTypeSize
                    )
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.layoutDirection, .leftToRight)
        }
    }

    private static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

// MARK: - Minute-boundary angles (tick)

private struct WWClockBaseAngles {
    let hour: Double
    let minute: Double

    init(date: Date) {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.hour, .minute], from: date)

        let hour24 = Double(comps.hour ?? 0)
        let minuteInt = Double(comps.minute ?? 0)

        let hour12 = hour24.truncatingRemainder(dividingBy: 12.0)

        self.minute = minuteInt * 6.0
        self.hour = (hour12 + (minuteInt / 60.0)) * 30.0
    }
}

// MARK: - Seconds + hub overlay (time-aware seconds hand)

private struct WWClockSecondsAndHubOverlay: View {
    let palette: WidgetWeaverClockPalette
    let timerRange: ClosedRange<Date>
    let pauseTime: Date
    let showsSeconds: Bool
    let handsOpacity: Double
    let fontOK: Bool

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let layout = WWClockDialLayout(size: proxy.size, scale: displayScale)

            ZStack {
                if showsSeconds {
                    WWClockSecondHandGlyphView(
                        palette: palette,
                        timerRange: timerRange,
                        pauseTime: pauseTime,
                        diameter: layout.dialDiameter,
                        fontOK: fontOK
                    )
                    .opacity(handsOpacity)
                }

                WidgetWeaverClockCentreHubView(
                    palette: palette,
                    baseRadius: layout.hubBaseRadius,
                    capRadius: layout.hubCapRadius,
                    scale: displayScale
                )
                .opacity(handsOpacity)
            }
            .frame(width: layout.dialDiameter, height: layout.dialDiameter)
            .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.5)
            .clipShape(Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct WWClockSecondHandGlyphView: View {
    let palette: WidgetWeaverClockPalette
    let timerRange: ClosedRange<Date>
    let pauseTime: Date
    let diameter: CGFloat
    let fontOK: Bool

    var body: some View {
        Group {
            if fontOK {
                Text(timerInterval: timerRange, pauseTime: pauseTime, countsDown: false, showsHours: false)
                    .font(WWClockSecondHandFont.font(size: diameter))
            } else {
                Text(timerInterval: timerRange, pauseTime: pauseTime, countsDown: false, showsHours: false)
                    .font(.system(size: max(12, diameter * 0.16), weight: .semibold, design: .monospaced))
            }
        }
        .foregroundStyle(palette.accent)
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .frame(width: diameter, height: diameter, alignment: .center)
        .shadow(color: palette.handShadow, radius: diameter * 0.012, x: 0, y: diameter * 0.006)
        .shadow(color: palette.accent.opacity(0.35), radius: diameter * 0.018, x: 0, y: 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWClockWidgetDebugOverlay: View {
    let timerRange: ClosedRange<Date>
    let isPrivacy: Bool
    let showSeconds: Bool
    let fontOK: Bool
    let reduceMotion: Bool
    let dynamicTypeSize: DynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("CLK DBG")
                .font(.caption2.weight(.semibold))

            Text("privacy \(isPrivacy ? 1 : 0)  sec \(showSeconds ? 1 : 0)  font \(fontOK ? "OK" : "NO")")
                .font(.caption2.monospacedDigit())

            Text("rm \(reduceMotion ? 1 : 0)  dt \(String(describing: dynamicTypeSize))")
                .font(.caption2.monospacedDigit())
                .opacity(0.85)

            Text(timerInterval: timerRange, countsDown: false)
                .font(.caption2.monospacedDigit())
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.55))
        )
        .foregroundStyle(Color.white.opacity(0.92))
        .padding(6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Dial layout (matches WidgetWeaverClockIconView)

private struct WWClockDialLayout {
    let dialDiameter: CGFloat
    let hubBaseRadius: CGFloat
    let hubCapRadius: CGFloat

    init(size: CGSize, scale: CGFloat) {
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
        self.dialDiameter = R * 2.0

        self.hubBaseRadius = WWClock.pixel(
            WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
            scale: scale
        )

        self.hubCapRadius = WWClock.pixel(
            WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
            scale: scale
        )
    }
}
