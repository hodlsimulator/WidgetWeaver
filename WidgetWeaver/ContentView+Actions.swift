//
//  ContentView+Actions.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI
import PhotosUI
import UIKit
import Vision
import ImageIO
import WidgetKit

extension ContentView {

    // MARK: - Actions

    func importFromClipboardIfPossible() async {
        guard let str = UIPasteboard.general.string else { return }
        guard let data = str.data(using: .utf8) else { return }

        do {
            let decoded = try WidgetWeaverDesignExchangeCodec.decode(data: data)

            var newSpecs = store.specs
            for s in decoded {
                if let idx = newSpecs.firstIndex(where: { $0.id == s.id }) {
                    newSpecs[idx] = s
                } else {
                    newSpecs.insert(s, at: 0)
                }
            }

            store.save(newSpecs)
            isShowingImportSuccess = true
        } catch {
            // ignore
        }
    }

    func saveCurrentDraft(asNew: Bool) {
        var outSpecs = store.specs

        let newSpec = draftSpec(id: asNew ? UUID() : selectedSpecID)

        if let existingIdx = outSpecs.firstIndex(where: { $0.id == newSpec.id }) {
            outSpecs[existingIdx] = newSpec
        } else {
            outSpecs.insert(newSpec, at: 0)
        }

        store.save(outSpecs)
        selectedSpecID = newSpec.id
        isEditingExisting = true
    }

    func deleteSelectedSpec() {
        store.delete(selectedSpecID)
        selectedSpecID = UUID()
        isEditingExisting = false
        draft = .defaultDraft()
    }

    func selectSpec(_ spec: WidgetSpec) {
        selectedSpecID = spec.id
        isEditingExisting = true
        draft.applySpec(spec)
    }

    func resetToDefaultDraft() {
        selectedSpecID = UUID()
        isEditingExisting = false
        draft = .defaultDraft()
    }

    // MARK: - Photos import

    func importPickedImage(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }

            let screen = WidgetPreviewMetrics.currentScreen()
            let targets = WidgetWeaverSmartPhotoImportTargets(
                smallPoints: WidgetPreviewMetrics.widgetSize(for: .systemSmall, screen: screen),
                mediumPoints: WidgetPreviewMetrics.widgetSize(for: .systemMedium, screen: screen),
                largePoints: WidgetPreviewMetrics.widgetSize(for: .systemLarge, screen: screen),
                screenScale: screen.scale
            )

            let prepared = try await Task.detached(priority: .userInitiated) {
                try WidgetWeaverSmartPhotoImporter.prepareAndStore(
                    imageData: data,
                    targets: targets
                )
            }.value

            await MainActor.run {
                var d = currentFamilyDraft()
                d.imageFileName = prepared.imageSpec.fileName
                d.imageSmartPhoto = prepared.imageSpec.smartPhoto
                setCurrentFamilyDraft(d)

                handleImportedImageTheme(uiImage: prepared.themeUIImage, fileName: prepared.imageSpec.fileName)
                pickedPhoto = nil
            }
        } catch {
            // Intentionally ignored (image remains unchanged).
        }
    }

    func addChip() {
        var d = currentFamilyDraft()
        d.chips.append(
            ChipDraft(
                id: UUID(),
                text: "New Chip",
                icon: "star.fill",
                backgroundHex: "#2A2A2E",
                textHex: "#FFFFFF",
                iconHex: "#FFFFFF"
            )
        )
        setCurrentFamilyDraft(d)
    }

    func deleteChip(_ id: UUID) {
        var d = currentFamilyDraft()
        d.chips.removeAll { $0.id == id }
        setCurrentFamilyDraft(d)
    }
}

// MARK: - Smart Photo import pipeline (Auto-focus crops for each widget family)

private struct WidgetWeaverSmartPhotoImportTargets: Sendable {
    let smallPoints: CGSize
    let mediumPoints: CGSize
    let largePoints: CGSize
    let screenScale: CGFloat

    func pixelSize(for family: WidgetFamily) -> CGSize {
        let points: CGSize
        switch family {
        case .systemSmall: points = smallPoints
        case .systemMedium: points = mediumPoints
        case .systemLarge: points = largePoints
        default: points = mediumPoints
        }

        let w = max(1, Int((points.width * screenScale).rounded(.up)))
        let h = max(1, Int((points.height * screenScale).rounded(.up)))
        return CGSize(width: w, height: h)
    }
}

private struct WidgetWeaverSmartPhotoPrepared: Sendable {
    let imageSpec: ImageSpec
    let themeUIImage: UIImage
}

