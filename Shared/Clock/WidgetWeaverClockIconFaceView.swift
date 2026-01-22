//
//  WidgetWeaverClockIconFaceView.swift
//  WidgetWeaver
//
//  Created by . . on 1/21/26.
//

import SwiftUI

/// Clock face renderer for Face = "icon".
///
/// Notes:
/// - Uses 12 numerals + 60 tick marks to remain clearly distinct from the Ceramic face.
/// - Layout constants are tuned for widget-size legibility (tick hierarchy, numeral radius, hand weights).
struct WidgetWeaverClockIconFaceView: View {
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

            let tickRadius = WWClock.pixel(
                WWClock.clamp(R * 0.95, min: R * 0.93, max: R * 0.96),
                scale: displayScale
            )
            let majorTickLength = WWClock.pixel(
                WWClock.clamp(R * 0.115, min: R * 0.095, max: R * 0.135),
                scale: displayScale
            )
            let minorTickLength = WWClock.pixel(
                WWClock.clamp(R * 0.062, min: R * 0.050, max: R * 0.075),
                scale: displayScale
            )

            let majorTickWidth = WWClock.pixel(
                WWClock.clamp(R * 0.024, min: R * 0.018, max: R * 0.030),
                scale: displayScale
            )
            let minorTickWidth = WWClock.pixel(
                WWClock.clamp(R * 0.009, min: R * 0.006, max: R * 0.012),
                scale: displayScale
            )

            let numeralsRadius = WWClock.pixel(
                WWClock.clamp(R * 0.75, min: R * 0.71, max: R * 0.79),
                scale: displayScale
            )
            let numeralsSize = WWClock.pixel(
                WWClock.clamp(R * 0.24, min: R * 0.22, max: R * 0.26),
                scale: displayScale
            )

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
                WWClock.clamp(R * 0.046, min: R * 0.040, max: R * 0.052),
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
                    WidgetWeaverClockIconFaceDialFaceView(
                        palette: palette,
                        occlusionWidth: occlusionWidth,
                        scale: displayScale
                    )

                    WidgetWeaverClockMinuteTickMarksView(
                        palette: palette,
                        radius: tickRadius,
                        majorLength: majorTickLength,
                        minorLength: minorTickLength,
                        majorWidth: majorTickWidth,
                        minorWidth: minorTickWidth,
                        scale: displayScale
                    )

                    WidgetWeaverClockTwelveNumeralsView(
                        palette: palette,
                        radius: numeralsRadius,
                        fontSize: numeralsSize,
                        scale: displayScale
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
                            secondLength: 0.0,
                            secondWidth: 0.0,
                            secondTipSide: 0.0,
                            scale: displayScale
                        )

                        if usedSecondLength > 0.0 && usedSecondWidth > 0.0 {
                            WidgetWeaverClockIconSecondHandView(
                                colour: palette.iconSecondHand,
                                angle: secondAngle,
                                length: usedSecondLength,
                                width: usedSecondWidth,
                                tipSide: usedSecondTipSide,
                                scale: displayScale
                            )
                        }

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

