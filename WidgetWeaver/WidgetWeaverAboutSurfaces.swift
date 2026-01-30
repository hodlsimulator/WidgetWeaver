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
        let h = appTheme.darkHighlights
        let o = appTheme.darkGlowOpacities
        let base = appTheme.backgroundBase(for: .dark)

        base
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        RadialGradient(
            colors: [h.first.opacity(o.first), Color.clear],
            center: .topLeading,
            startRadius: 0,
            endRadius: 600
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        RadialGradient(
            colors: [h.second.opacity(o.second), Color.clear],
            center: .bottomTrailing,
            startRadius: 0,
            endRadius: 760
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        RadialGradient(
            colors: [h.third.opacity(o.third), Color.clear],
            center: .top,
            startRadius: 0,
            endRadius: 820
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Image("RainFuzzNoise_Sparse")
            .resizable(resizingMode: .tile)
            .scaleEffect(1.35)
            .rotationEffect(.degrees(11))
            .opacity(0.05)
            .blendMode(.overlay)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        RadialGradient(
            colors: [
                Color.clear,
                Color.black.opacity(0.10)
            ],
            center: .center,
            startRadius: 0,
            endRadius: 900
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var lightLayers: some View {
        // Light mode: higher-contrast “paper” backdrop with soft colour energy + subtle texture.
        let h = appTheme.lightHighlights
        let o = appTheme.lightGlowOpacities
        let base = appTheme.backgroundBase(for: .light)

        base
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        LinearGradient(
            colors: [
                Color.white.opacity(0.92),
                base.opacity(0.70),
                base
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        Circle()
            .fill(
                RadialGradient(
                    colors: [h.first.opacity(o.first), Color.clear],
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
                    colors: [h.second.opacity(o.second), Color.clear],
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
                    colors: [h.third.opacity(o.third), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 420
                )
            )
            .frame(width: 760, height: 760)
            .blur(radius: 54)
            .offset(x: 160, y: 320)

        Image("RainFuzzNoise_Sparse")
            .resizable(resizingMode: .tile)
            .scaleEffect(1.35)
            .rotationEffect(.degrees(9))
            .opacity(0.06)
            .blendMode(.overlay)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

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

// MARK: - List helpers

extension View {
    func wwAboutListRow() -> some View {
        self
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }
}

// MARK: - Section header

struct WidgetWeaverAboutSectionHeader: View {
    let title: String
    let systemImage: String
    let accent: Color

    init(_ title: String, systemImage: String, accent: Color) {
        self.title = title
        self.systemImage = systemImage
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(accent)

            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .textCase(nil)
        .padding(.leading, 4)
        .padding(.top, 4)
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
