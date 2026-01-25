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

        // Photos-library path:
        // Prefer a PhotoKit-rendered UIImage so the pixels match what the Photos app displays.
        if let localIdentifier = item.itemIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
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

        // Fallback path (Files app, drag/drop, etc.).
        guard let data = try await item.loadTransferable(type: Data.self) else {
            return nil
        }

        let outData = try await normaliseImageDataOffMainThread(
            data,
            maxPixel: clampedMaxPixel,
            compressionQuality: clampedQuality
        )

        #if DEBUG
        let inInfo = AppGroup.debugPickedImageInfo(data: data)?.inlineSummary ?? "uti=? orient=? px=?x?"
        let outInfo = AppGroup.debugPickedImageInfo(data: outData)?.inlineSummary ?? "uti=? orient=? px=?x?"
        print("[WWPhotoImport] postNormalise in=\(inInfo) out=\(outInfo) source=transferableData")
        #endif

        return outData
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
        let base: UIImage = {
            if let cg = image.cgImage {
                return UIImage(cgImage: cg, scale: 1, orientation: .up)
            }
            return image
        }()

        let pixelSize: CGSize = {
            if let cg = base.cgImage {
                return CGSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
            }
            let w = base.size.width * base.scale
            let h = base.size.height * base.scale
            return CGSize(width: w, height: h)
        }()

        let longest = max(pixelSize.width, pixelSize.height)
        if longest <= 0 {
            throw ImportError.decodeFailed
        }

        let targetLongest = min(CGFloat(max(1, maxPixel)), longest)
        let ratio = targetLongest / longest

        let targetSize = CGSize(
            width: max(1, (pixelSize.width * ratio).rounded(.toNearestOrAwayFromZero)),
            height: max(1, (pixelSize.height * ratio).rounded(.toNearestOrAwayFromZero))
        )

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: rendererFormat)
        let rendered = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            base.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        guard let outCG = rendered.cgImage else {
            throw ImportError.encodeFailed
        }

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
