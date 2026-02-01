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
            guard let loaded = try await WWPhotoImportNormaliser.loadNormalisedJPEGUpData(for: item, maxPixel: 3072, compressionQuality: 0.92) else {
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
            try AppGroup.writePickedImageDataNormalised(data, fileName: fileName, maxPixel: 1024, compressionQuality: 0.85)

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


    // MARK: - Manual Smart Crop (per-size override)

    func applyManualSmartCrop(family: EditingFamily, cropRect: NormalisedRect) async {
        let newCrop = cropRect.normalised()

        var d = currentFamilyDraft()
        guard var smart = d.imageSmartPhoto else {
            saveStatusMessage = "No Smart Photo to edit."
            return
        }

        let existingVariant: SmartPhotoVariantSpec?
        switch family {
        case .small: existingVariant = smart.small
        case .medium: existingVariant = smart.medium
        case .large: existingVariant = smart.large
        }

        guard let variant = existingVariant else {
            saveStatusMessage = "Smart render data missing for \(family.label)."
            return
        }

        guard let masterData = AppGroup.readImageData(fileName: smart.masterFileName) else {
            saveStatusMessage = "Smart master file missing.\nTry “Regenerate smart renders”."
            return
        }

        saveStatusMessage = "Applying crop…"

        let targetPixels = variant.pixelSize.normalised()
        let oldRenderFileName = variant.renderFileName

        let newRenderFileName = AppGroup.createImageFileName(prefix: "smart-\(family.rawValue)-manual", ext: "jpg")

        let maxBytes: Int = {
            switch family {
            case .small: return 450_000
            case .medium: return 650_000
            case .large: return 900_000
            }
        }()

        do {
            try await Task.detached(priority: .userInitiated) {
                guard let masterImage = UIImage(data: masterData) else {
                    throw ManualSmartCropError.decodeFailed
                }

                let rendered = ManualSmartCropRenderer.render(
                    master: masterImage,
                    cropRect: newCrop,
                    targetPixels: targetPixels
                )

                let jpeg = try ManualSmartCropRenderer.encodeJPEG(
                    image: rendered,
                    startQuality: 0.85,
                    maxBytes: maxBytes
                )

                try AppGroup.writeImageData(jpeg, fileName: newRenderFileName)

                if !oldRenderFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    AppGroup.deleteImage(fileName: oldRenderFileName)
                }
            }.value

            var updated = variant
            updated.cropRect = newCrop
            updated.renderFileName = newRenderFileName

            switch family {
            case .small: smart.small = updated
            case .medium: smart.medium = updated
            case .large: smart.large = updated
            }

            smart.preparedAt = Date()
            smart = smart.normalised()

            d.imageSmartPhoto = smart

            // Backwards compatibility: ImageSpec.fileName remains the Medium render.
            if family == .medium {
                d.imageFileName = newRenderFileName
            }

            setCurrentFamilyDraft(d)

            saveStatusMessage = "Updated \(family.label) framing (draft only).\nSave to update widgets."
        } catch {
            saveStatusMessage = "Crop update failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Manual Smart Crop (Album Shuffle per-entry override)

    func applyManualSmartCropForShuffleEntry(
        manifestFileName: String,
        entryID: String,
        family: EditingFamily,
        cropRect: NormalisedRect
    ) async {
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mf.isEmpty else {
            saveStatusMessage = "Shuffle manifest file name is missing."
            return
        }

        let id = entryID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            saveStatusMessage = "Shuffle entry ID is missing."
            return
        }

        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            saveStatusMessage = "Shuffle manifest not found."
            return
        }

        guard let idx = manifest.entries.firstIndex(where: { $0.id == id }) else {
            saveStatusMessage = "Selected shuffle photo is no longer in the manifest."
            return
        }

        let entry = manifest.entries[idx]
        guard entry.isPrepared else {
            saveStatusMessage = "Selected shuffle photo has not been prepared yet."
            return
        }

        let sourceFile = (entry.sourceFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceFile.isEmpty else {
            saveStatusMessage = "Source image is missing for this shuffled photo.\nRe-prepare this album shuffle set to enable manual framing."
            return
        }

        guard let masterData = AppGroup.readImageData(fileName: sourceFile) else {
            saveStatusMessage = "Source image file not found on disk.\nRe-prepare this album shuffle set to enable manual framing."
            return
        }

        let newCrop = cropRect.normalised()

        let targets = SmartPhotoRenderTargets.forCurrentDevice()
        let targetPixels: PixelSize = {
            switch family {
            case .small: return targets.small
            case .medium: return targets.medium
            case .large: return targets.large
            }
        }()

        let oldManualFileName: String? = {
            switch family {
            case .small: return entry.smallManualFile
            case .medium: return entry.mediumManualFile
            case .large: return entry.largeManualFile
            }
        }()

        let newRenderFileName = AppGroup.createImageFileName(prefix: "smart-shuffle-\(family.rawValue)-manual", ext: "jpg")

        let maxBytes: Int = {
            switch family {
            case .small: return 450_000
            case .medium: return 650_000
            case .large: return 900_000
            }
        }()

        saveStatusMessage = "Applying crop…"

        do {
            try await Task.detached(priority: .userInitiated) {
                guard let masterImage = UIImage(data: masterData) else {
                    throw ManualSmartCropError.decodeFailed
                }

                let rendered = ManualSmartCropRenderer.render(
                    master: masterImage,
                    cropRect: newCrop,
                    targetPixels: targetPixels
                )

                let jpeg = try ManualSmartCropRenderer.encodeJPEG(
                    image: rendered,
                    startQuality: 0.85,
                    maxBytes: maxBytes
                )

                try AppGroup.writeImageData(jpeg, fileName: newRenderFileName)

                if let old = oldManualFileName?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !old.isEmpty
                {
                    AppGroup.deleteImage(fileName: old)
                }
            }.value

            guard var latest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
                saveStatusMessage = "Shuffle manifest not found after rendering."
                return
            }

            guard let latestIdx = latest.entries.firstIndex(where: { $0.id == id }) else {
                saveStatusMessage = "Selected shuffle photo is no longer in the manifest."
                return
            }

            var updated = latest.entries[latestIdx]
            switch family {
            case .small:
                updated.smallManualFile = newRenderFileName
                updated.smallManualCropRect = newCrop
            case .medium:
                updated.mediumManualFile = newRenderFileName
                updated.mediumManualCropRect = newCrop
            case .large:
                updated.largeManualFile = newRenderFileName
                updated.largeManualCropRect = newCrop
            }

            latest.entries[latestIdx] = updated
            try SmartPhotoShuffleManifestStore.save(latest, fileName: mf)

            saveStatusMessage = "Updated \(family.label) framing for the selected shuffled photo."
        } catch {
            saveStatusMessage = "Crop update failed: \(error.localizedDescription)"
        }
    }

    func resetManualSmartCropForShuffleEntry(
        manifestFileName: String,
        entryID: String,
        family: EditingFamily
    ) async {
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mf.isEmpty else {
            saveStatusMessage = "Shuffle manifest file name is missing."
            return
        }

        let id = entryID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            saveStatusMessage = "Shuffle entry ID is missing."
            return
        }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            saveStatusMessage = "Shuffle manifest not found."
            return
        }

        guard let idx = manifest.entries.firstIndex(where: { $0.id == id }) else {
            saveStatusMessage = "Selected shuffle photo is no longer in the manifest."
            return
        }

        var entry = manifest.entries[idx]

        let oldManualFile: String? = {
            switch family {
            case .small: return entry.smallManualFile
            case .medium: return entry.mediumManualFile
            case .large: return entry.largeManualFile
            }
        }()

        switch family {
        case .small:
            entry.smallManualFile = nil
            entry.smallManualCropRect = nil
        case .medium:
            entry.mediumManualFile = nil
            entry.mediumManualCropRect = nil
        case .large:
            entry.largeManualFile = nil
            entry.largeManualCropRect = nil
        }

        manifest.entries[idx] = entry

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)

            if let old = oldManualFile?.trimmingCharacters(in: .whitespacesAndNewlines),
               !old.isEmpty
            {
                AppGroup.deleteImage(fileName: old)
            }

            saveStatusMessage = "Reset \(family.label) framing to Auto for the selected shuffled photo."
        } catch {
            saveStatusMessage = "Failed to reset framing: \(error.localizedDescription)"
        }
    }

    func makeShuffleEntryCurrent(
        manifestFileName: String,
        entryID: String
    ) async {
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mf.isEmpty else {
            saveStatusMessage = "Shuffle manifest file name is missing."
            return
        }

        let id = entryID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            saveStatusMessage = "Shuffle entry ID is missing."
            return
        }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            saveStatusMessage = "Shuffle manifest not found."
            return
        }

        guard let idx = manifest.entries.firstIndex(where: { $0.id == id }) else {
            saveStatusMessage = "Selected shuffle photo is no longer in the manifest."
            return
        }

        let now = Date()
        _ = manifest.catchUpRotation(now: now)

        manifest.currentIndex = idx
        if manifest.rotationIntervalMinutes > 0 {
            manifest.nextChangeDate = now.addingTimeInterval(TimeInterval(manifest.rotationIntervalMinutes) * 60.0)
        }

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
            WidgetWeaverWidgetRefresh.forceKick()
            saveStatusMessage = "Pinned the selected shuffled photo as the current widget photo."
        } catch {
            saveStatusMessage = "Failed to set current photo: \(error.localizedDescription)"
        }
    }

    func upgradeLegacyPhotosInCurrentDesign(maxUpgrades: Int = 3) async {
        let clampedMax = max(1, min(3, maxUpgrades))

        guard matchedSetEnabled else {
            // Single-size designs already have a per-size “Make Smart Photo” button.
            // This helper upgrades the current size if it’s still legacy.
            if currentFamilyDraft().imageSmartPhoto == nil {
                await regenerateSmartPhotoRenders()
            } else {
                saveStatusMessage = "This photo is already a Smart Photo."
            }
            return
        }

        let orderedFamilies: [EditingFamily] = [.small, .medium, .large]

        var uniqueLegacyFiles: [String] = []
        var familiesByFile: [String: [EditingFamily]] = [:]

        for family in orderedFamilies {
            let draft = matchedDrafts[family]

            let trimmed = draft.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard draft.imageSmartPhoto == nil else { continue }

            let safeFileName = SmartPhotoSpec.sanitisedFileName(trimmed)
            guard !safeFileName.isEmpty else { continue }

            if familiesByFile[safeFileName] == nil {
                uniqueLegacyFiles.append(safeFileName)
                familiesByFile[safeFileName] = []
            }
            familiesByFile[safeFileName, default: []].append(family)
        }

        guard !uniqueLegacyFiles.isEmpty else {
            saveStatusMessage = "No legacy photos to upgrade in this design."
            return
        }

        let filesToProcess = Array(uniqueLegacyFiles.prefix(clampedMax))
        let remaining = max(0, uniqueLegacyFiles.count - filesToProcess.count)

        saveStatusMessage = "Upgrading legacy photos…"

        let targets = SmartPhotoRenderTargets.forCurrentDevice()

        var upgradedFamilies = Set<EditingFamily>()
        var failures: [String] = []

        for fileName in filesToProcess {
            guard let data = AppGroup.readImageData(fileName: fileName) else {
                failures.append(fileName)
                continue
            }

            do {
                let imageSpec = try await Task.detached(priority: .userInitiated) {
                    try SmartPhotoPipeline.prepare(from: data, renderTargets: targets)
                }.value

                let families = familiesByFile[fileName] ?? []
                for family in families {
                    var d = matchedDrafts[family]
                    d.imageFileName = imageSpec.fileName
                    d.imageSmartPhoto = imageSpec.smartPhoto
                    matchedDrafts[family] = d
                    upgradedFamilies.insert(family)
                }
            } catch {
                failures.append(fileName)
            }
        }

        if upgradedFamilies.isEmpty {
            if failures.isEmpty {
                saveStatusMessage = "No upgrades were performed."
            } else {
                saveStatusMessage = "Upgrade failed for \(failures.count) photo\(failures.count == 1 ? "" : "s").\nTry again, or upgrade each size individually using “Make Smart Photo”."
            }
            return
        }

        func sortKey(_ family: EditingFamily) -> Int {
            switch family {
            case .small: return 0
            case .medium: return 1
            case .large: return 2
            }
        }

        let upgradedLabel = upgradedFamilies
            .sorted { sortKey($0) < sortKey($1) }
            .map { $0.label }
            .joined(separator: ", ")

        var message = "Upgraded legacy photos to Smart Photo for: \(upgradedLabel) (draft only).\nSave to update widgets."

        if remaining > 0 {
            message += "\n\nMore legacy images remain (\(remaining)). Tap again to continue."
        }

        if !failures.isEmpty {
            message += "\n\nSome photos failed to upgrade (\(failures.count))."
        }

        saveStatusMessage = message
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
        WidgetWeaverWidgetReloadCoordinator.shared.scheduleReloadAllKnownTimelines(debounceSeconds: 0.0)
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

// MARK: - Manual Smart Crop helpers

private enum ManualSmartCropError: Error {
    case decodeFailed
    case encodeFailed
}

private enum ManualSmartCropRenderer {
    static func render(master: UIImage, cropRect: NormalisedRect, targetPixels: PixelSize) -> UIImage {
        guard let sourceCg = master.cgImage else { return master }

        let cropRectPixels = CGRect(
            x: CGFloat(cropRect.x) * CGFloat(sourceCg.width),
            y: CGFloat(cropRect.y) * CGFloat(sourceCg.height),
            width: CGFloat(cropRect.width) * CGFloat(sourceCg.width),
            height: CGFloat(cropRect.height) * CGFloat(sourceCg.height)
        ).integral

        let bounds = CGRect(x: 0, y: 0, width: sourceCg.width, height: sourceCg.height)
        let safeRect = cropRectPixels.intersection(bounds)

        let cropCg = (safeRect.isNull || safeRect.isEmpty)
        ? sourceCg
        : (sourceCg.cropping(to: safeRect) ?? sourceCg)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: targetPixels.width, height: targetPixels.height),
            format: format
        )

        let img = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: targetPixels.width, height: targetPixels.height))

            let cropped = UIImage(cgImage: cropCg, scale: 1, orientation: .up)
            cropped.draw(in: CGRect(x: 0, y: 0, width: targetPixels.width, height: targetPixels.height))
        }

        return img
    }

    static func encodeJPEG(image: UIImage, startQuality: CGFloat, maxBytes: Int) throws -> Data {
        var q = min(0.95, max(0.1, startQuality))
        let minQ: CGFloat = 0.65

        guard var data = image.jpegData(compressionQuality: q) else {
            throw ManualSmartCropError.encodeFailed
        }

        var steps = 0
        while data.count > maxBytes && q > minQ && steps < 6 {
            q = max(minQ, q - 0.05)
            guard let next = image.jpegData(compressionQuality: q) else { break }
            data = next
            steps += 1
        }

        if data.isEmpty {
            throw ManualSmartCropError.encodeFailed
        }

        return data
    }
}
