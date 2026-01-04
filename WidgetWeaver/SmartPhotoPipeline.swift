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
    case human
    case saliency
    case none
}

private struct SmartPhotoDetection {
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

        var boxes: [CGRect] = []

        let objReq = VNGenerateObjectnessBasedSaliencyImageRequest { request, _ in
            guard let results = request.results as? [VNSaliencyImageObservation],
                  let obs = results.first
            else { return }

            if let salient = obs.salientObjects {
                boxes.append(contentsOf: salient.map { toPixelTopLeftRect($0.boundingBox, imageSize: imageSize) })
            }
        }

        let attReq = VNGenerateAttentionBasedSaliencyImageRequest { request, _ in
            guard let results = request.results as? [VNSaliencyImageObservation],
                  let obs = results.first
            else { return }

            if let salient = obs.salientObjects {
                boxes.append(contentsOf: salient.map { toPixelTopLeftRect($0.boundingBox, imageSize: imageSize) })
            }
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        do {
            try handler.perform([objReq, attReq])
        } catch {
            return []
        }

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

        var selected: [CGRect] = []
        var effectiveKind: SmartPhotoSubjectKind = detection.kind

        switch family {
        case .systemSmall:
            if let pair = pickPairForSmall(detection: detection, imageSize: imageSize) {
                selected = pair.boxes
                effectiveKind = pair.kind
            } else {
                selected = Array(ranked.prefix(1))
                effectiveKind = detection.kind
            }

        case .systemMedium:
            selected = Array(ranked.prefix(2))
            effectiveKind = detection.kind

        case .systemLarge:
            selected = ranked
            effectiveKind = detection.kind

        default:
            selected = Array(ranked.prefix(1))
            effectiveKind = detection.kind
        }

        guard !selected.isEmpty else {
            return centredCropRect(imageSize: imageSize, targetAspect: targetAspect)
        }

        let expanded = selected.map { expandSubjectBox($0, kind: effectiveKind, family: family, imageSize: imageSize).intersection(bounds) }
        var unionRect = expanded.first ?? centredCropRect(imageSize: imageSize, targetAspect: targetAspect)
        for r in expanded.dropFirst() {
            unionRect = unionRect.union(r)
        }

        let padScale: CGFloat = {
            switch family {
            case .systemSmall: return 1.20
            case .systemMedium: return 1.15
            case .systemLarge: return 1.10
            default: return 1.15
            }
        }()

        // Padding is about safety; centre remains based on the subject union.
        let focus = scaleRect(unionRect, factor: padScale).intersection(bounds)

        // Small uses the union centre to keep pairs fairly centred, even if padding is clipped.
        // Medium/Large keep the previous behaviour (centre from the padded focus rect).
        var centre = CGPoint(x: focus.midX, y: focus.midY)
        if family == .systemSmall {
            centre = CGPoint(x: unionRect.midX, y: unionRect.midY)
        }

        var baseW = focus.width
        var baseH = focus.height
        let focusAspect = max(0.0001, baseW) / max(0.0001, baseH)

        if focusAspect > targetAspect {
            baseH = baseW / targetAspect
        } else {
            baseW = baseH * targetAspect
        }

        let extraScale: CGFloat = {
            switch family {
            case .systemSmall: return 1.06
            case .systemMedium: return 1.04
            case .systemLarge: return 1.02
            default: return 1.04
            }
        }()

        var cropW = baseW * extraScale
        var cropH = baseH * extraScale

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

        // Minimum size that still preserves the padded subject union.
        var minAllowedW = baseW
        var minAllowedH = baseH
        if minAllowedW < minW {
            minAllowedW = minW
            minAllowedH = minAllowedW / targetAspect
        }
        if minAllowedH < minH {
            minAllowedH = minH
            minAllowedW = minAllowedH * targetAspect
        }
        if minAllowedW > imageSize.width {
            minAllowedW = imageSize.width
            minAllowedH = minAllowedW / targetAspect
        }
        if minAllowedH > imageSize.height {
            minAllowedH = imageSize.height
            minAllowedW = minAllowedH * targetAspect
        }

        if cropW < minW {
            cropW = minW
            cropH = cropW / targetAspect
        }
        if cropH < minH {
            cropH = minH
            cropW = cropH * targetAspect
        }

        if cropW > imageSize.width {
            cropW = imageSize.width
            cropH = cropW / targetAspect
        }
        if cropH > imageSize.height {
            cropH = imageSize.height
            cropW = cropH * targetAspect
        }

        if effectiveKind == .face || effectiveKind == .human {
            let biasFactor: CGFloat = {
                switch effectiveKind {
                case .face:
                    switch family {
                    case .systemSmall: return 0.12
                    case .systemMedium: return 0.08
                    case .systemLarge: return 0.05
                    default: return 0.08
                    }

                case .human:
                    switch family {
                    case .systemSmall: return 0.10
                    case .systemMedium: return 0.07
                    case .systemLarge: return 0.05
                    default: return 0.07
                    }

                default:
                    return 0
                }
            }()

            if biasFactor > 0 {
                let biasHeight = (family == .systemSmall) ? unionRect.height : focus.height
                centre.y -= biasHeight * biasFactor
            }
        }

        // Small-specific clamp to avoid extreme zoom-out.
        if family == .systemSmall {
            let maxCropAreaFracSmall: CGFloat = 0.75
            let imageArea = max(1, imageSize.width * imageSize.height)
            let maxArea = imageArea * maxCropAreaFracSmall
            let cropArea = cropW * cropH

            if cropArea > maxArea {
                let maxWByArea = sqrt(maxArea * targetAspect)
                let maxWByBounds = min(imageSize.width, imageSize.height * targetAspect)
                let maxW = min(maxWByArea, maxWByBounds)
                let maxH = maxW / targetAspect

                if maxW >= minAllowedW && maxH >= minAllowedH {
                    cropW = min(cropW, maxW)
                    cropH = cropW / targetAspect
                }
            }
        }

        // Soft clamp for small: try shrinking toward the minimum acceptable size before shifting to bounds.
        if family == .systemSmall {
            let maxWBoundForCentre = 2.0 * min(centre.x, imageSize.width - centre.x)
            let maxHBoundForCentre = 2.0 * min(centre.y, imageSize.height - centre.y)
            let maxWCentred = min(maxWBoundForCentre, maxHBoundForCentre * targetAspect)
            let maxHCentred = maxWCentred / targetAspect

            if cropW > maxWCentred, maxWCentred >= minAllowedW, maxHCentred >= minAllowedH {
                cropW = maxWCentred
                cropH = maxHCentred
            }
        }

        var x = centre.x - cropW / 2.0
        var y = centre.y - cropH / 2.0

        x = min(max(0, x), imageSize.width - cropW)
        y = min(max(0, y), imageSize.height - cropH)

        return CGRect(x: x, y: y, width: cropW, height: cropH).intersection(bounds)
    }

