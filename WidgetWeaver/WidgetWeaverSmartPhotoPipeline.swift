//
//  WidgetWeaverSmartPhotoPipeline.swift
//  WidgetWeaver
//
//  Created by . . on 01/03/26.
//

import Foundation
import UIKit
import WidgetKit
import Vision
import ImageIO

struct WidgetWeaverSmartPhotoTargets: Hashable, Sendable {
    var smallPixels: CGSize
    var mediumPixels: CGSize
    var largePixels: CGSize

    @MainActor static func current() -> WidgetWeaverSmartPhotoTargets {
        let screen = currentScreen()
        let scale = screen.scale

        let smallPoints = WidgetPreview.widgetSize(for: .systemSmall)
        let mediumPoints = WidgetPreview.widgetSize(for: .systemMedium)
        let largePoints = WidgetPreview.widgetSize(for: .systemLarge)

        func px(_ points: CGSize) -> CGSize {
            CGSize(
                width: (points.width * scale).rounded(.up),
                height: (points.height * scale).rounded(.up)
            )
        }

        return WidgetWeaverSmartPhotoTargets(
            smallPixels: px(smallPoints),
            mediumPixels: px(mediumPoints),
            largePixels: px(largePoints)
        )
    }

    @MainActor
    private static func currentScreen() -> UIScreen {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }

        if let screen = screenFromWindowScenes(scenes, preferForegroundActive: true) {
            return screen
        }
        if let screen = screenFromWindowScenes(scenes, preferForegroundActive: false) {
            return screen
        }
        if let screen = scenes.first?.screen {
            return screen
        }
        if let screen = UIScreen.screens.first {
            return screen
        }

        preconditionFailure("WidgetWeaverSmartPhotoTargets.currentScreen(): no UIScreen available")
    }

    @MainActor
    private static func screenFromWindowScenes(_ scenes: [UIWindowScene], preferForegroundActive: Bool) -> UIScreen? {
        let orderedScenes: [UIWindowScene]
        if preferForegroundActive {
            let active = scenes.filter { $0.activationState == .foregroundActive }
            orderedScenes = active.isEmpty ? scenes : active
        } else {
            orderedScenes = scenes
        }

        for scene in orderedScenes {
            if let key = scene.windows.first(where: { $0.isKeyWindow }) {
                return key.screen
            }
            if let any = scene.windows.first {
                return any.screen
            }
        }

        return nil
    }
}

struct WidgetWeaverSmartPhotoPrepared: Hashable, Sendable {
    var imageSpec: ImageSpec
    var themeImageFileName: String
}

enum WidgetWeaverSmartPhotoPipeline {

