//
//  AppGroup.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import UIKit
import ImageIO

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

    private static var isAppExtension: Bool {
        let url = Bundle.main.bundleURL
        if url.pathExtension == "appex" { return true }
        return url.path.contains(".appex/")
    }

    private static let imageCache = ImageCacheBox(
        countLimit: isAppExtension ? 6 : 32,
        totalCostLimit: isAppExtension ? (12 * 1024 * 1024) : (64 * 1024 * 1024)
    )

    private static func estimatedDecodedByteCount(_ image: UIImage) -> Int {
        if let cg = image.cgImage {
            let bytes = Int64(cg.bytesPerRow) * Int64(cg.height)
            if bytes > Int64(Int.max) { return Int.max }
            if bytes <= 0 { return 1 }
            return Int(bytes)
        }

        let w = Int64(image.size.width * image.scale)
        let h = Int64(image.size.height * image.scale)
        let bytes = w * h * 4
        if bytes > Int64(Int.max) { return Int.max }
        if bytes <= 0 { return 1 }
        return Int(bytes)
    }

    public static func ensureImagesDirectoryExists() {
        let url = imagesDirectoryURL
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            // Intentionally ignored (fallbacks handle missing images).
        }
    }

    private static func sanitisedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        return String(last.prefix(256))
    }

    public static func imageFileURL(fileName: String) -> URL {
        ensureImagesDirectoryExists()
        let safe = sanitisedFileName(fileName)
        return imagesDirectoryURL.appendingPathComponent(safe)
    }

    public static func createImageFileName(ext: String = "jpg") -> String {
        createImageFileName(prefix: "image", ext: ext)
    }

    public static func createImageFileName(prefix: String, ext: String = "jpg") -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePrefix = trimmedPrefix.isEmpty ? "image" : String(trimmedPrefix.prefix(32))
        let safeExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "jpg" : ext
        return "\(safePrefix)-\(UUID().uuidString).\(safeExt)"
    }

    public static func writeImageData(_ data: Data, fileName: String) throws {
        ensureImagesDirectoryExists()
        let safe = sanitisedFileName(fileName)
        let url = imagesDirectoryURL.appendingPathComponent(safe)
        try data.write(to: url, options: [.atomic])
        imageCache.cache.removeObject(forKey: safe as NSString)
    }

    /// Reads raw image data for export/import.
    public static func readImageData(fileName: String) -> Data? {
        let safe = sanitisedFileName(fileName)
        guard !safe.isEmpty else { return nil }

        let url = imagesDirectoryURL.appendingPathComponent(safe)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
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

        let safe = sanitisedFileName(trimmed)
        guard !safe.isEmpty else { return nil }

        if let cached = imageCache.cache.object(forKey: safe as NSString) {
            return cached
        }

        let url = imagesDirectoryURL.appendingPathComponent(safe)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }

        imageCache.cache.setObject(img, forKey: safe as NSString, cost: estimatedDecodedByteCount(img))
        return img
    }

    /// Widget-first image loader: exactly one file read + one decode, no multi-image cache.
    ///
    /// Uses ImageIO thumbnailing to downsample at decode time (prevents decoding a large image
    /// into memory when only widget-sized pixels are needed).
    ///
    /// - Note: This intentionally performs **no** caching. SwiftUI/WidgetKit should own the
    ///   lifetime of the current render image.
    public static func loadWidgetImage(fileName: String, maxPixel: Int, debugContext: WWPhotoLogContext? = nil) -> UIImage? {
        let shouldLog = (debugContext != nil)

        let throttleBase: String = {
            guard let debugContext else { return "unknown" }
            let spec = (debugContext.specID ?? "unknown").replacingOccurrences(of: " ", with: "_")
            let fam = (debugContext.family ?? "unknown").replacingOccurrences(of: " ", with: "_")
            let ctx = (debugContext.renderContext ?? "unknown").replacingOccurrences(of: " ", with: "_")
            let tpl = (debugContext.template ?? "unknown").replacingOccurrences(of: " ", with: "_")
            return "\(spec).\(fam).\(ctx).\(tpl)"
        }()

        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.decode",
                    throttleID: "decode.emptyFileName.\(throttleBase)",
                    minInterval: 8.0,
                    context: debugContext
                ) {
                    "loadWidgetImage: empty fileName"
                }
            }
            return nil
        }

        let safe = sanitisedFileName(trimmed)
        guard !safe.isEmpty else {
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.decode",
                    throttleID: "decode.emptySanitised.\(throttleBase)",
                    minInterval: 8.0,
                    context: debugContext
                ) {
                    "loadWidgetImage: sanitised fileName empty raw=\(trimmed)"
                }
            }
            return nil
        }

        // Resolve URL inside the App Group container.
        let url = imagesDirectoryURL.appendingPathComponent(safe)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.decode",
                    throttleID: "decode.missing.\(throttleBase)",
                    minInterval: 10.0,
                    context: debugContext
                ) {
                    "loadWidgetImage: file missing file=\(safe)"
                }
            }
            return nil
        }

        let clampedMaxPixel = max(1, maxPixel)
        let t0 = CFAbsoluteTimeGetCurrent()

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false,
        ]

        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.decode",
                    throttleID: "decode.sourceFail.\(throttleBase)",
                    minInterval: 10.0,
                    context: debugContext
                ) {
                    "loadWidgetImage: CGImageSourceCreateWithURL failed file=\(safe)"
                }
            }
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
            if shouldLog {
                WWPhotoDebugLog.appendLazy(
                    category: "photo.decode",
                    throttleID: "decode.thumbFail.\(throttleBase).\(clampedMaxPixel)",
                    minInterval: 10.0,
                    context: debugContext
                ) {
                    "loadWidgetImage: CGImageSourceCreateThumbnailAtIndex failed file=\(safe) max=\(clampedMaxPixel)"
                }
            }
            return nil
        }

        let dtMs = Int(((CFAbsoluteTimeGetCurrent() - t0) * 1000.0).rounded())

        if shouldLog {
            WWPhotoDebugLog.appendLazy(
                category: "photo.decode",
                throttleID: "decode.ok.\(throttleBase).\(clampedMaxPixel)",
                minInterval: 30.0,
                context: debugContext
            ) {
                "decoded file=\(safe) px=\(cgImage.width)x\(cgImage.height) max=\(clampedMaxPixel) dt=\(dtMs)ms"
            }
        }

        #if DEBUG
        print("[WWWidgetImage] file=\(safe) px=\(cgImage.width)x\(cgImage.height) max=\(clampedMaxPixel) dt=\(dtMs)ms")
        #endif

        return UIImage(cgImage: cgImage)
    }

    public static func deleteImage(fileName: String) {
        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let safe = sanitisedFileName(trimmed)
        guard !safe.isEmpty else { return }

        let url = imagesDirectoryURL.appendingPathComponent(safe)
        try? FileManager.default.removeItem(at: url)
        imageCache.cache.removeObject(forKey: safe as NSString)
    }

    public static func listImageFileNames() -> [String] {
        ensureImagesDirectoryExists()
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: imagesDirectoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return urls.map(\.lastPathComponent).sorted()
        } catch {
            return []
        }
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
