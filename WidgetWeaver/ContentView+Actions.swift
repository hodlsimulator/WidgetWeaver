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

            let targets = WidgetWeaverSmartPhotoTargets.current()

            let prepared = try await Task.detached(priority: .userInitiated) {
                try WidgetWeaverSmartPhotoPipeline.prepareAndStore(imageData: data, targets: targets)
            }.value

            await MainActor.run {
                var d = currentFamilyDraft()
                d.imageFileName = prepared.imageSpec.fileName
                d.imageSmartPhoto = prepared.imageSpec.smartPhoto
                setCurrentFamilyDraft(d)

                if let themeUIImage = AppGroup.loadUIImage(fileName: prepared.themeImageFileName) {
                    handleImportedImageTheme(uiImage: themeUIImage, fileName: prepared.themeImageFileName)
                } else if let fallback = UIImage(data: data) {
                    handleImportedImageTheme(uiImage: fallback, fileName: prepared.imageSpec.fileName)
                }

                pickedPhoto = nil
            }
        } catch {
            // Intentionally ignored (image remains unchanged).
        }
    }

    // MARK: - Actions

    func saveCurrentSpec() {
        let spec = draftSpec(id: selectedSpecID)
        let results = store.saveSpec(spec)

        savedSpecs = results.savedSpecs
        defaultSpecID = results.defaultSpecID

        selectedSpecID = spec.id
        lastSavedAt = Date()

        saveStatusMessage = "Saved."
    }

    func deleteCurrentSpec() {
        let old = selectedSpecID
        let results = store.deleteSpec(id: old)

        savedSpecs = results.savedSpecs
        defaultSpecID = results.defaultSpecID

        if let first = savedSpecs.first {
            selectedSpecID = first.id
        } else {
            selectedSpecID = UUID()
        }

        lastSavedAt = Date()
        saveStatusMessage = "Deleted."
    }

    func setAsDefaultSpec() {
        let id = selectedSpecID
        store.setDefaultSpecID(id)
        defaultSpecID = id
        saveStatusMessage = "Default set."
    }

    func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        lastWidgetRefreshAt = Date()
        saveStatusMessage = "Widget refresh requested."
    }

    func exportDesignToClipboard(includeImages: Bool) {
        do {
            let specs = savedSpecs
            let payload = try store.exportExchangePayload(specs: specs, includeImages: includeImages)
            let data = try WidgetWeaverDesignExchangeCodec.encode(payload)
            let text = data.base64EncodedString()

            UIPasteboard.general.string = text
            saveStatusMessage = includeImages ? "Copied design + images to clipboard." : "Copied design to clipboard."
        } catch {
            saveStatusMessage = "Export failed."
        }
    }

    func importDesignFromClipboard() {
        guard let raw = UIPasteboard.general.string else {
            saveStatusMessage = "Clipboard empty."
            return
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = Data(base64Encoded: trimmed) else {
            saveStatusMessage = "Import failed: invalid text."
            return
        }

        do {
            let payload = try WidgetWeaverDesignExchangeCodec.decodeAny(data)
            let results = try store.importExchangePayload(payload, dedupePolicy: .renameIncomingIfConflict)

            savedSpecs = results.savedSpecs
            defaultSpecID = results.defaultSpecID

            if let first = results.importedIDs.first {
                selectedSpecID = first
            }

            saveStatusMessage = "Import complete."
        } catch {
            saveStatusMessage = "Import failed."
        }
    }
}
