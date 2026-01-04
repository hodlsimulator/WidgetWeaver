//
//  WidgetWeaverClockBackgroundView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockBackgroundView: View {
    let palette: WidgetWeaverClockPalette

    var body: some View {
        GeometryReader { proxy in
            let s = min(proxy.size.width, proxy.size.height)
            let corner = s * 0.205
            let px = max(CGFloat(1), s * 0.003)

            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

            shape
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [palette.backgroundTop, palette.backgroundBottom]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                // Outer edge highlight (thin, crisp).
                .overlay(
                    shape
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: px)
                        .blendMode(.overlay)
                )
                // Overall gloss: top lift → bottom weight (matches the mock “glass” look).
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.12),
                                    Color.white.opacity(0.02),
                                    Color.black.opacity(0.28)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blendMode(.overlay)
                )
                // Top-left specular bloom.
                .overlay(
                    shape
                        .fill(
                            RadialGradient(
                                gradient: Gradient(stops: [
                                    .init(color: Color.white.opacity(0.22), location: 0.00),
                                    .init(color: Color.white.opacity(0.08), location: 0.28),
                                    .init(color: Color.white.opacity(0.00), location: 0.70)
                                ]),
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: s * 0.95
                            )
                        )
                        .blendMode(.screen)
                        .opacity(0.90)
                )
                // Inner edge occlusion (gives the rounded square more depth).
                .overlay(
                    shape
                        .strokeBorder(Color.black.opacity(0.50), lineWidth: max(CGFloat(1), s * 0.010))
                        .blur(radius: s * 0.010)
                        .offset(x: s * 0.006, y: s * 0.010)
                        .mask(shape)
                        .blendMode(.multiply)
                        .opacity(0.55)
                )
        }
    }
}
