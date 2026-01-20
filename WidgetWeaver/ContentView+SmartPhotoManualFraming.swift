//
//  ContentView+SmartPhotoManualFraming.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import Foundation
import SwiftUI

extension ContentView {
    func applyManualSmartCropWithStraighten(
        family: EditingFamily,
        cropRect: NormalisedRect,
        straightenDegrees: Double,
        rotationQuarterTurns: Int
    ) async {
        guard var spec = currentSpec else { return }
        guard var smart = spec.layout?.smartPhoto else { return }

        let newCrop = cropRect.normalised()
        let normalisedStraighten = SmartPhotoManualCropRenderer.normalisedStraightenDegrees(straightenDegrees)
        let degreesToApply = normalisedStraighten ?? 0
        let normalisedRotation = SmartPhotoManualCropRenderer.normalisedRotationQuarterTurns(rotationQuarterTurns)
        let turnsToApply = normalisedRotation ?? 0

        let targetPixels: PixelSize
        let masterFileName: String
        var variant: SmartPhotoVariantSpec

        switch family {
        case .small:
            targetPixels = smart.small.pixelSize
            masterFileName = smart.masterFileName
            variant = smart.small
        case .medium:
            targetPixels = smart.medium.pixelSize
            masterFileName = smart.masterFileName
            variant = smart.medium
        case .large:
            targetPixels = smart.large.pixelSize
            masterFileName = smart.masterFileName
            variant = smart.large
        }

        let masterImage = AppGroup.loadUIImage(fileName: masterFileName)
        guard let masterImage else { return }

        let renderedFileName = AppGroup.makeUniqueFileName(prefix: "smartPhotoManual", ext: "jpg")

        do {
            let rendered = SmartPhotoManualCropRenderer.render(
                master: masterImage,
                cropRect: newCrop,
                straightenDegrees: degreesToApply,
                rotationQuarterTurns: turnsToApply,
                targetPixels: targetPixels
            )

            let jpeg = try SmartPhotoManualCropRenderer.encodeJPEG(
                image: rendered,
                startQuality: 0.92,
                maxBytes: 1_800_000
            )

            try AppGroup.writeData(jpeg, toFileName: renderedFileName)
        } catch {
            return
        }

        var updated = variant
        updated.renderFileName = renderedFileName
        updated.cropRect = newCrop
        updated.straightenDegrees = normalisedStraighten
        updated.rotationQuarterTurns = normalisedRotation

        switch family {
        case .small:
            smart.small = updated
        case .medium:
            smart.medium = updated
        case .large:
            smart.large = updated
        }

        spec.layout?.smartPhoto = smart
        await setCurrentSpecAndPersist(spec)
    }

    func applyManualSmartCropForShuffleEntryWithStraighten(
        manifestFileName: String,
        entryID: String,
        family: EditingFamily,
        cropRect: NormalisedRect,
        straightenDegrees: Double,
        rotationQuarterTurns: Int
    ) async {
        guard var manifest = AppGroup.loadSmartPhotoShuffleManifest(fileName: manifestFileName) else { return }
        guard let idx = manifest.entries.firstIndex(where: { $0.id == entryID }) else { return }

        let newCrop = cropRect.normalised()
        let normalisedStraighten = SmartPhotoManualCropRenderer.normalisedStraightenDegrees(straightenDegrees)
        let degreesToApply = normalisedStraighten ?? 0
        let normalisedRotation = SmartPhotoManualCropRenderer.normalisedRotationQuarterTurns(rotationQuarterTurns)
        let turnsToApply = normalisedRotation ?? 0

        let entry = manifest.entries[idx]
        let masterImage = AppGroup.loadUIImage(fileName: entry.masterFileName)
        guard let masterImage else { return }

        let targetPixels: PixelSize
        switch family {
        case .small:
            targetPixels = PixelSize(width: 483, height: 483)
        case .medium:
            targetPixels = PixelSize(width: 1010, height: 483)
        case .large:
            targetPixels = PixelSize(width: 1010, height: 1010)
        }

        let renderedFileName = AppGroup.makeUniqueFileName(prefix: "smartPhotoShuffleManual", ext: "jpg")

        do {
            let rendered = SmartPhotoManualCropRenderer.render(
                master: masterImage,
                cropRect: newCrop,
                straightenDegrees: degreesToApply,
                rotationQuarterTurns: turnsToApply,
                targetPixels: targetPixels
            )

            let jpeg = try SmartPhotoManualCropRenderer.encodeJPEG(
                image: rendered,
                startQuality: 0.92,
                maxBytes: 1_800_000
            )

            try AppGroup.writeData(jpeg, toFileName: renderedFileName)
        } catch {
            return
        }

        var updated = entry
        switch family {
        case .small:
            updated.smallManualRenderFileName = renderedFileName
            updated.smallManualCropRect = newCrop
            updated.smallManualStraightenDegrees = normalisedStraighten
            updated.smallManualRotationQuarterTurns = normalisedRotation
        case .medium:
            updated.mediumManualRenderFileName = renderedFileName
            updated.mediumManualCropRect = newCrop
            updated.mediumManualStraightenDegrees = normalisedStraighten
            updated.mediumManualRotationQuarterTurns = normalisedRotation
        case .large:
            updated.largeManualRenderFileName = renderedFileName
            updated.largeManualCropRect = newCrop
            updated.largeManualStraightenDegrees = normalisedStraighten
            updated.largeManualRotationQuarterTurns = normalisedRotation
        }

        manifest.entries[idx] = updated
        AppGroup.writeSmartPhotoShuffleManifest(manifest, fileName: manifestFileName)
        await refreshSmartPhotoShufflePreviewsIfVisible()
    }

    func resetManualSmartCropForShuffleEntry(
        manifestFileName: String,
        entryID: String
    ) {
        guard var manifest = AppGroup.loadSmartPhotoShuffleManifest(fileName: manifestFileName) else { return }
        guard let idx = manifest.entries.firstIndex(where: { $0.id == entryID }) else { return }

        var entry = manifest.entries[idx]

        entry.smallManualRenderFileName = nil
        entry.smallManualCropRect = nil
        entry.smallManualStraightenDegrees = nil
        entry.smallManualRotationQuarterTurns = nil

        entry.mediumManualRenderFileName = nil
        entry.mediumManualCropRect = nil
        entry.mediumManualStraightenDegrees = nil
        entry.mediumManualRotationQuarterTurns = nil

        entry.largeManualRenderFileName = nil
        entry.largeManualCropRect = nil
        entry.largeManualStraightenDegrees = nil
        entry.largeManualRotationQuarterTurns = nil

        manifest.entries[idx] = entry
        AppGroup.writeSmartPhotoShuffleManifest(manifest, fileName: manifestFileName)
    }
}
