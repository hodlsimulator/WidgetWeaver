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
import WidgetKit
import UniformTypeIdentifiers

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
    static let algorithmVersion: Int = 5

    /// Smart Photo work is expensive (Vision, decoding, rendering, I/O).
    ///
    /// When UX hardening is enabled, serialise the pipeline so overlapping work cannot
    /// compete for memory/CPU and destabilise the app.
    private static let prepareLock = NSLock()

    /// Creates:
    /// - master (largest preserved)
    /// - small render
    /// - medium render
    /// - large render
    ///
    /// Returns an `ImageSpec` where `fileName` is the **medium** render (backwards compatible),
    /// and `smartPhoto` contains master + per-family variants.
    static func prepare(from originalData: Data, renderTargets: SmartPhotoRenderTargets) throws -> ImageSpec {
        let didLock = FeatureFlags.smartPhotosUXHardeningEnabled
        if didLock { prepareLock.lock() }
        defer { if didLock { prepareLock.unlock() } }

        #if DEBUG
        let inInfo = AppGroup.debugPickedImageInfo(data: originalData)?.inlineSummary ?? "uti=? orient=? px=?x?"
        print("[WWSmartPhoto] prepare input=\(inInfo)")
        #endif

        let analysisLongestEdge = 1024
        let masterLongestEdge = 3072

        guard let analysisImage = SmartPhotoImageDecoder.downsample(data: originalData, maxPixel: analysisLongestEdge) else {
            throw SmartPhotoPipelineError.decodeFailed
        }
        guard let masterImage = SmartPhotoImageDecoder.downsample(data: originalData, maxPixel: masterLongestEdge) else {
            throw SmartPhotoPipelineError.decodeFailed
        }

        let analysisCGWidth = analysisImage.cgImage?.width ?? Int(analysisImage.size.width * analysisImage.scale)
        let analysisCGHeight = analysisImage.cgImage?.height ?? Int(analysisImage.size.height * analysisImage.scale)
        let analysisSize = CGSize(width: analysisCGWidth, height: analysisCGHeight)

        let detection = SmartPhotoSubjectDetector.detectSubjects(in: analysisImage)

        let preparedAt = Date()

        // Crop rects are computed in normalised space (0...1) so they can be applied to master.
        let smallPlan = SmartPhotoVariantBuilder.buildVariant(
            family: WidgetFamily.systemSmall,
            targetPixels: renderTargets.small,
            detection: detection,
            analysisSize: analysisSize
        )

        let mediumPlan = SmartPhotoVariantBuilder.buildVariant(
            family: WidgetFamily.systemMedium,
            targetPixels: renderTargets.medium,
            detection: detection,
            analysisSize: analysisSize
        )

        let largePlan = SmartPhotoVariantBuilder.buildVariant(
            family: WidgetFamily.systemLarge,
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
        let renderedSmall = SmartPhotoRenderer.render(master: masterImage, cropRect: smallPlan.cropRect, targetPixels: renderTargets.small)
        let renderedMedium = SmartPhotoRenderer.render(master: masterImage, cropRect: mediumPlan.cropRect, targetPixels: renderTargets.medium)
        let renderedLarge = SmartPhotoRenderer.render(master: masterImage, cropRect: largePlan.cropRect, targetPixels: renderTargets.large)

        let smallData = try SmartPhotoJPEG.encode(image: renderedSmall, startQuality: 0.85, maxBytes: 450_000)
        let mediumData = try SmartPhotoJPEG.encode(image: renderedMedium, startQuality: 0.85, maxBytes: 650_000)
        let largeData = try SmartPhotoJPEG.encode(image: renderedLarge, startQuality: 0.85, maxBytes: 900_000)

        try AppGroup.writeImageData(smallData, fileName: smallFileName)
        try AppGroup.writeImageData(mediumData, fileName: mediumFileName)
        try AppGroup.writeImageData(largeData, fileName: largeFileName)

        #if DEBUG
        let masterInfo = AppGroup.debugPickedImageInfo(fileName: masterFileName)?.inlineSummary ?? "uti=? orient=? px=?x?"
        let smallInfo = AppGroup.debugPickedImageInfo(fileName: smallFileName)?.inlineSummary ?? "uti=? orient=? px=?x?"
        let mediumInfo = AppGroup.debugPickedImageInfo(fileName: mediumFileName)?.inlineSummary ?? "uti=? orient=? px=?x?"
        let largeInfo = AppGroup.debugPickedImageInfo(fileName: largeFileName)?.inlineSummary ?? "uti=? orient=? px=?x?"
        print("[WWSmartPhoto] wrote master=\(masterFileName) \(masterInfo)")
        print("[WWSmartPhoto] wrote small=\(smallFileName) \(smallInfo)")
        print("[WWSmartPhoto] wrote medium=\(mediumFileName) \(mediumInfo)")
        print("[WWSmartPhoto] wrote large=\(largeFileName) \(largeInfo)")
        #endif

        let smartPhoto = SmartPhotoSpec(
            masterFileName: masterFileName,
            small: SmartPhotoVariantSpec(
                renderFileName: smallFileName,
                cropRect: smallPlan.cropRect,
                pixelSize: renderTargets.small
            ),
            medium: SmartPhotoVariantSpec(
                renderFileName: mediumFileName,
                cropRect: mediumPlan.cropRect,
                pixelSize: renderTargets.medium
            ),
            large: SmartPhotoVariantSpec(
                renderFileName: largeFileName,
                cropRect: largePlan.cropRect,
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

        let clampedMaxPixel = max(1, maxPixel)

        let props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?) as? [CFString: Any]

        let orientation: Int? = {
            if let v = props?[kCGImagePropertyOrientation] as? Int { return v }
            if let v = props?[kCGImagePropertyOrientation] as? NSNumber { return v.intValue }
            if let v = props?[kCGImagePropertyOrientation] as? UInt32 { return Int(v) }
            return nil
        }()

        let pixelWidth: Int? = {
            if let v = props?[kCGImagePropertyPixelWidth] as? Int { return v }
            if let v = props?[kCGImagePropertyPixelWidth] as? NSNumber { return v.intValue }
            return nil
        }()

        let pixelHeight: Int? = {
            if let v = props?[kCGImagePropertyPixelHeight] as? Int { return v }
            if let v = props?[kCGImagePropertyPixelHeight] as? NSNumber { return v.intValue }
            return nil
        }()

        let shouldApplyTransform: Bool = {
            let o = orientation ?? 1
            if o == 1 { return true }

            // Heuristic guardrail: some picker/transcoded bytes contain pixels already rotated to `.up`
            // while metadata still reports a rotated orientation. Applying the transform again would
            // double-rotate the pixels.
            //
            // When the EXIF orientation implies a 90°/270° rotation, the stored pixel dimensions are
            // usually landscape (width >= height). If the stored pixels are already portrait, skip
            // the transform.
            if o == 5 || o == 6 || o == 7 || o == 8 {
                if let w = pixelWidth, let h = pixelHeight, w < h {
                    return false
                }
            }

            return true
        }()

        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: clampedMaxPixel,
            kCGImageSourceCreateThumbnailWithTransform: shouldApplyTransform,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return nil
        }

        // The returned CGImage is already oriented correctly when `shouldApplyTransform` is true.
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }
}

