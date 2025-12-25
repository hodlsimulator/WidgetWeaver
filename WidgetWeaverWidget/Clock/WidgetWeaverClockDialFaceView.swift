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

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: palette.dialCenter, location: 0.0),
                        .init(color: palette.dialMid, location: 0.62),
                        .init(color: palette.dialEdge, location: 1.0)
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
            // Perimeter vignette: darken outer ~12–18% radius.
            .overlay(
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: palette.dialVignette, location: 1.0)
                            ]),
                            center: .center,
                            startRadius: radius * 0.84,
                            endRadius: radius
                        )
                    )
                    .blendMode(.multiply)
            )
            // Broad, biased dome highlight (ellipse, not perfectly centred or circular).
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
                    .frame(width: radius * 2.20, height: radius * 1.65)
                    .offset(x: -radius * 0.18, y: -radius * 0.22)
                    .blendMode(.screen)
                    .opacity(0.92)
                    .mask(Circle())
            )
            // Slight lower-half darkening to avoid a flat centre.
            .overlay(
                Circle()
                    .fill(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color.clear, location: 0.0),
                                .init(color: Color.clear, location: 0.48),
                                .init(color: WWClock.colour(0x000000, alpha: 0.22), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.multiply)
            )
    }
}
