//
//  PawPulseCache.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import Foundation
import UIKit
import ImageIO

public enum PawPulseCache {
    public static let directoryName: String = "PawPulse"
    public static let latestJSONFileName: String = "latest.json"
    public static let latestImageFileName: String = "latest.jpg"

    public static var directoryURL: URL {
        AppGroup.containerURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    public static var latestJSONURL: URL {
        directoryURL.appendingPathComponent(latestJSONFileName)
    }

    public static var latestImageURL: URL {
        directoryURL.appendingPathComponent(latestImageFileName)
    }

    public static func ensureDirectoryExists() {
        let url = directoryURL
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            // Intentionally ignored (fallbacks handle missing cache).
        }
    }

    public static func clearCache() {
        ensureDirectoryExists()
        try? FileManager.default.removeItem(at: latestJSONURL)
        try? FileManager.default.removeItem(at: latestImageURL)
    }

    public static func readLatestJSONData() -> Data? {
        ensureDirectoryExists()
        let url = latestJSONURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func readLatestImageData() -> Data? {
        ensureDirectoryExists()
        let url = latestImageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    public static func loadLatestItem() -> PawPulseLatestItem? {
        guard let data = readLatestJSONData() else { return nil }
        do {
            return try JSONDecoder().decode(PawPulseLatestItem.self, from: data)
        } catch {
            return nil
        }
    }

    public static func writeLatest(jsonData: Data, imageData: Data?) throws {
        ensureDirectoryExists()

        try jsonData.write(to: latestJSONURL, options: [.atomic])

        if let imageData {
            try imageData.write(to: latestImageURL, options: [.atomic])
        }
    }

    public static func loadUIImage() -> UIImage? {
        let url = latestImageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    /// Widget-first image loader: downsample at decode time using ImageIO.
    ///
    /// - Note: This intentionally performs no caching.
    public static func loadWidgetImage(maxPixel: Int) -> UIImage? {
        let url = latestImageURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let clampedMaxPixel = max(1, maxPixel)

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: clampedMaxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}
