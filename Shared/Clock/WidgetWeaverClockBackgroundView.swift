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

    var body: some View {
        let px = WWClock.px(scale: displayScale)

        let bg = LinearGradient(
            gradient: Gradient(colors: [palette.backgroundTop, palette.backgroundBottom]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        ContainerRelativeShape()
            .fill(bg)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
