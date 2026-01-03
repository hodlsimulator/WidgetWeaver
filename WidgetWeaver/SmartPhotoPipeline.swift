//
//  SmartPhotoPipeline.swift
//  WidgetWeaver
//
//  Created by . . on 1/3/26.
//

import Foundation
import ImageIO
import UIKit
import Vision

/// Pixel targets for the per-family widget renders.
///
/// Sizes are in **pixels** (not points) and should be close to the actual widget
/// render size on the current device.
struct SmartPhotoRenderTargets: Hashable, Sendable {
    var small: PixelSize
    var medium: PixelSize
    var large: PixelSize

    @MainActor
    static func forCurrentDevice(screen: UIScreen? = nil) -> SmartPhotoRenderTargets {
        let resolvedScreen = screen ?? WidgetPreviewMetrics.currentScreen()
        let sizes = WidgetPreviewMetrics.sizesForDevice(screen: resolvedScreen)
        let scale = max(1.0, resolvedScreen.scale)

        func toPixels(_ size: CGSize) -> PixelSize {
            let w = max(1, Int((size.width * scale).rounded()))
            let h = max(1, Int((size.height * scale).rounded()))
            return PixelSize(width: w, height: h).normalised()
        }

        return SmartPhotoRenderTargets(
            small: toPixels(sizes.small),
            medium: toPixels(sizes.medium),
            large: toPixels(sizes.large)
        )
    }
}

enum SmartPhotoPipelineError: Error {
    case decodeFailed
    case encodeFailed
}

struct SmartPhotoPipeline {
    static let algorithmVersion: Int = 1

    /// Creates:
    /// - master (largest preserved)
    /// - small render
    /// - medium render
    /// - large render
    ///
    /// Returns an `ImageSpec` where `fileName` is the **medium** render (backwards compatible),
    /// and `smartPhoto` contains master + per-family variants.
    static func prepare(from originalData: Data, renderTargets: SmartPhotoRenderTargets) throws -> ImageSpec {
        let analysisLongestEdge = 1024
        let masterLongestEdge = 3072

        guard let analysisImage = SmartPhotoImageDecoder.downsample(data: originalData, maxPixel: analysisLongestEdge) else {
            throw SmartPhotoPipelineError.decodeFailed
        }
        guard let masterImage = SmartPhotoImageDecoder.downsample(data: originalData, maxPixel: masterLongestEdge) else {
            throw SmartPhotoPipelineError.decodeFailed
        }

        let analysisSize = CGSize(width: analysisImage.size.width * analysisImage.scale, height: analysisImage.size.height * analysisImage.scale)

        let detection = SmartPhotoSubjectDetector.detectSubjects(in: analysisImage)

        let preparedAt = Date()

        // Crop rects are computed in normalised space (0...1) so they can be applied to master.
        let smallVariant = SmartPhotoVariantBuilder.buildVariant(
            family: .systemSmall,
            targetPixels: renderTargets.small,
            detection: detection,
            analysisSize: analysisSize
        )

        let mediumVariant = SmartPhotoVariantBuilder.buildVariant(
            family: .systemMedium,
            targetPixels: renderTargets.medium,
            detection: detection,
            analysisSize: analysisSize
        )

        let largeVariant = SmartPhotoVariantBuilder.buildVariant(
            family: .systemLarge,
            targetPixels: renderTargets.large,
            detection: detection,
            analysisSize: analysisSize
        )

        // Render from master image into the final pixel sizes.
        let masterFileName = AppGroup.createImageFileName(prefix: "smart-master", ext: "jpg")
        let smallFileName = AppGroup.createImageFileName(prefix: "smart-small", ext: "jpg")
        let mediumFileName = AppGroup.createImageFileName(prefix: "smart-medium", ext: "jpg")
        let largeFileName = AppGroup.createImageFileName(prefix: "smart-large", ext: "jpg")

        // Master: preserve high quality but still keep it reasonable.
        let masterData = try SmartPhotoJPEG.encode(image: masterImage, startQuality: 0.88, maxBytes: 2_500_000)
        try AppGroup.writeImageData(masterData, fileName: masterFileName)

        // Renders: keep widget-safe.
        let renderedSmall = SmartPhotoRenderer.render(master: masterImage, cropRect: smallVariant.cropRect, targetPixels: renderTargets.small)
        let renderedMedium = SmartPhotoRenderer.render(master: masterImage, cropRect: mediumVariant.cropRect, targetPixels: renderTargets.medium)
        let renderedLarge = SmartPhotoRenderer.render(master: masterImage, cropRect: largeVariant.cropRect, targetPixels: renderTargets.large)

        let smallData = try SmartPhotoJPEG.encode(image: renderedSmall, startQuality: 0.85, maxBytes: 450_000)
        let mediumData = try SmartPhotoJPEG.encode(image: renderedMedium, startQuality: 0.85, maxBytes: 650_000)
        let largeData = try SmartPhotoJPEG.encode(image: renderedLarge, startQuality: 0.85, maxBytes: 900_000)

        try AppGroup.writeImageData(smallData, fileName: smallFileName)
        try AppGroup.writeImageData(mediumData, fileName: mediumFileName)
        try AppGroup.writeImageData(largeData, fileName: largeFileName)

        let smartPhoto = SmartPhotoSpec(
            masterFileName: masterFileName,
            small: SmartPhotoVariant(
                renderFileName: smallFileName,
                cropRect: smallVariant.cropRect,
                pixelSize: renderTargets.small
            ),
            medium: SmartPhotoVariant(
                renderFileName: mediumFileName,
                cropRect: mediumVariant.cropRect,
                pixelSize: renderTargets.medium
            ),
            large: SmartPhotoVariant(
                renderFileName: largeFileName,
                cropRect: largeVariant.cropRect,
                pixelSize: renderTargets.large
            ),
            algorithmVersion: algorithmVersion,
            preparedAt: preparedAt
        ).normalised()

        // Backwards compatibility: keep ImageSpec.fileName pointing at a sensible default
        // (the medium render).
        return ImageSpec(fileName: mediumFileName, smartPhoto: smartPhoto).normalised()
    }
}

