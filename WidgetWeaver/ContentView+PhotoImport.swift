//
//  ContentView+PhotoImport.swift
//  WidgetWeaver
//
//  Created by . . on 1/25/26.
//

import Foundation
import SwiftUI
import Photos
import PhotosUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

private struct WWPickedImageFileTransfer: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            WWPickedImageFileTransfer(url: received.file)
        }
    }
}

private struct WWPickedImageDataTransfer: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            WWPickedImageDataTransfer(data: data)
        }
    }
}

/// Normalises picker-selected photos so downstream Smart Photo + widget decode cannot double-apply orientation.
///
/// Output contract:
/// - pixels are already oriented `.up`
/// - orientation metadata is explicitly `1`
enum WWPhotoImportNormaliser {

    enum ImportError: Swift.Error {
        case decodeFailed
        case encodeFailed
    }

    static func loadNormalisedJPEGUpData(
        for item: PhotosPickerItem,
        maxPixel: Int,
        compressionQuality: CGFloat
    ) async throws -> Data? {
        let clampedMaxPixel = max(1, maxPixel)
        let clampedQuality = min(max(compressionQuality, 0.0), 1.0)

        #if DEBUG
        let debugItemIdentifier = item.itemIdentifier ?? "nil"
        let debugToken = debugThrottleToken(debugItemIdentifier)
        let debugTypes = item.supportedContentTypes.map(\.identifier).joined(separator: ",")

        WWPhotoDebugLog.appendLazy(
            category: "photo.import",
            throttleID: "import.pick.\(debugToken)",
            minInterval: 2.0
        ) {
            "pick itemIdentifier=\(debugItemIdentifier) types=\(debugTypes) maxPixel=\(clampedMaxPixel) q=\(String(format: "%.2f", clampedQuality))"
        }
        #endif

        // 1) PhotoKit-rendered path (only when a stable asset identifier exists and Photos access is granted).
        // This produces pixels as displayed by Photos (including edits/orientation).
        if canUsePhotoKitForRenderedFetch,
           let localIdentifier = item.itemIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localIdentifier.isEmpty,
           let uiImage = try await requestPhotoKitRenderedUIImage(
            localIdentifier: localIdentifier,
            maxPixel: clampedMaxPixel
           ) {

            #if DEBUG
            let oLabel = debugUIKitOrientationLabel(uiImage.imageOrientation)
            let w = uiImage.cgImage?.width ?? Int(uiImage.size.width * uiImage.scale)
            let h = uiImage.cgImage?.height ?? Int(uiImage.size.height * uiImage.scale)

            WWPhotoDebugLog.appendLazy(
                category: "photo.import",
                throttleID: "import.photoKitRendered.\(debugToken)",
                minInterval: 2.0
            ) {
                "photoKitRendered px=\(w)x\(h) uiKitOrient=\(oLabel)"
            }
            #endif

            let outData = try await normaliseUIImageOffMainThread(
                uiImage,
                maxPixel: clampedMaxPixel,
                compressionQuality: clampedQuality
            )

            #if DEBUG
            let outInfo = AppGroup.debugPickedImageInfo(data: outData)?.inlineSummary ?? "uti=? orient=? px=?x?"
            let outUIKit = await debugUIKitOrientationLabel(for: outData)

            WWPhotoDebugLog.appendLazy(
                category: "photo.import",
                throttleID: "import.postNormalise.photoKitRendered.\(debugToken)",
                minInterval: 2.0
            ) {
                "postNormalise out=\(outInfo) uiKit=\(outUIKit) source=photoKitRendered"
            }
            #endif

            return outData
        }

        #if DEBUG
        if let localIdentifier = item.itemIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localIdentifier.isEmpty {

            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

            if !canUsePhotoKitForRenderedFetch {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.import",
                    throttleID: "import.photoKitRendered.skipped.\(debugToken)",
                    minInterval: 2.0
                ) {
                    "photoKitRendered skipped authStatus=\(status.rawValue) (no PHPhotoLibrary readWrite access)"
                }
            } else {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.import",
                    throttleID: "import.photoKitRendered.unavailable.\(debugToken)",
                    minInterval: 2.0
                ) {
                    "photoKitRendered unavailable (request returned nil) authStatus=\(status.rawValue)"
                }
            }
        }
        #endif

        // 2) Load bytes from the picker.
        let pickedData: Data
        let pickedSourceLabel: String

        if let transferredFile = try await item.loadTransferable(type: WWPickedImageFileTransfer.self) {
            do {
                pickedData = try Data(contentsOf: transferredFile.url)
            } catch {
                #if DEBUG
                WWPhotoDebugLog.appendLazy(
                    category: "photo.import",
                    throttleID: "import.fileTransfer.readFail.\(debugToken)",
                    minInterval: 2.0
                ) {
                    "fileTransfer(.image) Data(contentsOf:) failed error=\(String(describing: error))"
                }
                #endif
                return nil
            }
            pickedSourceLabel = "fileTransfer(.image)"
        } else if let transferredData = try await item.loadTransferable(type: WWPickedImageDataTransfer.self) {
            pickedData = transferredData.data
            pickedSourceLabel = "dataTransfer(.image)"
        } else if let data = try await item.loadTransferable(type: Data.self) {
            pickedData = data
            pickedSourceLabel = "transferableData"
        } else {
            #if DEBUG
            WWPhotoDebugLog.appendLazy(
                category: "photo.import",
                throttleID: "import.loadTransferable.nil.\(debugToken)",
                minInterval: 2.0
            ) {
                "loadTransferable returned nil (no file/data/Data representation)"
            }
            #endif
            return nil
        }

        #if DEBUG
        let loadedInfo = AppGroup.debugPickedImageInfo(data: pickedData)?.inlineSummary ?? "uti=? orient=? px=?x?"
        let loadedUIKit = await debugUIKitOrientationLabel(for: pickedData)

        WWPhotoDebugLog.appendLazy(
            category: "photo.import",
            throttleID: "import.bytesLoaded.\(debugToken)",
            minInterval: 2.0
        ) {
            "loaded bytes source=\(pickedSourceLabel) bytes=\(pickedData.count) meta=\(loadedInfo) uiKit=\(loadedUIKit)"
        }
        #endif

        // 3) Single source of truth: normalise from bytes via ImageIO.
        // This applies EXIF orientation consistently for JPEG/HEIC and avoids SwiftUI rasterisation variance.
        let outData = try await normaliseImageDataOffMainThread(
            pickedData,
            maxPixel: clampedMaxPixel,
            compressionQuality: clampedQuality
        )

        #if DEBUG
        let inInfo = AppGroup.debugPickedImageInfo(data: pickedData)?.inlineSummary ?? "uti=? orient=? px=?x?"
        let outInfo = AppGroup.debugPickedImageInfo(data: outData)?.inlineSummary ?? "uti=? orient=? px=?x?"
        let inUIKit = await debugUIKitOrientationLabel(for: pickedData)
        let outUIKit = await debugUIKitOrientationLabel(for: outData)

        WWPhotoDebugLog.appendLazy(
            category: "photo.import",
            throttleID: "import.postNormalise.imageIO.\(debugToken)",
            minInterval: 2.0
        ) {
            "postNormalise in=\(inInfo) uiKitIn=\(inUIKit) out=\(outInfo) uiKitOut=\(outUIKit) source=imageIO+\(pickedSourceLabel)"
        }
        #endif

        return outData
    }

    private static var canUsePhotoKitForRenderedFetch: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized { return true }
        if status == .limited { return true }
        return false
    }

    // MARK: - PhotoKit (rendered UIImage)

    private static func requestPhotoKitRenderedUIImage(
        localIdentifier: String,
        maxPixel: Int
    ) async throws -> UIImage? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let w = max(1, asset.pixelWidth)
        let h = max(1, asset.pixelHeight)
        let longest = max(w, h)

        let targetLongest = min(max(1, maxPixel), longest)
        let ratio = (longest > 0) ? (CGFloat(targetLongest) / CGFloat(longest)) : 1.0

        let targetSize = CGSize(
            width: max(1, (CGFloat(w) * ratio).rounded(.toNearestOrAwayFromZero)),
            height: max(1, (CGFloat(h) * ratio).rounded(.toNearestOrAwayFromZero))
        )

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.version = .current
        options.isSynchronous = false

        final class RequestState: @unchecked Sendable {
            let lock = NSLock()
            var didResume = false
            var degradedCandidate: UIImage?
            var didScheduleFallback = false
        }

        let state = RequestState()

        return try await withCheckedThrowingContinuation { continuation in
            func resumeOnce(_ result: Result<UIImage?, Error>) {
                state.lock.lock()
                if state.didResume {
                    state.lock.unlock()
                    return
                }
                state.didResume = true
                state.lock.unlock()

                switch result {
                case .success(let image):
                    continuation.resume(returning: image)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                if let cancelled = info?[PHImageCancelledKey] as? NSNumber, cancelled.boolValue {
                    resumeOnce(.success(nil))
                    return
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    resumeOnce(.failure(error))
                    return
                }

                guard let image else { return }

                let degraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                if degraded {
                    state.lock.lock()
                    if state.degradedCandidate == nil {
                        state.degradedCandidate = image
                    }
                    let shouldSchedule = (!state.didScheduleFallback && !state.didResume)
                    if shouldSchedule {
                        state.didScheduleFallback = true
                    }
                    state.lock.unlock()

                    if shouldSchedule {
                        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1.0) {
                            state.lock.lock()
                            if state.didResume {
                                state.lock.unlock()
                                return
                            }
                            guard let candidate = state.degradedCandidate else {
                                state.lock.unlock()
                                return
                            }
                            state.didResume = true
                            state.lock.unlock()

                            continuation.resume(returning: candidate)
                        }
                    }
                    return
                }

                resumeOnce(.success(image))
            }
        }
    }

    // MARK: - Normalise UIImage → JPEG (pixels up, orientation=1)

    private static func normaliseUIImageOffMainThread(
        _ image: UIImage,
        maxPixel: Int,
        compressionQuality: CGFloat
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let out = try normaliseUIImageToJPEGUp(
                        image,
                        maxPixel: max(1, maxPixel),
                        compressionQuality: min(max(compressionQuality, 0.0), 1.0)
                    )
                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func normaliseUIImageToJPEGUp(
        _ image: UIImage,
        maxPixel: Int,
        compressionQuality: CGFloat
    ) throws -> Data {
        let pixelSize: CGSize = {
            let w = image.size.width * image.scale
            let h = image.size.height * image.scale
            if w > 0, h > 0 { return CGSize(width: w, height: h) }
            if let cg = image.cgImage { return CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height)) }
            return .zero
        }()

        let longest = max(pixelSize.width, pixelSize.height)
        if longest <= 0 { throw ImportError.decodeFailed }

        let targetLongest = min(CGFloat(max(1, maxPixel)), longest)
        let ratio = targetLongest / longest

        let targetSize = CGSize(
            width: max(1, (pixelSize.width * ratio).rounded(.toNearestOrAwayFromZero)),
            height: max(1, (pixelSize.height * ratio).rounded(.toNearestOrAwayFromZero))
        )

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        // Drawing the UIImage bakes its `imageOrientation` into pixels.
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        let rendered = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let outCG = rendered.cgImage else { throw ImportError.encodeFailed }
        return try encodeJPEGUp(cgImage: outCG, compressionQuality: compressionQuality)
    }

    // MARK: - Normalise Data → JPEG (pixels up, orientation=1)

    private static func normaliseImageDataOffMainThread(
        _ data: Data,
        maxPixel: Int,
        compressionQuality: CGFloat
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let out = try AppGroup.normalisePickedImageDataToJPEGUp(
                        data,
                        maxPixel: max(1, maxPixel),
                        compressionQuality: min(max(compressionQuality, 0.0), 1.0)
                    )
                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func encodeJPEGUp(cgImage: CGImage, compressionQuality: CGFloat) throws -> Data {
        let q = min(max(compressionQuality, 0.0), 1.0)

        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImportError.encodeFailed
        }

        let props: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: q,
            kCGImagePropertyOrientation: 1
        ]

        CGImageDestinationAddImage(destination, cgImage, props as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw ImportError.encodeFailed
        }

        return out as Data
    }


    #if DEBUG
    private static func debugThrottleToken(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "empty" }

        var s = trimmed
        s = s.replacingOccurrences(of: " ", with: "_")
        s = s.replacingOccurrences(of: "/", with: "_")
        s = s.replacingOccurrences(of: ":", with: "_")

        if s.count <= 64 { return s }
        return String(s.prefix(64))
    }

    private static func debugUIKitOrientationLabel(_ orientation: UIImage.Orientation) -> String {
        switch orientation {
        case .up: return "up(0)"
        case .down: return "down(1)"
        case .left: return "left(2)"
        case .right: return "right(3)"
        case .upMirrored: return "upMirrored(4)"
        case .downMirrored: return "downMirrored(5)"
        case .leftMirrored: return "leftMirrored(6)"
        case .rightMirrored: return "rightMirrored(7)"
        @unknown default: return "unknown(\(orientation.rawValue))"
        }
    }

    private static func debugUIKitOrientationLabel(_ orientation: UIImage.Orientation?) -> String {
        guard let orientation else { return "nil" }
        return debugUIKitOrientationLabel(orientation)
    }

    private static func debugUIKitOrientationLabel(for data: Data) async -> String {
        await Task.detached(priority: .utility) {
            let o = UIImage(data: data)?.imageOrientation
            return debugUIKitOrientationLabel(o)
        }.value
    }
    #endif
}
