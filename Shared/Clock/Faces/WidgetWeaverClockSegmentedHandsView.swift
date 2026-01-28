//
//  WidgetWeaverClockSegmentedHandsView.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI

/// Drop shadows for the Segmented face hands.
///
/// Rendered separately so shadows can sit behind the hands but above the dial.
struct WidgetWeaverClockSegmentedHandShadowsView: View {
    let palette: WidgetWeaverClockPalette
    let dialDiameter: CGFloat

    let hourAngle: Angle
    let minuteAngle: Angle

    let hourLength: CGFloat
    let hourWidth: CGFloat

    let minuteLength: CGFloat
    let minuteWidth: CGFloat

    let scale: CGFloat

    init(
        palette: WidgetWeaverClockPalette,
        dialDiameter: CGFloat,
        hourAngle: Angle,
        minuteAngle: Angle,
        hourLength: CGFloat,
        hourWidth: CGFloat,
        minuteLength: CGFloat,
        minuteWidth: CGFloat,
        scale: CGFloat
    ) {
        self.palette = palette
        self.dialDiameter = dialDiameter
        self.hourAngle = hourAngle
        self.minuteAngle = minuteAngle
        self.hourLength = hourLength
        self.hourWidth = hourWidth
        self.minuteLength = minuteLength
        self.minuteWidth = minuteWidth
        self.scale = scale
    }