    static func prepareAndStore(imageData: Data, targets: WidgetWeaverSmartPhotoTargets) throws -> WidgetWeaverSmartPhotoPrepared {
        // Use a smaller decode for Vision analysis (fast + memory-light).
        let analysisCG = try downsampledCGImage(from: imageData, maxPixel: 1024)

        // Keep a larger “master” for future re-crops.
        let masterCG = try downsampledCGImage(from: imageData, maxPixel: 3072)

        let masterUIImage = UIImage(cgImage: masterCG, scale: 1, orientation: .up)

        let imageAspect = CGFloat(analysisCG.width) / max(1, CGFloat(analysisCG.height))

        let focus = detectFocusBoxes(in: analysisCG)

        let smallCrop = WidgetWeaverSmartCropper.cropRect(
            targetAspect: targets.smallPixels.width / max(1, targets.smallPixels.height),
            imageAspect: imageAspect,
            focusBoxes: focus,
            strategy: .singleBestSubject
        )
        let mediumCrop = WidgetWeaverSmartCropper.cropRect(
            targetAspect: targets.mediumPixels.width / max(1, targets.mediumPixels.height),
            imageAspect: imageAspect,
            focusBoxes: focus,
            strategy: .includeUpToSubjects(2)
        )
        let largeCrop = WidgetWeaverSmartCropper.cropRect(
            targetAspect: targets.largePixels.width / max(1, targets.largePixels.height),
            imageAspect: imageAspect,
            focusBoxes: focus,
            strategy: .includeAllSubjects
        )

        let masterFileName = AppGroup.createImageFileName(prefix: "photo-master", ext: "jpg")
        try AppGroup.writeUIImage(masterUIImage, fileName: masterFileName, compressionQuality: 0.90, maxPixel: 3072)

        let smallFileName = AppGroup.createImageFileName(prefix: "photo-small", ext: "jpg")
        let mediumFileName = AppGroup.createImageFileName(prefix: "photo-medium", ext: "jpg")
        let largeFileName = AppGroup.createImageFileName(prefix: "photo-large", ext: "jpg")

        let smallRender = render(masterCG, crop: smallCrop, outputPixels: targets.smallPixels)
        let mediumRender = render(masterCG, crop: mediumCrop, outputPixels: targets.mediumPixels)
        let largeRender = render(masterCG, crop: largeCrop, outputPixels: targets.largePixels)

        try AppGroup.writeUIImage(smallRender, fileName: smallFileName, compressionQuality: 0.88, maxPixel: max(targets.smallPixels.width, targets.smallPixels.height))
        try AppGroup.writeUIImage(mediumRender, fileName: mediumFileName, compressionQuality: 0.88, maxPixel: max(targets.mediumPixels.width, targets.mediumPixels.height))
        try AppGroup.writeUIImage(largeRender, fileName: largeFileName, compressionQuality: 0.88, maxPixel: max(targets.largePixels.width, targets.largePixels.height))

        let smart = WidgetWeaverSmartPhotoSpec(
            algorithmVersion: WidgetWeaverSmartPhotoSpec.currentAlgorithmVersion,
            preparedAt: Date(),
            masterFileName: masterFileName,
            small: WidgetWeaverSmartPhotoVariant(
                renderFileName: smallFileName,
                cropRect: WidgetWeaverNormalizedRect(x: smallCrop.origin.x, y: smallCrop.origin.y, width: smallCrop.width, height: smallCrop.height),
                pixelWidth: Int(targets.smallPixels.width),
                pixelHeight: Int(targets.smallPixels.height)
            ),
            medium: WidgetWeaverSmartPhotoVariant(
                renderFileName: mediumFileName,
                cropRect: WidgetWeaverNormalizedRect(x: mediumCrop.origin.x, y: mediumCrop.origin.y, width: mediumCrop.width, height: mediumCrop.height),
                pixelWidth: Int(targets.mediumPixels.width),
                pixelHeight: Int(targets.mediumPixels.height)
            ),
            large: WidgetWeaverSmartPhotoVariant(
                renderFileName: largeFileName,
                cropRect: WidgetWeaverNormalizedRect(x: largeCrop.origin.x, y: largeCrop.origin.y, width: largeCrop.width, height: largeCrop.height),
                pixelWidth: Int(targets.largePixels.width),
                pixelHeight: Int(targets.largePixels.height)
            )
        ).normalised()

        // `fileName` stays populated for backwards-compatibility.
        let imageSpec = ImageSpec(
            fileName: mediumFileName,
            contentMode: .fill,
            height: 120,
            cornerRadius: 16,
            smartPhoto: smart
        ).normalised()

        return WidgetWeaverSmartPhotoPrepared(imageSpec: imageSpec, themeImageFileName: mediumFileName)
    }
}

// MARK: - Focus detection

private struct WidgetWeaverFocusBox: Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case face
        case animal
        case saliency
    }

    var rectTopLeft01: CGRect
    var kind: Kind
    var weight: Double
}

