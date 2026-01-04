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
        let data: Data
        do {
            guard let loaded = try await item.loadTransferable(type: Data.self) else {
                pickedPhoto = nil
                return
            }
            data = loaded
        } catch {
            pickedPhoto = nil
            return
        }

        // Prefer Smart Photo: master + per-family renders saved in the App Group.
        do {
            let targets = SmartPhotoRenderTargets.forCurrentDevice()
            let imageSpec = try await Task.detached(priority: .userInitiated) {
                try SmartPhotoPipeline.prepare(from: data, renderTargets: targets)
            }.value

            var d = currentFamilyDraft()
            d.imageFileName = imageSpec.fileName
            d.imageSmartPhoto = imageSpec.smartPhoto
            setCurrentFamilyDraft(d)

            if let themeImage = AppGroup.loadUIImage(fileName: imageSpec.fileName) ?? UIImage(data: data) {
                handleImportedImageTheme(uiImage: themeImage, fileName: imageSpec.fileName)
            }

            pickedPhoto = nil
            return
        } catch {
            // Fall back to the legacy single-file import if Smart Photo fails.
        }

        do {
            guard let uiImage = UIImage(data: data) else {
                pickedPhoto = nil
                return
            }

            let fileName = AppGroup.createImageFileName(ext: "jpg")
            try AppGroup.writeUIImage(uiImage, fileName: fileName, compressionQuality: 0.85)

            var d = currentFamilyDraft()
            d.imageFileName = fileName
            d.imageSmartPhoto = nil
            setCurrentFamilyDraft(d)

            handleImportedImageTheme(uiImage: uiImage, fileName: fileName)
            pickedPhoto = nil
        } catch {
            // Intentionally ignored (image remains unchanged).
            pickedPhoto = nil
        }
    }


    // MARK: - Smart Photo

    func regenerateSmartPhotoRenders() async {
        let current = currentFamilyDraft()
        let baseFileName = current.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !baseFileName.isEmpty else {
            saveStatusMessage = "No photo selected."
            return
        }

        saveStatusMessage = "Regenerating smart renders…"

        let targets = SmartPhotoRenderTargets.forCurrentDevice()

        let sourceData: Data
        if let smart = current.imageSmartPhoto,
           let master = AppGroup.readImageData(fileName: smart.masterFileName) {
            sourceData = master
        } else if let base = AppGroup.readImageData(fileName: baseFileName) {
            sourceData = base
        } else {
            saveStatusMessage = "Image file not found in App Group."
            return
        }

        do {
            let imageSpec = try await Task.detached(priority: .userInitiated) {
                try SmartPhotoPipeline.prepare(from: sourceData, renderTargets: targets)
            }.value

            var d = currentFamilyDraft()
            d.imageFileName = imageSpec.fileName
            d.imageSmartPhoto = imageSpec.smartPhoto
            setCurrentFamilyDraft(d)

            var appliedTheme = false
            if let uiImage = AppGroup.loadUIImage(fileName: imageSpec.fileName) {
                let suggestion = WidgetWeaverImageThemeExtractor.suggestTheme(from: uiImage)
                lastImageThemeFileName = imageSpec.fileName
                lastImageThemeSuggestion = suggestion

                if autoThemeFromImage {
                    styleDraft.accent = suggestion.accent
                    styleDraft.background = suggestion.background
                    appliedTheme = true
                }
            }

            saveStatusMessage = appliedTheme
                ? "Regenerated smart renders and applied theme (draft only).\nSave to update widgets."
                : "Regenerated smart renders (draft only).\nSave to update widgets."
        } catch {
            saveStatusMessage = "Regeneration failed: \(error.localizedDescription)"
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

    func prepareImportReview(from url: URL) async {
        guard !importInProgress else { return }
        importInProgress = true
        defer { importInProgress = false }

        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try WidgetWeaverImportReviewLogic.decodeImportFile(data: data)

            let fileName = url.lastPathComponent
            let model = WidgetWeaverImportReviewLogic.makeReviewModel(payload: payload, fileName: fileName)

            let availableSlots = max(0, WidgetWeaverEntitlements.maxFreeDesigns - savedSpecs.count)
            let initialSelection = WidgetWeaverImportReviewModel.defaultSelection(
                items: model.items,
                isProUnlocked: proManager.isProUnlocked,
                availableSlots: availableSlots
            )

            importReviewModel = model
            importReviewSelection = initialSelection
            activeSheet = .importReview
        } catch {
            saveStatusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func importReviewSelectAll() {
        guard let model = importReviewModel else { return }
        importReviewSelection = Set(model.items.map(\.id))
    }

    func importReviewSelectNone() {
        importReviewSelection.removeAll()
    }

    func importReviewLimitState() -> WidgetWeaverImportReviewLimitState {
        let availableSlots = max(0, WidgetWeaverEntitlements.maxFreeDesigns - savedSpecs.count)
        return WidgetWeaverImportReviewModel.limitState(
            isProUnlocked: proManager.isProUnlocked,
            selectionCount: importReviewSelection.count,
            availableSlots: availableSlots
        )
    }

    func cancelImportReview() {
        activeSheet = nil
        importReviewModel = nil
        importReviewSelection.removeAll()
    }

    func performImportReview() async {
        guard let model = importReviewModel else {
            cancelImportReview()
            return
        }

        let selectedCount = importReviewSelection.count
        let totalCount = model.items.count
        let skippedNotSelected = max(0, totalCount - selectedCount)

        guard selectedCount > 0 else {
            saveStatusMessage = "No designs selected."
            return
        }

        let limitState = importReviewLimitState()
        if case .exceedsFreeLimit = limitState {
            saveStatusMessage = "Selection exceeds free-tier limit."
            return
        }

        guard !importInProgress else { return }
        importInProgress = true
        defer { importInProgress = false }

        do {
            let subsetPayload = WidgetWeaverImportReviewLogic.makeSubsetPayload(
                payload: model.payload,
                selectedIDs: importReviewSelection
            )

            let subsetData = try WidgetWeaverDesignExchangeCodec.encode(subsetPayload)
            let result = try store.importDesigns(from: subsetData, makeDefault: false)

            refreshSavedSpecs(preservingSelection: false)

            if let firstID = result.importedIDs.first {
                selectedSpecID = firstID
                loadSelected()
            }

            lastWidgetRefreshAt = Date()

            saveStatusMessage = "Imported \(result.importedCount) design\(result.importedCount == 1 ? "" : "s"). Skipped \(skippedNotSelected) (not selected)."

            if !result.notes.isEmpty {
                let suffix = result.notes.prefix(2).joined(separator: "\n")
                saveStatusMessage += "\n\(suffix)"
            }

            if !proManager.isProUnlocked, result.importedCount == 0 {
                activeSheet = .pro
            } else {
                cancelImportReview()
            }
        } catch {
            saveStatusMessage = "Import failed: \(error.localizedDescription)"
        }
    }

    func importReviewSheetAnyView() -> AnyView {
        guard let model = importReviewModel else {
            return AnyView(
                Text("Nothing to import.")
                    .padding()
                    .onAppear { activeSheet = nil }
            )
        }

        let limitState = importReviewLimitState()
        let showUnlockPro = !proManager.isProUnlocked

        return AnyView(
            WidgetWeaverImportReviewSheet(
                model: model,
                selection: $importReviewSelection,
                limitState: limitState,
                isImporting: importInProgress,
                showUnlockPro: showUnlockPro,
                onCancel: { cancelImportReview() },
                onImport: { Task { await performImportReview() } },
                onSelectAll: { importReviewSelectAll() },
                onSelectNone: { importReviewSelectNone() },
                onUnlockPro: { activeSheet = .pro }
            )
        )
    }

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
