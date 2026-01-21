//
//  WidgetWeaverClockHandsView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

enum WidgetWeaverClockHourHandStyle: String, Sendable {
    case ceramic
    case icon
}

struct WidgetWeaverClockHandShadowsView: View {
    let palette: WidgetWeaverClockPalette
    let dialDiameter: CGFloat

    let hourAngle: Angle
    let minuteAngle: Angle

    let hourLength: CGFloat
    let hourWidth: CGFloat
    let hourHandStyle: WidgetWeaverClockHourHandStyle = .ceramic

    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Hour stem + lifted wedge (stem visible near the hub).
        let hourStemLength = hourLength * 0.20
        let hourWedgeLift = max(0, hourStemLength - (px * 2.0))
        let hourWedgeLength = max(1, hourLength - hourWedgeLift)

        let hourTheta = hourAngle.radians
        let hourLiftX = CGFloat(sin(hourTheta)) * hourWedgeLift
        let hourLiftY = CGFloat(-cos(hourTheta)) * hourWedgeLift
        let hourWedgeOffsetY = (-hourWedgeLength / 2.0) + hourLiftY

        let hourShadowBlur = max(px, hourWidth * 0.065)
        let hourShadowOffset = max(px, hourWidth * 0.060)

        let stemWidth = max(px, hourWidth * 0.40)
        let stemCorner = stemWidth * 0.42

        let minuteShadowBlur = max(px, minuteWidth * 0.050)
        let minuteShadowOffset = max(px, minuteWidth * 0.050)