// MARK: - Decode (downsample + orientation)

private enum SmartPhotoImageDecoder {
    static func downsample(data: Data, maxPixel: Int) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return nil
        }

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        // Orientation is already applied by kCGImageSourceCreateThumbnailWithTransform.
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

// MARK: - Detection

private enum SmartPhotoSubjectKind {
    case face
    case animal
    case saliency
    case none
}

private struct SmartPhotoDetection {
    var kind: SmartPhotoSubjectKind
    var boxes: [CGRect] // pixel coords in analysis image (top-left origin)
}

private enum SmartPhotoSubjectDetector {
    static func detectSubjects(in analysisImage: UIImage) -> SmartPhotoDetection {
        guard let cg = analysisImage.cgImage else {
            return SmartPhotoDetection(kind: .none, boxes: [])
        }

        let size = CGSize(width: cg.width, height: cg.height)

        let faces = detectFaces(in: cg, imageSize: size)
        if !faces.isEmpty {
            return SmartPhotoDetection(kind: .face, boxes: rank(boxes: faces, imageSize: size))
        }

        let animals = detectAnimals(in: cg, imageSize: size)
        if !animals.isEmpty {
            return SmartPhotoDetection(kind: .animal, boxes: rank(boxes: animals, imageSize: size))
        }

        let saliency = detectSaliency(in: cg, imageSize: size)
        if !saliency.isEmpty {
            return SmartPhotoDetection(kind: .saliency, boxes: rank(boxes: saliency, imageSize: size))
        }

        return SmartPhotoDetection(kind: .none, boxes: [])
    }