private enum WidgetWeaverSmartPhotoImporter {

    // Tune these values carefully. Higher = higher quality but bigger files / more memory during import.
    private static let analysisMaxPixel: Int = 1024
    private static let masterMaxPixel: Int = 3072

    private static let renderCompressionQuality: CGFloat = 0.88
    private static let masterCompressionQuality: CGFloat = 0.90

    /// Generates:
    /// - a preserved master image (for future re-crops)
    /// - per-family render images (small / medium / large) with automatic subject-aware crops
    /// Returns an ImageSpec pointing at the correct renders.
    static func prepareAndStore(imageData: Data, targets: WidgetWeaverSmartPhotoImportTargets) throws -> WidgetWeaverSmartPhotoPrepared {
        // Downsample twice:
        // - analysis image: fast Vision processing
        // - master image: preserved for re-crops + render source
        guard let analysisCG = downsampledCGImage(from: imageData, maxPixel: analysisMaxPixel) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        guard let masterCG = downsampledCGImage(from: imageData, maxPixel: masterMaxPixel) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        let analysisUIImage = UIImage(cgImage: analysisCG, scale: 1, orientation: .up)
        let masterUIImage = UIImage(cgImage: masterCG, scale: 1, orientation: .up)

        // Vision detection is comparatively expensive; run it once and re-use the boxes for all sizes.
        let focusBoxes = detectFocusBoxes(in: analysisCG)

        // Compute crops + renders.
        let smallPx = targets.pixelSize(for: .systemSmall)
        let mediumPx = targets.pixelSize(for: .systemMedium)
        let largePx = targets.pixelSize(for: .systemLarge)

        let masterFileName = AppGroup.createImageFileName(prefix: "photo-master", ext: "jpg")
        let smallFileName = AppGroup.createImageFileName(prefix: "photo-small", ext: "jpg")
        let mediumFileName = AppGroup.createImageFileName(prefix: "photo-medium", ext: "jpg")
        let largeFileName = AppGroup.createImageFileName(prefix: "photo-large", ext: "jpg")

        // Render outputs (pixel-perfect for this device's widget sizes).
        let smallCrop = WWSmartCropper.cropRect(
            targetAspect: smallPx.width / smallPx.height,
            imageAspect: CGFloat(masterCG.width) / CGFloat(masterCG.height),
            focusBoxes: focusBoxes,
            strategy: .singleBestSubject,
            cornerSafeInset: 0.04
        )

        let mediumCrop = WWSmartCropper.cropRect(
            targetAspect: mediumPx.width / mediumPx.height,
            imageAspect: CGFloat(masterCG.width) / CGFloat(masterCG.height),
            focusBoxes: focusBoxes,
            strategy: .includeUpTo(2),
            cornerSafeInset: 0.03
        )

        let largeCrop = WWSmartCropper.cropRect(
            targetAspect: largePx.width / largePx.height,
            imageAspect: CGFloat(masterCG.width) / CGFloat(masterCG.height),
            focusBoxes: focusBoxes,
            strategy: .includeAllSubjects,
            cornerSafeInset: 0.03
        )

        // Rendering can allocate large temporary buffers.
        // Keep it sequential and prefer scale=1 contexts.
        guard let smallRender = render(masterUIImage: masterUIImage, cropRect: smallCrop, outputSize: smallPx) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let mediumRender = render(masterUIImage: masterUIImage, cropRect: mediumCrop, outputSize: mediumPx) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard let largeRender = render(masterUIImage: masterUIImage, cropRect: largeCrop, outputSize: largePx) else {
            throw CocoaError(.fileWriteUnknown)
        }

        // Store files.
        // Master is higher quality; renders are tuned for widget memory/size constraints.
        try AppGroup.writeUIImage(masterUIImage, fileName: masterFileName, compressionQuality: masterCompressionQuality, maxPixel: CGFloat(masterMaxPixel))

        try AppGroup.writeUIImage(smallRender, fileName: smallFileName, compressionQuality: renderCompressionQuality, maxPixel: max(smallPx.width, smallPx.height))
        try AppGroup.writeUIImage(mediumRender, fileName: mediumFileName, compressionQuality: renderCompressionQuality, maxPixel: max(mediumPx.width, mediumPx.height))
        try AppGroup.writeUIImage(largeRender, fileName: largeFileName, compressionQuality: renderCompressionQuality, maxPixel: max(largePx.width, largePx.height))

        let smart = WWSmartPhotoSpec(
            masterFileName: masterFileName,
            small: WWSmartPhotoVariant(renderFileName: smallFileName, cropRect: WWNormalizedRect(smallCrop), pixelWidth: Int(smallPx.width), pixelHeight: Int(smallPx.height)),
            medium: WWSmartPhotoVariant(renderFileName: mediumFileName, cropRect: WWNormalizedRect(mediumCrop), pixelWidth: Int(mediumPx.width), pixelHeight: Int(mediumPx.height)),
            large: WWSmartPhotoVariant(renderFileName: largeFileName, cropRect: WWNormalizedRect(largeCrop), pixelWidth: Int(largePx.width), pixelHeight: Int(largePx.height))
        ).normalised()

        // Keep fileName pointing at a reasonable default (medium) for any callers that don't pass WidgetFamily.
        let imageSpec = ImageSpec(
            fileName: mediumFileName,
            contentMode: .fill,
            height: 120,
            cornerRadius: 16,
            smartPhoto: smart
        ).normalised()

        return WidgetWeaverSmartPhotoPrepared(imageSpec: imageSpec, themeUIImage: analysisUIImage)
    }

