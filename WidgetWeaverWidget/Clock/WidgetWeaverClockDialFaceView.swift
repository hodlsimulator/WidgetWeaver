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
                        .init(color: palette.dialCenter, location: 0.0),
                        .init(color: palette.dialMid, location: 0.60),
                        .init(color: palette.dialEdge, location: 1.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            // Subtle top-to-bottom tone curve (helps the dial read as dark graphite, not pure black).
            //
            // Avoid fully-transparent stops: WidgetKit can rasterise those into hard seams.
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.white.opacity(0.06), location: 0.00),
                                .init(color: Color.black.opacity(0.02), location: 0.55),
                                .init(color: Color.black.opacity(0.22), location: 1.00)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.overlay)
                    .opacity(0.90)
            )
            // Perimeter vignette: darken outer ~12–18%.
            //
            // Spread the transition over a slightly wider band to avoid a hard edge just inside the dots.
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.dialVignette.opacity(0.02), location: 0.00),
                                .init(color: palette.dialVignette.opacity(0.22), location: 0.55),
                                .init(color: palette.dialVignette, location: 1.00)
                            ]),
                            center: .center,
                            startRadius: radius * 0.76,
                            endRadius: radius
                        )
                    )
                    .blendMode(.multiply)
            )
            // Broad dome highlight biased upper-left (large area, low contrast).
            //
            // Note:
            // A previous “lower-half darkening” layer used multiply-blended gradients with
            // fully-transparent stops. WidgetKit can occasionally rasterise that into a hard
            // horizontal seam that reads like a rectangular overlay.
            .overlay(
                Ellipse()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.dialDomeHighlight, location: 0.0),
                                .init(color: Color.white.opacity(0.00), location: 1.0)
                            ]),
                            center: .center,
                            startRadius: 0,
                            endRadius: radius * 1.10
                        )
                    )
                    .frame(width: radius * 2.15, height: radius * 1.70)
                    .offset(x: -radius * 0.20, y: -radius * 0.24)
                    .blendMode(.screen)
                    .opacity(0.95)
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