    private static func detectFaces(in cgImage: CGImage, imageSize: CGSize) -> [CGRect] {
        var out: [CGRect] = []

        let req = VNDetectFaceRectanglesRequest { request, _ in
            guard let results = request.results as? [VNFaceObservation] else { return }
            out = results.map { toPixelTopLeftRect($0.boundingBox, imageSize: imageSize) }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([req])
        } catch {
            return []
        }

        return out.compactMap { $0.intersection(CGRect(origin: .zero, size: imageSize)).isNull ? nil : $0.intersection(CGRect(origin: .zero, size: imageSize)) }
    }

    private static func detectAnimals(in cgImage: CGImage, imageSize: CGSize) -> [CGRect] {
        guard #available(iOS 13.0, *) else { return [] }

        var out: [CGRect] = []
        let req = VNRecognizeAnimalsRequest { request, _ in
            guard let results = request.results as? [VNRecognizedObjectObservation] else { return }
            out = results.map { toPixelTopLeftRect($0.boundingBox, imageSize: imageSize) }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([req])
        } catch {
            return []
        }

        return out.compactMap { $0.intersection(CGRect(origin: .zero, size: imageSize)).isNull ? nil : $0.intersection(CGRect(origin: .zero, size: imageSize)) }
    }

    private static func detectSaliency(in cgImage: CGImage, imageSize: CGSize) -> [CGRect] {
        guard #available(iOS 13.0, *) else { return [] }

        var boxes: [CGRect] = []

        // Objectness-based saliency tends to give useful bounding boxes.
        let objReq = VNGenerateObjectnessBasedSaliencyImageRequest { request, _ in
            guard let results = request.results as? [VNSaliencyImageObservation], let obs = results.first else { return }
            boxes.append(contentsOf: obs.salientObjects.map { toPixelTopLeftRect($0.boundingBox, imageSize: imageSize) })
        }

        // Attention-based saliency can help when objectness is empty.
        let attReq = VNGenerateAttentionBasedSaliencyImageRequest { request, _ in
            guard let results = request.results as? [VNSaliencyImageObservation], let obs = results.first else { return }
            boxes.append(contentsOf: obs.salientObjects.map { toPixelTopLeftRect($0.boundingBox, imageSize: imageSize) })
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([objReq, attReq])
        } catch {
            return []
        }

        let clamped = boxes.compactMap { $0.intersection(CGRect(origin: .zero, size: imageSize)).isNull ? nil : $0.intersection(CGRect(origin: .zero, size: imageSize)) }
        return clamped
    }

    /// Vision bounding boxes are normalised with origin at bottom-left.
    /// Convert to pixel rect with origin at top-left.
    private static func toPixelTopLeftRect(_ visionRect: CGRect, imageSize: CGSize) -> CGRect {
        let w = visionRect.width * imageSize.width
        let h = visionRect.height * imageSize.height
        let x = visionRect.minX * imageSize.width
        let y = (1.0 - visionRect.maxY) * imageSize.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private static func rank(boxes: [CGRect], imageSize: CGSize) -> [CGRect] {
        guard boxes.count > 1 else { return boxes }
        let centre = CGPoint(x: imageSize.width / 2.0, y: imageSize.height / 2.0)

        func area(_ r: CGRect) -> CGFloat { max(0, r.width) * max(0, r.height) }
        func dist2(_ r: CGRect) -> CGFloat {
            let dx = r.midX - centre.x
            let dy = r.midY - centre.y
            return dx * dx + dy * dy
        }

        return boxes.sorted {
            let aA = area($0)
            let bA = area($1)
            if abs(aA - bA) > max(64, 0.01 * max(aA, bA)) {
                return aA > bA
            }
            return dist2($0) < dist2($1)
        }
    }
}

// MARK: - Crop decision

private struct SmartPhotoVariantPlan {
    var cropRect: NormalisedRect
}

private enum SmartPhotoVariantBuilder {
    static func buildVariant(
        family: WidgetFamily,
        targetPixels: PixelSize,
        detection: SmartPhotoDetection,
        analysisSize: CGSize
    ) -> SmartPhotoVariantPlan {
        let targetAspect = CGFloat(targetPixels.width) / CGFloat(max(1, targetPixels.height))

        let crop: CGRect
        if detection.kind == .none || detection.boxes.isEmpty {
            crop = centredCropRect(imageSize: analysisSize, targetAspect: targetAspect)
        } else {
            crop = subjectCropRect(
                imageSize: analysisSize,
                targetAspect: targetAspect,
                detection: detection,
                family: family
            )
        }

        let norm = NormalisedRect(
            x: Double(crop.minX / analysisSize.width),
            y: Double(crop.minY / analysisSize.height),
            width: Double(crop.width / analysisSize.width),
            height: Double(crop.height / analysisSize.height)
        ).normalised()

        return SmartPhotoVariantPlan(cropRect: norm)
    }