    private static func downsampledCGImage(from data: Data, maxPixel: Int) -> CGImage? {
        let cfData = data as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func render(masterUIImage: UIImage, cropRect: CGRect, outputSize: CGSize) -> UIImage? {
        guard outputSize.width > 0, outputSize.height > 0 else { return nil }

        let sourceSize = masterUIImage.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let crop = cropRect.normalisedToUnit()
        let cropX = crop.origin.x * sourceSize.width
        let cropY = crop.origin.y * sourceSize.height
        let cropW = crop.size.width * sourceSize.width
        let cropH = crop.size.height * sourceSize.height

        guard cropW > 1, cropH > 1 else { return nil }

        let scaleX = outputSize.width / cropW
        let scaleY = outputSize.height / cropH
        let s = min(scaleX, scaleY)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)
        return renderer.image { _ in
            let drawRect = CGRect(
                x: -cropX * s,
                y: -cropY * s,
                width: sourceSize.width * s,
                height: sourceSize.height * s
            )
            masterUIImage.draw(in: drawRect)
        }
    }
}

// MARK: - Focus detection

private struct WWFocusBox: Sendable {
    enum Kind: String, Sendable {
        case face
        case animal
        case saliency
    }

    var rect: CGRect            // Normalised, top-left origin, 0...1
    var weight: CGFloat
    var kind: Kind
}

private func detectFocusBoxes(in cgImage: CGImage) -> [WWFocusBox] {
    var boxes: [WWFocusBox] = []

    // Face detection
    do {
        let req = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([req])

        let faces = (req.results as? [VNFaceObservation]) ?? []
        for f in faces {
            let r = visionRectToTopLeft(f.boundingBox)
            let area = max(0.0001, r.width * r.height)
            boxes.append(WWFocusBox(rect: r, weight: 1.0 + area, kind: .face))
        }
    } catch {
        // ignore
    }

    // Animal detection (pets) – availability varies by OS.
    if #available(iOS 17.0, *) {
        do {
            let req = VNRecognizeAnimalsRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([req])

            let animals = (req.results as? [VNRecognizedObjectObservation]) ?? []
            for a in animals {
                let r = visionRectToTopLeft(a.boundingBox)
                let area = max(0.0001, r.width * r.height)
                boxes.append(WWFocusBox(rect: r, weight: 0.9 + area, kind: .animal))
            }
        } catch {
            // ignore
        }
    }

    // Saliency fallback (when no faces/animals, or to improve single-subject framing).
    do {
        let req = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([req])

        if let obs = (req.results as? [VNSaliencyImageObservation])?.first {
            // Union of salient object rects.
            let rects = obs.salientObjects.map { visionRectToTopLeft($0.boundingBox) }
            if let union = rects.reduce(nil as CGRect?)({ partial, next in
                partial?.union(next) ?? next
            }) {
                let r = union
                let area = max(0.0001, r.width * r.height)
                boxes.append(WWFocusBox(rect: r, weight: 0.6 + area, kind: .saliency))
            }
        }
    } catch {
        // ignore
    }

    // Prefer people/animals, then saliency. If nothing detected, return empty.
    boxes.sort { $0.weight > $1.weight }
    return boxes
}

private func visionRectToTopLeft(_ visionRect: CGRect) -> CGRect {
    // Vision normalised rectangles use a bottom-left origin.
    CGRect(
        x: visionRect.origin.x,
        y: 1.0 - visionRect.origin.y - visionRect.size.height,
        width: visionRect.size.width,
        height: visionRect.size.height
    ).normalisedToUnit()
}

