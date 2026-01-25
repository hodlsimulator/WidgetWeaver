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

        if let localIdentifier = item.itemIdentifier?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
           !localIdentifier.isEmpty,
           let (assetData, assetOrientation) = try await requestPhotoKitDataAndOrientation(localIdentifier: localIdentifier) {

            let metaOrientation = readOrientationFromMetadata(data: assetData)
            let effectiveOrientation = metaOrientation ?? assetOrientation

            #if DEBUG
            if let metaOrientation, metaOrientation != assetOrientation {
                print("[WWPhotoImport] orientation mismatch photoKit=\(assetOrientation.rawValue) meta=\(metaOrientation.rawValue)")
            }
            #endif

            return try await normaliseOffMainThread(
                data: assetData,
                orientation: effectiveOrientation,
                maxPixel: clampedMaxPixel,
                compressionQuality: clampedQuality
            )
        }

        guard let data = try await item.loadTransferable(type: Data.self) else {
            return nil
        }

        let metaOrientation = readOrientationFromMetadata(data: data) ?? .up

        return try await normaliseOffMainThread(
            data: data,
            orientation: metaOrientation,
            maxPixel: clampedMaxPixel,
            compressionQuality: clampedQuality
        )
    }

    private static func requestPhotoKitDataAndOrientation(
        localIdentifier: String
    ) async throws -> (Data, CGImagePropertyOrientation)? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.version = .current
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, orientation, info in
                if let cancelled = info?[PHImageCancelledKey] as? NSNumber, cancelled.boolValue {
                    continuation.resume(returning: nil)
                    return
                }

                if let error = info?[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                let degraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
                if degraded {
                    return
                }

                guard let data else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: (data, orientation))
            }
        }
    }

    private static func normaliseOffMainThread(
        data: Data,
        orientation: CGImagePropertyOrientation,
        maxPixel: Int,
        compressionQuality: CGFloat
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let out = try normaliseToJPEGUp(
                        data: data,
                        orientation: orientation,
                        maxPixel: maxPixel,
                        compressionQuality: compressionQuality
                    )
                    continuation.resume(returning: out)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func normaliseToJPEGUp(
        data: Data,
        orientation: CGImagePropertyOrientation,
        maxPixel: Int,
        compressionQuality: CGFloat
    ) throws -> Data {
        guard let cgImage = downsampleCGImage(data: data, maxPixel: max(1, maxPixel)) else {
            throw ImportError.decodeFailed
        }

        let uiOrientation = UIImage.Orientation(ww_exifOrientation: orientation)
        let orientedImage = UIImage(cgImage: cgImage, scale: 1, orientation: uiOrientation)

        let outputSize = pixelSizeAfterApplyingOrientation(
            width: cgImage.width,
            height: cgImage.height,
            orientation: orientation
        )

        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 1
        rendererFormat.opaque = true

        let renderer = UIGraphicsImageRenderer(size: outputSize, format: rendererFormat)
        let rendered = renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: outputSize))
            orientedImage.draw(in: CGRect(origin: .zero, size: outputSize))
        }

        guard let outCG = rendered.cgImage else {
            throw ImportError.encodeFailed
        }

        return try encodeJPEGUp(cgImage: outCG, compressionQuality: compressionQuality)
    }

    private static func downsampleCGImage(data: Data, maxPixel: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
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

    private static func pixelSizeAfterApplyingOrientation(
        width: Int,
        height: Int,
        orientation: CGImagePropertyOrientation
    ) -> CGSize {
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: max(1, height), height: max(1, width))
        default:
            return CGSize(width: max(1, width), height: max(1, height))
        }
    }

    private static func readOrientationFromMetadata(data: Data) -> CGImagePropertyOrientation? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as NSDictionary? else {
            return nil
        }

        let rawValue: UInt32? = {
            if let n = props[kCGImagePropertyOrientation] as? NSNumber { return n.uint32Value }
            if let v = props[kCGImagePropertyOrientation] as? UInt32 { return v }
            if let v = props[kCGImagePropertyOrientation] as? Int { return UInt32(v) }
            return nil
        }()

        guard let rawValue, let o = CGImagePropertyOrientation(rawValue: rawValue) else {
            return nil
        }

        return o
    }
}

private extension UIImage.Orientation {
    init(ww_exifOrientation: CGImagePropertyOrientation) {
        switch ww_exifOrientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
