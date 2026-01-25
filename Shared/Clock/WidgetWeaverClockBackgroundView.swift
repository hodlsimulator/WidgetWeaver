//
//  WidgetWeaverClockBackgroundView.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

struct WidgetWeaverClockBackgroundView: View {
    let palette: WidgetWeaverClockPalette

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let px = WWClock.px(scale: displayScale)
        let isDark = (colorScheme == .dark)

        let bg = LinearGradient(
            gradient: Gradient(colors: [palette.backgroundTop, palette.backgroundBottom]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        // A subtle scheme tint makes scheme changes obvious even when the dial changes are subtle.
        // Kept deliberately restrained to avoid distracting from the dial and hands.
        let tint = RadialGradient(
            gradient: Gradient(colors: [
                palette.accent.opacity(isDark ? 0.22 : 0.12),
                Color.clear
            ]),
            center: .topLeading,
            startRadius: 1,
            endRadius: 260
        )

        Rectangle()
            .fill(bg)
            .overlay(tint.blendMode(.overlay))
            .overlay(
                ContainerRelativeShape()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: px)
                    .blendMode(.overlay)
            )
            .overlay(
                ContainerRelativeShape()
                    .strokeBorder(Color.black.opacity(0.28), lineWidth: px)
                    .blendMode(.multiply)
            )
            .ignoresSafeArea()
    }
}
