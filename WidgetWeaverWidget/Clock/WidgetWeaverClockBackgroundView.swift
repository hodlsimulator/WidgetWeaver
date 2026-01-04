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

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [palette.backgroundTop, palette.backgroundBottom]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: max(1, s * 0.003))
                        .blendMode(.overlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.00),
                                    Color.black.opacity(0.22)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blendMode(.overlay)
                )
        }
    }
}
