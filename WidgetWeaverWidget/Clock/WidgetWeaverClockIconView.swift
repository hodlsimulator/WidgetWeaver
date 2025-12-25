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

            // Circular coordinate system: centre C and radius R (outer edge of the dial bezel).
            let outerDiameter = s * 0.925
            let R = outerDiameter * 0.5

            let bezelWidth = WWClock.pixel(WWClock.clamp(R * 0.064, min: R * 0.055, max: R * 0.070), scale: displayScale)
            let separatorWidth = WWClock.pixel(WWClock.clamp(R * 0.016, min: R * 0.014, max: R * 0.018), scale: displayScale)

            let dialRadius = R - bezelWidth - separatorWidth
            let dialDiameter = dialRadius * 2.0

            // Dial layout
            let dotRadius = WWClock.pixel(WWClock.clamp(R * 0.922, min: R * 0.910, max: R * 0.930), scale: displayScale)
            let dotDiameter = WWClock.pixel(WWClock.clamp(R * 0.011, min: R * 0.010, max: R * 0.012), scale: displayScale)

            let batonCentreRadius = WWClock.pixel(WWClock.clamp(R * 0.805, min: R * 0.79, max: R * 0.82), scale: displayScale)
            let batonLength = WWClock.pixel(WWClock.clamp(R * 0.133, min: R * 0.12, max: R * 0.145), scale: displayScale)
            let batonWidth = WWClock.pixel(WWClock.clamp(R * 0.032, min: R * 0.028, max: R * 0.036), scale: displayScale)

            let capLength = WWClock.pixel(WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.030), scale: displayScale)

            let pipSide = WWClock.pixel(WWClock.clamp(R * 0.017, min: R * 0.015, max: R * 0.020), scale: displayScale)
            let pipRadius = WWClock.pixel(dotRadius - dotDiameter * 1.15, scale: displayScale)

            let numeralsRadius = WWClock.pixel(R * 0.60, scale: displayScale)
            let numeralsSize = WWClock.pixel(R * 0.325, scale: displayScale)

            // Hands
            let hourAngle = Angle.degrees(310.0)   // ~10:20
            let minuteAngle = Angle.degrees(120.0) // ~4 o’clock
            let secondAngle = Angle.degrees(180.0) // 6 o’clock

            let hourLength = WWClock.pixel(WWClock.clamp(R * 0.46, min: R * 0.42, max: R * 0.48), scale: displayScale)
            let hourWidth = WWClock.pixel(WWClock.clamp(R * 0.175, min: R * 0.14, max: R * 0.20), scale: displayScale)

            let minuteLength = WWClock.pixel(WWClock.clamp(R * 0.83, min: R * 0.79, max: R * 0.85), scale: displayScale)
            let minuteWidth = WWClock.pixel(WWClock.clamp(R * 0.032, min: R * 0.026, max: R * 0.038), scale: displayScale)

            let secondLength = WWClock.pixel(WWClock.clamp(R * 0.90, min: R * 0.86, max: R * 0.92), scale: displayScale)
            let secondWidth = WWClock.pixel(WWClock.clamp(R * 0.0055, min: R * 0.004, max: R * 0.007), scale: displayScale)
            let secondTipSide = WWClock.pixel(WWClock.clamp(R * 0.014, min: R * 0.011, max: R * 0.016), scale: displayScale)

            // Hub
            let hubBaseRadius = WWClock.pixel(WWClock.clamp(R * 0.045, min: R * 0.038, max: R * 0.052), scale: displayScale)
            let hubCapRadius = WWClock.pixel(WWClock.clamp(R * 0.026, min: R * 0.022, max: R * 0.032), scale: displayScale)

            ZStack {
                // Dial content (everything clipped to the dial circle before compositing onto the bezel)
                ZStack {
                    WidgetWeaverClockDialFaceView(palette: palette, radius: dialRadius)

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

                // Bezel group (3-component ring + separator + occlusion)
                WidgetWeaverClockBezelView(
                    palette: palette,
                    outerDiameter: outerDiameter,
                    bezelWidth: bezelWidth,
                    separatorWidth: separatorWidth,
                    dialDiameter: dialDiameter,
                    scale: displayScale
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
        }
    }
}
