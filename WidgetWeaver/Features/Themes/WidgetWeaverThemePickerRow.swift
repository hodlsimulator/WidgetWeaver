//
//  WidgetWeaverThemePickerRow.swift
//  WidgetWeaver
//
//  Created by . . on 1/31/26.
//

import SwiftUI

private enum WidgetWeaverThemePickerStorageKeys {
    static let selectedPresetID: String = "widgetweaver.theme.selectedPresetID"
}

@MainActor
struct WidgetWeaverThemePickerRow: View {

    var applyToDraft: (String) -> Void
    var applyToAllDesigns: ((String) -> Void)? = nil

    /// Hidden by default.
    ///
    /// This is intended for a later step (bulk apply) without changing the stored key or picker flow.
    var showsApplyToAllDesignsAction: Bool = false

    @AppStorage(WidgetWeaverThemePickerStorageKeys.selectedPresetID)
    private var selectedPresetIDRaw: String = ""

    @State private var isPickerPresented: Bool = false

    private var resolvedPreset: WidgetWeaverThemePreset {
        Self.resolvePreset(from: selectedPresetIDRaw)
    }

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            HStack(spacing: 10) {
                Label("Theme", systemImage: "paintpalette")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(resolvedPreset.displayName)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    WidgetWeaverThemeSwatch(style: resolvedPreset.style)
                        .frame(width: 46, height: 30)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Theme")
            .accessibilityValue(resolvedPreset.displayName)
            .accessibilityHint("Opens the theme picker.")
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $isPickerPresented) {
            WidgetWeaverThemePickerSheet(
                selectedPresetIDRaw: $selectedPresetIDRaw,
                applyToDraft: applyToDraft,
                applyToAllDesigns: applyToAllDesigns,
                showsApplyToAllDesignsAction: showsApplyToAllDesignsAction
            )
        }
        .onAppear {
            let cleaned = resolvedPreset.id
            if selectedPresetIDRaw != cleaned {
                selectedPresetIDRaw = cleaned
            }
        }
    }

    private static func resolvePreset(from rawID: String) -> WidgetWeaverThemePreset {
        if let preset = WidgetWeaverThemeCatalog.preset(matching: rawID) {
            return preset
        }

        if let preset = WidgetWeaverThemeCatalog.preset(matching: WidgetWeaverThemeCatalog.defaultPresetID) {
            return preset
        }

        return WidgetWeaverThemeCatalog.ordered.first
            ?? WidgetWeaverThemePreset(
                id: "classic",
                displayName: "Classic",
                detail: "System default theme.",
                style: .defaultStyle
            )
    }
}

@MainActor
private struct WidgetWeaverThemePickerSheet: View {
    @Binding var selectedPresetIDRaw: String

    let applyToDraft: (String) -> Void
    let applyToAllDesigns: ((String) -> Void)?
    let showsApplyToAllDesignsAction: Bool

    @Environment(\.dismiss) private var dismiss

    private var resolvedSelectedID: String {
        WidgetWeaverThemeCatalog.preset(matching: selectedPresetIDRaw)?.id
            ?? WidgetWeaverThemeCatalog.defaultPresetID
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Themes are curated presets that overwrite style in one deterministic operation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Themes") {
                    ForEach(WidgetWeaverThemeCatalog.ordered) { preset in
                        Button {
                            select(preset)
                        } label: {
                            WidgetWeaverThemePickerListRow(
                                preset: preset,
                                isSelected: preset.id == resolvedSelectedID
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    Button("Reset to default") {
                        selectDefault()
                    }
                }

                if showsApplyToAllDesignsAction, applyToAllDesigns != nil {
                    Section("Library") {
                        Text("Bulk apply is disabled in this build.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Themes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func selectDefault() {
        let id = WidgetWeaverThemeCatalog.defaultPresetID
        selectedPresetIDRaw = id
        applyToDraft(id)
        dismiss()
    }

    private func select(_ preset: WidgetWeaverThemePreset) {
        selectedPresetIDRaw = preset.id
        applyToDraft(preset.id)
        dismiss()
    }
}

private struct WidgetWeaverThemePickerListRow: View {
    let preset: WidgetWeaverThemePreset
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            WidgetWeaverThemeSwatch(style: preset.style)
                .frame(width: 96, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(preset.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(preset.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

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

private struct WidgetWeaverThemeSwatch: View {
    let style: StyleSpec

    var body: some View {
        let accent = style.accent.swiftUIColor
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        ZStack {
            Color(uiColor: .systemBackground)

            Rectangle()
                .fill(style.background.shapeStyle(accent: accent))

            Rectangle()
                .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                .opacity(style.backgroundOverlayOpacity)

            if style.backgroundGlowEnabled {
                glow(accent: accent)
            }

            accentPill(accent: accent)
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func glow(accent: Color) -> some View {
        Circle()
            .fill(accent.opacity(0.22))
            .frame(width: 92, height: 92)
            .blur(radius: 18)
            .offset(x: -26, y: -22)

        Circle()
            .fill(accent.opacity(0.16))
            .frame(width: 110, height: 110)
            .blur(radius: 22)
            .offset(x: 32, y: 22)
    }

    @ViewBuilder
    private func accentPill(accent: Color) -> some View {
        Capsule(style: .continuous)
            .fill(accent.opacity(0.85))
            .frame(width: 22, height: 5)
            .offset(x: 18, y: 16)
    }
}