    private struct SmartPhotoPairChoice {
        var boxes: [CGRect]
        var score: CGFloat
    }

    private struct SmartPhotoPairCandidate {
        var kind: SmartPhotoSubjectKind
        var boxes: [CGRect]
        var score: CGFloat
    }

    private static func pickPairForSmall(detection: SmartPhotoDetection, imageSize: CGSize) -> (kind: SmartPhotoSubjectKind, boxes: [CGRect])? {
        var candidates: [SmartPhotoPairCandidate] = []

        func kindWeight(_ kind: SmartPhotoSubjectKind) -> CGFloat {
            switch kind {
            case .face:
                return 1.00
            case .human:
                return 0.97
            case .animal:
                return 0.94
            case .saliency:
                return 0.88
            case .none:
                return 0
            }
        }

        let perKind: [(SmartPhotoSubjectKind, [CGRect])] = [
            (.face, detection.faces),
            (.human, detection.humans),
            (.animal, detection.animals),
            (.saliency, detection.saliency)
        ]

        for (kind, boxes) in perKind {
            guard boxes.count >= 2 else { continue }
            if let choice = bestPairCandidate(from: boxes, imageSize: imageSize) {
                candidates.append(SmartPhotoPairCandidate(kind: kind, boxes: choice.boxes, score: choice.score))
            }
        }

        candidates.append(contentsOf: syntheticFacePartnerCandidates(detection: detection, imageSize: imageSize))

        guard !candidates.isEmpty else { return nil }

        let chosen = candidates.max { lhs, rhs in
            let l = lhs.score * kindWeight(lhs.kind)
            let r = rhs.score * kindWeight(rhs.kind)

            if abs(l - r) > 0.0005 {
                return l < r
            }

            return lhs.score < rhs.score
        }

        guard let best = chosen else { return nil }
        return (kind: best.kind, boxes: best.boxes)
    }

