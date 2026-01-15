//
//  WidgetWeaverClockIconView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockIconView: View {
    let palette: WidgetWeaverClockPalette

    let hourAngle: Angle
    let minuteAngle: Angle
    let secondAngle: Angle

    let showsSecondHand: Bool
    let showsMinuteHand: Bool
    let showsHandShadows: Bool
    let showsGlows: Bool
    let showsCentreHub: Bool
    let handsOpacity: Double

    init(
        palette: WidgetWeaverClockPalette,
        hourAngle: Angle,
        minuteAngle: Angle,
        secondAngle: Angle,
        showsSecondHand: Bool = true,
        showsMinuteHand: Bool = true,
        showsHandShadows: Bool = true,
        showsGlows: Bool = true,
        showsCentreHub: Bool = true,
        handsOpacity: Double = 1.0
    ) {
        self.palette = palette
        self.hourAngle = hourAngle
        self.minuteAngle = minuteAngle
        self.secondAngle = secondAngle
        self.showsSecondHand = showsSecondHand
        self.showsMinuteHand = showsMinuteHand
        self.showsHandShadows = showsHandShadows
        self.showsGlows = showsGlows
        self.showsCentreHub = showsCentreHub
        self.handsOpacity = handsOpacity
    }

    var body: some View {
        GeometryReader { proxy in
            let displayScale = proxy.environment.displayScale
            let s = min(proxy.size.width, proxy.size.height)

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
            let dialRadius = R

            let hourLength = WWClock.pixel(
                WWClock.clamp(R * 0.60, min: R * 0.56, max: R * 0.64),
                scale: displayScale
            )

            let hourWidth = WWClock.pixel(
                WWClock.clamp(R * 0.090, min: R * 0.075, max: R * 0.105),
                scale: displayScale
            )

            let minuteLength = WWClock.pixel(
                WWClock.clamp(R * 0.84, min: R * 0.80, max: R * 0.88),
                scale: displayScale
            )

            let minuteWidth = WWClock.pixel(
                WWClock.clamp(R * 0.034, min: R * 0.028, max: R * 0.040),
                scale: displayScale
            )

            let usedMinuteLength: CGFloat = showsMinuteHand ? minuteLength : 0.0
            let usedMinuteWidth: CGFloat = showsMinuteHand ? minuteWidth : 0.0

            let secondLength = WWClock.pixel(
                WWClock.clamp(R * 0.90, min: R * 0.87, max: R * 0.94),
                scale: displayScale
            )

            let secondWidth = WWClock.pixel(
                WWClock.clamp(R * 0.010, min: R * 0.008, max: R * 0.012),
                scale: displayScale
            )

            let secondTipSide = WWClock.pixel(
                WWClock.clamp(R * 0.020, min: R * 0.016, max: R * 0.024),
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

            ZStack {
                WidgetWeaverClockFaceView(
                    palette: palette,
                    ringA: ringA,
                    ringB: ringB,
                    ringC: ringC,
                    dialRadius: dialRadius,
                    scale: displayScale
                )
                .frame(width: outerDiameter, height: outerDiameter)

                if showsHandShadows {
                    WidgetWeaverClockHandShadowsView(
                        palette: palette,
                        dialDiameter: dialDiameter,
                        hourAngle: hourAngle,
                        minuteAngle: minuteAngle,
                        hourLength: hourLength,
                        hourWidth: hourWidth,
                        minuteLength: usedMinuteLength,
                        minuteWidth: usedMinuteWidth,
                        scale: displayScale
                    )
                    .opacity(handsOpacity)
                }

                WidgetWeaverClockHandsView(
                    palette: palette,
                    dialDiameter: dialDiameter,
                    hourAngle: hourAngle,
                    minuteAngle: minuteAngle,
                    secondAngle: secondAngle,
                    hourLength: hourLength,
                    hourWidth: hourWidth,
                    minuteLength: usedMinuteLength,
                    minuteWidth: usedMinuteWidth,
                    secondLength: showsSecondHand ? secondLength : 0.0,
                    secondWidth: showsSecondHand ? secondWidth : 0.0,
                    secondTipSide: showsSecondHand ? secondTipSide : 0.0,
                    scale: displayScale
                )
                .opacity(handsOpacity)

                if showsGlows {
                    WidgetWeaverClockGlowsOverlayView(
                        palette: palette,
                        dialDiameter: dialDiameter,
                        secondAngle: secondAngle,
                        minuteAngle: minuteAngle,
                        secondLength: showsSecondHand ? secondLength : 0.0,
                        secondWidth: showsSecondHand ? secondWidth : 0.0,
                        minuteLength: usedMinuteLength,
                        minuteWidth: usedMinuteWidth,
                        scale: displayScale
                    )
                    .opacity(handsOpacity)
                }

                if showsCentreHub {
                    WidgetWeaverClockCentreHubView(
                        palette: palette,
                        baseRadius: hubBaseRadius,
                        capRadius: hubCapRadius,
                        scale: displayScale
                    )
                    .opacity(handsOpacity)
                }

                WidgetWeaverClockHandPipsView(
                    palette: palette,
                    dialRadius: dialRadius,
                    scale: displayScale
                )
                .frame(width: dialDiameter, height: dialDiameter)
                .clipShape(Circle())

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
        }
    }
}
