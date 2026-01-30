//
//  WidgetWeaverAboutMark.swift
//  WidgetWeaver
//
//  Created by . . on 1/30/26.
//

import SwiftUI

struct WidgetWeaverAboutMark: View {
    let accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.90), accent.opacity(0.25)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)

            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
        }
        .frame(width: 40, height: 40)
        .shadow(color: accent.opacity(0.22), radius: 14, x: 0, y: 8)
        .accessibilityHidden(true)
    }
}
