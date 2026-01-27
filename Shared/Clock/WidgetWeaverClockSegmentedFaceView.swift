//
//  WidgetWeaverClockSegmentedFaceView.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI

/// Clock face renderer for Face = "segmented".
///
/// Step 2 scaffold:
/// - Uses a dedicated view so routing and geometry are stable.
/// - Renders only bezel + dial placeholders and reuses the existing hands + centre hub.
/// - Segment blocks, numerals, and tick marks are implemented in later steps.
struct WidgetWeaverClockSegmentedFaceView: View {
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

    @Environment(\.displayScale) private var displayScale

    init(
        palette: WidgetWeaverClockPalette,
        hourAngle: Angle = .degrees(310.0),
        minuteAngle: Angle = .degrees(120.0),
        secondAngle: Angle = .degrees(180.0),
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
            let s = min(proxy.size.width, proxy.size.height)

            let outerDiameter = WWClock.outerBezelDiameter(containerSide: s, scale: displayScale)
            let outerRadius = outerDiameter * 0.5

            // Mirror existing face geometry conventions so widget sizes remain stable.
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

            // Placeholder hand sizes (final segmented hands are added in a later step).
            let hourLength = WWClock.pixel(
                WWClock.clamp(R * 0.52, min: R * 0.48, max: R * 0.56),
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
                WWClock.clamp(R * 0.060, min: R * 0.052, max: R * 0.068),
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
                WWClock.clamp(R * 0.016, min: R * 0.012, max: R * 0.020),
                scale: displayScale
            )

            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.034, min: R * 0.030, max: R * 0.040),
                scale: displayScale
            )
            let hubCapRadius = WWClock.pixel(
                WWClock.clamp(R * 0.027, min: R * 0.022, max: R * 0.032),
                scale: displayScale
            )

            ZStack {
                ZStack {
                    // Dark dial base (placeholder).
                    WidgetWeaverClockDialFaceView(
                        palette: palette,
                        radius: R,
                        occlusionWidth: occlusionWidth
                    )

                    ZStack {
                        let usedSecondLength = showsSecondHand ? secondLength : 0.0
                        let usedSecondWidth = showsSecondHand ? secondWidth : 0.0
                        let usedSecondTipSide = showsSecondHand ? secondTipSide : 0.0

                        let usedMinuteLength = showsMinuteHand ? minuteLength : 0.0
                        let usedMinuteWidth = showsMinuteHand ? minuteWidth : 0.0

                        if showsHandShadows {
                            WidgetWeaverClockHandShadowsView(
                                palette: palette,
                                dialDiameter: dialDiameter,
                                hourAngle: hourAngle,
                                minuteAngle: minuteAngle,
                                hourLength: hourLength,
                                hourWidth: hourWidth,
                                hourHandStyle: .icon,
                                minuteLength: usedMinuteLength,
                                minuteWidth: usedMinuteWidth,
                                scale: displayScale
                            )
                        }

                        WidgetWeaverClockHandsView(
                            palette: palette,
                            dialDiameter: dialDiameter,
                            hourAngle: hourAngle,
                            minuteAngle: minuteAngle,
                            secondAngle: secondAngle,
                            hourLength: hourLength,
                            hourWidth: hourWidth,
                            hourHandStyle: .icon,
                            minuteLength: usedMinuteLength,
                            minuteWidth: usedMinuteWidth,
                            secondLength: usedSecondLength,
                            secondWidth: usedSecondWidth,
                            secondTipSide: usedSecondTipSide,
                            scale: displayScale
                        )

                        if showsCentreHub {
                            WidgetWeaverClockCentreHubView(
                                palette: palette,
                                baseRadius: hubBaseRadius,
                                capRadius: hubCapRadius,
                                scale: displayScale
                            )
                        }
                    }
                    .opacity(handsOpacity)
                }
                .frame(width: dialDiameter, height: dialDiameter)
                .clipShape(Circle())

                // Dark bezel + inner separator ring (placeholder).
                WidgetWeaverClockSegmentedBezelPlaceholderView(
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

private struct WidgetWeaverClockSegmentedBezelPlaceholderView: View {
    let palette: WidgetWeaverClockPalette

    let outerDiameter: CGFloat
    let ringA: CGFloat
    let ringB: CGFloat
    let ringC: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let bezelThickness = ringA + ringB
        let separatorThickness = ringC
        let separatorDiameter = max(1, outerDiameter - (bezelThickness * 2.0))

        // Dark, slightly lifted bezel placeholder.
        let bezelFill = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.dialMid.opacity(0.98), location: 0.00),
                .init(color: palette.dialEdge.opacity(1.00), location: 0.60),
                .init(color: Color.black.opacity(0.96), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let bezelHighlight = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.14), location: 0.00),
                .init(color: Color.white.opacity(0.00), location: 0.55),
                .init(color: Color.black.opacity(0.22), location: 1.00)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )

        let separatorStroke = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.separatorRing.opacity(0.92), location: 0.00),
                .init(color: palette.separatorRing.opacity(0.65), location: 0.55),
                .init(color: Color.black.opacity(0.92), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let bezelShadowRadius = max(px, bezelThickness * 0.90)

        ZStack {
            Circle()
                .strokeBorder(bezelFill, lineWidth: bezelThickness)
                .frame(width: outerDiameter, height: outerDiameter)
                .shadow(color: Color.black.opacity(0.60), radius: bezelShadowRadius, x: 0, y: bezelShadowRadius * 0.30)

            Circle()
                .strokeBorder(bezelHighlight, lineWidth: max(px, bezelThickness * 0.24))
                .frame(width: outerDiameter, height: outerDiameter)
                .blendMode(.overlay)

            Circle()
                .strokeBorder(separatorStroke, lineWidth: separatorThickness)
                .frame(width: separatorDiameter, height: separatorDiameter)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
