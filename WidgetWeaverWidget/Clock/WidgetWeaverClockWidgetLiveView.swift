//
//  WidgetWeaverClockWidgetLiveView.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/25/25.
//

import Foundation
import SwiftUI

struct WidgetWeaverClockWidgetLiveView: View {
    let palette: WidgetWeaverClockPalette

    @Environment(\.displayScale) private var displayScale

    private static let tickSeconds: TimeInterval = 2.0

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let layout = WWClockLayout(side: side, scale: displayScale)

            let now = WidgetWeaverRenderClock.now
            let angles = WWClockMonotonicAngles(date: now)

            ZStack {
                // Static face (time-independent).
                WWClockStaticFaceView(
                    palette: palette,
                    layout: layout,
                    scale: displayScale
                )
                .frame(width: layout.dialDiameter, height: layout.dialDiameter)
                .clipShape(Circle())

                // Dynamic overlay (time-dependent).
                WWClockDynamicOverlayView(
                    palette: palette,
                    layout: layout,
                    hourAngle: .degrees(angles.hourDegrees),
                    minuteAngle: .degrees(angles.minuteDegrees),
                    secondAngle: .degrees(angles.secondDegrees),
                    showsSecondHand: true,
                    handsOpacity: 1.0,
                    scale: displayScale
                )
                .frame(width: layout.dialDiameter, height: layout.dialDiameter)
                .clipShape(Circle())
                .animation(.linear(duration: Self.tickSeconds), value: angles.secondDegrees)

                // Bezel on top, static.
                WidgetWeaverClockBezelView(
                    palette: palette,
                    outerDiameter: layout.outerDiameter,
                    ringA: layout.ringA,
                    ringB: layout.ringB,
                    ringC: layout.ringC,
                    scale: displayScale
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Layout

private struct WWClockLayout {
    // Bezel
    let outerDiameter: CGFloat
    let ringA: CGFloat
    let ringB: CGFloat
    let ringC: CGFloat

    // Dial
    let dialRadius: CGFloat
    let dialDiameter: CGFloat
    let occlusionWidth: CGFloat

    // Markers
    let dotRadius: CGFloat
    let dotDiameter: CGFloat

    let batonCentreRadius: CGFloat
    let batonLength: CGFloat
    let batonWidth: CGFloat
    let capLength: CGFloat

    let pipSide: CGFloat
    let pipRadius: CGFloat

    let numeralsRadius: CGFloat
    let numeralsSize: CGFloat

    // Hands
    let hourLength: CGFloat
    let hourWidth: CGFloat

    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat

    // Hub
    let hubBaseRadius: CGFloat
    let hubCapRadius: CGFloat

    init(side: CGFloat, scale: CGFloat) {
        let s = max(1.0, side)

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
        let ringB = WWClock.pixel(
            max(minB, outerRadius - provisionalR - ringA - ringC),
            scale: scale
        )

        let R = outerRadius - ringA - ringB - ringC
        let dialDiameter = R * 2.0

        let occlusionWidth = WWClock.pixel(
            WWClock.clamp(R * 0.013, min: R * 0.010, max: R * 0.015),
            scale: scale
        )

        let dotRadius = WWClock.pixel(
            WWClock.clamp(R * 0.922, min: R * 0.910, max: R * 0.930),
            scale: scale
        )
        let dotDiameter = WWClock.pixel(
            WWClock.clamp(R * 0.010, min: R * 0.009, max: R * 0.011),
            scale: scale
        )

        let batonCentreRadius = WWClock.pixel(
            WWClock.clamp(R * 0.815, min: R * 0.780, max: R * 0.830),
            scale: scale
        )
        let batonLength = WWClock.pixel(
            WWClock.clamp(R * 0.155, min: R * 0.135, max: R * 0.170),
            scale: scale
        )
        let batonWidth = WWClock.pixel(
            WWClock.clamp(R * 0.034, min: R * 0.030, max: R * 0.038),
            scale: scale
        )
        let capLength = WWClock.pixel(
            WWClock.clamp(R * 0.026, min: R * 0.020, max: R * 0.030),
            scale: scale
        )

        let pipSide = WWClock.pixel(
            WWClock.clamp(R * 0.016, min: R * 0.014, max: R * 0.018),
            scale: scale
        )
        let pipInset = WWClock.pixel(1.5, scale: scale)
        let pipRadius = dotRadius - pipInset

        let numeralsRadius = WWClock.pixel(
            WWClock.clamp(R * 0.70, min: R * 0.66, max: R * 0.74),
            scale: scale
        )
        let numeralsSize = WWClock.pixel(R * 0.32, scale: scale)

        let hourLength = WWClock.pixel(
            WWClock.clamp(R * 0.50, min: R * 0.46, max: R * 0.54),
            scale: scale
        )
        let hourWidth = WWClock.pixel(
            WWClock.clamp(R * 0.18, min: R * 0.16, max: R * 0.20),
            scale: scale
        )

        let minuteLength = WWClock.pixel(
            WWClock.clamp(R * 0.84, min: R * 0.80, max: R * 0.86),
            scale: scale
        )
        let minuteWidth = WWClock.pixel(
            WWClock.clamp(R * 0.034, min: R * 0.030, max: R * 0.038),
            scale: scale
        )

        let secondLength = WWClock.pixel(
            WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92),
            scale: scale
        )
        let secondWidth = WWClock.pixel(
            WWClock.clamp(R * 0.006, min: R * 0.004, max: R * 0.007),
            scale: scale
        )
        let secondTipSide = WWClock.pixel(
            WWClock.clamp(R * 0.014, min: R * 0.012, max: R * 0.016),
            scale: scale
        )

        let hubBaseRadius = WWClock.pixel(
            WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
            scale: scale
        )
        let hubCapRadius = WWClock.pixel(
            WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
            scale: scale
        )

        self.outerDiameter = outerDiameter
        self.ringA = ringA
        self.ringB = ringB
        self.ringC = ringC

        self.dialRadius = R
        self.dialDiameter = dialDiameter
        self.occlusionWidth = occlusionWidth

        self.dotRadius = dotRadius
        self.dotDiameter = dotDiameter

        self.batonCentreRadius = batonCentreRadius
        self.batonLength = batonLength
        self.batonWidth = batonWidth
        self.capLength = capLength

        self.pipSide = pipSide
        self.pipRadius = pipRadius

        self.numeralsRadius = numeralsRadius
        self.numeralsSize = numeralsSize

        self.hourLength = hourLength
        self.hourWidth = hourWidth

        self.minuteLength = minuteLength
        self.minuteWidth = minuteWidth

        self.secondLength = secondLength
        self.secondWidth = secondWidth
        self.secondTipSide = secondTipSide

        self.hubBaseRadius = hubBaseRadius
        self.hubCapRadius = hubCapRadius
    }
}

// MARK: - Static face

private struct WWClockStaticFaceView: View {
    let palette: WidgetWeaverClockPalette
    let layout: WWClockLayout
    let scale: CGFloat

    var body: some View {
        ZStack {
            WidgetWeaverClockDialFaceView(
                palette: palette,
                radius: layout.dialRadius,
                occlusionWidth: layout.occlusionWidth
            )

            WidgetWeaverClockMinuteDotsView(
                count: 60,
                radius: layout.dotRadius,
                dotDiameter: layout.dotDiameter,
                dotColour: palette.minuteDot,
                scale: scale
            )

            WidgetWeaverClockHourIndicesView(
                palette: palette,
                dialDiameter: layout.dialDiameter,
                centreRadius: layout.batonCentreRadius,
                length: layout.batonLength,
                width: layout.batonWidth,
                capLength: layout.capLength,
                capColour: palette.accent,
                scale: scale
            )

            WidgetWeaverClockCardinalPipsView(
                pipColour: palette.accent,
                side: layout.pipSide,
                radius: layout.pipRadius
            )

            WidgetWeaverClockNumeralsView(
                palette: palette,
                radius: layout.numeralsRadius,
                fontSize: layout.numeralsSize,
                scale: scale
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Dynamic overlay

private struct WWClockDynamicOverlayView: View {
    let palette: WidgetWeaverClockPalette
    let layout: WWClockLayout

    let hourAngle: Angle
    let minuteAngle: Angle
    let secondAngle: Angle

    let showsSecondHand: Bool
    let handsOpacity: Double
    let scale: CGFloat

    var body: some View {
        let usedSecondLength: CGFloat = showsSecondHand ? layout.secondLength : 0.0
        let usedSecondWidth: CGFloat = showsSecondHand ? layout.secondWidth : 0.0
        let usedSecondTipSide: CGFloat = showsSecondHand ? layout.secondTipSide : 0.0

        ZStack {
            WidgetWeaverClockHandsView(
                palette: palette,
                dialDiameter: layout.dialDiameter,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                secondAngle: secondAngle,
                hourLength: layout.hourLength,
                hourWidth: layout.hourWidth,
                minuteLength: layout.minuteLength,
                minuteWidth: layout.minuteWidth,
                secondLength: usedSecondLength,
                secondWidth: usedSecondWidth,
                secondTipSide: usedSecondTipSide,
                scale: scale
            )

            WidgetWeaverClockCentreHubView(
                palette: palette,
                baseRadius: layout.hubBaseRadius,
                capRadius: layout.hubCapRadius,
                scale: scale
            )
        }
        .opacity(handsOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Monotonic angles

private struct WWClockMonotonicAngles {
    let hourDegrees: Double
    let minuteDegrees: Double
    let secondDegrees: Double

    init(date: Date) {
        let tz = TimeInterval(TimeZone.autoupdatingCurrent.secondsFromGMT(for: date))
        let localSeconds = date.timeIntervalSince1970 + tz

        secondDegrees = localSeconds * 6.0
        minuteDegrees = localSeconds * (360.0 / 3600.0)
        hourDegrees = localSeconds * (360.0 / 43200.0)
    }
}