    private static func centredCropRect(imageSize: CGSize, targetAspect: CGFloat) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }

        let imageAspect = imageSize.width / imageSize.height

        var cropW: CGFloat
        var cropH: CGFloat

        if imageAspect > targetAspect {
            cropH = imageSize.height
            cropW = cropH * targetAspect
        } else {
            cropW = imageSize.width
            cropH = cropW / targetAspect
        }

        let x = (imageSize.width - cropW) / 2.0
        let y = (imageSize.height - cropH) / 2.0
        return CGRect(x: x, y: y, width: cropW, height: cropH)
    }

    private static func subjectCropRect(
        imageSize: CGSize,
        targetAspect: CGFloat,
        detection: SmartPhotoDetection,
        family: WidgetFamily
    ) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)

        let ranked = detection.boxes
        let selected: [CGRect]
        switch family {
        case .systemSmall:
            selected = Array(ranked.prefix(1))
        case .systemMedium:
            selected = Array(ranked.prefix(2))
        case .systemLarge:
            selected = ranked
        default:
            selected = Array(ranked.prefix(1))
        }

        // Expand boxes (headroom + breathing room) and union them.
        let expanded = selected.map { expandSubjectBox($0, kind: detection.kind, family: family, imageSize: imageSize).intersection(bounds) }
        var focus = expanded.first ?? centredCropRect(imageSize: imageSize, targetAspect: targetAspect)
        for r in expanded.dropFirst() {
            focus = focus.union(r)
        }

        // Add gentle padding around the union.
        let padScale: CGFloat = {
            switch family {
            case .systemSmall: return 1.20
            case .systemMedium: return 1.15
            case .systemLarge: return 1.10
            default: return 1.15
            }
        }()
        focus = scaleRect(focus, factor: padScale).intersection(bounds)

        // Fit an aspect-ratio crop around the focus rect.
        var cropW = focus.width
        var cropH = focus.height
        let focusAspect = max(0.0001, cropW) / max(0.0001, cropH)

        if focusAspect > targetAspect {
            cropH = cropW / targetAspect
        } else {
            cropW = cropH * targetAspect
        }

        // Slight extra context.
        let extraScale: CGFloat = {
            switch family {
            case .systemSmall: return 1.06
            case .systemMedium: return 1.04
            case .systemLarge: return 1.02
            default: return 1.04
            }
        }()
        cropW *= extraScale
        cropH *= extraScale

        // Avoid extreme zoom (especially on panoramas / tiny detections).
        let minDimFrac: CGFloat = {
            switch family {
            case .systemSmall: return 0.38
            case .systemMedium: return 0.40
            case .systemLarge: return 0.55
            default: return 0.40
            }
        }()
        let minW = imageSize.width * minDimFrac
        let minH = imageSize.height * minDimFrac

        if cropW < minW {
            cropW = minW
            cropH = cropW / targetAspect
        }
        if cropH < minH {
            cropH = minH
            cropW = cropH * targetAspect
        }

        // Clamp to image bounds.
        if cropW > imageSize.width {
            cropW = imageSize.width
            cropH = cropW / targetAspect
        }
        if cropH > imageSize.height {
            cropH = imageSize.height
            cropW = cropH * targetAspect
        }

        // Position crop around focus centre (with upward bias for faces).
        var centre = CGPoint(x: focus.midX, y: focus.midY)
        if detection.kind == .face {
            let biasFactor: CGFloat = {
                switch family {
                case .systemSmall: return 0.12
                case .systemMedium: return 0.08
                case .systemLarge: return 0.05
                default: return 0.08
                }
            }()
            centre.y -= focus.height * biasFactor
        }

        var x = centre.x - cropW / 2.0
        var y = centre.y - cropH / 2.0

        x = min(max(0, x), imageSize.width - cropW)
        y = min(max(0, y), imageSize.height - cropH)

        return CGRect(x: x, y: y, width: cropW, height: cropH).intersection(bounds)
    }

    private static func expandSubjectBox(_ rect: CGRect, kind: SmartPhotoSubjectKind, family: WidgetFamily, imageSize: CGSize) -> CGRect {
        var r = rect

        switch kind {
        case .face:
            // Faces: add headroom (top) and a touch more side padding.
            let side = r.width * 0.20
            let top = r.height * 0.32
            let bottom = r.height * 0.14
            r = r.insetBy(dx: -side, dy: 0)
            r.origin.y -= top
            r.size.height += top + bottom

        case .animal:
            // Animals: padding all around.
            let dx = r.width * 0.18
            let dy = r.height * 0.18
            r = r.insetBy(dx: -dx, dy: -dy)

        case .saliency:
            // Saliency boxes can be noisy; keep padding modest.
            let dx = r.width * 0.12
            let dy = r.height * 0.12
            r = r.insetBy(dx: -dx, dy: -dy)

        case .none:
            break
        }

        // Additional breathing room for rounded corners on small widgets.
        if family == .systemSmall {
            r = r.insetBy(dx: -r.width * 0.06, dy: -r.height * 0.06)
        }

        let bounds = CGRect(origin: .zero, size: imageSize)
        return r.intersection(bounds)
    }

    private static func scaleRect(_ rect: CGRect, factor: CGFloat) -> CGRect {
        guard factor > 0 else { return rect }
        let dx = rect.width * (factor - 1.0) / 2.0
        let dy = rect.height * (factor - 1.0) / 2.0
        return rect.insetBy(dx: -dx, dy: -dy)
    }
}

