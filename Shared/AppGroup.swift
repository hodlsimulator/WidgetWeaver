//
//  AppGroup.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import UIKit

#if canImport(WidgetKit)
import WidgetKit
#endif

private final class ImageCacheBox: @unchecked Sendable {
    let cache: NSCache<NSString, UIImage>

    init(countLimit: Int, totalCostLimit: Int) {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = countLimit
        c.totalCostLimit = totalCostLimit
        self.cache = c
    }
}

private extension UIImage {
    var estimatedDecodedByteCount: Int {
        if let cg = self.cgImage {
            return cg.bytesPerRow * cg.height
        }

        let w = max(1, Int(size.width * scale))
        let h = max(1, Int(size.height * scale))
        return w * h * 4
    }
}

public enum AppGroup {

    public static let groupID = "group.conor.WidgetWeaver"
    public static let imagesDirectoryName = "images"
    public static let widgetSpecsFileName = "widget-specs-v3.json"

    // Keep widget memory usage low: widgets run under much tighter memory constraints than the app.
    private static let isWidgetExtension: Bool = Bundle.main.bundleURL.pathExtension == "appex"

    private static let imageCache: ImageCacheBox = {
        if isWidgetExtension {
            return ImageCacheBox(countLimit: 6, totalCostLimit: 12 * 1024 * 1024)
        }
        return ImageCacheBox(countLimit: 64, totalCostLimit: 96 * 1024 * 1024)
    }()

    public static var containerURL: URL {
        guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            fatalError("App group container URL not found. Check group ID setup.")
        }
        return url
    }

    public static var imagesDirectoryURL: URL {
        containerURL.appendingPathComponent(imagesDirectoryName, isDirectory: true)
    }

    public static var widgetSpecsFileURL: URL {
        containerURL.appendingPathComponent(widgetSpecsFileName)
    }

    public static func ensureImagesDirectoryExists() throws {
        let dir = imagesDirectoryURL
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public static func createImageFileName(ext: String = "jpg") -> String {
        createImageFileName(prefix: "image", ext: ext)
    }

    public static func createImageFileName(prefix: String, ext: String = "jpg") -> String {
        let p = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePrefix = p.isEmpty ? "image" : String(p.prefix(32))
        return "\(safePrefix)-\(UUID().uuidString).\(ext)"
    }

    public static func imageFileURL(fileName: String) -> URL {
        imagesDirectoryURL.appendingPathComponent(fileName)
    }

    public static func listAllImageFiles() -> [URL] {
        let dir = imagesDirectoryURL
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }
        return files
    }

    public static func loadUIImage(fileName: String) -> UIImage? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let cached = imageCache.cache.object(forKey: trimmed as NSString) {
            return cached
        }

        let url = imagesDirectoryURL.appendingPathComponent(trimmed)
        guard FileManager.default.fileExists(atPath: url.path),
              let img = UIImage(contentsOfFile: url.path) else {
            return nil
        }

        imageCache.cache.setObject(img, forKey: trimmed as NSString, cost: img.estimatedDecodedByteCount)
        return img
    }

    public static func writeImageData(_ data: Data, fileName: String) throws {
        try ensureImagesDirectoryExists()
        let url = imagesDirectoryURL.appendingPathComponent(fileName)
        try data.write(to: url, options: .atomic)
    }

    /// Writes an image as JPG. If `maxPixel` is provided, the image is downsampled to keep the longest edge <= maxPixel.
    public static func writeUIImage(_ image: UIImage, fileName: String, compressionQuality: CGFloat = 0.85, maxPixel: CGFloat = 1024) throws {
        try ensureImagesDirectoryExists()

        let normalised = image.normalisedOrientation()
        let downsized = normalised.downsampled(maxPixel: maxPixel)

        guard let jpg = downsized.jpegData(compressionQuality: compressionQuality) else {
            throw NSError(domain: "AppGroup", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create JPEG data"])
        }

        let url = imagesDirectoryURL.appendingPathComponent(fileName)
        try jpg.write(to: url, options: .atomic)

        imageCache.cache.setObject(downsized, forKey: fileName as NSString, cost: downsized.estimatedDecodedByteCount)
    }

    public static func deleteImageFile(fileName: String) {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let url = imagesDirectoryURL.appendingPathComponent(trimmed)
        try? FileManager.default.removeItem(at: url)
        imageCache.cache.removeObject(forKey: trimmed as NSString)
    }

    public static func saveSpecs(_ specs: [WidgetSpec]) throws {
        let data = try JSONEncoder().encode(specs)
        try data.write(to: widgetSpecsFileURL, options: .atomic)

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    public static func loadSpecs() -> [WidgetSpec] {
        guard let data = try? Data(contentsOf: widgetSpecsFileURL) else { return [] }
        return (try? JSONDecoder().decode([WidgetSpec].self, from: data)) ?? []
    }
}

public extension UIImage {
    func normalisedOrientation() -> UIImage {
        if imageOrientation == .up { return self }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    func downsampled(maxPixel: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > maxPixel, maxSide > 0 else { return self }

        let scaleFactor = maxPixel / maxSide
        let newSize = CGSize(width: size.width * scaleFactor, height: size.height * scaleFactor)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
