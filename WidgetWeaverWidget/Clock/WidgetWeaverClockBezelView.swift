//
//  WidgetWeaverClockBezelView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockBezelView: View {
    let palette: WidgetWeaverClockPalette

    let outerDiameter: CGFloat
    let bezelWidth: CGFloat
    let separatorWidth: CGFloat
    let dialDiameter: CGFloat

    let scale: CGFloat

    var body: some View {
        let px = WWClock.px(scale: scale)

        // A) Outer rim highlight stroke (very thin)
        let outerRimWidth = max(px, bezelWidth * 0.12)

        // C) Inner occlusion stroke (thin), biased lower-right
        let innerOcclusionStrokeWidth = max(px, px)
        let innerBandWidth = max(px * 5.0, separatorWidth * 0.95)

        let outerR = outerDiameter * 0.5
        let innerR = outerR - bezelWidth
        let innerFraction = max(0.01, innerR / outerR)

        ZStack {
            // B) Main body ring: thickness gradient (outer edge slightly brighter than inner edge)
            WWClockAnnulus(innerRadiusFraction: innerFraction)
                .fill(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelDark, location: 0.00),
                            .init(color: palette.bezelMid, location: 0.62),
                            .init(color: palette.bezelBright, location: 1.00)
                        ]),
                        center: .center,
                        startRadius: innerR,
                        endRadius: outerR
                    ),
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .frame(width: outerDiameter, height: outerDiameter)

            // B) Angular spec: strong highlight around upper-left (~10–11), darker at lower-right (~4–5)
            WWClockAnnulus(innerRadiusFraction: innerFraction)
                .fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelBright.opacity(0.92), location: 0.00),
                            .init(color: palette.bezelBright.opacity(0.92), location: 0.03),
                            .init(color: palette.bezelMid.opacity(0.55), location: 0.11),
                            .init(color: palette.bezelMid.opacity(0.08), location: 0.24),
                            .init(color: palette.bezelDark.opacity(0.22), location: 0.58),
                            .init(color: palette.bezelDark.opacity(0.70), location: 0.73),
                            .init(color: palette.bezelMid.opacity(0.20), location: 0.86),
                            .init(color: palette.bezelBright.opacity(0.50), location: 0.96),
                            .init(color: palette.bezelBright.opacity(0.92), location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(-135)
                    ),
                    style: FillStyle(eoFill: true, antialiased: true)
                )
                .frame(width: outerDiameter, height: outerDiameter)
                .blendMode(.overlay)

            // A) Outer rim highlight: thin bright stroke, strongest on upper-left arc
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: palette.bezelBright.opacity(0.00), location: 0.00),
                            .init(color: palette.bezelBright.opacity(0.00), location: 0.86),
                            .init(color: palette.bezelBright.opacity(0.78), location: 0.90),
                            .init(color: palette.bezelBright.opacity(0.78), location: 0.95),
                            .init(color: palette.bezelBright.opacity(0.00), location: 1.00)
                        ]),
                        center: .center,
                        angle: .degrees(-135)
                    ),
                    lineWidth: outerRimWidth
                )
                .frame(width: outerDiameter, height: outerDiameter)
                .blendMode(.screen)

            // Strengthened separator ring immediately inside the bezel
            Circle()
                .strokeBorder(palette.separatorRing, lineWidth: separatorWidth)
                .frame(
                    width: outerDiameter - (bezelWidth * 2.0),
                    height: outerDiameter - (bezelWidth * 2.0)
                )

            // C) Inner occlusion: tight, biased lower-right, confined to a thin inner band
            Circle()
                .stroke(palette.bezelOcclusion, lineWidth: innerOcclusionStrokeWidth)
                .frame(width: dialDiameter, height: dialDiameter)
                .shadow(
                    color: palette.bezelOcclusion.opacity(0.75),
                    radius: px * 0.90,
                    x: px * 0.90,
                    y: px * 0.90
                )
                .mask(
                    Circle()
                        .stroke(Color.white, lineWidth: innerBandWidth)
                        .frame(width: dialDiameter, height: dialDiameter)
                )
                .blendMode(.multiply)
        }
        // Subtle outer drop shadow (tight, neutral)
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