        ZStack {
            // Hour stem shadow (helps separate the stem from the dial and hub).
            RoundedRectangle(cornerRadius: stemCorner, style: .continuous)
                .fill(palette.handShadow.opacity(0.42))
                .frame(width: stemWidth, height: hourStemLength)
                .rotationEffect(hourAngle, anchor: .bottom)
                .offset(y: -hourStemLength / 2.0)
                .offset(x: hourShadowOffset, y: hourShadowOffset)
                .blur(radius: hourShadowBlur)

            // Hour wedge shadow.
            if hourHandStyle == .icon {
                WidgetWeaverClockHourTaperedShape(tipWidthFraction: 0.42)
                    .fill(palette.handShadow.opacity(0.52))
                    .frame(width: hourWidth, height: hourWedgeLength)
                    .rotationEffect(hourAngle, anchor: .bottom)
                    .offset(x: hourLiftX, y: hourWedgeOffsetY)
                    .offset(x: hourShadowOffset, y: hourShadowOffset)
                    .blur(radius: hourShadowBlur)
            } else {
                WidgetWeaverClockHourWedgeShape()
                    .fill(palette.handShadow.opacity(0.55))
                    .frame(width: hourWidth, height: hourWedgeLength)
                    .rotationEffect(hourAngle, anchor: .bottom)
                    .offset(x: hourLiftX, y: hourWedgeOffsetY)
                    .offset(x: hourShadowOffset, y: hourShadowOffset)
                    .blur(radius: hourShadowBlur)
            }

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
    let hourHandStyle: WidgetWeaverClockHourHandStyle = .ceramic

    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    let secondLength: CGFloat
    let secondWidth: CGFloat
    let secondTipSide: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // Hour stem + lifted wedge (keep the original silhouette, but expose a brighter stem).
        let hourStemLength = hourLength * 0.20
        let hourWedgeLift = max(0, hourStemLength - (px * 2.0))
        let hourWedgeLength = max(1, hourLength - hourWedgeLift)

        let hourTheta = hourAngle.radians
        let hourLiftX = CGFloat(sin(hourTheta)) * hourWedgeLift
        let hourLiftY = CGFloat(-cos(hourTheta)) * hourWedgeLift
        let hourWedgeOffsetY = (-hourWedgeLength / 2.0) + hourLiftY

        let stemWidth = max(px, hourWidth * 0.40)
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
            // MARK: Hour stem
            ZStack {
                let stemShape = RoundedRectangle(cornerRadius: stemCorner, style: .continuous)

                metalField.mask(stemShape)

                // Centre ridge highlight.
                Rectangle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.55), location: 0.00),
                                .init(color: Color.white.opacity(0.22), location: 0.32),
                                .init(color: Color.white.opacity(0.00), location: 1.00)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: max(px, stemWidth * 0.18), height: hourStemLength)
                    .offset(x: -stemWidth * 0.06)
                    .blur(radius: max(px, stemWidth * 0.06))
                    .blendMode(.screen)
                    .mask(stemShape)

                // Subtle opposing plane darkening.
                Rectangle()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: max(px, stemWidth * 0.16), height: hourStemLength)
                    .offset(x: stemWidth * 0.12)
                    .blendMode(.multiply)
                    .mask(stemShape)

                stemShape
                    .strokeBorder(Color.black.opacity(0.34), lineWidth: max(px, stemWidth * 0.12))

                stemShape
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: max(px, stemWidth * 0.10))
                    .blendMode(.screen)
            }
            .frame(width: stemWidth, height: hourStemLength)
            .rotationEffect(hourAngle, anchor: .bottom)
            .offset(y: -hourStemLength / 2.0)

            // MARK: Hour hand
            if hourHandStyle == .icon {
                // MARK: Hour hand (icon tapered variant)
                metalField
                    .mask(
                        WidgetWeaverClockHourTaperedShape(tipWidthFraction: 0.42)
                            .frame(width: hourWidth, height: hourWedgeLength)
                            .rotationEffect(hourAngle, anchor: .bottom)
                            .offset(x: hourLiftX, y: hourWedgeOffsetY)
                    )
                    .overlay(
                        // Specular ridge line (narrow highlight).
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(0.62), location: 0.00),
                                        .init(color: Color.white.opacity(0.28), location: 0.30),
                                        .init(color: Color.white.opacity(0.00), location: 1.00)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(px, hourWidth * 0.078), height: hourWedgeLength)
                            .offset(x: -hourWidth * 0.05 + hourLiftX, y: hourWedgeOffsetY)
                            .rotationEffect(hourAngle)
                            .blur(radius: max(px, hourWidth * 0.018))
                            .blendMode(.screen)
                            .mask(
                                WidgetWeaverClockHourTaperedShape(tipWidthFraction: 0.42)
                                    .frame(width: hourWidth, height: hourWedgeLength)
                                    .rotationEffect(hourAngle, anchor: .bottom)
                                    .offset(x: hourLiftX, y: hourWedgeOffsetY)
                            )
                    )
                    .overlay(
                        // Dark underside plane (tight).
                        Rectangle()
                            .fill(Color.black.opacity(0.20))
                            .frame(width: max(px, hourWidth * 0.22), height: hourWedgeLength)
                            .offset(x: hourWidth * 0.16 + hourLiftX, y: hourWedgeOffsetY)
                            .rotationEffect(hourAngle)
                            .blendMode(.multiply)
                            .mask(
                                WidgetWeaverClockHourTaperedShape(tipWidthFraction: 0.42)
                                    .frame(width: hourWidth, height: hourWedgeLength)
                                    .rotationEffect(hourAngle, anchor: .bottom)
                                    .offset(x: hourLiftX, y: hourWedgeOffsetY)
                            )
                    )
                    .overlay(
                        WidgetWeaverClockHourTaperedShape(tipWidthFraction: 0.42)
                            .stroke(palette.handEdge, lineWidth: max(px, hourWidth * 0.045))
                            .frame(width: hourWidth, height: hourWedgeLength)
                            .rotationEffect(hourAngle, anchor: .bottom)
                            .offset(x: hourLiftX, y: hourWedgeOffsetY)
                    )
            } else {
                // MARK: Hour hand (original wedge, slightly more rounded corners + centre ridge)
                metalField
                    .mask(
                        WidgetWeaverClockHourWedgeShape()
                            .frame(width: hourWidth, height: hourWedgeLength)
                            .rotationEffect(hourAngle, anchor: .bottom)
                            .offset(x: hourLiftX, y: hourWedgeOffsetY)
                    )
                    .overlay(
                        // Specular ridge line (narrow highlight).
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(color: Color.white.opacity(0.62), location: 0.00),
                                        .init(color: Color.white.opacity(0.28), location: 0.30),
                                        .init(color: Color.white.opacity(0.00), location: 1.00)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(px, hourWidth * 0.085), height: hourWedgeLength)
                            .offset(x: -hourWidth * 0.06 + hourLiftX, y: hourWedgeOffsetY)
                            .rotationEffect(hourAngle)
                            .blur(radius: max(px, hourWidth * 0.020))
                            .blendMode(.screen)
                            .mask(
                                WidgetWeaverClockHourWedgeShape()
                                    .frame(width: hourWidth, height: hourWedgeLength)
                                    .rotationEffect(hourAngle, anchor: .bottom)
                                    .offset(x: hourLiftX, y: hourWedgeOffsetY)
                            )
                    )
                    .overlay(
                        // Dark underside plane (tight).
                        Rectangle()
                            .fill(Color.black.opacity(0.22))
                            .frame(width: max(px, hourWidth * 0.24), height: hourWedgeLength)
                            .offset(x: hourWidth * 0.18 + hourLiftX, y: hourWedgeOffsetY)
                            .rotationEffect(hourAngle)
                            .blendMode(.multiply)
                            .mask(
                                WidgetWeaverClockHourWedgeShape()
                                    .frame(width: hourWidth, height: hourWedgeLength)
                                    .rotationEffect(hourAngle, anchor: .bottom)
                                    .offset(x: hourLiftX, y: hourWedgeOffsetY)
                            )
                    )
                    .overlay(
                        WidgetWeaverClockHourWedgeShape()
                            .stroke(palette.handEdge, lineWidth: max(px, hourWidth * 0.045))
                            .frame(width: hourWidth, height: hourWedgeLength)
                            .rotationEffect(hourAngle, anchor: .bottom)
                            .offset(x: hourLiftX, y: hourWedgeOffsetY)
                    )
            }


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
                                        .init(color: palette.accent.opacity(0.00), location: 1.00)
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: max(px, minuteWidth * 0.12), height: minuteLength)
                            .offset(x: minuteWidth * 0.20, y: -minuteLength / 2.0)
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
                        WidgetWeaverClockMinuteNeedleShape()
                            .stroke(palette.handEdge, lineWidth: max(px, minuteWidth * 0.042))
                            .frame(width: minuteWidth, height: minuteLength)
                            .rotationEffect(minuteAngle, anchor: .bottom)
                            .offset(y: -minuteLength / 2.0)
                    )
            }

            if secondLength > 0.0 && secondWidth > 0.0 && secondTipSide > 0.0 {
                // MARK: Second hand (kept crisp; glow handled elsewhere)
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

// MARK: - Shapes

struct WidgetWeaverClockHourWedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        let baseHalf = w * 0.50
        let tipHalf = w * 0.30
        let shoulderY = rect.minY + h * 0.18

        let points: [CGPoint] = [
            CGPoint(x: rect.midX - baseHalf, y: rect.maxY),
            CGPoint(x: rect.midX - tipHalf, y: shoulderY),
            CGPoint(x: rect.midX, y: rect.minY),
            CGPoint(x: rect.midX + tipHalf, y: shoulderY),
            CGPoint(x: rect.midX + baseHalf, y: rect.maxY)
        ]

        let cornerRadius = w * 0.12

        func add(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
        func sub(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
        func mul(_ v: CGPoint, _ s: CGFloat) -> CGPoint { CGPoint(x: v.x * s, y: v.y * s) }

        func norm(_ v: CGPoint) -> CGPoint {
            let d = max(0.00001, sqrt(v.x * v.x + v.y * v.y))
            return CGPoint(x: v.x / d, y: v.y / d)
        }

        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
            let dx = a.x - b.x
            let dy = a.y - b.y
            return sqrt(dx * dx + dy * dy)
        }

        var path = Path()
        let n = points.count

        for i in 0..<n {
            let prev = points[(i - 1 + n) % n]
            let cur = points[i]
            let next = points[(i + 1) % n]

            let v1 = norm(sub(prev, cur))
            let v2 = norm(sub(next, cur))

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

struct WidgetWeaverClockHourTaperedShape: InsettableShape {
    var tipWidthFraction: CGFloat
    var insetAmount: CGFloat = 0.0

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)

        let w = insetRect.width

        let clampedTipFraction = WWClock.clamp(tipWidthFraction, min: 0.05, max: 0.98)
        let tipWidth = w * clampedTipFraction
        let tipLeft = insetRect.minX + (w - tipWidth) * 0.5
        let tipRight = tipLeft + tipWidth

        let bottomLeft = CGPoint(x: insetRect.minX, y: insetRect.maxY)
        let bottomRight = CGPoint(x: insetRect.maxX, y: insetRect.maxY)
        let topLeft = CGPoint(x: tipLeft, y: insetRect.minY)
        let topRight = CGPoint(x: tipRight, y: insetRect.minY)

        var p = Path()
        p.move(to: bottomLeft)
        p.addLine(to: topLeft)
        p.addLine(to: topRight)
        p.addLine(to: bottomRight)
        p.closeSubpath()
        return p
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

            // Outer edge (slightly brighter).
            Rectangle()
                .fill(colour.opacity(0.90))
                .frame(width: max(px, width * 0.46), height: length)
                .offset(x: -width * 0.20, y: -length / 2.0)
                .blendMode(.screen)

            // Tiny tip square (sharp).
            RoundedRectangle(cornerRadius: max(px, tipSide * 0.18), style: .continuous)
                .fill(colour)
                .frame(width: tipSide, height: tipSide)
                .offset(y: -(length - tipSide / 2.0))
        }
        .rotationEffect(angle, anchor: .center)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
