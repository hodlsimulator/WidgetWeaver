//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/29/25.
//

import SwiftUI
import WidgetKit
import UIKit
import Foundation

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let tickMode: WidgetWeaverClockTickMode
    let tickSeconds: TimeInterval

    @Environment(\.redactionReasons) private var redactionReasons
    @Environment(\.displayScale) private var displayScale

    init(
        palette: WidgetWeaverClockPalette,
        entryDate: Date,
        tickMode: WidgetWeaverClockTickMode,
        tickSeconds: TimeInterval
    ) {
        self.palette = palette
        self.entryDate = entryDate
        self.tickMode = tickMode
        self.tickSeconds = tickSeconds
    }

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPlaceholder = redactionReasons.contains(.placeholder)
            let isPrivacy = redactionReasons.contains(.privacy)

            let secondsEnabled =
                (tickMode == .secondsSweep)
                && !isPlaceholder
                && !isPrivacy

            let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0
            let baseAngles = WWClockBaseAngles(date: entryDate)

            ZStack(alignment: .bottomTrailing) {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(baseAngles.hour),
                    minuteAngle: .degrees(baseAngles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    showsCentreHub: !secondsEnabled,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)

                if secondsEnabled {
                    ZStack {
                        WWClockSecondHandWedgeTickOverlay(
                            palette: palette,
                            entryDate: entryDate,
                            handsOpacity: handsOpacity
                        )

                        GeometryReader { proxy in
                            let geo = WWClockDialGeometry(
                                containerSize: min(proxy.size.width, proxy.size.height),
                                scale: displayScale
                            )

                            WidgetWeaverClockCentreHubView(
                                palette: palette,
                                baseRadius: geo.hubBaseRadius,
                                capRadius: geo.hubCapRadius,
                                scale: displayScale
                            )
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .opacity(handsOpacity)
                        }
                    }
                }

                WWClockWidgetHeartbeat(start: entryDate)
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Geometry

private struct WWClockDialGeometry {
    let dialDiameter: CGFloat
    let radius: CGFloat

    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat

    let hubBaseRadius: CGFloat
    let hubCapRadius: CGFloat

    init(containerSize s: CGFloat, scale: CGFloat) {
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
        self.radius = R
        self.dialDiameter = R * 2.0

        self.secondLength = WWClock.pixel(
            WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
            scale: scale
        )
        self.secondWidth = WWClock.pixel(
            WWClock.clamp(R * 0.006, min: R * 0.004, max: R * 0.007),
            scale: scale
        )
        self.secondTipSide = WWClock.pixel(
            WWClock.clamp(R * 0.014, min: R * 0.012, max: R * 0.016),
            scale: scale
        )

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

// MARK: - Seconds overlay (centre-reaching wedge)

private struct WWClockSecondHandWedgeTickOverlay: View {
    let palette: WidgetWeaverClockPalette
    let entryDate: Date
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let geo = WWClockDialGeometry(containerSize: min(proxy.size.width, proxy.size.height), scale: displayScale)

            let startOfMinute = WWClockTime.minuteAnchor(entryDate: entryDate)
            let endOfMinute = startOfMinute.addingTimeInterval(60.0)

            ZStack {
                ZStack {
                    ForEach(0..<60, id: \.self) { tick in
                        let angle = Angle.degrees(Double(tick) * 6.0)
                        WidgetWeaverClockSecondHandView(
                            colour: palette.accent,
                            width: geo.secondWidth,
                            length: geo.secondLength,
                            angle: angle,
                            tipSide: geo.secondTipSide,
                            scale: displayScale
                        )
                    }
                }
                .opacity(handsOpacity)

                WWClockSecondHandOutsideWedgeMatte(
                    start: startOfMinute,
                    end: endOfMinute,
                    dialDiameter: geo.dialDiameter,
                    windowSeconds: 1.0
                )
                .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: geo.dialDiameter, height: geo.dialDiameter)
            .clipShape(Circle())
            .frame(width: proxy.size.width, height: proxy.size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct WWClockSecondHandOutsideWedgeMatte: View {
    let start: Date
    let end: Date
    let dialDiameter: CGFloat
    let windowSeconds: TimeInterval

    var body: some View {
        ZStack {
            Color.white

            WWClockSecondHandWedgeWindow(
                start: start,
                end: end,
                dialDiameter: dialDiameter,
                windowSeconds: windowSeconds
            )
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: dialDiameter, height: dialDiameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWClockThickCircularProgress: View {
    let interval: ClosedRange<Date>
    let dialDiameter: CGFloat
    let thicknessScale: CGFloat

    var body: some View {
        ProgressView(timerInterval: interval, countsDown: false)
            .progressViewStyle(.circular)
            .tint(Color.white)
            .frame(width: dialDiameter, height: dialDiameter)
            .scaleEffect(thicknessScale)
            .frame(width: dialDiameter, height: dialDiameter)
            .clipShape(Circle())
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct WWClockSecondHandWedgeWindow: View {
    let start: Date
    let end: Date
    let dialDiameter: CGFloat
    let windowSeconds: TimeInterval

    private let thicknessScale: CGFloat = 8.0

    var body: some View {
        let leadStart = start.addingTimeInterval(-windowSeconds)
        let leadEnd = end.addingTimeInterval(-windowSeconds)

        ZStack {
            WWClockThickCircularProgress(
                interval: leadStart...leadEnd,
                dialDiameter: dialDiameter,
                thicknessScale: thicknessScale
            )

            WWClockThickCircularProgress(
                interval: start...end,
                dialDiameter: dialDiameter,
                thicknessScale: thicknessScale
            )
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: dialDiameter, height: dialDiameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum WWClockTime {
    static func minuteAnchor(entryDate: Date) -> Date {
        let systemNow = Date()

        if entryDate > systemNow { return floorToMinute(systemNow) }
        if systemNow.timeIntervalSince(entryDate) > 90.0 { return floorToMinute(systemNow) }

        return floorToMinute(entryDate)
    }

    static func floorToMinute(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let floored = floor(t / 60.0) * 60.0
        return Date(timeIntervalSinceReferenceDate: floored)
    }
}

// MARK: - Heartbeat

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

// MARK: - Base angles (minute-anchored)

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
