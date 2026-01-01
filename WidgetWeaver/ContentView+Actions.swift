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

                handleImportedImageTheme(uiImage: uiImage, fileName: fileName)
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

        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }

        lastWidgetRefreshAt = Date()
        saveStatusMessage = "Widgets refreshed."
    }

    func revertUnsavedChanges() {
        loadSelected()
        saveStatusMessage = "Reverted to last saved."
    }

    private func freeTierHasCapacityForNewDesign() -> Bool {
        if proManager.isProUnlocked { return true }
        return savedSpecs.count < WidgetWeaverEntitlements.maxFreeDesigns
    }

    private func showProForDesignLimit(message: String) {
        saveStatusMessage = message
        activeSheet = .pro
    }

    func createNewDesign() {
        guard freeTierHasCapacityForNewDesign() else {
            showProForDesignLimit(
                message: "Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) designs.\nUnlock Pro for unlimited designs."
            )
            return
        }

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

    func addTemplateDesign(_ template: WidgetSpec, makeDefault: Bool) {
        guard freeTierHasCapacityForNewDesign() else {
            showProForDesignLimit(
                message: "Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) designs.\nUnlock Pro to add more templates."
            )
            return
        }

        var spec = template.normalised()
        spec.id = UUID()
        spec.updatedAt = Date()

        store.save(spec, makeDefault: makeDefault)

        defaultSpecID = store.defaultSpecID()
        lastSavedAt = spec.updatedAt
        lastWidgetRefreshAt = Date()

        refreshSavedSpecs(preservingSelection: false)
        selectedSpecID = spec.id
        applySpec(spec)

        saveStatusMessage = makeDefault
        ? "Added template and set as default.\nWidgets refreshed."
        : "Added template.\nWidgets refreshed."
    }

    func duplicateCurrentDesign() {
        guard freeTierHasCapacityForNewDesign() else {
            showProForDesignLimit(
                message: "Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) designs.\nUnlock Pro for unlimited designs."
            )
            return
        }

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

    // MARK: - Draft helpers

    func randomiseStyleDraft() {
        var s = styleDraft

        s.background = BackgroundToken.allCases.randomElement() ?? s.background
        s.accent = AccentToken.allCases.randomElement() ?? s.accent

        s.padding = Double(Int.random(in: 8...24))
        s.cornerRadius = Double(Int.random(in: 16...32))

        let primaryOptions: [TextStyleToken] = [.automatic, .headline, .subheadline, .title3, .title2]
        let secondaryOptions: [TextStyleToken] = [.automatic, .caption, .caption2, .footnote, .subheadline]

        s.primaryTextStyle = primaryOptions.randomElement() ?? s.primaryTextStyle
        s.secondaryTextStyle = secondaryOptions.randomElement() ?? s.secondaryTextStyle
        s.nameTextStyle = .automatic

        styleDraft = s
        saveStatusMessage = "Randomised style (draft only)."
    }

    func cleanupUnusedImages() {
        let result = store.cleanupUnusedImages()
        lastWidgetRefreshAt = Date()

        if result.deletedCount == 0 {
            saveStatusMessage = "No unused images found.\n(\(result.existingCount) files, \(result.referencedCount) referenced)"
            return
        }

        saveStatusMessage = "Cleaned up \(result.deletedCount) unused image\(result.deletedCount == 1 ? "" : "s").\n(\(result.existingCount) files, \(result.referencedCount) referenced)"
    }

    // MARK: - AI

    @MainActor
    func generateNewDesignFromPrompt() async {
        aiStatusMessage = ""

        guard freeTierHasCapacityForNewDesign() else {
            aiStatusMessage = "Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) designs.\nUnlock Pro for unlimited designs."
            activeSheet = .pro
            return
        }

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

        if !proManager.isProUnlocked {
            let available = WidgetWeaverEntitlements.maxFreeDesigns - savedSpecs.count
            if available <= 0 {
                showProForDesignLimit(
                    message: "Free tier is at the \(WidgetWeaverEntitlements.maxFreeDesigns)-design limit.\nUnlock Pro to import more."
                )
                return
            }
        }

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

            if !proManager.isProUnlocked, result.importedCount == 0 {
                activeSheet = .pro
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
