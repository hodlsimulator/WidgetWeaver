//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

private enum WWClockWidgetLiveTuning {
    // Matches README observations: Home Screen widget updates often coalesce to ~2 seconds.
    static let tickSeconds: TimeInterval = 2.0

    // Always-on for now so the host behaviour is obvious during debugging.
    static let showDebugOverlay: Bool = true
}

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let s = min(size.width, size.height)

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
            let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: displayScale)

            let R = outerRadius - ringA - ringB - ringC
            let dialDiameter = R * 2.0

            let occlusionWidth = WWClock.pixel(
                WWClock.clamp(R * 0.013, min: R * 0.010, max: R * 0.015),
                scale: displayScale
            )

            let dotRadius = WWClock.pixel(
                WWClock.clamp(R * 0.922, min: R * 0.910, max: R * 0.930),
                scale: displayScale
            )
            let dotDiameter = WWClock.pixel(
                WWClock.clamp(R * 0.010, min: R * 0.009, max: R * 0.011),
                scale: displayScale
            )

            let batonCentreRadius = WWClock.pixel(
                WWClock.clamp(R * 0.815, min: R * 0.780, max: R * 0.830),
                scale: displayScale
            )
            let batonLength = WWClock.pixel(
                WWClock.clamp(R * 0.155, min: R * 0.135, max: R * 0.170),
                scale: displayScale
            )
            let batonWidth = WWClock.pixel(
                WWClock.clamp(R * 0.034, min: R * 0.030, max: R * 0.038),
                scale: displayScale
            )
            let capLength = WWClock.pixel(
                WWClock.clamp(R * 0.026, min: R * 0.020, max: R * 0.030),
                scale: displayScale
            )

            let pipSide = WWClock.pixel(
                WWClock.clamp(R * 0.016, min: R * 0.014, max: R * 0.018),
                scale: displayScale
            )
            let pipInset = WWClock.pixel(1.5, scale: displayScale)
            let pipRadius = dotRadius - pipInset

            let numeralsRadius = WWClock.pixel(
                WWClock.clamp(R * 0.70, min: R * 0.66, max: R * 0.74),
                scale: displayScale
            )
            let numeralsSize = WWClock.pixel(R * 0.32, scale: displayScale)

            let hourLength = WWClock.pixel(
                WWClock.clamp(R * 0.50, min: R * 0.46, max: R * 0.54),
                scale: displayScale
            )
            let hourWidth = WWClock.pixel(
                WWClock.clamp(R * 0.18, min: R * 0.16, max: R * 0.20),
                scale: displayScale
            )

            let minuteLength = WWClock.pixel(
                WWClock.clamp(R * 0.84, min: R * 0.80, max: R * 0.86),
                scale: displayScale
            )
            let minuteWidth = WWClock.pixel(
                WWClock.clamp(R * 0.034, min: R * 0.030, max: R * 0.038),
                scale: displayScale
            )

            let secondLength = WWClock.pixel(
                WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
                scale: displayScale
            )
            let secondWidth = WWClock.pixel(
                WWClock.clamp(R * 0.006, min: R * 0.004, max: R * 0.007),
                scale: displayScale
            )
            let secondTipSide = WWClock.pixel(
                WWClock.clamp(R * 0.014, min: R * 0.012, max: R * 0.016),
                scale: displayScale
            )

            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
                scale: displayScale
            )
            let hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: displayScale
            )

            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    ZStack {
                        WidgetWeaverClockDialFaceView(
                            palette: palette,
                            radius: R,
                            occlusionWidth: occlusionWidth
                        )

                        WidgetWeaverClockMinuteDotsView(
                            count: 60,
                            radius: dotRadius,
                            dotDiameter: dotDiameter,
                            dotColour: palette.minuteDot,
                            scale: displayScale
                        )

                        WidgetWeaverClockHourIndicesView(
                            palette: palette,
                            dialDiameter: dialDiameter,
                            centreRadius: batonCentreRadius,
                            length: batonLength,
                            width: batonWidth,
                            capLength: capLength,
                            capColour: palette.accent,
                            scale: displayScale
                        )

                        WidgetWeaverClockCardinalPipsView(
                            pipColour: palette.accent,
                            side: pipSide,
                            radius: pipRadius
                        )

                        WidgetWeaverClockNumeralsView(
                            palette: palette,
                            radius: numeralsRadius,
                            fontSize: numeralsSize,
                            scale: displayScale
                        )
                    }
                    .frame(width: dialDiameter, height: dialDiameter)
                    .clipShape(Circle())
                    .compositingGroup()

                    TimelineView(.periodic(from: Date(), by: WWClockWidgetLiveTuning.tickSeconds)) { context in
                        let angles = WidgetWeaverClockAngles(now: context.date)

                        ZStack {
                            WidgetWeaverClockHandsView(
                                palette: palette,
                                dialDiameter: dialDiameter,
                                hourAngle: angles.hour,
                                minuteAngle: angles.minute,
                                secondAngle: angles.second,
                                hourLength: hourLength,
                                hourWidth: hourWidth,
                                minuteLength: minuteLength,
                                minuteWidth: minuteWidth,
                                secondLength: secondLength,
                                secondWidth: secondWidth,
                                secondTipSide: secondTipSide,
                                scale: displayScale
                            )

                            WidgetWeaverClockCentreHubView(
                                palette: palette,
                                baseRadius: hubBaseRadius,
                                capRadius: hubCapRadius,
                                scale: displayScale
                            )
                        }
                        .frame(width: dialDiameter, height: dialDiameter)
                        .animation(.linear(duration: WWClockWidgetLiveTuning.tickSeconds), value: angles.secondDegrees)
                    }

                    WidgetWeaverClockBezelView(
                        palette: palette,
                        outerDiameter: outerDiameter,
                        ringA: ringA,
                        ringB: ringB,
                        ringC: ringC,
                        scale: displayScale
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)

                if WWClockWidgetLiveTuning.showDebugOverlay {
                    TimelineView(.periodic(from: Date(), by: WWClockWidgetLiveTuning.tickSeconds)) { context in
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(context.date, format: .dateTime.hour().minute().second())
                            Text("CLK V3")
                        }
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary.opacity(0.55))
                    }
                    .padding(6)
                }
            }
        }
    }
}

private struct WidgetWeaverClockAngles {
    let hour: Angle
    let minute: Angle
    let second: Angle

    let secondDegrees: Double

    init(now: Date) {
        let tz = TimeInterval(TimeZone.current.secondsFromGMT(for: now))
        let local = now.timeIntervalSince1970 + tz

        let secondDeg = local * 6.0
        let minuteDeg = local * (360.0 / 3600.0)
        let hourDeg = local * (360.0 / 43200.0)

        self.secondDegrees = secondDeg
        self.second = .degrees(secondDeg)
        self.minute = .degrees(minuteDeg)
        self.hour = .degrees(hourDeg)
    }
}
