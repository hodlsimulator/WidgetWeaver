//
//  ContentView+Actions.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import SwiftUI
import WidgetKit
import PhotosUI
import UIKit

extension ContentView {

    // MARK: - Photos import

    func importPickedImage(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }

            // Widget render targets depend on the current device + screen scale.
            let targets = await MainActor.run { WidgetWeaverSmartPhotoTargets.current() }

            let prepared = try await Task.detached(priority: .userInitiated) {
                try WidgetWeaverSmartPhotoPipeline.prepareAndStore(imageData: data, targets: targets)
            }.value

            await MainActor.run {
                var d = currentFamilyDraft()
                d.imageFileName = prepared.imageSpec.fileName
                d.imageSmartPhoto = prepared.imageSpec.smartPhoto
                setCurrentFamilyDraft(d)

                if let uiImage = AppGroup.loadUIImage(fileName: prepared.themeImageFileName) {
                    handleImportedImageTheme(uiImage: uiImage, fileName: prepared.themeImageFileName)
                }
                pickedPhoto = nil
            }
        } catch {
            // Intentionally ignored (image remains unchanged).
        }
    }

    // MARK: - Share / Import (Design Exchange)

    func exportDesignExchangeText(includeImages: Bool) {
        let text = WidgetSpecStore.shared.exportExchangeFile(includeImages: includeImages)
        UIPasteboard.general.string = text
        exportStatusMessage = includeImages ? "Copied design + images to clipboard." : "Copied design to clipboard."
    }

    func importDesignExchangeText(from rawText: String, mergeStrategy: WidgetWeaverImportMergeStrategy) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let payload = WidgetWeaverDesignExchangeCodec.decodeFromText(trimmed) else {
            importStatusMessage = "Import failed: invalid text."
            return
        }

        do {
            try WidgetSpecStore.shared.importExchangePayload(payload, mergeStrategy: mergeStrategy)
            importStatusMessage = "Import complete."
        } catch {
            importStatusMessage = "Import failed."
        }
    }

    // MARK: - Widget refresh

    func reloadWidgets() {
        WidgetWeaverEntitlements.flushAndNotifyWidgets()
        widgetStatusMessage = "Requested widget reload."
    }

    // MARK: - Draft management

    func startNewDraft() {
        draft = EditorDraft.makeNew()
        isEditingExisting = false
        editorStatusMessage = "New design."
    }

    func startEditingSpec(_ spec: WidgetSpec) {
        draft = EditorDraft(from: spec)
        isEditingExisting = true
        editorStatusMessage = "Editing: \(spec.name)"
    }

    func saveDraft() {
        let spec = draft.toWidgetSpec()
        WidgetSpecStore.shared.upsertSpec(spec)
        isEditingExisting = true
        editorStatusMessage = "Saved."
    }

    func deleteCurrentDesign() {
        let id = draft.id
        WidgetSpecStore.shared.deleteSpec(id: id)
        let fallback = WidgetSpecStore.shared.loadDefaultSpec()
        draft = EditorDraft(from: fallback)
        isEditingExisting = true
        editorStatusMessage = "Deleted."
    }

    func revertDraftToSaved() {
        let id = draft.id
        let specs = WidgetSpecStore.shared.loadAllSpecs()
        if let saved = specs.first(where: { $0.id == id }) {
            draft = EditorDraft(from: saved)
            isEditingExisting = true
            editorStatusMessage = "Reverted to last saved."
        }
    }
}
