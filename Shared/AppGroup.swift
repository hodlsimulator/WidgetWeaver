//
//  AppGroup.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import UIKit

public enum AppGroup {
    public static let identifier = "group.com.conornolan.widgetweaver"

    public static var userDefaults: UserDefaults {
        if let ud = UserDefaults(suiteName: identifier) {
            return ud
        }
        assertionFailure("App Group UserDefaults unavailable. Check App Groups entitlement: \(identifier)")
        return .standard
    }

    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        assertionFailure("App Group container URL unavailable. Check App Groups entitlement: \(identifier)")
        return FileManager.default.temporaryDirectory
    }

    public static var imagesDirectoryURL: URL {
        containerURL.appendingPathComponent("WidgetWeaverImages", isDirectory: true)
    }

    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 32
        return cache
    }()

    public static func ensureImagesDirectoryExists() {
        let url = imagesDirectoryURL
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            // Intentionally ignored (fallbacks handle missing images).
        }
    }

    public static func imageFileURL(fileName: String) -> URL {
        ensureImagesDirectoryExists()
        return imagesDirectoryURL.appendingPathComponent(fileName)
    }

    public static func createImageFileName(ext: String = "jpg") -> String {
        "image-\(UUID().uuidString).\(ext)"
    }

    public static func writeImageData(_ data: Data, fileName: String) throws {
        ensureImagesDirectoryExists()
        let url = imagesDirectoryURL.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        imageCache.removeObject(forKey: fileName as NSString)
    }

    public static func writeUIImage(_ image: UIImage, fileName: String, compressionQuality: CGFloat = 0.85) throws {
        ensureImagesDirectoryExists()

        let normalised = image.normalisedOrientation()
        let downsized = normalised.downsampled(maxPixel: 1024)

        if let data = downsized.jpegData(compressionQuality: compressionQuality) {
            try writeImageData(data, fileName: fileName)
            return
        }

        if let data = normalised.jpegData(compressionQuality: compressionQuality) {
            try writeImageData(data, fileName: fileName)
            return
        }

        throw CocoaError(.fileWriteUnknown)
    }

    public static func loadUIImage(fileName: String) -> UIImage? {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let cached = imageCache.object(forKey: trimmed as NSString) {
            return cached
        }

        let url = imagesDirectoryURL.appendingPathComponent(trimmed)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }

        imageCache.setObject(img, forKey: trimmed as NSString)
        return img
    }

    public static func deleteImage(fileName: String) {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let url = imagesDirectoryURL.appendingPathComponent(trimmed)
        try? FileManager.default.removeItem(at: url)
        imageCache.removeObject(forKey: trimmed as NSString)
    }
}

private extension UIImage {
    func normalisedOrientation() -> UIImage {
        if imageOrientation == .up { return self }

        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return img ?? self
    }

    func downsampled(maxPixel: CGFloat) -> UIImage {
        let maxSide = max(size.width, size.height)
        guard maxSide > 0, maxSide > maxPixel else { return self }

        let ratio = maxPixel / maxSide
        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        draw(in: CGRect(origin: .zero, size: newSize))
        let img = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return img ?? self
    }
}
