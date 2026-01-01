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
            //
            // Note:
            // A previous “lower-half darkening” layer used multiply-blended gradients with
            // fully-transparent stops. WidgetKit can occasionally rasterise that into a hard
            // horizontal seam that reads like a rectangular overlay. The dial looks close
            // enough without that extra layer, and removing it avoids the artefact entirely.
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