// MARK: - Detection

enum SmartPhotoSubjectKind {
    case face
    case animal
    case human
    case saliency
    case none
}

struct SmartPhotoDetection {
    var kind: SmartPhotoSubjectKind
    var boxes: [CGRect] // pixel coords in analysis image (top-left origin)

    /// Ranked boxes per detector kind so small-crop logic can build a robust pair/cluster
    /// even when the chosen `kind` only produces a single box.
    var faces: [CGRect]
    var humans: [CGRect]
    var animals: [CGRect]
    var saliency: [CGRect]
}

private enum SmartPhotoSubjectDetector {
    static func detectSubjects(in analysisImage: UIImage) -> SmartPhotoDetection {
        guard let cg = analysisImage.cgImage else {
            return SmartPhotoDetection(kind: .none, boxes: [], faces: [], humans: [], animals: [], saliency: [])
        }

        let size = CGSize(width: cg.width, height: cg.height)

        let faces = rank(boxes: detectFaces(in: cg, imageSize: size), imageSize: size)
        let humans = rank(boxes: detectHumans(in: cg, imageSize: size), imageSize: size)
        let animals = rank(boxes: detectAnimals(in: cg, imageSize: size), imageSize: size)
        let saliency = rank(boxes: detectSaliency(in: cg, imageSize: size), imageSize: size)

        let chosenKind: SmartPhotoSubjectKind
        let chosenBoxes: [CGRect]

        if faces.count >= 2 {
            chosenKind = .face
            chosenBoxes = faces
        } else if faces.count == 1 {
            if humans.count >= 2 {
                chosenKind = .human
                chosenBoxes = humans
            } else if saliency.count >= 2 {
                chosenKind = .saliency
                chosenBoxes = saliency
            } else {
                chosenKind = .face
                chosenBoxes = faces
            }
        } else {
            if !animals.isEmpty {
                chosenKind = .animal
                chosenBoxes = animals
            } else if !humans.isEmpty {
                chosenKind = .human
                chosenBoxes = humans
            } else if !saliency.isEmpty {
                chosenKind = .saliency
                chosenBoxes = saliency
            } else {
                chosenKind = .none
                chosenBoxes = []
            }
        }

        return SmartPhotoDetection(
            kind: chosenKind,
            boxes: chosenBoxes,
            faces: faces,
            humans: humans,
            animals: animals,
            saliency: saliency
        )
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

        let bounds = CGRect(origin: .zero, size: imageSize)
        return out.compactMap {
            let r = $0.intersection(bounds)
            return (r.isNull || r.isEmpty) ? nil : r
        }
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

        let bounds = CGRect(origin: .zero, size: imageSize)
        return out.compactMap {
            let r = $0.intersection(bounds)
            return (r.isNull || r.isEmpty) ? nil : r
        }
    }