                WidgetWeaverClockIconFaceBezelView(
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

private struct WidgetWeaverClockIconSecondHandView: View {
    let colour: Color
    let angle: Angle
    let length: CGFloat
    let width: CGFloat
    let tipSide: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        ZStack {
            Rectangle()
                .fill(colour.opacity(0.92))
                .frame(width: width, height: length)
                .offset(y: -length / 2.0)

            Rectangle()
                .fill(colour)
                .frame(width: tipSide, height: tipSide)
                .offset(y: -length)
        }
        .overlay(
            Rectangle()
                .strokeBorder(Color.black.opacity(0.12), lineWidth: max(px, width * 0.14))
                .frame(width: tipSide, height: tipSide)
                .offset(y: -length)
        )
        .rotationEffect(angle)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Icon face dial + bezel

private struct WidgetWeaverClockIconFaceDialFaceView: View {
    let palette: WidgetWeaverClockPalette
    let occlusionWidth: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // The Icon face dial is intentionally a uniform fill (no vignette).
        // A subtle separator stroke provides edge definition without darkening the dial field.
        return Circle()
            .fill(palette.iconDialFill)
            .overlay(
                Circle()
                    .strokeBorder(palette.separatorRing.opacity(0.22), lineWidth: max(px, occlusionWidth * 0.25))
            )
    }
}

private struct WidgetWeaverClockIconFaceBezelView: View {
    let palette: WidgetWeaverClockPalette
    let outerDiameter: CGFloat
    let ringA: CGFloat
    let ringB: CGFloat
    let ringC: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let outerA = outerDiameter
        let ringAInner = max(1, outerA - (ringA * 2.0))
        let ringBInner = max(1, outerA - ((ringA + ringB) * 2.0))

        // Slightly “cooler” metal range than the shipped face.
        let metalHi = WWClock.colour(0xF6FAFF, alpha: 1.0)
        let metalMid = WWClock.colour(0xD6DEEA, alpha: 1.0)
        let metalLo = WWClock.colour(0x9AA8BA, alpha: 1.0)

        let ringAStroke = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: metalHi, location: 0.00),
                .init(color: metalMid, location: 0.55),
                .init(color: metalLo, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let ringAInnerStroke = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.18), location: 0.00),
                .init(color: Color.white.opacity(0.00), location: 0.62),
                .init(color: Color.black.opacity(0.18), location: 1.00)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )

        // Deep matte ring B.
        let ringBFill = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: WWClock.colour(0x0A0E14, alpha: 1.0), location: 0.00),
                .init(color: WWClock.colour(0x0B0F15, alpha: 1.0), location: 0.60),
                .init(color: WWClock.colour(0x05080C, alpha: 1.0), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Thin inner metal ring C.
        let ringCStroke = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.22), location: 0.00),
                .init(color: Color.white.opacity(0.06), location: 0.50),
                .init(color: Color.black.opacity(0.22), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let ringAShadow = max(px, ringA * 0.60)
        let ringBShadow = max(px, ringB * 0.85)
        let ringCShadow = max(px, ringC * 1.05)

        ZStack {
            // A) Outer metal rim.
            Circle()
                .strokeBorder(ringAStroke, lineWidth: ringA)
                .frame(width: outerA, height: outerA)
                .shadow(color: Color.black.opacity(0.20), radius: ringAShadow, x: 0, y: ringAShadow * 0.45)

            // A) Inner rim definition stroke.
            Circle()
                .strokeBorder(ringAInnerStroke, lineWidth: max(px, ringA * 0.22))
                .frame(width: ringAInner, height: ringAInner)
                .blendMode(.overlay)

            // B) Matte ring (ring only; never fill the dial field).
            Circle()
                .strokeBorder(ringBFill, lineWidth: ringB)
                .frame(width: ringAInner, height: ringAInner)
                .shadow(color: Color.black.opacity(0.32), radius: ringBShadow, x: 0, y: ringBShadow * 0.40)

            // C) Inner metal ring right before the dial.
            Circle()
                .strokeBorder(ringCStroke, lineWidth: ringC)
                .frame(width: ringBInner, height: ringBInner)
                .shadow(color: Color.black.opacity(0.22), radius: ringCShadow, x: 0, y: ringCShadow * 0.38)

            // Outer gloss (subtle).
            Circle()
                .trim(from: 0.06, to: 0.42)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.00), location: 0.00),
                            .init(color: Color.white.opacity(0.08), location: 0.55),
                            .init(color: Color.white.opacity(0.16), location: 1.00)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: max(px, ringA * 0.26), lineCap: .round)
                )
                .rotationEffect(.degrees(-14))
                .blur(radius: max(px, ringA * 0.12))
                .blendMode(.screen)
                .frame(width: outerA, height: outerA)
        }
        .frame(width: outerA, height: outerA)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
