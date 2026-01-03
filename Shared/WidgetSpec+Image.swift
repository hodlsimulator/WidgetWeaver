//
//  WidgetSpec+Image.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(WidgetKit)
import WidgetKit
#endif

public enum ImageContentModeToken: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fill
    case fit

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        }
    }
}

/// Backwards-compatible alias used by older specs/code.
public typealias ImageCropToken = ImageContentModeToken

// MARK: - Smart Photo (auto-crop + per-family renders)

/// A unit rectangle in normalised image coordinates, origin at top-left.
/// Values are clamped into 0...1 during normalisation.
public struct WidgetWeaverNormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self = normalised()
    }

    public func normalised() -> WidgetWeaverNormalizedRect {
        var r = self

        // Clamp origin and size to sane bounds.
        r.x = r.x.clamped(to: 0...1)
        r.y = r.y.clamped(to: 0...1)
        r.width = r.width.clamped(to: 0...1)
        r.height = r.height.clamped(to: 0...1)

        // Ensure width/height do not overflow beyond 1.0.
        if r.x + r.width > 1 { r.width = max(0, 1 - r.x) }
        if r.y + r.height > 1 { r.height = max(0, 1 - r.y) }

        // Avoid degenerate rects.
        let minSize: Double = 0.0001
        if r.width < minSize { r.width = minSize }
        if r.height < minSize { r.height = minSize }

        return r
    }
}

public struct WidgetWeaverSmartPhotoVariant: Codable, Hashable, Sendable {
    public var renderFileName: String
    public var cropRect: WidgetWeaverNormalizedRect
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public init(renderFileName: String, cropRect: WidgetWeaverNormalizedRect, pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
        self.renderFileName = renderFileName
        self.cropRect = cropRect
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self = normalised()
    }

    public func normalised() -> WidgetWeaverSmartPhotoVariant {
        var v = self

        let trimmed = v.renderFileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        v.renderFileName = String(last.prefix(256))

        v.cropRect = v.cropRect.normalised()

        if let w = v.pixelWidth { v.pixelWidth = max(1, w) }
        if let h = v.pixelHeight { v.pixelHeight = max(1, h) }

        return v
    }
}

public struct WidgetWeaverSmartPhotoSpec: Codable, Hashable, Sendable {
    public static let currentAlgorithmVersion: Int = 1

    public var algorithmVersion: Int
    public var preparedAt: Date

    /// A larger “master” photo used to regenerate crops later without re-importing.
    public var masterFileName: String

    public var small: WidgetWeaverSmartPhotoVariant?
    public var medium: WidgetWeaverSmartPhotoVariant?
    public var large: WidgetWeaverSmartPhotoVariant?

    public init(
        algorithmVersion: Int = WidgetWeaverSmartPhotoSpec.currentAlgorithmVersion,
        preparedAt: Date = Date(),
        masterFileName: String,
        small: WidgetWeaverSmartPhotoVariant? = nil,
        medium: WidgetWeaverSmartPhotoVariant? = nil,
        large: WidgetWeaverSmartPhotoVariant? = nil
    ) {
        self.algorithmVersion = algorithmVersion
        self.preparedAt = preparedAt
        self.masterFileName = masterFileName
        self.small = small
        self.medium = medium
        self.large = large
        self = normalised()
    }

    public func normalised() -> WidgetWeaverSmartPhotoSpec {
        var s = self

        let trimmed = s.masterFileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        s.masterFileName = String(last.prefix(256))

        s.algorithmVersion = max(0, s.algorithmVersion)

        if let v = s.small?.normalised() { s.small = v }
        if let v = s.medium?.normalised() { s.medium = v }
        if let v = s.large?.normalised() { s.large = v }

        return s
    }

