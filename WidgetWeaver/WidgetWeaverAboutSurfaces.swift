//
//  WidgetWeaverAboutSurfaces.swift
//  WidgetWeaver
//
//  Created by . . on 1/18/26.
//

import Foundation
import SwiftUI
import WidgetKit

// MARK: - Theme

enum WidgetWeaverAboutTheme {
    static var pageTint: Color {
        WidgetWeaverAppThemeReader.selectedTheme().tint
    }

    static let backgroundBase: Color = Color(uiColor: .systemGroupedBackground)

    static func sectionAccent(title: String) -> Color {
        let t = title.lowercased()
        if t.contains("photos") { return .pink }
        if t.contains("calendar") { return .blue }
        if t.contains("weather") { return .blue }
        if t.contains("steps") { return .green }
        if t.contains("activity") { return .green }
        if t.contains("reminders") { return .indigo }
        if t.contains("noise") { return .mint }
        if t.contains("pro") { return .orange }
        if t.contains("templates") { return .orange }
        if t.contains("variables") { return .teal }
        if t.contains("ai") { return .purple }
        if t.contains("privacy") { return .gray }
        if t.contains("support") { return .yellow }
        return WidgetWeaverAppThemeReader.selectedTheme().tint
    }
}

// MARK: - Background

struct WidgetWeaverAboutBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage(WidgetWeaverAppAppearanceKeys.theme)
    private var appThemeRaw: String = WidgetWeaverAppTheme.defaultTheme.rawValue

    private var appTheme: WidgetWeaverAppTheme {
        WidgetWeaverAppTheme.resolve(appThemeRaw)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if colorScheme == .dark {
                    darkLayers
                } else {
                    lightLayers
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var darkLayers: some View {
        // Dark mode is intentionally unchanged (layout is constrained to avoid sizing the parent).
        let h = appTheme.darkHighlights

        WidgetWeaverAboutTheme.backgroundBase
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        RadialGradient(
            colors: [h.first.opacity(0.18), Color.clear],
            center: .topLeading,
            startRadius: 0,
            endRadius: 600
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        RadialGradient(
            colors: [h.second.opacity(0.16), Color.clear],
            center: .bottomTrailing,
            startRadius: 0,
            endRadius: 760
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        RadialGradient(
            colors: [h.third.opacity(0.14), Color.clear],
            center: .top,
            startRadius: 0,
            endRadius: 820
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var lightLayers: some View {
        // Light mode: higher-contrast “paper” backdrop with soft colour energy + subtle texture.
        let h = appTheme.lightHighlights

        WidgetWeaverAboutTheme.backgroundBase
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        LinearGradient(
            colors: [
                Color.white.opacity(0.92),
                Color(uiColor: .systemGroupedBackground).opacity(0.70),
                Color(uiColor: .systemGroupedBackground)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Soft colour fields (kept low-saturation to avoid fighting content).
        Circle()
            .fill(
                RadialGradient(
                    colors: [h.first.opacity(0.18), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 260
                )
            )
            .frame(width: 520, height: 520)
            .blur(radius: 40)
            .offset(x: -210, y: -260)

        Circle()
            .fill(
                RadialGradient(
                    colors: [h.second.opacity(0.12), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 320
                )
            )
            .frame(width: 620, height: 620)
            .blur(radius: 44)
            .offset(x: 240, y: -120)

        Circle()
            .fill(
                RadialGradient(
                    colors: [h.third.opacity(0.10), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 420
                )
            )
            .frame(width: 760, height: 760)
            .blur(radius: 54)
            .offset(x: 160, y: 320)

        // Subtle noise texture (to reduce banding and “flatness”).
        Image("RainFuzzNoise_Sparse")
            .resizable(resizingMode: .tile)
            .scaleEffect(1.35)
            .rotationEffect(.degrees(9))
            .opacity(0.06)
            .blendMode(.overlay)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        // Gentle vignette to keep focus on content.
        RadialGradient(
            colors: [
                Color.clear,
                Color.black.opacity(0.06)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 900
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card surface

struct WidgetWeaverAboutCard<Content: View>: View {
    var title: String? = nil
    var accent: Color? = nil
    var content: Content

    init(title: String? = nil, accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)

                    if let accent {
                        Circle()
                            .fill(accent)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.bottom, 2)
            }

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
    }
}

// MARK: - Header surface

struct WidgetWeaverAboutHeaderCard<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 16, x: 0, y: 10)
    }
}
