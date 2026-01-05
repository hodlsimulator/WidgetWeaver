//
//  ContentView+ImageTheme.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import SwiftUI
import UIKit

extension ContentView {

    func handleImportedImageTheme(uiImage: UIImage, fileName: String) {
        let suggestion = WidgetWeaverImageThemeExtractor.suggestTheme(from: uiImage)

        lastImageThemeFileName = fileName
        lastImageThemeSuggestion = suggestion

        guard autoThemeFromImage else { return }

        styleDraft.accent = suggestion.accent
        styleDraft.background = suggestion.background
        saveStatusMessage = "Applied theme from photo (draft only)."
    }

    func applyThemeFromCurrentImageIfPossible() {
        let fileName = currentFamilyDraft().imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileName.isEmpty else { return }
        guard let uiImage = AppGroup.loadUIImage(fileName: fileName) else { return }

        let suggestion = WidgetWeaverImageThemeExtractor.suggestTheme(from: uiImage)

        lastImageThemeFileName = fileName
        lastImageThemeSuggestion = suggestion

        styleDraft.accent = suggestion.accent
        styleDraft.background = suggestion.background
        saveStatusMessage = "Applied theme from photo (draft only)."
    }

    @ViewBuilder
    func imageThemeControls(currentImageFileName: String, hasImage: Bool) -> some View {
        Toggle("Auto theme from photo", isOn: $autoThemeFromImage)

        if hasImage {
            Button {
                applyThemeFromCurrentImageIfPossible()
            } label: {
                Label("Extract theme now", systemImage: "paintpalette")
            }

            if let suggestion = lastThemeSuggestionIfMatches(fileName: currentImageFileName) {
                Text("Suggested: \(suggestion.accent.displayName) accent · \(suggestion.background.displayName) background")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Theme suggestion updates when a new photo is picked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Theme extraction becomes available after choosing a photo.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        SmartPhotoAlbumShuffleControls(
            smartPhoto: binding(\.imageSmartPhoto),
            importInProgress: $importInProgress,
            saveStatusMessage: $saveStatusMessage
        )
    }

    private func lastThemeSuggestionIfMatches(fileName: String) -> WidgetWeaverImageThemeSuggestion? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed == lastImageThemeFileName else { return nil }
        return lastImageThemeSuggestion
    }
}
