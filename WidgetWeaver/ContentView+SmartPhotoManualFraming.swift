//
//  ContentView+SmartPhotoManualFraming.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import SwiftUI
import UIKit

extension ContentView {
    func applyManualSmartCropWithStraighten(
        family: EditingFamily,
        cropRect: NormalisedRect,
        straightenDegrees: Double
    ) async {
        let newCrop = cropRect.normalised()
        let normalisedStraighten = SmartPhotoManualCropRenderer.normalisedStraightenDegrees(straightenDegrees)
        let degreesToApply = normalisedStraighten ?? 0

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
            saveStatusMessage = "Smart render data missing for \(family.label).\nTry “Regenerate smart renders”."
            return
        }

        let masterFileName = smart.masterFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !masterFileName.isEmpty else {
            saveStatusMessage = "Smart master file missing.\nTry “Regenerate smart renders”."
            return
        }

        guard let masterData = AppGroup.readImageData(fileName: masterFileName) else {
            saveStatusMessage = "Smart master file missing.\nTry “Regenerate smart renders”."
            return
        }

        saveStatusMessage = "Applying framing…"

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
                    throw SmartPhotoManualTransformError.masterDecodeFailed
                }

                let rendered = SmartPhotoManualCropRenderer.render(
                    master: masterImage,
                    cropRect: newCrop,
                    straightenDegrees: degreesToApply,
                    targetPixels: targetPixels
                )

                let jpeg = try SmartPhotoManualCropRenderer.encodeJPEG(
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
            updated.straightenDegrees = normalisedStraighten

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
            saveStatusMessage = "Framing update failed: \(error.localizedDescription)"
        }
    }

    func applyManualSmartCropForShuffleEntryWithStraighten(
        manifestFileName: String,
        entryID: String,
        family: EditingFamily,
        cropRect: NormalisedRect,
        straightenDegrees: Double
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
        let normalisedStraighten = SmartPhotoManualCropRenderer.normalisedStraightenDegrees(straightenDegrees)
        let degreesToApply = normalisedStraighten ?? 0

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

        saveStatusMessage = "Applying framing…"

        do {
            try await Task.detached(priority: .userInitiated) {
                guard let masterImage = UIImage(data: masterData) else {
                    throw SmartPhotoManualTransformError.masterDecodeFailed
                }

                let rendered = SmartPhotoManualCropRenderer.render(
                    master: masterImage,
                    cropRect: newCrop,
                    straightenDegrees: degreesToApply,
                    targetPixels: targetPixels
                )

                let jpeg = try SmartPhotoManualCropRenderer.encodeJPEG(
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
                updated.smallManualStraightenDegrees = normalisedStraighten
            case .medium:
                updated.mediumManualFile = newRenderFileName
                updated.mediumManualCropRect = newCrop
                updated.mediumManualStraightenDegrees = normalisedStraighten
            case .large:
                updated.largeManualFile = newRenderFileName
                updated.largeManualCropRect = newCrop
                updated.largeManualStraightenDegrees = normalisedStraighten
            }

            latest.entries[latestIdx] = updated
            try SmartPhotoShuffleManifestStore.save(latest, fileName: mf)

            saveStatusMessage = "Updated \(family.label) framing for the selected shuffled photo."
        } catch {
            saveStatusMessage = "Framing update failed: \(error.localizedDescription)"
        }
    }

    func resetManualSmartCropForShuffleEntryWithStraighten(
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
            entry.smallManualStraightenDegrees = nil
        case .medium:
            entry.mediumManualFile = nil
            entry.mediumManualCropRect = nil
            entry.mediumManualStraightenDegrees = nil
        case .large:
            entry.largeManualFile = nil
            entry.largeManualCropRect = nil
            entry.largeManualStraightenDegrees = nil
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
}