    var body: some View {
        let px = WWClock.px(scale: scale)

        let hourShadowBlur = WWClock.pixel(max(px, hourWidth * 0.070), scale: scale)
        let hourShadowOffset = WWClock.pixel(max(px, hourWidth * 0.060), scale: scale)

        let minuteShadowBlur = WWClock.pixel(max(px, minuteWidth * 0.085), scale: scale)
        let minuteShadowOffset = WWClock.pixel(max(px, minuteWidth * 0.060), scale: scale)

        ZStack {
            WidgetWeaverClockSegmentedTaperedBarHandShape(
                tipWidthFraction: 0.68,
                baseInsetFraction: 0.060,
                cornerRadiusFraction: 0.16
            )
            .fill(palette.handShadow.opacity(0.48))
            .frame(width: hourWidth, height: hourLength)
            .rotationEffect(hourAngle, anchor: .bottom)
            .offset(y: -hourLength / 2.0)
            .offset(x: hourShadowOffset, y: hourShadowOffset)
            .blur(radius: hourShadowBlur)

            if minuteLength > 0.0 && minuteWidth > 0.0 {
                WidgetWeaverClockSegmentedTaperedBarHandShape(
                    tipWidthFraction: 0.86,
                    baseInsetFraction: 0.050,
                    cornerRadiusFraction: 0.18
                )
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

/// Segmented face hands.
///
/// Matches the mock's bar-like, bevelled hour/minute hands and the yellow seconds hand with
/// counterweight and terminal end bar.
struct WidgetWeaverClockSegmentedHandsView: View {
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

    let scale: CGFloat

    init(
        palette: WidgetWeaverClockPalette,
        dialDiameter: CGFloat,
        hourAngle: Angle,
        minuteAngle: Angle,
        secondAngle: Angle,
        hourLength: CGFloat,
        hourWidth: CGFloat,
        minuteLength: CGFloat,
        minuteWidth: CGFloat,
        secondLength: CGFloat,
        secondWidth: CGFloat,
        scale: CGFloat
    ) {
        self.palette = palette
        self.dialDiameter = dialDiameter
        self.hourAngle = hourAngle
        self.minuteAngle = minuteAngle
        self.secondAngle = secondAngle
        self.hourLength = hourLength
        self.hourWidth = hourWidth
        self.minuteLength = minuteLength
        self.minuteWidth = minuteWidth
        self.secondLength = secondLength
        self.secondWidth = secondWidth
        self.scale = scale
    }

    private var metalField: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: palette.handLight, location: 0.00),
                .init(color: palette.handMid, location: 0.52),
                .init(color: palette.handDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(width: dialDiameter, height: dialDiameter)
    }

    private var metalSpecularOverlay: LinearGradient {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: Color.white.opacity(0.16), location: 0.00),
                .init(color: Color.white.opacity(0.00), location: 0.48),
                .init(color: Color.black.opacity(0.24), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func ridgeHighlight(width: CGFloat, length: CGFloat, px: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white.opacity(0.72), location: 0.00),
                        .init(color: Color.white.opacity(0.28), location: 0.28),
                        .init(color: Color.white.opacity(0.00), location: 1.00)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: max(px, width * 0.090), height: length)
            .blur(radius: max(px, width * 0.020))
            .blendMode(.screen)
    }

    private func darkPlane(width: CGFloat, length: CGFloat, px: CGFloat) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.22))
            .frame(width: max(px, width * 0.22), height: length)
            .blendMode(.multiply)
    }

    var body: some View {
        let px = WWClock.px(scale: scale)

        let hourMask = WidgetWeaverClockSegmentedTaperedBarHandShape(
            tipWidthFraction: 0.68,
            baseInsetFraction: 0.060,
            cornerRadiusFraction: 0.16
        )
        .frame(width: hourWidth, height: hourLength)
        .rotationEffect(hourAngle, anchor: .bottom)
        .offset(y: -hourLength / 2.0)

        ZStack {
            // MARK: Hour hand
            metalField
                .mask(hourMask)
                .overlay(
                    metalSpecularOverlay
                        .opacity(0.90)
                        .blendMode(.overlay)
                        .mask(hourMask)
                )
                .overlay(
                    ridgeHighlight(width: hourWidth, length: hourLength, px: px)
                        .offset(x: -hourWidth * 0.08, y: -hourLength / 2.0)
                        .rotationEffect(hourAngle)
                        .mask(hourMask)
                )
                .overlay(
                    darkPlane(width: hourWidth, length: hourLength, px: px)
                        .offset(x: hourWidth * 0.18, y: -hourLength / 2.0)
                        .rotationEffect(hourAngle)
                        .mask(hourMask)
                )
                .overlay(
                    WidgetWeaverClockSegmentedTaperedBarHandShape(
                        tipWidthFraction: 0.68,
                        baseInsetFraction: 0.060,
                        cornerRadiusFraction: 0.16
                    )
                    .stroke(palette.handEdge, lineWidth: max(px, hourWidth * 0.040))
                    .frame(width: hourWidth, height: hourLength)
                    .rotationEffect(hourAngle, anchor: .bottom)
                    .offset(y: -hourLength / 2.0)
                )

            // MARK: Minute hand
            if minuteLength > 0.0 && minuteWidth > 0.0 {
                let minuteMask = WidgetWeaverClockSegmentedTaperedBarHandShape(
                    tipWidthFraction: 0.86,
                    baseInsetFraction: 0.050,
                    cornerRadiusFraction: 0.18
                )
                .frame(width: minuteWidth, height: minuteLength)
                .rotationEffect(minuteAngle, anchor: .bottom)
                .offset(y: -minuteLength / 2.0)

                metalField
                    .mask(minuteMask)
                    .overlay(
                        metalSpecularOverlay
                            .opacity(0.88)
                            .blendMode(.overlay)
                            .mask(minuteMask)
                    )
                    .overlay(
                        ridgeHighlight(width: minuteWidth, length: minuteLength, px: px)
                            .offset(x: -minuteWidth * 0.16, y: -minuteLength / 2.0)
                            .rotationEffect(minuteAngle)
                            .mask(minuteMask)
                    )
                    .overlay(
                        darkPlane(width: minuteWidth, length: minuteLength, px: px)
                            .offset(x: minuteWidth * 0.22, y: -minuteLength / 2.0)
                            .rotationEffect(minuteAngle)
                            .mask(minuteMask)
                    )
                    .overlay(
                        // Tight tip highlight (keeps the end crisp at small widget sizes).
                        RoundedRectangle(cornerRadius: max(px, minuteWidth * 0.18), style: .continuous)
                            .fill(Color.white.opacity(0.20))
                            .frame(width: minuteWidth * 0.72, height: max(px, minuteWidth * 0.55))
                            .offset(x: -minuteWidth * 0.08, y: -minuteLength)
                            .rotationEffect(minuteAngle)
                            .blendMode(.screen)
                            .mask(minuteMask)
                    )
                    .overlay(
                        WidgetWeaverClockSegmentedTaperedBarHandShape(
                            tipWidthFraction: 0.86,
                            baseInsetFraction: 0.050,
                            cornerRadiusFraction: 0.18
                        )
                        .stroke(palette.handEdge, lineWidth: max(px, minuteWidth * 0.080))
                        .frame(width: minuteWidth, height: minuteLength)
                        .rotationEffect(minuteAngle, anchor: .bottom)
                        .offset(y: -minuteLength / 2.0)
                    )
            }

            // MARK: Second hand
            if secondLength > 0.0 && secondWidth > 0.0 {
                WidgetWeaverClockSegmentedSecondHandView(
                    dialDiameter: dialDiameter,
                    angle: secondAngle,
                    stemLength: secondLength,
                    stemWidth: secondWidth,
                    scale: scale
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WidgetWeaverClockSegmentedSecondHandView: View {
    let dialDiameter: CGFloat
    let angle: Angle
    let stemLength: CGFloat
    let stemWidth: CGFloat
    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)
        let dialRadius = dialDiameter * 0.5

        let yellowLight = WWClock.colour(0xE5D05A, alpha: 1.0)
        let yellowMid = WWClock.colour(0xBCA429, alpha: 1.0)
        let yellowDark = WWClock.colour(0x6B5A14, alpha: 1.0)

        let yellowFill = LinearGradient(
            gradient: Gradient(stops: [
                .init(color: yellowLight, location: 0.00),
                .init(color: yellowMid, location: 0.55),
                .init(color: yellowDark, location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        let stemStroke = Color.black.opacity(0.22)

        let endBarLength = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.075, min: px * 6.0, max: dialRadius * 0.095),
            scale: scale
        )
        let endBarThickness = WWClock.pixel(
            WWClock.clamp(stemWidth * 2.2, min: px, max: px * 2.0),
            scale: scale
        )

        let leafLength = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.16, min: px * 10.0, max: dialRadius * 0.22),
            scale: scale
        )
        let leafWidth = WWClock.pixel(
            WWClock.clamp(dialRadius * 0.045, min: max(px * 2.0, stemWidth * 5.0), max: dialRadius * 0.065),
            scale: scale
        )

        let stemShadowRadius = WWClock.pixel(max(px, stemWidth * 0.90), scale: scale)
        let stemShadowY = WWClock.pixel(max(0.0, stemWidth * 0.80), scale: scale)

        let stemCornerRadius = max(px, stemWidth * 0.55)
        let endBarCornerRadius = max(px, endBarThickness * 0.60)

        ZStack {
            // A clear, dial-sized container keeps rotation stable while avoiding any large masked gradient field.
            Color.clear

            // Main seconds stem.
            RoundedRectangle(cornerRadius: stemCornerRadius, style: .continuous)
                .fill(yellowFill)
                .frame(width: stemWidth, height: stemLength)
                .offset(y: -stemLength / 2.0)
                .overlay(
                    RoundedRectangle(cornerRadius: stemCornerRadius, style: .continuous)
                        .stroke(stemStroke, lineWidth: max(px, stemWidth * 0.35))
                        .frame(width: stemWidth, height: stemLength)
                        .offset(y: -stemLength / 2.0)
                )
                .shadow(color: Color.black.opacity(0.24), radius: stemShadowRadius, x: 0, y: stemShadowY)

            // Terminal end bar near the tip (perpendicular to the stem).
            RoundedRectangle(cornerRadius: endBarCornerRadius, style: .continuous)
                .fill(yellowFill)
                .frame(width: endBarLength, height: endBarThickness)
                .offset(y: -stemLength)
                .overlay(
                    RoundedRectangle(cornerRadius: endBarCornerRadius, style: .continuous)
                        .stroke(stemStroke, lineWidth: max(px, endBarThickness * 0.35))
                        .frame(width: endBarLength, height: endBarThickness)
                        .offset(y: -stemLength)
                )

            // Leaf counterweight (opposite direction from the stem).
            WidgetWeaverClockSegmentedSecondHandLeafShape()
                .fill(yellowFill)
                .frame(width: leafWidth, height: leafLength)
                .offset(y: leafLength / 2.0)
                .overlay(
                    WidgetWeaverClockSegmentedSecondHandLeafShape()
                        .stroke(stemStroke, lineWidth: max(px, stemWidth * 0.35))
                        .frame(width: leafWidth, height: leafLength)
                        .offset(y: leafLength / 2.0)
                )
        }
        .frame(width: dialDiameter, height: dialDiameter)
        .rotationEffect(angle)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes

/// Trapezoid bar used for Segmented hour/minute hands.
///
/// The shape is designed to be used in a vertical frame where:
/// - the base sits on `rect.maxY`
/// - the tip sits on `rect.minY`
private struct WidgetWeaverClockSegmentedTaperedBarHandShape: Shape {
    let tipWidthFraction: CGFloat
    let baseInsetFraction: CGFloat
    let cornerRadiusFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        let tipFraction = WWClock.clamp(tipWidthFraction, min: 0.20, max: 0.98)
        let baseInset = w * WWClock.clamp(baseInsetFraction, min: 0.0, max: 0.25)

        let tipWidth = w * tipFraction
        let tipInsetX = (w - tipWidth) * 0.5

        let a = CGPoint(x: rect.minX + baseInset, y: rect.maxY)                 // base-left
        let b = CGPoint(x: rect.minX + tipInsetX, y: rect.minY)                 // tip-left
        let c = CGPoint(x: rect.maxX - tipInsetX, y: rect.minY)                 // tip-right
        let d = CGPoint(x: rect.maxX - baseInset, y: rect.maxY)                 // base-right

        let cornerRadius = max(1, min(min(w, h) * cornerRadiusFraction, w * 0.22))

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

        let points = [a, b, c, d]
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

/// Leaf counterweight shape for the Segmented seconds hand.
///
/// Oriented vertically with the base at `rect.minY` and the pointed end at `rect.maxY`.
private struct WidgetWeaverClockSegmentedSecondHandLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        let midX = rect.midX
        let minY = rect.minY
        let maxY = rect.maxY

        let baseHalf = w * 0.14
        let shoulderHalf = w * 0.50

        let shoulderY = minY + (h * 0.36)
        let bellyY = minY + (h * 0.68)

        let tip = CGPoint(x: midX, y: maxY)

        let baseLeft = CGPoint(x: midX - baseHalf, y: minY)
        let baseRight = CGPoint(x: midX + baseHalf, y: minY)

        let leftShoulder = CGPoint(x: midX - shoulderHalf, y: shoulderY)
        let rightShoulder = CGPoint(x: midX + shoulderHalf, y: shoulderY)

        let leftBelly = CGPoint(x: midX - (shoulderHalf * 0.30), y: bellyY)
        let rightBelly = CGPoint(x: midX + (shoulderHalf * 0.30), y: bellyY)

        var p = Path()
        p.move(to: baseLeft)

        p.addQuadCurve(to: leftShoulder, control: CGPoint(x: rect.minX, y: minY + (h * 0.18)))
        p.addQuadCurve(to: leftBelly, control: CGPoint(x: rect.minX, y: minY + (h * 0.56)))
        p.addQuadCurve(to: tip, control: CGPoint(x: midX - (w * 0.08), y: maxY - (h * 0.10)))

        p.addQuadCurve(to: rightBelly, control: CGPoint(x: midX + (w * 0.08), y: maxY - (h * 0.10)))
        p.addQuadCurve(to: rightShoulder, control: CGPoint(x: rect.maxX, y: minY + (h * 0.56)))
        p.addQuadCurve(to: baseRight, control: CGPoint(x: rect.maxX, y: minY + (h * 0.18)))

        p.closeSubpath()
        return p
    }
}
