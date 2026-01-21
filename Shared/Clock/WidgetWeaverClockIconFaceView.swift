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

            let dotRadius = WWClock.pixel(
                WWClock.clamp(R * 0.922, min: R * 0.910, max: R * 0.930),
                scale: displayScale
            )
            let dotDiameter = WWClock.pixel(
                WWClock.clamp(R * 0.013, min: R * 0.011, max: R * 0.014),
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
                WWClock.clamp(R * 0.020, min: R * 0.018, max: R * 0.024),
                scale: displayScale
            )
            let pipRadius = dotRadius

            let numeralsRadius = WWClock.pixel(
                WWClock.clamp(R * 0.70, min: R * 0.66, max: R * 0.74),
                scale: displayScale
            )
            let numeralsSize = WWClock.pixel(R * 0.32, scale: displayScale)

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
                            secondLength: usedSecondLength,
                            secondWidth: usedSecondWidth,
                            secondTipSide: usedSecondTipSide,
                            scale: displayScale
                        )

                        if showsGlows {
                            WidgetWeaverClockGlowsOverlayView(
                                palette: palette,
                                hourCapCentreRadius: batonCentreRadius,
                                batonLength: batonLength,
                                batonWidth: batonWidth,
                                capLength: capLength,
                                pipSide: pipSide,
                                pipRadius: pipRadius,
                                minuteAngle: minuteAngle,
                                minuteLength: usedMinuteLength,
                                minuteWidth: usedMinuteWidth,
                                secondAngle: secondAngle,
                                secondLength: usedSecondLength,
                                secondWidth: usedSecondWidth,
                                secondTipSide: usedSecondTipSide,
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
                            startRadius: radius * 0.86,
                            endRadius: radius
                        )
                    )
                    .blendMode(.multiply)
            )
            // Broad highlight biased upper-left (kept smooth to avoid WidgetKit seams).
            .overlay(
                Ellipse()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.dialDomeHighlight.opacity(0.78), location: 0.0),
                                .init(color: Color.clear, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: radius * 1.10
                        )
                    )
                    .frame(width: radius * 2.10, height: radius * 1.62)
                    .offset(x: -radius * 0.22, y: -radius * 0.26)
                    .blendMode(.screen)
                    .opacity(0.72)
                    .mask(Circle())
            )
            // Thin inner highlight ring (improves edge definition at small sizes).
            .overlay(
                Circle()
                    .inset(by: max(px, occlusionWidth * 0.52))
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: max(px, occlusionWidth * 0.22))
                    .blendMode(.screen)
            )
            // Ring D: occlusion separator.
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.separatorRing.opacity(0.62), location: 0.0),
                                .init(color: palette.separatorRing.opacity(0.96), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: occlusionWidth
                    )
            )
    }
}

private struct WidgetWeaverClockIconFaceBezelView: View {
    let palette: WidgetWeaverClockPalette

    // Outer metal diameter (outer edge of bezel)
    let outerDiameter: CGFloat

    // Ring widths (A/B/C)
    let ringA: CGFloat   // outer rim highlight
    let ringB: CGFloat   // main metal body
    let ringC: CGFloat   // inner bevel ridge

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let outerA = outerDiameter
        let outerB = max(1, outerA - (ringA * 2.0))
        let outerC = max(1, outerA - ((ringA + ringB) * 2.0))

        let outerBR = outerB * 0.5
        let innerBR = max(0.0, outerBR - ringB)
        let innerFractionB = (outerBR > 0) ? (innerBR / outerBR) : 0.01

        ZStack {
            // B) Main metal body: brighter inner chamfer, darker outer edge.
            WWIconClockAnnulus(innerRadiusFraction: innerFractionB)
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelBright.opacity(0.92), location: 0.00),
                            .init(color: palette.bezelMid.opacity(0.78), location: 0.52),
                            .init(color: palette.bezelDark.opacity(0.94), location: 1.00)
                        ]),
                        center: .center,
                        startRadius: innerBR,
                        endRadius: outerBR
                    ),
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .frame(width: outerB, height: outerB)

            // B) Specular sweep (slightly more contrast than the shipped face).
            WWIconClockAnnulus(innerRadiusFraction: innerFractionB)
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelBright.opacity(0.92), location: 0.000),
                            .init(color: palette.bezelBright.opacity(0.92), location: 0.050),
                            .init(color: palette.bezelMid.opacity(0.34), location: 0.160),
                            .init(color: palette.bezelDark.opacity(0.18), location: 0.420),
                            .init(color: palette.bezelDark.opacity(0.74), location: 0.710),
                            .init(color: palette.bezelMid.opacity(0.22), location: 0.880),
                            .init(color: palette.bezelBright.opacity(0.56), location: 1.000)
                        ]),
                        center: .center,
                        angle: .degrees(-135)
                    ),
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .frame(width: outerB, height: outerB)
                .blendMode(.overlay)

            // A) Outer rim highlight (tight).
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelBright.opacity(0.00), location: 0.000),
                            .init(color: palette.bezelBright.opacity(0.00), location: 0.780),
                            .init(color: palette.bezelBright.opacity(0.62), location: 0.860),
                            .init(color: palette.bezelBright.opacity(0.84), location: 0.915),
                            .init(color: palette.bezelBright.opacity(0.00), location: 1.000)
                        ]),
                        center: .center,
                        angle: .degrees(-135)
                    ),
                    lineWidth: ringA
                )
                .frame(width: outerA, height: outerA)
                .blendMode(.screen)

            // C) Inner bevel ridge: crisp line + tight shadow.
            Circle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelBright.opacity(0.70), location: 0.00),
                            .init(color: palette.bezelMid.opacity(0.64), location: 0.55),
                            .init(color: palette.bezelDark.opacity(0.88), location: 1.00)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: ringC
                )
                .frame(width: outerC, height: outerC)
                .overlay(
                    Circle()
                        .strokeBorder(
                            Color.black.opacity(0.22),
                            lineWidth: max(px, ringC * 0.42)
                        )
                        .frame(width: outerC, height: outerC)
                        .blendMode(.multiply)
                )
        }
        .shadow(color: Color.black.opacity(0.32), radius: px * 1.6, x: 0, y: px * 1.1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WWIconClockAnnulus: Shape {
    var innerRadiusFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(rect.width, rect.height) * 0.5
        let innerR = r * innerRadiusFraction
        let c = CGPoint(x: rect.midX, y: rect.midY)

        var p = Path()
        p.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2.0, height: r * 2.0))
        p.addEllipse(in: CGRect(x: c.x - innerR, y: c.y - innerR, width: innerR * 2.0, height: innerR * 2.0))
        return p
    }
}