private func detectFocusBoxes(in cgImage: CGImage) -> [WidgetWeaverFocusBox] {
    var out: [WidgetWeaverFocusBox] = []

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    var requests: [VNRequest] = []

    let faces = VNDetectFaceRectanglesRequest()
    requests.append(faces)

    if #available(iOS 17.0, *) {
        let animals = VNRecognizeAnimalsRequest()
        requests.append(animals)
    }

    let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
    requests.append(saliency)

    do {
        try handler.perform(requests)
    } catch {
        // Best-effort: fall through with whatever results are available.
    }

    if let results = faces.results {
        for face in results {
            let r = visionRectToTopLeft(face.boundingBox)
            let area = Double(r.width * r.height)
            let weight = 3.0 + area * 2.0
            out.append(WidgetWeaverFocusBox(rectTopLeft01: r, kind: .face, weight: weight))
        }
    }

    if #available(iOS 17.0, *) {
        if let req = requests.first(where: { $0 is VNRecognizeAnimalsRequest }) as? VNRecognizeAnimalsRequest,
           let results = req.results {
            for obs in results {
                let r = visionRectToTopLeft(obs.boundingBox)
                let area = Double(r.width * r.height)
                let weight = 2.4 + area * 1.5
                out.append(WidgetWeaverFocusBox(rectTopLeft01: r, kind: .animal, weight: weight))
            }
        }
    }

    if let sal = saliency.results?.first {
        // `salientObjects` are rectangles (often rough). Convert using corner points.
        let rects: [CGRect] = (sal.salientObjects ?? []).compactMap { rectObs in
            let xs = [rectObs.topLeft.x, rectObs.topRight.x, rectObs.bottomLeft.x, rectObs.bottomRight.x]
            let ys = [rectObs.topLeft.y, rectObs.topRight.y, rectObs.bottomLeft.y, rectObs.bottomRight.y]

            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
            let visionRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            return visionRectToTopLeft(visionRect)
        }

        for r in rects {
            let area = Double(r.width * r.height)
            let weight = 1.0 + area
            out.append(WidgetWeaverFocusBox(rectTopLeft01: r, kind: .saliency, weight: weight))
        }
    }

    return out
}

private func visionRectToTopLeft(_ visionRect: CGRect) -> CGRect {
    // Vision uses a bottom-left origin in normalised coordinates.
    // Convert to top-left origin for easier UIKit/CGImage mapping.
    CGRect(
        x: visionRect.origin.x,
        y: 1.0 - visionRect.origin.y - visionRect.size.height,
        width: visionRect.size.width,
        height: visionRect.size.height
    )
    .standardized
}

// MARK: - Smart cropping

private enum WidgetWeaverSmartCropStrategy: Hashable, Sendable {
    case singleBestSubject
    case includeUpToSubjects(Int)
    case includeAllSubjects
}

private enum WidgetWeaverSmartCropper {

    static func cropRect(targetAspect: CGFloat, imageAspect: CGFloat, focusBoxes: [WidgetWeaverFocusBox], strategy: WidgetWeaverSmartCropStrategy) -> CGRect {
        let aspect = max(0.1, min(10, targetAspect))

        let selected: [WidgetWeaverFocusBox] = {
            let sorted = focusBoxes.sorted { $0.weight > $1.weight }

            switch strategy {
            case .singleBestSubject:
                return Array(sorted.prefix(1))
            case .includeUpToSubjects(let n):
                return Array(sorted.prefix(max(1, n)))
            case .includeAllSubjects:
                return sorted
            }
        }()

        var base: CGRect = {
            guard let first = selected.first else {
                return centredAspectCrop(targetAspect: aspect, imageAspect: imageAspect)
            }
            var u = first.rectTopLeft01
            for b in selected.dropFirst() {
                u = u.union(b.rectTopLeft01)
            }
            return u
        }()

        // Face headroom and general breathing room.
        let hasFace = selected.contains(where: { $0.kind == .face })
        let extraTop: CGFloat = hasFace ? 0.06 : 0.03
        let extraSides: CGFloat = 0.06
        let extraBottom: CGFloat = 0.05

        base = expand(base, dx: extraSides, dyTop: extraTop, dyBottom: extraBottom)

        // Match the widget’s aspect by expanding, then clamp.
        base = expandToMatchAspect(base, targetAspect: aspect, imageAspect: imageAspect)
        base = clamp01(base)

        // Extra context so corners rarely cut into important content.
        base = expand(base, dx: 0.02, dyTop: 0.02, dyBottom: 0.02)
        base = clamp01(base)

        // Ensure non-degenerate.
        let minSide: CGFloat = 0.15
        if base.width < minSide || base.height < minSide {
            base = centredAspectCrop(targetAspect: aspect, imageAspect: imageAspect)
        }

        return clamp01(base)
    }

