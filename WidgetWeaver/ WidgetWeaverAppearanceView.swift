//
//   WidgetWeaverAppearanceView.swift
//  WidgetWeaver
//
//  Created by . . on 1/30/26.
//

import SwiftUI

@MainActor
struct WidgetWeaverAppearanceView: View {

    var onClose: (() -> Void)? = nil

    @AppStorage(WidgetWeaverAppAppearanceKeys.theme)
    private var themeRaw: String = WidgetWeaverAppTheme.defaultTheme.rawValue

    @Environment(\.colorScheme) private var environmentColourScheme

    @State private var previewMode: PreviewMode = .system

    private enum PreviewMode: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var title: String {
            switch self {
            case .system:
                return "System"
            case .light:
                return "Light"
            case .dark:
                return "Dark"
            }
        }
    }

    private var selectedTheme: WidgetWeaverAppTheme {
        WidgetWeaverAppTheme.resolve(themeRaw)
    }

    private var swatchScheme: ColorScheme {
        switch previewMode {
        case .system:
            return environmentColourScheme
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Preview", selection: $previewMode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

            } footer: {
                Text("Themes apply across the app immediately and are saved on this device.")
            }

            Section("Themes") {
                ForEach(WidgetWeaverAppTheme.ordered) { theme in
                    Button {
                        themeRaw = theme.rawValue
                    } label: {
                        WidgetWeaverAppThemeRow(
                            theme: theme,
                            isSelected: theme == selectedTheme,
                            swatchScheme: swatchScheme
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button("Reset to default") {
                    themeRaw = WidgetWeaverAppTheme.defaultTheme.rawValue
                }
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let onClose {
                    Button("Done") { onClose() }
                }
            }
        }
    }
}

private struct WidgetWeaverAppThemeRow: View {
    let theme: WidgetWeaverAppTheme
    let isSelected: Bool
    let swatchScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            WidgetWeaverAppThemeSwatch(theme: theme, scheme: swatchScheme)
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(theme.displayName)
                    .font(.headline)

                Text(theme.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Selected")
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct WidgetWeaverAppThemeSwatch: View {
    let theme: WidgetWeaverAppTheme
    let scheme: ColorScheme

    var body: some View {
        ZStack {
            if scheme == .dark {
                dark
            } else {
                light
            }
        }
        .environment(\.colorScheme, scheme)
        .clipped()
        .accessibilityHidden(true)
    }

    private var dark: some View {
        let h = theme.darkHighlights

        return ZStack {
            Color(uiColor: .systemGroupedBackground)

            RadialGradient(
                colors: [h.first.opacity(0.18), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 220
            )

            RadialGradient(
                colors: [h.second.opacity(0.16), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 260
            )

            RadialGradient(
                colors: [h.third.opacity(0.14), Color.clear],
                center: .top,
                startRadius: 0,
                endRadius: 280
            )
        }
    }

    private var light: some View {
        let h = theme.lightHighlights

        return ZStack {
            Color(uiColor: .systemGroupedBackground)

            LinearGradient(
                colors: [
                    Color.white.opacity(0.92),
                    Color(uiColor: .systemGroupedBackground).opacity(0.70),
                    Color(uiColor: .systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [h.first.opacity(0.18), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 220, height: 220)
                .blur(radius: 18)
                .offset(x: -70, y: -80)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [h.second.opacity(0.12), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 140
                    )
                )
                .frame(width: 260, height: 260)
                .blur(radius: 18)
                .offset(x: 90, y: -40)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [h.third.opacity(0.10), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 170
                    )
                )
                .frame(width: 320, height: 320)
                .blur(radius: 20)
                .offset(x: 60, y: 120)
        }
    }
}
