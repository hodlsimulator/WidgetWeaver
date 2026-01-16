//
//  WidgetWeaverClockHandsView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockHandShadowsView: View {
    let palette: WidgetWeaverClockPalette
    let dialDiameter: CGFloat

    let hourAngle: Angle
    let minuteAngle: Angle

    let hourLength: CGFloat
    let hourWidth: CGFloat

    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Hour stem + lifted wedge (stem visible near the hub).
        let hourStemLength = hourLength * 0.20
        let hourWedgeLift = max(0, hourStemLength - (px * 2.0))
        let hourWedgeLength = max(1, hourLength - hourWedgeLift)

        let hourShadowBlur = max(px, hourWidth * 0.055)
        let hourShadowOffset = max(px, hourWidth * 0.055)

        let minuteShadowBlur = max(px, minuteWidth * 0.050)
        let minuteShadowOffset = max(px, minuteWidth * 0.050)

        ZStack {
            WidgetWeaverClockHourWedgeShape()
                .fill(palette.handShadow.opacity(0.55))
                .frame(width: hourWidth, height: hourWedgeLength)
                .rotationEffect(hourAngle, anchor: .bottom)
                .offset(y: -(hourWedgeLength / 2.0 + hourWedgeLift))
                .offset(x: hourShadowOffset, y: hourShadowOffset)
                .blur(radius: hourShadowBlur)

            if minuteLength > 0.0 && minuteWidth > 0.0 {
                WidgetWeaverClockMinuteNeedleShape()
                    .fill(palette.handShadow.opacity(0.40))
                    .frame(width: minuteWidth, height: minuteLength)
                    .rotationEffect(minuteAngle, anchor: .bottom)
                    .offset(y: -minuteLength / 2.0)
                    .offset(x: minuteShadowOffset, y: minuteShadowOffset)
                    .blur(radius: minuteShadowBlur)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WidgetWeaverClockHandsView: View {
    let palette: WidgetWeaverClockPalette
    let dialDiameter: CGFloat

    let hourAngle: Angle
    let minuteAngle: Angle
    let secondAngle: Angle

    let hourLength: CGFloat
    let hourWidth: CGFloat

    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Hour stem + lifted wedge (keep the original silhouette, but expose a dark stem).
        let hourStemLength = hourLength * 0.20
        let hourWedgeLift = max(0, hourStemLength - (px * 2.0))
        let hourWedgeLength = max(1, hourLength - hourWedgeLift)

        let stemWidth = max(px, hourWidth * 0.34)
        let stemCorner = stemWidth * 0.42

        // Screen-space metal field (consistent light direction).
        let metalField = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.handLight, location: 0.00),
                .init(color: palette.handMid, location: 0.52),
                .init(color: palette.handDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: dialDiameter, height: dialDiameter)

        ZStack {
            // MARK: Hour hand stem (dark, understated)
            ZStack {
                let stemShape = RoundedRectangle(cornerRadius: stemCorner, style: .continuous)

                stemShape
                    .fill(palette.separatorRing.opacity(0.98))

                stemShape
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.10), location: 0.00),
                                .init(color: Color.clear, location: 0.55),
                                .init(color: Color.black.opacity(0.26), location: 1.00)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.overlay)

                stemShape
                    .strokeBorder(Color.black.opacity(0.42), lineWidth: max(px, stemWidth * 0.13))

                stemShape
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: max(px, stemWidth * 0.10))
                    .blendMode(.screen)
            }
            .frame(width: stemWidth, height: hourStemLength)
            .rotationEffect(hourAngle, anchor: .bottom)
            .offset(y: -hourStemLength / 2.0)

            // MARK: Hour hand (original wedge, subtly rounded corners)
            metalField
                .mask(
                    WidgetWeaverClockHourWedgeShape()
                        .frame(width: hourWidth, height: hourWedgeLength)
                        .rotationEffect(hourAngle, anchor: .bottom)
                        .offset(y: -(hourWedgeLength / 2.0 + hourWedgeLift))
                )
                .overlay(
                    // Bright ridge highlight (tight).
                    Rectangle()
                        .fill(Color.white.opacity(0.30))
                        .frame(width: max(px, hourWidth * 0.16), height: hourWedgeLength)
                        .offset(x: -hourWidth * 0.12, y: -(hourWedgeLength / 2.0 + hourWedgeLift))
                        .rotationEffect(hourAngle)
                        .blendMode(.screen)
                        .mask(
                            WidgetWeaverClockHourWedgeShape()
                                .frame(width: hourWidth, height: hourWedgeLength)
                                .rotationEffect(hourAngle, anchor: .bottom)
                                .offset(y: -(hourWedgeLength / 2.0 + hourWedgeLift))
                        )
                )
                .overlay(
                    // Dark underside plane (tight).
                    Rectangle()
                        .fill(Color.black.opacity(0.22))
                        .frame(width: max(px, hourWidth * 0.22), height: hourWedgeLength)
                        .offset(x: hourWidth * 0.16, y: -(hourWedgeLength / 2.0 + hourWedgeLift))
                        .rotationEffect(hourAngle)
                        .blendMode(.multiply)
                        .mask(
                            WidgetWeaverClockHourWedgeShape()
                                .frame(width: hourWidth, height: hourWedgeLength)
                                .rotationEffect(hourAngle, anchor: .bottom)
                                .offset(y: -(hourWedgeLength / 2.0 + hourWedgeLift))
                        )
                )
                .overlay(
                    WidgetWeaverClockHourWedgeShape()
                        .stroke(palette.handEdge, lineWidth: max(px, hourWidth * 0.045))
                        .frame(width: hourWidth, height: hourWedgeLength)
                        .rotationEffect(hourAngle, anchor: .bottom)
                        .offset(y: -(hourWedgeLength / 2.0 + hourWedgeLift))
                )

            if minuteLength > 0.0 && minuteWidth > 0.0 {
                // MARK: Minute hand (reduced glow, keep crisp metal definition)
                metalField
                    .mask(
                        WidgetWeaverClockMinuteNeedleShape()
                            .frame(width: minuteWidth, height: minuteLength)
                            .rotationEffect(minuteAngle, anchor: .bottom)
                            .offset(y: -minuteLength / 2.0)
                    )
                    .overlay(
                        // Ridge highlight (lit side).
                        Rectangle()
                            .fill(Color.white.opacity(0.34))
                            .frame(width: max(px, minuteWidth * 0.14), height: minuteLength)
                            .offset(x: -minuteWidth * 0.18, y: -minuteLength / 2.0)
                            .rotationEffect(minuteAngle)
                            .blendMode(.screen)
                            .mask(
                                WidgetWeaverClockMinuteNeedleShape()
                                    .frame(width: minuteWidth, height: minuteLength)
                                    .rotationEffect(minuteAngle, anchor: .bottom)
                                    .offset(y: -minuteLength / 2.0)
                            )
                    )
                    .overlay(
                        // Dark opposing edge.
                        Rectangle()
                            .fill(Color.black.opacity(0.22))
                            .frame(width: max(px, minuteWidth * 0.12), height: minuteLength)
                            .offset(x: minuteWidth * 0.22, y: -minuteLength / 2.0)
                            .rotationEffect(minuteAngle)
                            .blendMode(.multiply)
                            .mask(
                                WidgetWeaverClockMinuteNeedleShape()
                                    .frame(width: minuteWidth, height: minuteLength)
                                    .rotationEffect(minuteAngle, anchor: .bottom)
                                    .offset(y: -minuteLength / 2.0)
                            )
                    )
                    .overlay(
                        // Blue edge emission (very subtle; glow comes from overlay layer).
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: palette.accent.opacity(0.00), location: 0.00),
                                        .init(color: palette.accent.opacity(0.06), location: 0.45),
                                        .init(color: palette.accent.opacity(0.55), location: 1.00)
                                    ]),
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: max(px, minuteWidth * 0.08), height: minuteLength)
                            .offset(x: minuteWidth * 0.34, y: -minuteLength / 2.0)
                            .rotationEffect(minuteAngle)
                            .blendMode(.screen)
                            .mask(
                                WidgetWeaverClockMinuteNeedleShape()
                                    .frame(width: minuteWidth, height: minuteLength)
                                    .rotationEffect(minuteAngle, anchor: .bottom)
                                    .offset(y: -minuteLength / 2.0)
                            )
                    )
                    .overlay(
                        // Crisp tip highlight (no blob).
                        Ellipse()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: minuteWidth * 0.70, height: minuteWidth * 0.55)
                            .offset(x: -minuteWidth * 0.06, y: -minuteLength * 0.48)
                            .mask(
                                WidgetWeaverClockMinuteNeedleShape()
                                    .frame(width: minuteWidth, height: minuteLength)
                                    .rotationEffect(minuteAngle, anchor: .bottom)
                                    .offset(y: -minuteLength / 2.0)
                            )
                            .blendMode(.screen)
                    )
                    .overlay(
                        WidgetWeaverClockMinuteNeedleShape()
                            .stroke(palette.handEdge, lineWidth: max(px, minuteWidth * 0.075))
                            .frame(width: minuteWidth, height: minuteLength)
                            .rotationEffect(minuteAngle, anchor: .bottom)
                            .offset(y: -minuteLength / 2.0)
                    )
            }

            if secondLength > 0.0 && secondWidth > 0.0 {
                // MARK: Second hand (thin, straight, reduced dominance + terminal square)
                WidgetWeaverClockSecondHandView(
                    colour: palette.accent,
                    width: secondWidth,
                    length: secondLength,
                    angle: secondAngle,
                    tipSide: secondTipSide,
                    scale: scale
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct WidgetWeaverClockCentreHubView: View {
    let palette: WidgetWeaverClockPalette
    let baseRadius: CGFloat
    let capRadius: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        let baseD = baseRadius * 2.0
        let capD = capRadius * 2.0

        ZStack {
            Circle()
                .fill(palette.hubBase)
                .frame(width: baseD, height: baseD)
                .shadow(color: palette.hubShadow, radius: baseRadius * 0.22, x: baseRadius * 0.10, y: baseRadius * 0.14)

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.hubCapLight, location: 0.00),
                            .init(color: palette.hubCapMid, location: 0.58),
                            .init(color: palette.hubCapDark, location: 1.00)
                        ]),
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: capRadius * 1.20
                    )
                )
                .frame(width: capD, height: capD)
                // Tiny shadow under cap to separate from base disc.
                .shadow(color: Color.black.opacity(0.20), radius: max(px, capRadius * 0.10), x: px, y: px)
                // Tight specular highlight biased upper-left.
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: capD * 0.44, height: capD * 0.44)
                        .offset(x: -capRadius * 0.18, y: -capRadius * 0.22)
                        .blur(radius: max(px, capRadius * 0.09))
                        .blendMode(.screen)
                )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes

struct WidgetWeaverClockHourWedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        let baseInset = w * 0.035
        let a = CGPoint(x: rect.minX + baseInset, y: rect.maxY)
        let b = CGPoint(x: rect.midX, y: rect.minY)
        let c = CGPoint(x: rect.maxX - baseInset, y: rect.maxY)

        // Subtle rounding only.
        let cornerRadius = max(1, min(min(w, h) * 0.055, w * 0.09))

        func length(_ v: CGPoint) -> CGFloat {
            sqrt(v.x * v.x + v.y * v.y)
        }

        func normalised(_ v: CGPoint) -> CGPoint {
            let l = max(0.0001, length(v))
            return CGPoint(x: v.x / l, y: v.y / l)
        }

        func add(_ p: CGPoint, _ v: CGPoint) -> CGPoint {
            CGPoint(x: p.x + v.x, y: p.y + v.y)
        }

        func sub(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
            CGPoint(x: p.x - q.x, y: p.y - q.y)
        }

        func mul(_ v: CGPoint, _ s: CGFloat) -> CGPoint {
            CGPoint(x: v.x * s, y: v.y * s)
        }

        func dist(_ p: CGPoint, _ q: CGPoint) -> CGFloat {
            length(sub(p, q))
        }

        let points = [a, b, c]

        var path = Path()

        for i in 0..<points.count {
            let prev = points[(i - 1 + points.count) % points.count]
            let cur = points[i]
            let next = points[(i + 1) % points.count]

            let v1 = normalised(sub(prev, cur))
            let v2 = normalised(sub(next, cur))

            let r1 = dist(cur, prev) * 0.5
            let r2 = dist(cur, next) * 0.5
            let r = min(cornerRadius, r1, r2)

            let p1 = add(cur, mul(v1, r))
            let p2 = add(cur, mul(v2, r))

            if i == 0 {
                path.move(to: p1)
            } else {
                path.addLine(to: p1)
            }

            path.addQuadCurve(to: p2, control: cur)
        }

        path.closeSubpath()
        return path
    }
}

struct WidgetWeaverClockMinuteNeedleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width

        let tipHeight = max(1, w * 0.95)
        let shaftTopY = rect.minY + tipHeight
        let shaftInset = w * 0.10

        let bottomLeft = CGPoint(x: rect.minX + shaftInset, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX - shaftInset, y: rect.maxY)

        let shaftTopLeft = CGPoint(x: rect.minX + shaftInset, y: shaftTopY)
        let shaftTopRight = CGPoint(x: rect.maxX - shaftInset, y: shaftTopY)

        let tip = CGPoint(x: rect.midX, y: rect.minY)

        var p = Path()
        p.move(to: bottomLeft)
        p.addLine(to: shaftTopLeft)
        p.addLine(to: tip)
        p.addLine(to: shaftTopRight)
        p.addLine(to: bottomRight)
        p.closeSubpath()
        return p
    }
}

struct WidgetWeaverClockSecondHandView: View {
    let colour: Color
    let width: CGFloat
    let length: CGFloat
    let angle: Angle
    let tipSide: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        ZStack {
            Rectangle()
                .fill(colour.opacity(0.62))
                .frame(width: width, height: length)
                .offset(y: -length / 2.0)

            Rectangle()
                .fill(colour.opacity(0.82))
                .frame(width: tipSide, height: tipSide)
                .offset(y: -length)
        }
        .overlay(
            Rectangle()
                .strokeBorder(Color.black.opacity(0.10), lineWidth: max(px, width * 0.14))
                .frame(width: tipSide, height: tipSide)
                .offset(y: -length)
        )
        .rotationEffect(angle)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
