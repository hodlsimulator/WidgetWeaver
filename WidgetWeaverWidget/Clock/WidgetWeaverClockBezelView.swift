//
//  WidgetWeaverClockBezelView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockBezelView: View {
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
            // B) Main metal body: radial gradient across thickness
            WWClockAnnulus(innerRadiusFraction: innerFractionB)
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelDark, location: 0.00),
                            .init(color: palette.bezelMid, location: 0.62),
                            .init(color: palette.bezelBright, location: 1.00)
                        ]),
                        center: .center,
                        startRadius: innerBR,
                        endRadius: outerBR
                    ),
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .frame(width: outerB, height: outerB)

            // B) Angular/specular highlight: strong at ~10–11 o’clock, darker at ~4–5 o’clock
            WWClockAnnulus(innerRadiusFraction: innerFractionB)
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelBright.opacity(0.90), location: 0.000),
                            .init(color: palette.bezelBright.opacity(0.90), location: 0.040),
                            .init(color: palette.bezelMid.opacity(0.46), location: 0.120),
                            .init(color: palette.bezelMid.opacity(0.10), location: 0.260),
                            .init(color: palette.bezelDark.opacity(0.20), location: 0.560),
                            .init(color: palette.bezelDark.opacity(0.62), location: 0.740),
                            .init(color: palette.bezelMid.opacity(0.18), location: 0.880),
                            .init(color: palette.bezelBright.opacity(0.58), location: 0.965),
                            .init(color: palette.bezelBright.opacity(0.90), location: 1.000)
                        ]),
                        center: .center,
                        angle: .degrees(-135)
                    ),
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .frame(width: outerB, height: outerB)
                .blendMode(.overlay)

            // A) Outer rim highlight (very thin)
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelBright.opacity(0.00), location: 0.000),
                            .init(color: palette.bezelBright.opacity(0.00), location: 0.820),
                            .init(color: palette.bezelBright.opacity(0.72), location: 0.880),
                            .init(color: palette.bezelBright.opacity(0.90), location: 0.930),
                            .init(color: palette.bezelBright.opacity(0.72), location: 0.980),
                            .init(color: palette.bezelBright.opacity(0.00), location: 1.000)
                        ]),
                        center: .center,
                        angle: .degrees(-135)
                    ),
                    lineWidth: ringA
                )
                .frame(width: outerA, height: outerA)
                .blendMode(.screen)

            // C) Inner bevel ridge: thin bright chamfer right before the dial.
            Circle()
                .strokeBorder(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelBright.opacity(0.72), location: 0.00),
                            .init(color: palette.bezelMid.opacity(0.86), location: 0.55),
                            .init(color: palette.bezelDark.opacity(0.90), location: 1.00)
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
                            AngularGradient(
                                gradient: Gradient(stops: [
                                    .init(color: palette.bezelBright.opacity(0.44), location: 0.000),
                                    .init(color: palette.bezelBright.opacity(0.44), location: 0.060),
                                    .init(color: palette.bezelMid.opacity(0.14), location: 0.260),
                                    .init(color: palette.bezelDark.opacity(0.22), location: 0.700),
                                    .init(color: palette.bezelMid.opacity(0.16), location: 0.860),
                                    .init(color: palette.bezelBright.opacity(0.38), location: 1.000)
                                ]),
                                center: .center,
                                angle: .degrees(-135)
                            ),
                            lineWidth: ringC
                        )
                        .frame(width: outerC, height: outerC)
                        .blendMode(.overlay)
                )
        }
        // Subtle outer drop shadow (tight).
        .shadow(color: Color.black.opacity(0.30), radius: px * 1.4, x: 0, y: px * 1.0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Shapes

private struct WWClockAnnulus: Shape {
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