    private static func syntheticFacePartnerCandidates(detection: SmartPhotoDetection, imageSize: CGSize) -> [SmartPhotoPairCandidate] {
        guard !detection.faces.isEmpty else { return [] }
        guard imageSize.width > 1, imageSize.height > 1 else { return [] }

        let faces = Array(detection.faces.prefix(2))
        let humans = Array(detection.humans.prefix(6))
        let animals = Array(detection.animals.prefix(6))
        let saliency = Array(detection.saliency.prefix(8))

        func normalised(_ r: CGRect) -> CGRect {
            CGRect(
                x: r.minX / imageSize.width,
                y: r.minY / imageSize.height,
                width: r.width / imageSize.width,
                height: r.height / imageSize.height
            )
        }

        func area(_ r: CGRect) -> CGFloat {
            max(0, r.width) * max(0, r.height)
        }

        func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let inter = a.intersection(b)
            if inter.isNull || inter.isEmpty { return 0 }
            let interA = area(inter)
            let unionA = area(a) + area(b) - interA
            return unionA > 0 ? interA / unionA : 0
        }

        func overlapRatioMin(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let inter = a.intersection(b)
            if inter.isNull || inter.isEmpty { return 0 }
            let interA = area(inter)
            let minA = min(area(a), area(b))
            return minA > 0 ? interA / minA : 0
        }

        func score(_ r: CGRect) -> CGFloat {
            let a = area(r)
            let cx = r.midX
            let cy = r.midY
            let dx = cx - 0.5
            let dy = cy - 0.5
            let dist = sqrt(dx * dx + dy * dy)
            let maxDist: CGFloat = 0.70710678
            let prox = max(0, 1.0 - min(1.0, dist / maxDist))
            return a * 0.6 + prox * 0.4
        }

        let minEachArea: CGFloat = 0.015
        let minUnionArea: CGFloat = 0.06
        let maxHorizontalSeparation: CGFloat = 0.60
        let maxVerticalSeparation: CGFloat = 0.35
        let maxIou: CGFloat = 0.55
        let minUnionAspect: CGFloat = 0.35
        let maxUnionAspect: CGFloat = 2.80

        func pairPassesBaseConstraints(_ a: CGRect, _ b: CGRect) -> Bool {
            let aArea = area(a)
            let bArea = area(b)
            let union = a.union(b)
            let unionArea = area(union)

            if (aArea < minEachArea || bArea < minEachArea) && unionArea < minUnionArea {
                return false
            }

            let dx = abs(a.midX - b.midX)
            let dy = abs(a.midY - b.midY)
            if dx > maxHorizontalSeparation || dy > maxVerticalSeparation {
                return false
            }

            let unionAspect = union.width / max(0.0001, union.height)
            if unionAspect < minUnionAspect || unionAspect > maxUnionAspect {
                return false
            }

            if iou(a, b) > maxIou {
                return false
            }

            return true
        }

        func facePartnerAllowed(face: CGRect, partner: CGRect, partnerKind: SmartPhotoSubjectKind) -> Bool {
            let baseIoU = iou(face, partner)
            if baseIoU > maxIou {
                return false
            }

            // Humans/animals often include the face region for the same subject.
            // This rejects that case so a second subject can still be found.
            if partnerKind == .human || partnerKind == .animal {
                if overlapRatioMin(face, partner) > 0.78 {
                    return false
                }
            }

            // Saliency boxes can be broad; keep a cap to avoid selecting the whole image.
            if partnerKind == .saliency {
                let a = area(partner)
                if a < 0.025 || a > 0.70 {
                    return false
                }
            }

            return true
        }

        var out: [SmartPhotoPairCandidate] = []

        for facePx in faces {
            let face = normalised(facePx)

            var bestPartner: (rect: CGRect, kind: SmartPhotoSubjectKind, pairScore: CGFloat)? = nil

            func considerPartners(kind: SmartPhotoSubjectKind, list: [CGRect]) {
                for pPx in list {
                    let partner = normalised(pPx)
                    guard facePartnerAllowed(face: face, partner: partner, partnerKind: kind) else { continue }
                    guard pairPassesBaseConstraints(face, partner) else { continue }

                    let s = score(face) + score(partner)
                    if bestPartner == nil || s > (bestPartner?.pairScore ?? -1) {
                        bestPartner = (rect: pPx, kind: kind, pairScore: s)
                    }
                }
            }

            considerPartners(kind: .human, list: humans)
            considerPartners(kind: .animal, list: animals)
            considerPartners(kind: .saliency, list: saliency)

            if let partner = bestPartner {
                // When a face is in play, treating the crop kind as human preserves headroom bias.
                out.append(SmartPhotoPairCandidate(kind: .human, boxes: [facePx, partner.rect], score: partner.pairScore))
            }
        }

