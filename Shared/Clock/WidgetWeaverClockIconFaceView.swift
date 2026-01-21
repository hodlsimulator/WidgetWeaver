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
/// - Only the bezel/dial treatment and hour hand styling are face-specific.
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
        hourAngle: Angle,
        minuteAngle: Angle,
        secondAngle: Angle,
        showsSecondHand: Bool,
        showsMinuteHand: Bool,
        showsHandShadows: Bool,
        showsGlows: Bool,
        showsCentreHub: Bool,
        handsOpacity: Double
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
            let R = s / 2.0
            let px = WWClock.px(scale: displayScale)

            // Dial geometry (kept identical to the shipped face).
            let bezelThickness = R * 0.160
            let dialDiameter = s - (bezelThickness * 2.0)
            let dialR = dialDiameter / 2.0

            // Bezel ring widths (A/B/C) and dial occlusion ring (D).
            let ringA = R * 0.010
            let ringB = R * 0.120
            let ringC = R * 0.030
            let ringD = R * 0.013

            // Markers / indices geometry.
            let minuteDotDiameter = max(px, dialR * 0.007)
            let minuteDotRadius = dialR * 0.88

            let batonLength = dialR * 0.22
            let batonWidth = dialR * 0.065
            let hourCapCentreRadius = dialR * 0.62

            let pipSide = dialR * 0.13
            let pipRadius = dialR * 0.66

            let numeralRadius = dialR * 0.49

            // Hands geometry.
            let hourHandLength = dialR * 0.48
            let hourHandWidth = dialR * 0.20

            let minuteHandLength = dialR * 0.78
            let minuteHandWidth = dialR * 0.10

            let secondHandLength = dialR * 0.86
            let secondHandWidth = dialR * 0.020
            let secondTipSide = dialR * 0.060

            ZStack {
                ZStack {
                    WidgetWeaverClockIconFaceDialFaceView(
                        palette: palette,
                        radius: dialR,
                        occlusionWidth: ringD,
                        scale: displayScale
                    )

                    // MARK: Minute dots
                    ForEach(0..<60, id: \.self) { i in
                        let degrees = (Double(i) / 60.0) * 360.0
                        Circle()
                            .fill(palette.dot)
                            .frame(width: minuteDotDiameter, height: minuteDotDiameter)
                            .offset(y: -minuteDotRadius)
                            .rotationEffect(.degrees(degrees))
                    }

                    // MARK: Hour indices (caps)
                    ForEach([1, 2, 4, 5, 7, 8, 10, 11], id: \.self) { i in
                        let degrees = (Double(i) / 12.0) * 360.0
                        RoundedRectangle(cornerRadius: batonWidth * 0.18, style: .continuous)
                            .fill(palette.cap)
                            .frame(width: batonWidth, height: batonLength)
                            .offset(y: -(hourCapCentreRadius + batonLength / 2.0))
                            .rotationEffect(.degrees(degrees))
                    }

                    // MARK: Pips (3/6/9)
                    ForEach([3, 6, 9], id: \.self) { i in
                        let degrees = (Double(i) / 12.0) * 360.0
                        RoundedRectangle(cornerRadius: pipSide * 0.32, style: .continuous)
                            .fill(palette.cap)
                            .frame(width: pipSide, height: pipSide)
                            .offset(y: -pipRadius)
                            .rotationEffect(.degrees(degrees))
                    }

                    // MARK: Numerals (12 only)
                    ForEach([12], id: \.self) { i in
                        let degrees = (Double(i % 12) / 12.0) * 360.0
                        let text = "\(i)"
                        Text(text)
                            .font(.system(size: dialR * 0.22, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.text)
                            .offset(y: -numeralRadius)
                            .rotationEffect(.degrees(degrees))
                            .rotationEffect(.degrees(-degrees))
                    }

                    Group {
                        if showsHandShadows {
                            WidgetWeaverClockHandShadowsView(
                                palette: palette,
                                dialDiameter: dialDiameter,
                                hourAngle: hourAngle,
                                minuteAngle: minuteAngle,
                                hourLength: hourHandLength,
                                hourWidth: hourHandWidth,
                                hourHandStyle: .icon,
                                minuteLength: showsMinuteHand ? minuteHandLength : 0.0,
                                minuteWidth: showsMinuteHand ? minuteHandWidth : 0.0,
                                scale: displayScale
                            )
                        }

                        WidgetWeaverClockHandsView(
                            palette: palette,
                            dialDiameter: dialDiameter,
                            hourAngle: hourAngle,
                            minuteAngle: minuteAngle,
                            secondAngle: secondAngle,
                            hourLength: hourHandLength,
                            hourWidth: hourHandWidth,
                            hourHandStyle: .icon,
                            minuteLength: showsMinuteHand ? minuteHandLength : 0.0,
                            minuteWidth: showsMinuteHand ? minuteHandWidth : 0.0,
                            secondLength: showsSecondHand ? secondHandLength : 0.0,
                            secondWidth: showsSecondHand ? secondHandWidth : 0.0,
                            secondTipSide: showsSecondHand ? secondTipSide : 0.0,
                            scale: displayScale
                        )

                        if showsGlows {
                            WidgetWeaverClockGlowsOverlayView(
                                palette: palette,
                                hourCapCentreRadius: hourCapCentreRadius,
                                batonLength: batonLength,
                                batonWidth: batonWidth,
                                capLength: batonLength * 0.28,
                                pipSide: pipSide,
                                pipRadius: pipRadius,
                                minuteAngle: minuteAngle,
                                minuteLength: minuteHandLength,
                                minuteWidth: minuteHandWidth,
                                secondAngle: secondAngle,
                                secondLength: secondHandLength,
                                secondWidth: secondHandWidth,
                                secondTipSide: secondTipSide,
                                scale: displayScale
                            )
                        }

                        if showsCentreHub {
                            WidgetWeaverClockCentreHubView(
                                palette: palette,
                                size: dialR * 0.16,
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
                    outerDiameter: s,
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

        let dialTop = WWClock.colour(0x384A61)
        let dialMid = WWClock.colour(0x2B3B4D)
        let dialBottom = WWClock.colour(0x1C2633)

        Circle()
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: dialTop, location: 0.00),
                        .init(color: dialMid, location: 0.56),
                        .init(color: dialBottom, location: 1.00)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            // Centre darkening to push depth.
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.black.opacity(0.05), location: 0.00),
                                .init(color: Color.black.opacity(0.42), location: 1.00)
                            ]),
                            center: .center,
                            startRadius: 0.0,
                            endRadius: radius
                        )
                    )
                    .blendMode(.multiply)
            )
            // Broad highlight biased upper-left.
            .overlay(
                Ellipse()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.16), location: 0.00),
                                .init(color: Color.clear, location: 1.00)
                            ]),
                            center: .center,
                            startRadius: 0.0,
                            endRadius: radius * 1.20
                        )
                    )
                    .frame(width: radius * 2.20, height: radius * 1.70)
                    .offset(x: -radius * 0.22, y: -radius * 0.30)
                    .blur(radius: max(px, radius * 0.06))
                    .blendMode(.screen)
                    .mask(Circle())
            )
            // Outer occlusion ring (darker, more icon-like).
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.black.opacity(0.62), location: 0.00),
                                .init(color: Color.black.opacity(0.92), location: 1.00)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: occlusionWidth
                    )
            )
            // Thin inner highlight line.
            .overlay(
                Circle()
                    .inset(by: max(0.0, occlusionWidth * 0.70))
                    .strokeBorder(
                        (palette.separatorRing.opacity(0.55)),
                        lineWidth: max(px, occlusionWidth * 0.28)
                    )
                    .blendMode(.overlay)
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

        let bezelOuterDark = WWClock.colour(0x080A0D)
        let bezelOuterMid = WWClock.colour(0x2E3640)
        let bezelHighlight = WWClock.colour(0xEDF2FA)

        let outerA = outerDiameter
        let outerB = max(1, outerA - (ringA * 2.0))
        let outerC = max(1, outerA - ((ringA + ringB) * 2.0))

        let outerBR = outerB * 0.5
        let innerBR = max(0.0, outerBR - ringB)
        let innerFractionB = (outerBR > 0) ? (innerBR / outerBR) : 0.01

        ZStack {
            // B) Main body (darker outer edge, brighter inner chamfer)
            WWIconClockAnnulus(innerRadiusFraction: innerFractionB)
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: bezelHighlight.opacity(0.90), location: 0.00),
                            .init(color: bezelOuterMid.opacity(0.86), location: 0.52),
                            .init(color: bezelOuterDark.opacity(0.94), location: 1.00)
                        ]),
                        center: .center,
                        startRadius: innerBR,
                        endRadius: outerBR
                    ),
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .frame(width: outerB, height: outerB)

            // B) Specular sweep: strong highlight upper-left.
            WWIconClockAnnulus(innerRadiusFraction: innerFractionB)
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: bezelHighlight.opacity(0.90), location: 0.000),
                            .init(color: bezelHighlight.opacity(0.90), location: 0.050),
                            .init(color: bezelOuterMid.opacity(0.28), location: 0.160),
                            .init(color: bezelOuterDark.opacity(0.18), location: 0.420),
                            .init(color: bezelOuterDark.opacity(0.72), location: 0.710),
                            .init(color: bezelOuterMid.opacity(0.22), location: 0.880),
                            .init(color: bezelHighlight.opacity(0.56), location: 1.000)
                        ]),
                        center: .center,
                        angle: .degrees(-135)
                    ),
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .frame(width: outerB, height: outerB)
                .blendMode(.overlay)

            // A) Outer rim highlight.
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: bezelHighlight.opacity(0.00), location: 0.000),
                            .init(color: bezelHighlight.opacity(0.00), location: 0.780),
                            .init(color: bezelHighlight.opacity(0.60), location: 0.860),
                            .init(color: bezelHighlight.opacity(0.82), location: 0.915),
                            .init(color: bezelHighlight.opacity(0.00), location: 1.000)
                        ]),
                        center: .center,
                        angle: .degrees(-135)
                    ),
                    lineWidth: ringA
                )
                .frame(width: outerA, height: outerA)
                .blendMode(.screen)

            // C) Inner bevel ridge (thin).
            Circle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: bezelHighlight.opacity(0.70), location: 0.00),
                            .init(color: bezelOuterMid.opacity(0.60), location: 0.55),
                            .init(color: bezelOuterDark.opacity(0.88), location: 1.00)
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
        .shadow(color: Color.black.opacity(0.34), radius: px * 1.6, x: 0, y: px * 1.1)
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
