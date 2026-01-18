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
            let stroke = max(1, s * 0.003)

            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(palette.backgroundTop)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: stroke)
                        .blendMode(.overlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.28), lineWidth: stroke)
                        .blendMode(.multiply)
                )
        }
    }
}