// MARK: - Smart cropping

private enum WWSmartCropStrategy: Sendable {
    case singleBestSubject
    case includeUpTo(Int)
    case includeAllSubjects
}

private enum WWSmartCropper {
    static func cropRect(
        targetAspect: CGFloat,
        imageAspect: CGFloat,
        focusBoxes: [WWFocusBox],
        strategy: WWSmartCropStrategy,
        cornerSafeInset: CGFloat
    ) -> CGRect {
        let safe = max(0, min(cornerSafeInset, 0.12))

        // Default crop when nothing is detected: centred crop to aspect.
        let defaultCrop = centredCrop(targetAspect: targetAspect, imageAspect: imageAspect)

        guard !focusBoxes.isEmpty else {
            return inset(defaultCrop, by: safe)
        }

        // Pick which boxes to consider.
        let sorted = focusBoxes.sorted { $0.weight > $1.weight }
        let selected: [WWFocusBox] = {
            switch strategy {
            case .singleBestSubject:
                return Array(sorted.prefix(1))
            case .includeUpTo(let n):
                return Array(sorted.prefix(max(1, n)))
            case .includeAllSubjects:
                return sorted
            }
        }()

        // Union of selected boxes.
        var roi = selected[0].rect
        for b in selected.dropFirst() {
            roi = roi.union(b.rect)
        }

        // Add headroom above the subject, biasing slightly upwards.
        roi = roi.insetBy(dx: -roi.width * 0.12, dy: -roi.height * 0.18)
        roi.origin.y -= roi.height * 0.06

        // Clamp ROI to image bounds.
        roi = roi.normalisedToUnit()

        // Expand ROI into a crop of the requested aspect ratio.
        let crop = expandToAspect(roi: roi, targetAspect: targetAspect)

        // Keep away from widget rounded corners.
        return inset(crop, by: safe)
    }

    private static func centredCrop(targetAspect: CGFloat, imageAspect: CGFloat) -> CGRect {
        guard targetAspect > 0, imageAspect > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }

        if imageAspect > targetAspect {
            // Image is wider; crop horizontally.
            let w = targetAspect / imageAspect
            return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        } else {
            // Image is taller; crop vertically.
            let h = imageAspect / targetAspect
            return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        }
    }

    private static func expandToAspect(roi: CGRect, targetAspect: CGFloat) -> CGRect {
        var crop = roi

        // Minimum crop size avoids extreme zoom.
        let minW: CGFloat = 0.35
        let minH: CGFloat = 0.35

        crop.size.width = max(crop.size.width, minW)
        crop.size.height = max(crop.size.height, minH)

        let currentAspect = crop.size.width / crop.size.height
        if currentAspect > targetAspect {
            // Too wide; expand height.
            let newH = crop.size.width / targetAspect
            let delta = newH - crop.size.height
            crop.origin.y -= delta * 0.55
            crop.size.height = newH
        } else {
            // Too tall; expand width.
            let newW = crop.size.height * targetAspect
            let delta = newW - crop.size.width
            crop.origin.x -= delta / 2
            crop.size.width = newW
        }

        // Centre crop on ROI centre.
        let centre = CGPoint(x: roi.midX, y: roi.midY)
        crop.origin.x = centre.x - crop.size.width / 2
        crop.origin.y = centre.y - crop.size.height / 2

        return crop.normalisedToUnit()
    }

    private static func inset(_ rect: CGRect, by amount: CGFloat) -> CGRect {
        let a = max(0, min(amount, 0.2))
        return CGRect(
            x: rect.origin.x + a,
            y: rect.origin.y + a,
            width: rect.size.width - 2 * a,
            height: rect.size.height - 2 * a
        ).normalisedToUnit()
    }
}

private extension CGRect {
    func normalisedToUnit() -> CGRect {
        var r = self

        if r.size.width.isNaN || r.size.height.isNaN || r.origin.x.isNaN || r.origin.y.isNaN {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        if r.size.width <= 0 { r.size.width = 1 }
        if r.size.height <= 0 { r.size.height = 1 }

        r.origin.x = max(0, min(r.origin.x, 1))
        r.origin.y = max(0, min(r.origin.y, 1))
        r.size.width = max(0, min(r.size.width, 1))
        r.size.height = max(0, min(r.size.height, 1))

        if r.origin.x + r.size.width > 1 { r.origin.x = max(0, 1 - r.size.width) }
        if r.origin.y + r.size.height > 1 { r.origin.y = max(0, 1 - r.size.height) }

        return r
    }
}
