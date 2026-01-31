//
//  ContentView+ThemeActions.swift
//  WidgetWeaver
//
//  Created by . . on 1/31/26.
//

import Foundation

extension ContentView {

    func applyThemeToDraft(themeID: String) {
        let preset: WidgetWeaverThemePreset = {
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
        }()

        styleDraft = StyleDraft(from: preset.style)

        if currentFamilyDraft().template == .clockIcon, let clockThemeRaw = preset.clockThemeRaw {
            var d = currentFamilyDraft()
            d.clockThemeRaw = clockThemeRaw
            setCurrentFamilyDraft(d)
        }

        saveStatusMessage = "Applied theme: \(preset.displayName) (draft only)."
    }
}
