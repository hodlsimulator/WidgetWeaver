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
            guard let uiImage = UIImage(data: data) else { return }

            let fileName = AppGroup.createImageFileName(ext: "jpg")
            try AppGroup.writeUIImage(uiImage, fileName: fileName, compressionQuality: 0.85)

            await MainActor.run {
                var d = currentFamilyDraft()
                d.imageFileName = fileName
                setCurrentFamilyDraft(d)
                pickedPhoto = nil
            }
        } catch {
            // Intentionally ignored (image remains unchanged).
        }
    }

    // MARK: - Actions

    func loadSelected() {
        let spec = store.load(id: selectedSpecID) ?? store.loadDefault()
        applySpec(spec)
    }

    func saveSelected(makeDefault: Bool) {
        var spec = draftSpec(id: selectedSpecID)
        spec.updatedAt = Date()
        spec = spec.normalised()

        store.save(spec, makeDefault: makeDefault)

        lastSavedAt = spec.updatedAt
        defaultSpecID = store.defaultSpecID()
        lastWidgetRefreshAt = Date()

        saveStatusMessage = makeDefault
            ? "Saved and set as default.\nWidgets refreshed."
            : "Saved.\nWidgets refreshed."

        refreshSavedSpecs(preservingSelection: true)
    }

    func refreshWidgets() {
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
        WidgetCenter.shared.invalidateConfigurationRecommendations()
        lastWidgetRefreshAt = Date()
        saveStatusMessage = "Widgets refreshed."
    }

    func createNewDesign() {
        var spec = WidgetSpec.defaultSpec().normalised()
        spec.id = UUID()
        spec.updatedAt = Date()
        spec.name = "New Design"

        store.save(spec, makeDefault: false)

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)

        saveStatusMessage = "Created a new design."
    }

    func duplicateCurrentDesign() {
        let base = draftSpec(id: selectedSpecID)

        var spec = base
        spec.id = UUID()
        spec.updatedAt = Date()
        spec.name = "Copy of \(base.name)"

        store.save(spec, makeDefault: false)

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)

        saveStatusMessage = "Duplicated design."
    }

    func deleteCurrentDesign() {
        store.delete(id: selectedSpecID)
        refreshSavedSpecs(preservingSelection: false)
        loadSelected()
        lastWidgetRefreshAt = Date()
        saveStatusMessage = "Deleted design.\nWidgets refreshed."
    }

    // MARK: - AI

    @MainActor
    func generateNewDesignFromPrompt() async {
        aiStatusMessage = ""

        let prompt = aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        let result = await WidgetSpecAIService.shared.generateNewSpec(from: prompt)

        var spec = result.spec.normalised()
        spec.updatedAt = Date()

        store.save(spec, makeDefault: aiMakeGeneratedDefault)

        defaultSpecID = store.defaultSpecID()
        lastWidgetRefreshAt = Date()
        aiStatusMessage = result.note
        aiPrompt = ""

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)

        saveStatusMessage = "Generated design saved.\nWidgets refreshed."
    }

    @MainActor
    func applyPatchToCurrentDesign() async {
        aiStatusMessage = ""

        let instruction = aiPatchInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return }

        let style = styleDraft.toStyleSpec()
        let current = currentFamilyDraft().toFlatSpec(
            id: selectedSpecID,
            name: designName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "WidgetWeaver"
                : designName.trimmingCharacters(in: .whitespacesAndNewlines),
            style: style,
            updatedAt: Date()
        )

        let result = await WidgetSpecAIService.shared.applyPatch(to: current, instruction: instruction)
        let patched = result.spec.normalised()

        designName = patched.name
        styleDraft = StyleDraft(from: patched.style)

        var d = currentFamilyDraft()
        d.apply(flatSpec: patched)
        setCurrentFamilyDraft(d)

        var combined = draftSpec(id: selectedSpecID).normalised()
        combined.updatedAt = Date()
        store.save(combined, makeDefault: false)

        lastSavedAt = combined.updatedAt
        lastWidgetRefreshAt = Date()
        aiStatusMessage = result.note
        aiPatchInstruction = ""

        refreshSavedSpecs(preservingSelection: true)

        saveStatusMessage = "Patched design saved.\nWidgets refreshed."
    }

    // MARK: - Import

    func importDesigns(from url: URL) async {
        guard !importInProgress else { return }
        importInProgress = true
        defer { importInProgress = false }

        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let result = try store.importDesigns(from: data, makeDefault: false)

            refreshSavedSpecs(preservingSelection: false)

            if let firstID = result.importedIDs.first {
                selectedSpecID = firstID
                loadSelected()
            }

            lastWidgetRefreshAt = Date()

            if result.importedCount == 0 {
                saveStatusMessage = "Import complete.\nNo designs were added."
            } else {
                saveStatusMessage = "Imported \(result.importedCount) design\(result.importedCount == 1 ? "" : "s").\nWidgets refreshed."
            }

            if !result.notes.isEmpty {
                let suffix = result.notes.prefix(2).joined(separator: "\n")
                saveStatusMessage += "\n\(suffix)"
            }
        } catch {
            saveStatusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Sharing

    func sharePackageForCurrentDesign() -> WidgetWeaverSharePackage {
        let spec = draftSpec(id: selectedSpecID).normalised()
        let fileName = WidgetWeaverSharePackage.suggestedFileName(prefix: spec.name, suffix: "design")

        let data = (try? store.exportExchangeData(specs: [spec], includeImages: true)) ?? Data()
        return WidgetWeaverSharePackage(fileName: fileName, data: data)
    }

    func sharePackageForAllDesigns() -> WidgetWeaverSharePackage {
        let fileName = WidgetWeaverSharePackage.suggestedFileName(prefix: "WidgetWeaver", suffix: "designs")
        let data = (try? store.exportAllExchangeData(includeImages: true)) ?? Data()
        return WidgetWeaverSharePackage(fileName: fileName, data: data)
    }

    // MARK: - Appearance

    static func applyAppearanceIfNeeded() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}
