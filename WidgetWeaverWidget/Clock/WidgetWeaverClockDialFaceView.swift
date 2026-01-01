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
            // Perimeter vignette: darken outer ~12–18%.
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: palette.dialVignette, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: radius * 0.82,
                            endRadius: radius
                        )
                    )
                    .blendMode(.multiply)
            )
            // Broad dome highlight biased upper-left (large area, low contrast).
            .overlay(
                Ellipse()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: palette.dialDomeHighlight, location: 0.0),
                                .init(color: Color.clear, location: 1.0)
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
            // Slight lower-half darkening to keep the face “near-black”.
            //
            // Using `.blendMode(.multiply)` with fully transparent gradient stops can produce
            // a hard horizontal seam in some WidgetKit renders (reads like a rectangular overlay).
            // A simple alpha overlay avoids that artefact and remains visually close.
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.black.opacity(0.00), location: 0.00),
                                .init(color: Color.black.opacity(0.06), location: 0.55),
                                .init(color: Color.black.opacity(0.18), location: 1.00)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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