        return out
    }

    private static func bestPairCandidate(from boxes: [CGRect], imageSize: CGSize) -> SmartPhotoPairChoice? {
        guard imageSize.width > 1, imageSize.height > 1 else { return nil }

        let considered = Array(boxes.prefix(8))
        guard considered.count >= 2 else { return nil }

        func normalised(_ r: CGRect) -> CGRect {
            CGRect(
                x: r.minX / imageSize.width,
                y: r.minY / imageSize.height,
                width: r.width / imageSize.width,
                height: r.height / imageSize.height
            )
        }

        func area(_ r: CGRect) -> CGFloat {
            max(0, r.width) * max(0, r.height)
        }

        func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
            let inter = a.intersection(b)
            if inter.isNull || inter.isEmpty { return 0 }
            let interA = area(inter)
            let unionA = area(a) + area(b) - interA
            return unionA > 0 ? interA / unionA : 0
        }

        func score(_ r: CGRect) -> CGFloat {
            let a = area(r)
            let cx = r.midX
            let cy = r.midY
            let dx = cx - 0.5
            let dy = cy - 0.5
            let dist = sqrt(dx * dx + dy * dy)
            let maxDist: CGFloat = 0.70710678
            let prox = max(0, 1.0 - min(1.0, dist / maxDist))
            return a * 0.6 + prox * 0.4
        }

        let minEachArea: CGFloat = 0.015
        let minUnionArea: CGFloat = 0.06
        let maxHorizontalSeparation: CGFloat = 0.60
        let maxVerticalSeparation: CGFloat = 0.35
        let maxIou: CGFloat = 0.55
        let minUnionAspect: CGFloat = 0.35
        let maxUnionAspect: CGFloat = 2.80

        var best: (i: Int, j: Int, score: CGFloat) = (0, 1, -1)
        for i in 0..<(considered.count - 1) {
            for j in (i + 1)..<considered.count {
                let aP = considered[i]
                let bP = considered[j]

                let a = normalised(aP)
                let b = normalised(bP)

                let aArea = area(a)
                let bArea = area(b)
                let union = a.union(b)
                let unionArea = area(union)

                if (aArea < minEachArea || bArea < minEachArea) && unionArea < minUnionArea {
                    continue
                }

                let dx = abs(a.midX - b.midX)
                let dy = abs(a.midY - b.midY)
                if dx > maxHorizontalSeparation || dy > maxVerticalSeparation {
                    continue
                }

                let unionAspect = union.width / max(0.0001, union.height)
                if unionAspect < minUnionAspect || unionAspect > maxUnionAspect {
                    continue
                }

                if iou(a, b) > maxIou {
                    continue
                }

                let s = score(a) + score(b)
                if s > best.score {
                    best = (i: i, j: j, score: s)
                }
            }
        }

        if best.score < 0 { return nil }
        return SmartPhotoPairChoice(boxes: [considered[best.i], considered[best.j]], score: best.score)
    }

    private static func expandSubjectBox(_ rect: CGRect, kind: SmartPhotoSubjectKind, family: WidgetFamily, imageSize: CGSize) -> CGRect {
        var r = rect

        switch kind {
        case .face:
            let side = r.width * 0.20
            let top = r.height * 0.32
            let bottom = r.height * 0.14
            r = r.insetBy(dx: -side, dy: 0)
            r.origin.y -= top
            r.size.height += top + bottom

        case .animal:
            let dx = r.width * 0.18
            let dy = r.height * 0.18
            r = r.insetBy(dx: -dx, dy: -dy)

        case .human:
            let side = r.width * 0.14
            let top = r.height * 0.22
            let bottom = r.height * 0.10
            r = r.insetBy(dx: -side, dy: 0)
            r.origin.y -= top
            r.size.height += top + bottom

        case .saliency:
            let dx = r.width * 0.12
            let dy = r.height * 0.12
            r = r.insetBy(dx: -dx, dy: -dy)

        case .none:
            break
        }

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