// MARK: - Rendering

private enum SmartPhotoRenderer {
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
        let cropCg = (safeRect.isNull || safeRect.isEmpty) ? sourceCg : (sourceCg.cropping(to: safeRect) ?? sourceCg)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: targetPixels.width, height: targetPixels.height), format: format)
        let img = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: targetPixels.width, height: targetPixels.height))

            let cropped = UIImage(cgImage: cropCg, scale: 1, orientation: .up)
            cropped.draw(in: CGRect(x: 0, y: 0, width: targetPixels.width, height: targetPixels.height))
        }

        return img
    }
}

// MARK: - JPEG encoding with size discipline

private enum SmartPhotoJPEG {
    static func encode(image: UIImage, startQuality: CGFloat, maxBytes: Int) throws -> Data {
        var q = min(0.95, max(0.1, startQuality))
        let minQ: CGFloat = 0.65

        guard var data = image.jpegData(compressionQuality: q) else {
            throw SmartPhotoPipelineError.encodeFailed
        }

        // If too large, iteratively reduce quality (small number of steps).
        var steps = 0
        while data.count > maxBytes && q > minQ && steps < 6 {
            q = max(minQ, q - 0.05)
            guard let next = image.jpegData(compressionQuality: q) else { break }
            data = next
            steps += 1
        }

        if data.isEmpty {
            throw SmartPhotoPipelineError.encodeFailed
        }

        return data
    }
}