    public func allFileNames() -> [String] {
        var out: [String] = []
        let m = masterFileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !m.isEmpty { out.append(m) }
        if let s = small?.renderFileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !s.isEmpty { out.append(s) }
        if let m = medium?.renderFileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !m.isEmpty { out.append(m) }
        if let l = large?.renderFileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), !l.isEmpty { out.append(l) }
        return out
    }

    #if canImport(WidgetKit)
    public func renderFileName(for family: WidgetFamily) -> String? {
        switch family {
        case .systemSmall: return small?.renderFileName
        case .systemMedium: return medium?.renderFileName
        case .systemLarge: return large?.renderFileName
        default: return medium?.renderFileName ?? small?.renderFileName ?? large?.renderFileName
        }
    }
    #endif
}

public struct ImageSpec: Hashable, Codable, Sendable {
    public var fileName: String
    public var contentMode: ImageContentModeToken
    public var height: Double
    public var cornerRadius: Double

    /// Optional metadata + per-family renders for Smart Photo.
    public var smartPhoto: WidgetWeaverSmartPhotoSpec?

    public init(
        fileName: String,
        contentMode: ImageContentModeToken = .fill,
        height: Double = 120,
        cornerRadius: Double = 16,
        smartPhoto: WidgetWeaverSmartPhotoSpec? = nil
    ) {
        self.fileName = fileName
        self.contentMode = contentMode
        self.height = height
        self.cornerRadius = cornerRadius
        self.smartPhoto = smartPhoto?.normalised()
    }

    public func normalised() -> ImageSpec {
        var s = self

        // Trim + strip any path components (defensive against imported specs).
        let trimmed = s.fileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        s.fileName = String(last.prefix(256))

        // Keep values in a sane range.
        s.height = s.height.clamped(to: 0...512)
        s.cornerRadius = s.cornerRadius.clamped(to: 0...128)

        if let sp = s.smartPhoto?.normalised() {
            if sp.masterFileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                s.smartPhoto = nil
            } else {
                s.smartPhoto = sp
            }
        } else {
            s.smartPhoto = nil
        }

        return s
    }

    public func allReferencedFileNames() -> [String] {
        var set = Set<String>()

        let base = fileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        if !base.isEmpty { set.insert(base) }

        if let smart = smartPhoto {
            for name in smart.allFileNames() {
                let trimmed = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if !trimmed.isEmpty { set.insert(trimmed) }
            }
        }

        return Array(set).sorted()
    }

    // MARK: Codable compatibility (older specs may omit newer keys)

    private enum CodingKeys: String, CodingKey {
        case fileName
        case contentMode
        case height
        case cornerRadius
        case smartPhoto

        // Older key name used by an earlier schema.
        case crop
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let fileName = (try? c.decode(String.self, forKey: .fileName)) ?? ""

        let mode =
            (try? c.decode(ImageContentModeToken.self, forKey: .contentMode))
            ?? (try? c.decode(ImageContentModeToken.self, forKey: .crop))
            ?? .fill

        let height = (try? c.decode(Double.self, forKey: .height)) ?? 120
        let cornerRadius = (try? c.decode(Double.self, forKey: .cornerRadius)) ?? 16
        let smartPhoto = (try? c.decodeIfPresent(WidgetWeaverSmartPhotoSpec.self, forKey: .smartPhoto)) ?? nil

        self.init(
            fileName: fileName,
            contentMode: mode,
            height: height,
            cornerRadius: cornerRadius,
            smartPhoto: smartPhoto
        )
        self = self.normalised()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(fileName, forKey: .fileName)
        try c.encode(contentMode, forKey: .contentMode)
        try c.encode(height, forKey: .height)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encodeIfPresent(smartPhoto, forKey: .smartPhoto)

        // Backwards compatibility for older readers.
        try c.encode(contentMode, forKey: .crop)
    }
}

#if canImport(UIKit)
public extension ImageSpec {
    func loadUIImageFromAppGroup() -> UIImage? {
        AppGroup.loadUIImage(fileName: fileName)
    }

    #if canImport(WidgetKit)
    func loadUIImageFromAppGroup(for family: WidgetFamily) -> UIImage? {
        if let smart = smartPhoto?.renderFileName(for: family) {
            let trimmed = smart.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            if !trimmed.isEmpty, let img = AppGroup.loadUIImage(fileName: trimmed) {
                return img
            }
        }
        return AppGroup.loadUIImage(fileName: fileName)
    }
    #endif
}
#endif
