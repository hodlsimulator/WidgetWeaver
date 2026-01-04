//
//  WidgetWeaverClockDialFaceView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockDialFaceView: View {
    let palette: WidgetWeaverClockPalette
    let radius: CGFloat
    let occlusionWidth: CGFloat

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        // A slightly flatter centre and a longer mid transition avoids the hard “ring”
                        // where the dial drops into the rim vignette.
                        .init(color: palette.dialCenter, location: 0.00),
                        .init(color: palette.dialCenter, location: 0.22),
                        .init(color: palette.dialMid, location: 0.62),
                        .init(color: palette.dialEdge, location: 0.90),
                        .init(color: palette.dialEdge, location: 1.00)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            // Subtle top-to-bottom tone curve.
            //
            // Avoid fully-transparent stops: WidgetKit can rasterise those into hard seams.
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.06), location: 0.00),
                                .init(color: Color.black.opacity(0.02), location: 0.55),
                                .init(color: Color.black.opacity(0.18), location: 1.00)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.overlay)
                    .opacity(0.88)
            )
            // Perimeter vignette: soften the falloff so it reads like curvature rather than a hard ring.
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.dialVignette.opacity(0.00), location: 0.00),
                                .init(color: palette.dialVignette.opacity(0.38), location: 0.55),
                                .init(color: palette.dialVignette.opacity(0.78), location: 1.00)
                            ]),
                            center: .center,
                            startRadius: radius * 0.70,
                            endRadius: radius
                        )
                    )
                    .blendMode(.multiply)
                    .opacity(0.95)
            )
            // Broad dome highlight biased upper-left (large area, low contrast).
            .overlay(
                Ellipse()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.dialDomeHighlight, location: 0.00),
                                .init(color: Color.white.opacity(0.00), location: 1.00)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: radius * 1.10
                        )
                    )
                    .frame(width: radius * 2.15, height: radius * 1.70)
                    .offset(x: -radius * 0.20, y: -radius * 0.24)
                    .blendMode(.screen)
                    .opacity(0.92)
                    .mask(Circle())
            )
            // Ring D: tight inner occlusion separator (crisp, no halo).
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.separatorRing.opacity(0.58), location: 0.0),
                                .init(color: palette.separatorRing.opacity(0.92), location: 1.0)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: occlusionWidth
                    )
            )
    }
}
