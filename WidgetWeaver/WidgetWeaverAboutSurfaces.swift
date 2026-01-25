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
    static let pageTint: Color = .orange

    static let backgroundBase: Color = Color(uiColor: .systemGroupedBackground)

    static func sectionAccent(title: String) -> Color {
        let t = title.lowercased()
        if t.contains("weather") { return .blue }
        if t.contains("calendar") { return .green }
        if t.contains("pro") { return .yellow }
        if t.contains("templates") { return .pink }
        if t.contains("ai") { return .indigo }
        if t.contains("variables") { return .teal }
        if t.contains("sharing") { return .mint }
        if t.contains("diagnostics") { return .gray }
        return .purple
    }
}

struct WidgetWeaverAboutBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                // Dark mode is intentionally unchanged.
                WidgetWeaverAboutTheme.backgroundBase
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [Color.pink.opacity(0.18), Color.clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 600
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [Color.orange.opacity(0.16), Color.clear],
                    center: .bottomTrailing,
                    startRadius: 0,
                    endRadius: 760
                )
                .ignoresSafeArea()

                RadialGradient(
                    colors: [Color.purple.opacity(0.14), Color.clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 820
                )
                .ignoresSafeArea()
            } else {
                // Light mode: higher-contrast “paper” backdrop with soft colour energy + subtle texture.
                WidgetWeaverAboutTheme.backgroundBase
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [
                        Color.white.opacity(0.92),
                        Color(uiColor: .systemGroupedBackground).opacity(0.70),
                        Color(uiColor: .systemGroupedBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                // Soft colour fields (kept low-saturation to avoid fighting content).
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color("AccentColor").opacity(0.18), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 260
                        )
                    )
                    .frame(width: 520, height: 520)
                    .blur(radius: 40)
                    .offset(x: -210, y: -260)
                    .ignoresSafeArea()

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.12), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 320
                        )
                    )
                    .frame(width: 620, height: 620)
                    .blur(radius: 44)
                    .offset(x: 240, y: -120)
                    .ignoresSafeArea()

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.10), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 360
                        )
                    )
                    .frame(width: 720, height: 720)
                    .blur(radius: 48)
                    .offset(x: 160, y: 340)
                    .ignoresSafeArea()

                // Fine grain helps the light UI feel less flat.
                Image("RainFuzzNoise_Sparse")
                    .resizable(resizingMode: .tile)
                    .scaleEffect(1.35)
                    .rotationEffect(.degrees(9))
                    .blendMode(.softLight)
                    .opacity(0.14)
                    .ignoresSafeArea()

                // Gentle vignette improves legibility near the bottom.
                LinearGradient(
                    colors: [Color.black.opacity(0.06), Color.clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
                .ignoresSafeArea()
            }
        }
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

// MARK: - Cards + headers

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

struct WidgetWeaverAboutCard: View {
    let accent: Color
    private let content: AnyView

    @Environment(\.colorScheme) private var colorScheme

    init<Content: View>(accent: Color, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = AnyView(content())
    }

    @ViewBuilder
    var body: some View {
        if colorScheme == .dark {
            // Dark mode is intentionally unchanged.
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.60),
                                    accent.opacity(0.18),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.22), Color.clear],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 260
                            )
                        )
                )
                .shadow(color: accent.opacity(0.10), radius: 18, x: 0, y: 10)
        } else {
            content
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Light mode: solid “ink on paper” surface with a clean border and gentle lift.
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    Color(uiColor: .systemBackground)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.26),
                                    accent.opacity(0.08),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(0.14), Color.clear],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 320
                            )
                        )
                )
                .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 12)
                .shadow(color: accent.opacity(0.10), radius: 30, x: 0, y: 18)
        }
    }
}

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
