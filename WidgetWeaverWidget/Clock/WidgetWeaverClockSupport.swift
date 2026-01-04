//
//  WidgetWeaverClockSupport.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import SwiftUI

enum WWClock {
    @inline(__always)
    static func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }

    @inline(__always)
    static func pixel(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return (value * scale).rounded(.toNearestOrAwayFromZero) / scale
    }

    @inline(__always)
    static func px(scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return 1.0 }
        return 1.0 / scale
    }

    @inline(__always)
    static func colour(_ hex: UInt32, alpha: Double = 1.0) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        return Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension View {
    @ViewBuilder
    func wwWidgetContainerBackground<Background: View>(
        @ViewBuilder _ background: () -> Background
    ) -> some View {
        // Prefer the widget container background API when available.
        // On older OS versions, fall back to a regular background so widgets never render as black.
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { background() }
        } else {
            self.background(background())
        }
    }
}
