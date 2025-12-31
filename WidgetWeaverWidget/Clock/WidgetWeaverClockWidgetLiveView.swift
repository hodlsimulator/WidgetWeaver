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
    let minuteAnchor: Date
    let tickMode: WidgetWeaverClockTickMode

    @Environment(\.redactionReasons) private var redactionReasons

    init(
        palette: WidgetWeaverClockPalette,
        entryDate: Date,
        minuteAnchor: Date,
        tickMode: WidgetWeaverClockTickMode
    ) {
        self.palette = palette
        self.entryDate = entryDate
        self.minuteAnchor = minuteAnchor
        self.tickMode = tickMode
    }

    var body: some View {
        WidgetWeaverRenderClock.withNow(entryDate) {
            let isPlaceholder = redactionReasons.contains(.placeholder)
            let isPrivacy = redactionReasons.contains(.privacy)
            let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            let isReduceMotion = UIAccessibility.isReduceMotionEnabled

            let secondsEnabled =
                (tickMode == .secondsSweep)
                && !isPlaceholder
                && !isPrivacy
                && !isLowPowerMode
                && !isReduceMotion

            let handsOpacity: Double = (isPlaceholder || isPrivacy) ? 0.85 : 1.0

            let baseAngles = WWClockBaseAngles(date: minuteAnchor)

            ZStack {
                WidgetWeaverClockIconView(
                    palette: palette,
                    hourAngle: .degrees(baseAngles.hour),
                    minuteAngle: .degrees(baseAngles.minute),
                    secondAngle: .degrees(0),
                    showsSecondHand: false,
                    showsHandShadows: true,
                    showsGlows: true,
                    handsOpacity: handsOpacity
                )
                .privacySensitive(isPrivacy)

                if secondsEnabled {
                    WWClockSecondHandHostDrivenNeedleOverlay(
                        palette: palette,
                        startOfMinute: minuteAnchor,
                        handsOpacity: handsOpacity
                    )
                }
            }
            .widgetURL(URL(string: "widgetweaver://clock"))
        }
    }
}

// MARK: - Host-driven seconds "needle" (no fractionCompleted dependency)

private struct WWClockSecondHandHostDrivenNeedleOverlay: View {
    let palette: WidgetWeaverClockPalette
    let startOfMinute: Date
    let handsOpacity: Double

    @Environment(\.displayScale) private var displayScale

    // Controls the visible “tail” size of the moving segment.
    // Larger = thicker/brighter needle, smaller = finer needle.
    private let trailSeconds: Double = 0.28

    // Controls how solid the needle looks.
    // More samples = more solid (but more expensive).
    private let radialSamples: Int = 14

    // Controls how close to centre the needle extends.
    // Smaller = extends closer to centre.
    private let innerScale: CGFloat = 0.20

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            // Mirror the clock geometry used by WidgetWeaverClockIconView.
            let outerDiameter = WWClock.pixel(s * 0.925, scale: displayScale)
            let outerRadius = outerDiameter * 0.5

            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            let ringA = WWClock.pixel(provisionalR * 0.010, scale: displayScale)
            let ringC = WWClock.pixel(
                WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
                scale: displayScale
            )
            let minB = WWClock.px(scale: displayScale)
            let ringB = WWClock.pixel(
                max(minB, outerRadius - provisionalR - ringA - ringC),
                scale: displayScale
            )

            let R = outerRadius - ringA - ringB - ringC

            let secondLength = WWClock.pixel(
                WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
                scale: displayScale
            )

            let needleDiameter = secondLength * 2.0

            let frontStart = startOfMinute
            let frontEnd = startOfMinute.addingTimeInterval(60.0)

            // Lagging copy used to carve out only the leading edge segment.
            let backStart = frontStart.addingTimeInterval(trailSeconds)
            let backEnd = frontEnd.addingTimeInterval(trailSeconds)

            ZStack {
                ForEach(0..<max(radialSamples, 1), id: \.self) { i in
                    let denom = CGFloat(max(radialSamples - 1, 1))
                    let t = CGFloat(i) / denom
                    let scale = innerScale + (1.0 - innerScale) * t

                    WWClockLeadingProgressSegment(
                        palette: palette,
                        front: frontStart...frontEnd,
                        back: backStart...backEnd
                    )
                    .frame(width: needleDiameter, height: needleDiameter)
                    .scaleEffect(scale)
                }
            }
            .frame(width: s, height: s)
            .opacity(handsOpacity)
            .compositingGroup()
            .overlay {
                // Centre cut-out keeps the hub from being occluded by the moving overlay.
                let cutoutDiameter = WWClock.pixel(R * 0.22, scale: displayScale)
                Circle()
                    .frame(width: cutoutDiameter, height: cutoutDiameter)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWClockLeadingProgressSegment: View {
    let palette: WidgetWeaverClockPalette
    let front: ClosedRange<Date>
    let back: ClosedRange<Date>

    var body: some View {
        ZStack {
            ProgressView(timerInterval: front, countsDown: false)
                .progressViewStyle(.circular)
                .tint(palette.accent)

            ProgressView(timerInterval: back, countsDown: false)
                .progressViewStyle(.circular)
                .tint(palette.accent)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
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
