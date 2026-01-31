//
//  ContentView+ThemeActions.swift
//  WidgetWeaver
//
//  Created by . . on 1/31/26.
//

import Foundation

extension ContentView {

    private func resolvedThemePreset(themeID: String) -> WidgetWeaverThemePreset {
        if let match = WidgetWeaverThemeCatalog.preset(matching: themeID) {
            return match
        }

        if let fallback = WidgetWeaverThemeCatalog.preset(matching: WidgetWeaverThemeCatalog.defaultPresetID) {
            return fallback
        }

        return WidgetWeaverThemeCatalog.ordered.first
            ?? WidgetWeaverThemePreset(
                id: "classic",
                displayName: "Classic",
                detail: "System default theme.",
                style: StyleSpec.defaultStyle
            )
    }

    func applyThemeToDraft(themeID: String) {
        let preset = resolvedThemePreset(themeID: themeID)

        styleDraft = StyleDraft(from: preset.style)

        if currentFamilyDraft().template == .clockIcon, let clockThemeRaw = preset.clockThemeRaw {
            var d = currentFamilyDraft()
            d.clockThemeRaw = clockThemeRaw
            setCurrentFamilyDraft(d)
        }

        saveStatusMessage = "Applied theme: \(preset.displayName) (draft only)."
    }

    func applyThemeToAllDesigns(themeID: String) {
        let preset = resolvedThemePreset(themeID: themeID)

        saveStatusMessage = "Applying theme: \(preset.displayName) to all designs…"

        let store = store

        Task {
            let changedCount = await Task.detached(priority: .userInitiated) { () -> Int in
                store.bulkUpdate(ids: nil) { spec in
                    WidgetWeaverThemeApplier.apply(preset: preset, to: spec)
                }
            }.value

            refreshSavedSpecs(preservingSelection: true)

            if changedCount <= 0 {
                saveStatusMessage = "No saved designs needed updating for theme: \(preset.displayName)."
            } else if changedCount == 1 {
                saveStatusMessage = "Applied theme: \(preset.displayName) to 1 saved design."
            } else {
                saveStatusMessage = "Applied theme: \(preset.displayName) to \(changedCount) saved designs."
            }
        }
    }
}
