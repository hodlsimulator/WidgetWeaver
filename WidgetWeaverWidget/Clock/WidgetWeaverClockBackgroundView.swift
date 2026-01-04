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
                // Solid background (no gradient) per the dial mock.
                .fill(palette.backgroundBottom)
                // Thin outer edge highlight (keeps the rounded-square readable without shading the fill).
                .overlay(
                    shape
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: px)
                        .blendMode(.overlay)
                )
        }
    }
}
