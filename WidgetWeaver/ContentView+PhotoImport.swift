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
        let id = item.itemIdentifier ?? "nil"
        let types = item.supportedContentTypes.map(\.identifier).joined(separator: ",")
        print("[WWPhotoImport] pick itemIdentifier=\(id) types=\(types)")
        #endif

        // 1) PhotoKit-rendered path (only when PhotoKit access is available).
        // This produces pixels as displayed by Photos (including orientation/edits).
        if canUsePhotoKitForRenderedFetch,
           let localIdentifier = item.itemIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           !localIdentifier.isEmpty,
           let uiImage = try await requestPhotoKitRenderedUIImage(
            localIdentifier: localIdentifier,
            maxPixel: clampedMaxPixel
           ) {

            #if DEBUG
            let o = uiImage.imageOrientation.rawValue
            let w = uiImage.cgImage?.width ?? Int(uiImage.size.width * uiImage.scale)
            let h = uiImage.cgImage?.height ?? Int(uiImage.size.height * uiImage.scale)
            print("[WWPhotoImport] photoKitRendered orient=\(o) px=\(w)x\(h)")
            #endif

            let outData = try await normaliseUIImageOffMainThread(
                uiImage,
                maxPixel: clampedMaxPixel,
                compressionQuality: clampedQuality
            )

            #if DEBUG
            let outInfo = AppGroup.debugPickedImageInfo(data: outData)?.inlineSummary ?? "uti=? orient=? px=?x?"
            print("[WWPhotoImport] postNormalise out=\(outInfo) source=photoKitRendered")
            #endif

            return outData
        }

        // 2) Preferred picker path: ask for an image FILE representation.
        // This tends to preserve original metadata better than generic `Data.self`.
        let pickedData: Data
        let pickedSourceLabel: String

        if let transferredFile = try await item.loadTransferable(type: WWPickedImageFileTransfer.self) {
            do {
                pickedData = try Data(contentsOf: transferredFile.url)
            } catch {
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
            return nil
        }

        // 3) Preferred orientation-safe path (PhotosPicker): ask for a SwiftUI Image.
        // This tends to match what the picker previews, even in environments where the exported
        // JPEG bytes carry inconsistent orientation metadata.
        let targetPixelSize = computeTargetPixelSize(from: pickedData, maxPixel: clampedMaxPixel)
        if let uiImage = try await loadRenderedUIImageFromPickerItem(item, targetPixelSize: targetPixelSize) {
            let outData = try await encodeUIImageToJPEGUpOffMainThread(
                uiImage,
                compressionQuality: clampedQuality
            )

            #if DEBUG
            let inInfo = AppGroup.debugPickedImageInfo(data: pickedData)?.inlineSummary ?? "uti=? orient=? px=?x?"
            let outInfo = AppGroup.debugPickedImageInfo(data: outData)?.inlineSummary ?? "uti=? orient=? px=?x?"
            let sz = "\(Int(targetPixelSize.width))x\(Int(targetPixelSize.height))"
            print("[WWPhotoImport] postNormalise in=\(inInfo) out=\(outInfo) target=\(sz) source=swiftUIImage+\(pickedSourceLabel)")
            #endif

            return outData
        }

        // 4) Fallback: normalise bytes via ImageIO.
        let outData = try await normaliseImageDataOffMainThread(
            pickedData,
            maxPixel: clampedMaxPixel,
            compressionQuality: clampedQuality
        )

        #if DEBUG
        let inInfo = AppGroup.debugPickedImageInfo(data: pickedData)?.inlineSummary ?? "uti=? orient=? px=?x?"
        let outInfo = AppGroup.debugPickedImageInfo(data: outData)?.inlineSummary ?? "uti=? orient=? px=?x?"
        print("[WWPhotoImport] postNormalise in=\(inInfo) out=\(outInfo) source=\(pickedSourceLabel)")
        #endif

        return outData
    }

    // MARK: - SwiftUI Image → UIImage (for PhotosPicker correctness)

    @MainActor
    private static func loadRenderedUIImageFromPickerItem(
        _ item: PhotosPickerItem,
        targetPixelSize: CGSize
    ) async throws -> UIImage? {
        guard let swiftUIImage = try await item.loadTransferable(type: SwiftUI.Image.self) else {
            return nil
        }
        return renderSwiftUIImageToUIImage(swiftUIImage, targetPixelSize: targetPixelSize)
    }

    private static func computeTargetPixelSize(from data: Data, maxPixel: Int) -> CGSize {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return CGSize(width: max(1, maxPixel), height: max(1, maxPixel))
        }

        let props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary?) as? [CFString: Any]

        func intValue(_ key: CFString) -> Int? {
            if let v = props?[key] as? Int { return v }
            if let v = props?[key] as? NSNumber { return v.intValue }
            if let v = props?[key] as? UInt32 { return Int(v) }
            return nil
        }

        let o = intValue(kCGImagePropertyOrientation) ?? 1
        var w = intValue(kCGImagePropertyPixelWidth) ?? 0
        var h = intValue(kCGImagePropertyPixelHeight) ?? 0
        if w <= 0 || h <= 0 {
            // Avoid a degenerate layout size.
            return CGSize(width: max(1, maxPixel), height: max(1, maxPixel))
        }

        // Orientations 5-8 are rotated 90°/270°.
        if o == 5 || o == 6 || o == 7 || o == 8 {
            swap(&w, &h)
        }

        let longest = max(w, h)
        let targetLongest = min(max(1, maxPixel), longest)
        let ratio = CGFloat(targetLongest) / CGFloat(max(1, longest))

        let tw = max(1, (CGFloat(w) * ratio).rounded(.toNearestOrAwayFromZero))
        let th = max(1, (CGFloat(h) * ratio).rounded(.toNearestOrAwayFromZero))

        return CGSize(width: tw, height: th)
    }

    @MainActor
    private static func renderSwiftUIImageToUIImage(
        _ image: SwiftUI.Image,
        targetPixelSize: CGSize
    ) -> UIImage? {
        let target = CGSize(width: max(1, targetPixelSize.width), height: max(1, targetPixelSize.height))

        let content = ZStack {
            Color.black
            image
                .resizable()
                .scaledToFill()
                .frame(width: target.width, height: target.height)
                .clipped()
        }
        .frame(width: target.width, height: target.height)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        if #available(iOS 17.0, *) {
            renderer.isOpaque = true
        }

        return renderer.uiImage
    }

    private static func encodeUIImageToJPEGUpOffMainThread(
        _ image: UIImage,
        compressionQuality: CGFloat
    ) async throws -> Data {
        let q = min(max(compressionQuality, 0.0), 1.0)

        guard let cg = image.cgImage else {
            // Fallback: bake via UIKit draw then encode.
            return try await normaliseUIImageOffMainThread(image, maxPixel: Int(max(image.size.width, image.size.height)), compressionQuality: q)
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let out = try encodeJPEGUp(cgImage: cg, compressionQuality: q)
                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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
}