    private static func detectHumans(in cgImage: CGImage, imageSize: CGSize) -> [CGRect] {
        guard #available(iOS 11.0, *) else { return [] }

        var out: [CGRect] = []

        let req = VNDetectHumanRectanglesRequest { request, _ in
            guard let results = request.results as? [VNHumanObservation] else { return }
            out = results.map { toPixelTopLeftRect($0.boundingBox, imageSize: imageSize) }
        }

        req.upperBodyOnly = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([req])
        } catch {
            return []
        }

        let bounds = CGRect(origin: .zero, size: imageSize)
        return out.compactMap {
            let r = $0.intersection(bounds)
            return (r.isNull || r.isEmpty) ? nil : r
        }
    }

    private static func detectSaliency(in cgImage: CGImage, imageSize: CGSize) -> [CGRect] {
        guard #available(iOS 13.0, *) else { return [] }

        let objReq = VNGenerateObjectnessBasedSaliencyImageRequest(completionHandler: nil)
        let attReq = VNGenerateAttentionBasedSaliencyImageRequest(completionHandler: nil)

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            // Avoid shared mutable state across Vision completion handlers (can crash under concurrency).
            try handler.perform([objReq, attReq])
        } catch {
            return []
        }

        func salientBoxes(from request: VNRequest) -> [CGRect] {
            guard let results = request.results as? [VNSaliencyImageObservation],
                  let obs = results.first,
                  let salient = obs.salientObjects
            else { return [] }

            return salient.map { toPixelTopLeftRect($0.boundingBox, imageSize: imageSize) }
        }

        let boxes = salientBoxes(from: objReq) + salientBoxes(from: attReq)

        let bounds = CGRect(origin: .zero, size: imageSize)
        return boxes.compactMap {
            let r = $0.intersection(bounds)
            return (r.isNull || r.isEmpty) ? nil : r
        }
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
        let orientedUp = normalisedOrientationIfNeeded(image)
        let preparedImage = ensureOpaquePixelFormatIfNeeded(orientedUp)

        guard let cgImage = preparedImage.cgImage else {
            throw SmartPhotoPipelineError.encodeFailed
        }

        var q = min(0.95, max(0.1, startQuality))
        let minQ: CGFloat = 0.65

        var data = try autoreleasepool(invoking: { try encodeImageIOJPEG(cgImage: cgImage, quality: q) })

        var steps = 0
        while data.count > maxBytes && q > minQ && steps < 6 {
            q = max(minQ, q - 0.05)
            data = try autoreleasepool(invoking: { try encodeImageIOJPEG(cgImage: cgImage, quality: q) })
            steps += 1
        }

        if data.isEmpty {
            throw SmartPhotoPipelineError.encodeFailed
        }

        return data
    }

    /// Normalises UIKit orientation to guarantee pixels are `.up` before encoding.
    ///
    /// This avoids downstream decode paths applying EXIF orientation transforms (double-rotate).
    private static func normalisedOrientationIfNeeded(_ image: UIImage) -> UIImage {
        if image.imageOrientation == .up { return image }

        let size: CGSize = {
            if let cg = image.cgImage {
                return CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
            }

            let w = image.size.width * image.scale
            let h = image.size.height * image.scale
            return CGSize(width: w, height: h)
        }()

        if size.width <= 0 || size.height <= 0 { return image }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Encodes JPEG bytes via ImageIO with explicit orientation metadata `1`.
    ///
    /// Requirement for widget-safety:
    /// - pixels are already `.up`
    /// - metadata orientation is `1` (so thumbnailing with transform is a no-op)
    private static func encodeImageIOJPEG(cgImage: CGImage, quality: CGFloat) throws -> Data {
        let q = min(max(quality, 0.0), 1.0)

        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw SmartPhotoPipelineError.encodeFailed
        }

        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: q,
            kCGImagePropertyOrientation: 1
        ]

        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw SmartPhotoPipelineError.encodeFailed
        }

        return out as Data
    }

    private static func ensureOpaquePixelFormatIfNeeded(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        if isAlphaFree(cgImage.alphaInfo) { return image }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return image }

        #if DEBUG
        print("[WWSmartPhoto] alphaFix inputAlpha=\(cgImage.alphaInfo.rawValue) px=\(width)x\(height)")
        #endif

        let size = CGSize(width: CGFloat(width), height: CGFloat(height))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func isAlphaFree(_ alphaInfo: CGImageAlphaInfo) -> Bool {
        switch alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            return true
        default:
            return false
        }
    }
}
