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

    init(countLimit: Int) {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = countLimit
        self.cache = c
    }
}

public enum AppGroup {
    public static let identifier = "group.com.conornolan.widgetweaver"

    public static var userDefaults: UserDefaults {
        if let ud = UserDefaults(suiteName: identifier) {
            return ud
        }
        assertionFailure("App Group UserDefaults unavailable.\nCheck App Groups entitlement: \(identifier)")
        return .standard
    }

    public static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
            return url
        }
        assertionFailure("App Group container URL unavailable.\nCheck App Groups entitlement: \(identifier)")
        return FileManager.default.temporaryDirectory
    }

    public static var imagesDirectoryURL: URL {
        containerURL.appendingPathComponent("WidgetWeaverImages", isDirectory: true)
    }

    private static let imageCache = ImageCacheBox(countLimit: 32)

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
        imageCache.cache.removeObject(forKey: fileName as NSString)
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

        if let cached = imageCache.cache.object(forKey: trimmed as NSString) {
            return cached
        }

        let url = imagesDirectoryURL.appendingPathComponent(trimmed)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }

        imageCache.cache.setObject(img, forKey: trimmed as NSString)
        return img
    }

    public static func deleteImage(fileName: String) {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let url = imagesDirectoryURL.appendingPathComponent(trimmed)
        try? FileManager.default.removeItem(at: url)
        imageCache.cache.removeObject(forKey: trimmed as NSString)
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

// MARK: - Monetisation / Entitlements (Milestone 8)

public enum WidgetWeaverEntitlements {
    private static let proUnlockedKey = "widgetweaver.pro.v1.unlocked"

    public static let maxFreeDesigns: Int = 3

    public static var isProUnlocked: Bool {
        AppGroup.userDefaults.bool(forKey: proUnlockedKey)
    }

    public static func setProUnlocked(_ unlocked: Bool) {
        AppGroup.userDefaults.set(unlocked, forKey: proUnlockedKey)
        flushAndNotifyWidgets()
    }

    public static func flushAndNotifyWidgets() {
        AppGroup.userDefaults.synchronize()

        #if canImport(WidgetKit)
        let kind = WidgetWeaverWidgetKinds.main
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }
        #endif
    }
}
