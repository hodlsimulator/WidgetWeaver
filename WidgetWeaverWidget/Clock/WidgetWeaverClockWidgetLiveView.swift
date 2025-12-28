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

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let layout = WWClockLayout(side: side, scale: displayScale)

            ZStack {
                // Static dial content (does not depend on time).
                WWClockStaticDialLayerView(
                    palette: palette,
                    layout: layout,
                    scale: displayScale
                )
                .frame(width: layout.dialDiameter, height: layout.dialDiameter)
                .clipShape(Circle())

                // Dynamic overlay (hands + dynamic glows), driven at 1 Hz.
                WWClockDynamicOverlayHostView(
                    palette: palette,
                    layout: layout,
                    showsSecondHand: true,
                    handsOpacity: 1.0,
                    scale: displayScale
                )
                .frame(width: layout.dialDiameter, height: layout.dialDiameter)
                .clipShape(Circle())

                // Bezel stays above everything and remains static.
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

        // Match the existing icon layout ratios.
        let outerDiameter = WWClock.pixel(s * 0.925, scale: scale)
        let outerRadius = outerDiameter * 0.5

        let metalThicknessRatio: CGFloat = 0.062
        let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

        let ringA = WWClock.pixel(provisionalR * 0.010, scale: scale)
        let ringC = WWClock.pixel(
            WWClock.clamp(
                provisionalR * 0.0095,
                min: provisionalR * 0.008,
                max: provisionalR * 0.012
            ),
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
            WWClock.clamp(
                R * 0.013,
                min: R * 0.010,
                max: R * 0.015
            ),
            scale: scale
        )

        let dotRadius = WWClock.pixel(
            WWClock.clamp(
                R * 0.922,
                min: R * 0.910,
                max: R * 0.930
            ),
            scale: scale
        )

        let dotDiameter = WWClock.pixel(
            WWClock.clamp(
                R * 0.010,
                min: R * 0.009,
                max: R * 0.011
            ),
            scale: scale
        )

        let batonCentreRadius = WWClock.pixel(
            WWClock.clamp(
                R * 0.815,
                min: R * 0.780,
                max: R * 0.830
            ),
            scale: scale
        )

        let batonLength = WWClock.pixel(
            WWClock.clamp(
                R * 0.155,
                min: R * 0.135,
                max: R * 0.170
            ),
            scale: scale
        )

        let batonWidth = WWClock.pixel(
            WWClock.clamp(
                R * 0.034,
                min: R * 0.030,
                max: R * 0.038
            ),
            scale: scale
        )

        let capLength = WWClock.pixel(
            WWClock.clamp(
                R * 0.026,
                min: R * 0.020,
                max: R * 0.030
            ),
            scale: scale
        )

        let pipSide = WWClock.pixel(
            WWClock.clamp(
                R * 0.016,
                min: R * 0.014,
                max: R * 0.018
            ),
            scale: scale
        )

        let pipInset = WWClock.pixel(1.5, scale: scale)
        let pipRadius = dotRadius - pipInset

        let numeralsRadius = WWClock.pixel(
            WWClock.clamp(
                R * 0.70,
                min: R * 0.66,
                max: R * 0.74
            ),
            scale: scale
        )

        let numeralsSize = WWClock.pixel(R * 0.32, scale: scale)

        let hourLength = WWClock.pixel(
            WWClock.clamp(
                R * 0.50,
                min: R * 0.46,
                max: R * 0.54
            ),
            scale: scale
        )

        let hourWidth = WWClock.pixel(
            WWClock.clamp(
                R * 0.18,
                min: R * 0.16,
                max: R * 0.20
            ),
            scale: scale
        )

        let minuteLength = WWClock.pixel(
            WWClock.clamp(
                R * 0.84,
                min: R * 0.80,
                max: R * 0.86
            ),
            scale: scale
        )

        let minuteWidth = WWClock.pixel(
            WWClock.clamp(
                R * 0.034,
                min: R * 0.030,
                max: R * 0.038
            ),
            scale: scale
        )

        let secondLength = WWClock.pixel(
            WWClock.clamp(
                R * 0.90,
                min: R * 0.86,
                max: R * 0.92
            ),
            scale: scale
        )

        let secondWidth = WWClock.pixel(
            WWClock.clamp(
                R * 0.006,
                min: R * 0.004,
                max: R * 0.007
            ),
            scale: scale
        )

        let secondTipSide = WWClock.pixel(
            WWClock.clamp(
                R * 0.014,
                min: R * 0.012,
                max: R * 0.016
            ),
            scale: scale
        )

        let hubBaseRadius = WWClock.pixel(
            WWClock.clamp(
                R * 0.047,
                min: R * 0.040,
                max: R * 0.055
            ),
            scale: scale
        )

        let hubCapRadius = WWClock.pixel(
            WWClock.clamp(
                R * 0.027,
                min: R * 0.022,
                max: R * 0.032
            ),
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

// MARK: - Static dial layer

private struct WWClockStaticDialLayerView: View {
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

            WWClockStaticGlowsView(
                palette: palette,
                hourCapCentreRadius: layout.batonCentreRadius,
                batonLength: layout.batonLength,
                batonWidth: layout.batonWidth,
                capLength: layout.capLength,
                pipSide: layout.pipSide,
                pipRadius: layout.pipRadius,
                scale: scale
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWClockStaticGlowsView: View {
    let palette: WidgetWeaverClockPalette

    let hourCapCentreRadius: CGFloat
    let batonLength: CGFloat
    let batonWidth: CGFloat
    let capLength: CGFloat

    let pipSide: CGFloat
    let pipRadius: CGFloat

    let scale: CGFloat

    private let hourIndices: [Int] = [1, 2, 4, 5, 7, 8, 10, 11]

    var body: some View {
        let px = WWClock.px(scale: scale)
        let capGlowBlur = max(px, capLength * 0.18)
        let pipGlowBlur = max(px, pipSide * 0.20)

        ZStack {
            ForEach(hourIndices, id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0
                RoundedRectangle(cornerRadius: batonWidth * 0.18, style: .continuous)
                    .fill(palette.accent.opacity(0.32))
                    .frame(width: batonWidth, height: capLength)
                    .offset(y: -(hourCapCentreRadius + (batonLength * 0.5) - (capLength * 0.5)))
                    .rotationEffect(.degrees(degrees))
                    .blur(radius: capGlowBlur)
                    .blendMode(.screen)
            }

            ForEach([3, 6, 9], id: \.self) { i in
                let degrees = (Double(i) / 12.0) * 360.0
                RoundedRectangle(cornerRadius: pipSide * 0.14, style: .continuous)
                    .fill(palette.accent.opacity(0.26))
                    .frame(width: pipSide, height: pipSide)
                    .offset(y: -pipRadius)
                    .rotationEffect(.degrees(degrees))
                    .blur(radius: pipGlowBlur)
                    .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Dynamic overlay host (1 Hz timeline + smoothing)

private struct WWClockDynamicOverlayHostView: View {
    let palette: WidgetWeaverClockPalette
    let layout: WWClockLayout
    let showsSecondHand: Bool
    let handsOpacity: Double
    let scale: CGFloat

    private let scheduleStart: Date

    @State private var angles: WWClockMonotonicAngles
    @State private var lastTickDate: Date

    init(
        palette: WidgetWeaverClockPalette,
        layout: WWClockLayout,
        showsSecondHand: Bool,
        handsOpacity: Double,
        scale: CGFloat
    ) {
        self.palette = palette
        self.layout = layout
        self.showsSecondHand = showsSecondHand
        self.handsOpacity = handsOpacity
        self.scale = scale

        let now = Date()
        self.scheduleStart = WWClockSecondAlignedSchedule.nextSecond(after: now)

        let initialAngles = WWClockMonotonicAngles(date: now)
        self._angles = State(initialValue: initialAngles)
        self._lastTickDate = State(initialValue: now)
    }

    var body: some View {
        TimelineView(.periodic(from: scheduleStart, by: 1.0)) { context in
            WWClockDynamicOverlayView(
                palette: palette,
                layout: layout,
                hourAngle: .degrees(angles.hourDegrees),
                minuteAngle: .degrees(angles.minuteDegrees),
                secondAngle: .degrees(angles.secondDegrees),
                showsSecondHand: showsSecondHand,
                handsOpacity: handsOpacity,
                scale: scale
            )
            .onAppear {
                let d = context.date
                lastTickDate = d
                angles = WWClockMonotonicAngles(date: d)
            }
            .onChange(of: context.date) { _, newDate in
                let dt = newDate.timeIntervalSince(lastTickDate)
                let newAngles = WWClockMonotonicAngles(date: newDate)

                if dt.isFinite, dt > 0, dt < 5.0 {
                    let duration = max(0.15, min(2.0, dt))
                    withAnimation(.linear(duration: duration)) {
                        angles = newAngles
                    }
                } else {
                    angles = newAngles
                }

                lastTickDate = newDate
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private enum WWClockSecondAlignedSchedule {
    static func nextSecond(after date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        let next = floor(t) + 1.0
        return Date(timeIntervalSinceReferenceDate: next)
    }
}

// MARK: - Dynamic overlay content (hands + dynamic glows + hub)

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
            WidgetWeaverClockHandShadowsView(
                palette: palette,
                dialDiameter: layout.dialDiameter,
                hourAngle: hourAngle,
                minuteAngle: minuteAngle,
                hourLength: layout.hourLength,
                hourWidth: layout.hourWidth,
                minuteLength: layout.minuteLength,
                minuteWidth: layout.minuteWidth,
                scale: scale
            )

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

            WWClockDynamicGlowsView(
                palette: palette,
                minuteAngle: minuteAngle,
                minuteLength: layout.minuteLength,
                minuteWidth: layout.minuteWidth,
                secondAngle: secondAngle,
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

private struct WWClockDynamicGlowsView: View {
    let palette: WidgetWeaverClockPalette

    let minuteAngle: Angle
    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    let secondAngle: Angle
    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let minuteGlowWidth = max(px, minuteWidth * 0.14)
        let minuteGlowBlur = max(px, minuteWidth * 0.20)

        let secondGlowBlur = max(px, secondWidth * 0.95)
        let secondTipGlowBlur = max(px, secondWidth * 1.05)

        ZStack {
            // Minute-hand edge emission glow.
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.accent.opacity(0.00), location: 0.00),
                            .init(color: palette.accent.opacity(0.08), location: 0.55),
                            .init(color: palette.accent.opacity(0.34), location: 1.00)
                        ]),
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: minuteGlowWidth, height: minuteLength)
                .offset(x: minuteWidth * 0.36, y: 0)
                .frame(width: minuteWidth, height: minuteLength)
                .rotationEffect(minuteAngle, anchor: .bottom)
                .offset(y: -minuteLength / 2.0)
                .blur(radius: minuteGlowBlur)
                .blendMode(.screen)

            if secondLength > 0.0, secondWidth > 0.0 {
                // Second-hand glow (minimal).
                Rectangle()
                    .fill(palette.accent.opacity(0.12))
                    .frame(width: secondWidth, height: secondLength)
                    .offset(y: -secondLength / 2.0)
                    .rotationEffect(secondAngle)
                    .blur(radius: secondGlowBlur)
                    .blendMode(.screen)

                // Terminal square glow.
                Rectangle()
                    .fill(palette.accent.opacity(0.18))
                    .frame(width: secondTipSide, height: secondTipSide)
                    .offset(y: -secondLength)
                    .rotationEffect(secondAngle)
                    .blur(radius: secondTipGlowBlur)
                    .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Monotonic angles (prevents reverse wrap at 59->00)

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