    private static func centredAspectCrop(targetAspect: CGFloat, imageAspect: CGFloat) -> CGRect {
        let target = max(0.1, min(10, targetAspect))
        let imgAspect = max(0.1, min(10, imageAspect))

        // If the source is wider than the target, keep full height and crop width.
        if imgAspect >= target {
            let w = target / imgAspect
            let x = (1.0 - w) / 2.0
            return CGRect(x: x, y: 0, width: w, height: 1)
        }

        // Otherwise keep full width and crop height.
        let h = imgAspect / target
        let y = (1.0 - h) / 2.0
        return CGRect(x: 0, y: y, width: 1, height: h)
    }

    private static func expand(_ r: CGRect, dx: CGFloat, dyTop: CGFloat, dyBottom: CGFloat) -> CGRect {
        CGRect(
            x: r.origin.x - dx,
            y: r.origin.y - dyTop,
            width: r.size.width + (dx * 2),
            height: r.size.height + dyTop + dyBottom
        )
    }

    private static func expandToMatchAspect(_ r: CGRect, targetAspect: CGFloat, imageAspect: CGFloat) -> CGRect {
        let target = max(0.0001, targetAspect)
        let imgAspect = max(0.0001, imageAspect)

        // Convert the current rect's aspect into pixel space:
        // (rectWidth * imageWidth) / (rectHeight * imageHeight)
        let current = max(0.0001, (r.width * imgAspect) / max(0.0001, r.height))

        if abs(current - target) < 0.0001 { return r }

        if current < target {
            // Too tall/narrow -> expand width.
            let newWidth = (target * r.height) / imgAspect
            let delta = newWidth - r.width
            return CGRect(x: r.origin.x - (delta / 2), y: r.origin.y, width: newWidth, height: r.height)
        } else {
            // Too wide -> expand height.
            let newHeight = (r.width * imgAspect) / target
            let delta = newHeight - r.height
            return CGRect(x: r.origin.x, y: r.origin.y - (delta / 2), width: r.width, height: newHeight)
        }
    }

    private static func clamp01(_ r: CGRect) -> CGRect {
        var out = r.standardized

        if out.width > 1 { out.size.width = 1 }
        if out.height > 1 { out.size.height = 1 }

        if out.origin.x < 0 { out.origin.x = 0 }
        if out.origin.y < 0 { out.origin.y = 0 }

        if out.origin.x + out.size.width > 1 { out.origin.x = max(0, 1 - out.size.width) }
        if out.origin.y + out.size.height > 1 { out.origin.y = max(0, 1 - out.size.height) }

        // Avoid negative sizes from extreme clamps.
        if out.size.width < 0.0001 { out.size.width = 0.0001 }
        if out.size.height < 0.0001 { out.size.height = 0.0001 }

        return out
    }
}

// MARK: - Rendering

private func render(_ source: CGImage, crop: CGRect, outputPixels: CGSize) -> UIImage {
    let w = CGFloat(source.width)
    let h = CGFloat(source.height)

    let cropPx = CGRect(
        x: crop.origin.x * w,
        y: crop.origin.y * h,
        width: crop.size.width * w,
        height: crop.size.height * h
    ).integral

    let cropped = source.cropping(to: cropPx) ?? source
    let input = UIImage(cgImage: cropped, scale: 1, orientation: .up)

    let outSize = CGSize(width: max(1, outputPixels.width), height: max(1, outputPixels.height))

    let fmt = UIGraphicsImageRendererFormat.default()
    fmt.scale = 1
    fmt.opaque = true

    let renderer = UIGraphicsImageRenderer(size: outSize, format: fmt)
    return renderer.image { _ in
        input.draw(in: CGRect(origin: .zero, size: outSize))
    }
}

// MARK: - Downsampling

private enum WidgetWeaverSmartPhotoError: Error {
    case decodeFailed
}

private func downsampledCGImage(from data: Data, maxPixel: CGFloat) throws -> CGImage {
    let options: [CFString: Any] = [
        kCGImageSourceShouldCache: false
    ]

    guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
        throw WidgetWeaverSmartPhotoError.decodeFailed
    }

    let downsampleOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel)
    ]

    guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
        throw WidgetWeaverSmartPhotoError.decodeFailed
    }

    return cg
}
