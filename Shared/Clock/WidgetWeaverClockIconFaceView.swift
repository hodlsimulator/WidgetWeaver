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
/// - Geometry is matched to the shipped renderer so layout remains stable.
/// - Only the dial/bezel treatment and hour hand styling are face-specific.
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

            let tickRadius = WWClock.pixel(
                WWClock.clamp(R * 0.95, min: R * 0.93, max: R * 0.96),
                scale: displayScale
            )
            let majorTickLength = WWClock.pixel(
                WWClock.clamp(R * 0.14, min: R * 0.12, max: R * 0.16),
                scale: displayScale
            )
            let minorTickLength = WWClock.pixel(
                WWClock.clamp(R * 0.07, min: R * 0.055, max: R * 0.085),
                scale: displayScale
            )

            let majorTickWidth = WWClock.pixel(
                WWClock.clamp(R * 0.028, min: R * 0.020, max: R * 0.034),
                scale: displayScale
            )
            let minorTickWidth = WWClock.pixel(
                WWClock.clamp(R * 0.009, min: R * 0.006, max: R * 0.012),
                scale: displayScale
            )

            let numeralsRadius = WWClock.pixel(
                WWClock.clamp(R * 0.78, min: R * 0.74, max: R * 0.82),
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

            let usedMinuteLength: CGFloat = showsMinuteHand ? minuteLength : 0.0
            let usedMinuteWidth: CGFloat = showsMinuteHand ? minuteWidth : 0.0

            let usedSecondLength: CGFloat = showsSecondHand ? secondLength : 0.0
            let usedSecondWidth: CGFloat = showsSecondHand ? secondWidth : 0.0
            let usedSecondTipSide: CGFloat = showsSecondHand ? secondTipSide : 0.0

            let hubBaseRadius = WWClock.pixel(
                WWClock.clamp(R * 0.047, min: R * 0.040, max: R * 0.055),
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
                        radius: R,
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

                    Group {
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
    let angle: Angle
    let length: CGFloat
    let width: CGFloat
    let tipSide: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)
        let red = WWClock.colour(0xF53842, alpha: 1.0)

        ZStack {
            Rectangle()
                .fill(red.opacity(0.92))
                .frame(width: width, height: length)
                .offset(y: -length / 2.0)

            Rectangle()
                .fill(red)
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
    let radius: CGFloat
    let occlusionWidth: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let dialTintTop = WWClock.colour(0x2E4764, alpha: 0.22)
        let dialTintBottom = WWClock.colour(0x0B0F15, alpha: 0.00)

        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: palette.dialCenter, location: 0.00),
                        .init(color: palette.dialMid, location: 0.82),
                        .init(color: palette.dialEdge, location: 1.00)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            // Cool tint so the dial reads more “icon-like” (subtle, non-scheme-dependent).
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: dialTintTop, location: 0.00),
                                .init(color: dialTintBottom, location: 1.00)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)
            )
            // Perimeter vignette (slightly stronger than the shipped face).
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: palette.dialVignette.opacity(0.78), location: 1.0)
                            ]),
                            center: .center,
                            startRadius: radius * 0.62,
                            endRadius: radius
                        )
                    )
                    .blendMode(.multiply)
            )
            // Specular highlight arc near top-right.
            .overlay(
                Circle()
                    .trim(from: 0.05, to: 0.44)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.00), location: 0.0),
                                .init(color: Color.white.opacity(0.10), location: 0.55),
                                .init(color: Color.white.opacity(0.22), location: 1.0)
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: max(px, radius * 0.020), lineCap: .round)
                    )
                    .rotationEffect(.degrees(-18))
                    .blur(radius: max(px, radius * 0.010))
                    .blendMode(.screen)
            )
            // Inner separator ring / occlusion
            .overlay(
                Circle()
                    .strokeBorder(palette.separatorRing, lineWidth: occlusionWidth)
                    .blur(radius: max(px, occlusionWidth * 0.18))
                    .blendMode(.overlay)
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.36), lineWidth: max(px, occlusionWidth * 0.20))
                    .blur(radius: max(px, occlusionWidth * 0.10))
                    .blendMode(.multiply)
            )
            // Subtle grain / noise impression (no actual noise texture to keep WidgetKit-safe).
            .overlay(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0.016), location: 0.0),
                        .init(color: Color.black.opacity(0.018), location: 1.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .blendMode(.overlay)
                .opacity(0.55)
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

        let outerR = outerDiameter / 2.0
        let dialR = outerR - ringA - ringB - ringC

        let ringAInner = outerR - ringA
        let ringBInner = ringAInner - ringB
        let ringCInner = ringBInner - ringC

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

        let ringBStroke = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: metalHi.opacity(0.80), location: 0.00),
                .init(color: metalMid.opacity(0.95), location: 0.48),
                .init(color: metalLo.opacity(0.90), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let ringCStroke = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: metalHi.opacity(0.85), location: 0.00),
                .init(color: metalMid.opacity(0.95), location: 0.55),
                .init(color: metalLo.opacity(0.90), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // Outer rim: subtle shadow and highlight to separate from background.
        let outerShadow = Color.black.opacity(0.32)
        let outerHighlight = Color.white.opacity(0.20)

        ZStack {
            // Outer diameter clip
            Circle()
                .fill(Color.clear)
                .frame(width: outerDiameter, height: outerDiameter)
                .overlay(
                    Circle()
                        .strokeBorder(outerShadow, lineWidth: max(px, ringA * 0.65))
                        .blur(radius: max(px, ringA * 0.30))
                        .offset(x: 0, y: max(px, ringA * 0.22))
                )
                .overlay(
                    Circle()
                        .strokeBorder(outerHighlight, lineWidth: max(px, ringA * 0.55))
                        .blur(radius: max(px, ringA * 0.25))
                        .offset(x: 0, y: -max(px, ringA * 0.18))
                        .blendMode(.screen)
                )

            // Ring A
            Circle()
                .strokeBorder(ringAStroke, lineWidth: ringA)
                .frame(width: (ringAInner + outerR) * 2.0, height: (ringAInner + outerR) * 2.0)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.10), lineWidth: max(px, ringA * 0.18))
                        .frame(width: (ringAInner + outerR) * 2.0, height: (ringAInner + outerR) * 2.0)
                        .blur(radius: max(px, ringA * 0.12))
                        .blendMode(.multiply)
                )

            // Ring B
            Circle()
                .strokeBorder(ringBStroke, lineWidth: ringB)
                .frame(width: (ringBInner + ringAInner) * 2.0, height: (ringBInner + ringAInner) * 2.0)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: max(px, ringB * 0.22))
                        .frame(width: (ringBInner + ringAInner) * 2.0, height: (ringBInner + ringAInner) * 2.0)
                        .blur(radius: max(px, ringB * 0.14))
                        .blendMode(.screen)
                )

            // Ring C
            Circle()
                .strokeBorder(ringCStroke, lineWidth: ringC)
                .frame(width: (ringCInner + ringBInner) * 2.0, height: (ringCInner + ringBInner) * 2.0)
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(0.14), lineWidth: max(px, ringC * 0.20))
                        .frame(width: (ringCInner + ringBInner) * 2.0, height: (ringCInner + ringBInner) * 2.0)
                        .blur(radius: max(px, ringC * 0.12))
                        .blendMode(.multiply)
                )

            // Inner edge shadow where metal meets dial.
            Circle()
                .strokeBorder(Color.black.opacity(0.30), lineWidth: max(px, dialR * 0.014))
                .frame(width: dialR * 2.0, height: dialR * 2.0)
                .blur(radius: max(px, dialR * 0.008))
                .blendMode(.multiply)

            // A small top-right specular highlight on the bezel, similar to icon.
            Circle()
                .trim(from: 0.10, to: 0.26)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color.white.opacity(0.00), location: 0.0),
                            .init(color: Color.white.opacity(0.18), location: 0.70),
                            .init(color: Color.white.opacity(0.34), location: 1.0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: max(px, ringA * 0.85), lineCap: .round)
                )
                .rotationEffect(.degrees(-10))
                .blur(radius: max(px, ringA * 0.25))
                .blendMode(.screen)
        }
        .frame(width: outerDiameter, height: outerDiameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
