//
//  WidgetWeaverClockIconView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockIconView: View {
    let palette: WidgetWeaverClockPalette

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)

            // Outer metal diameter in widget space.
            let outerDiameter = WWClock.pixel(s * 0.925, scale: displayScale)
            let outerRadius = outerDiameter * 0.5

            // R is the dial radius at the INNER edge of the metal bezel.
            // Metal thickness target ≈ 0.055R–0.070R (choose 0.062R).
            let metalThicknessRatio: CGFloat = 0.062
            let provisionalR = outerRadius / (1.0 + metalThicknessRatio)

            // Bezel rings (A/B/C), computed from the provisional dial radius.
            let ringA = WWClock.pixel(provisionalR * 0.010, scale: displayScale)
            let ringC = WWClock.pixel(
                WWClock.clamp(provisionalR * 0.0095, min: provisionalR * 0.008, max: provisionalR * 0.012),
                scale: displayScale
            )

            // Ring B is the remaining metal thickness after A and C.
            let minB = WWClock.px(scale: displayScale)
            let ringB = WWClock.pixel(max(minB, outerRadius - provisionalR - ringA - ringC), scale: displayScale)

            // Final dial radius after pixel-rounded rings (ensures perfect concentric alignment).
            let R = outerRadius - ringA - ringB - ringC
            let dialDiameter = R * 2.0

            // Ring D: inner occlusion separator (tight, near-black).
            let occlusionWidth = WWClock.pixel(
                WWClock.clamp(R * 0.013, min: R * 0.010, max: R * 0.015),
                scale: displayScale
            )

            // Layout radii (content pushed outward).
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

            // Fixed “reference” pose.
            let hourAngle = Angle.degrees(310.0)   // ~10:20
            let minuteAngle = Angle.degrees(120.0) // ~4 o’clock
            let secondAngle = Angle.degrees(180.0) // 6 o’clock

            // Hands (slightly heavier hour wedge).
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

            // Hub
            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
                scale: displayScale
            )
            let hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: displayScale
            )

            ZStack {
                // Dial content (everything clipped to the dial circle)
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

                    WidgetWeaverClockHandShadowsView(
                        palette: palette,
                        dialDiameter: dialDiameter,
                        hourAngle: hourAngle,
                        minuteAngle: minuteAngle,
                        hourLength: hourLength,
                        hourWidth: hourWidth,
                        minuteLength: minuteLength,
                        minuteWidth: minuteWidth,
                        scale: displayScale
                    )

                    WidgetWeaverClockHandsView(
                        palette: palette,
                        dialDiameter: dialDiameter,
                        hourAngle: hourAngle,
                        minuteAngle: minuteAngle,
                        secondAngle: secondAngle,
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

                    WidgetWeaverClockGlowsOverlayView(
                        palette: palette,
                        hourCapCentreRadius: batonCentreRadius,
                        batonLength: batonLength,
                        batonWidth: batonWidth,
                        capLength: capLength,
                        pipSide: pipSide,
                        pipRadius: pipRadius,
                        minuteAngle: minuteAngle,
                        minuteLength: minuteLength,
                        minuteWidth: minuteWidth,
                        secondAngle: secondAngle,
                        secondLength: secondLength,
                        secondWidth: secondWidth,
                        secondTipSide: secondTipSide,
                        hubCutoutRadius: hubBaseRadius + hubCapRadius * 0.12,
                        scale: displayScale
                    )
                }
                .frame(width: dialDiameter, height: dialDiameter)
                .clipShape(Circle())

                // Bezel (layered metal rings A/B/C)
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
