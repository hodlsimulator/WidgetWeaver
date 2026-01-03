//
//  WidgetSpec+Image.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(UIKit)
import UIKit
#endif

public enum ImageContentModeToken: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case fill
    case fit

    public var id: String { rawValue }
}

/// Reserved for future (e.g. storing a crop identifier or params).
public typealias ImageCropToken = String

// MARK: - Smart Photo

public struct WWNormalizedRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    #if canImport(CoreGraphics)
    public init(_ rect: CGRect) {
        self.x = Double(rect.origin.x)
        self.y = Double(rect.origin.y)
        self.width = Double(rect.size.width)
        self.height = Double(rect.size.height)
    }

    public var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
    #endif

    public func normalised() -> WWNormalizedRect {
        func clamp(_ v: Double) -> Double { min(max(v, 0.0), 1.0) }

        var out = self
        out.x = clamp(out.x)
        out.y = clamp(out.y)
        out.width = clamp(out.width)
        out.height = clamp(out.height)

        if out.width <= 0 { out.width = 1 }
        if out.height <= 0 { out.height = 1 }

        if out.x + out.width > 1 { out.x = max(0, 1 - out.width) }
        if out.y + out.height > 1 { out.y = max(0, 1 - out.height) }

        return out
    }
}

public struct WWSmartPhotoVariant: Codable, Hashable, Sendable {
    public var renderFileName: String
    public var cropRect: WWNormalizedRect
    public var pixelWidth: Int?
    public var pixelHeight: Int?

    public init(renderFileName: String, cropRect: WWNormalizedRect, pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
        self.renderFileName = renderFileName
        self.cropRect = cropRect
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    public func normalised() -> WWSmartPhotoVariant {
        var out = self
        out.renderFileName = String(renderFileName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
        out.cropRect = cropRect.normalised()

        if let w = pixelWidth { out.pixelWidth = max(1, min(w, 10_000)) }
        if let h = pixelHeight { out.pixelHeight = max(1, min(h, 10_000)) }

        return out
    }
}

public struct WWSmartPhotoSpec: Codable, Hashable, Sendable {
    public static let currentAlgorithmVersion: Int = 1

    public var algorithmVersion: Int
    public var masterFileName: String
    public var small: WWSmartPhotoVariant?
    public var medium: WWSmartPhotoVariant?
    public var large: WWSmartPhotoVariant?
    public var preparedAt: Date

    public init(
        algorithmVersion: Int = WWSmartPhotoSpec.currentAlgorithmVersion,
        masterFileName: String,
        small: WWSmartPhotoVariant?,
        medium: WWSmartPhotoVariant?,
        large: WWSmartPhotoVariant?,
        preparedAt: Date = Date()
    ) {
        self.algorithmVersion = algorithmVersion
        self.masterFileName = masterFileName
        self.small = small
        self.medium = medium
        self.large = large
        self.preparedAt = preparedAt
    }

    public func normalised() -> WWSmartPhotoSpec {
        var out = self

        out.algorithmVersion = max(1, min(out.algorithmVersion, 999))
        out.masterFileName = String(masterFileName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))

        out.small = out.small?.normalised()
        out.medium = out.medium?.normalised()
        out.large = out.large?.normalised()

        return out
    }

    public func allFileNames() -> [String] {
        var names: [String] = []

        let master = masterFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !master.isEmpty { names.append(master) }

        if let s = small?.renderFileName.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { names.append(s) }
        if let m = medium?.renderFileName.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { names.append(m) }
        if let l = large?.renderFileName.trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty { names.append(l) }

        return names
    }

    #if canImport(WidgetKit)
    public func renderFileName(for family: WidgetFamily) -> String? {
        switch family {
        case .systemSmall: return small?.renderFileName
        case .systemMedium: return medium?.renderFileName
        case .systemLarge: return large?.renderFileName
        default: return medium?.renderFileName
        }
    }
    #endif
}

// MARK: - Image Spec

public struct ImageSpec: Codable, Hashable, Sendable {
    public var fileName: String
    public var contentMode: ImageContentModeToken
    public var height: Double
    public var cornerRadius: Double
    public var crop: ImageCropToken?
    public var smartPhoto: WWSmartPhotoSpec?

    public init(
        fileName: String,
        contentMode: ImageContentModeToken,
        height: Double,
        cornerRadius: Double,
        crop: ImageCropToken? = nil,
        smartPhoto: WWSmartPhotoSpec? = nil
    ) {
        self.fileName = fileName
        self.contentMode = contentMode
        self.height = height
        self.cornerRadius = cornerRadius
        self.crop = crop
        self.smartPhoto = smartPhoto
    }

    public func normalised() -> ImageSpec {
        var out = self

        let trimmed = out.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        out.fileName = String(last.prefix(256))

        out.height = max(1, min(out.height, 10_000))
        out.cornerRadius = max(0, min(out.cornerRadius, 1_000))

        if let crop = out.crop {
            let c = crop.trimmingCharacters(in: .whitespacesAndNewlines)
            out.crop = c.isEmpty ? nil : String(c.prefix(512))
        }

        out.smartPhoto = out.smartPhoto?.normalised()

        return out
    }

    public func allReferencedFileNames() -> [String] {
        var names: [String] = []

        let base = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !base.isEmpty { names.append(base) }

        if let smartPhoto {
            names.append(contentsOf: smartPhoto.allFileNames())
        }

        // De-dupe while preserving order.
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    #if canImport(WidgetKit)
    public func fileNameForRender(family: WidgetFamily) -> String {
        if let smart = smartPhoto, let fn = smart.renderFileName(for: family) {
            let trimmed = fn.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return fileName
    }
    #endif

    enum CodingKeys: String, CodingKey {
        case fileName
        case contentMode
        case height
        case cornerRadius
        case crop
        case smartPhoto
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        contentMode = try c.decodeIfPresent(ImageContentModeToken.self, forKey: .contentMode) ?? .fill
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 120
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 16
        crop = try c.decodeIfPresent(ImageCropToken.self, forKey: .crop)
        smartPhoto = try c.decodeIfPresent(WWSmartPhotoSpec.self, forKey: .smartPhoto)

        self = self.normalised()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(fileName, forKey: .fileName)
        try c.encode(contentMode, forKey: .contentMode)
        try c.encode(height, forKey: .height)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encodeIfPresent(crop, forKey: .crop)
        try c.encodeIfPresent(smartPhoto, forKey: .smartPhoto)
    }

    #if canImport(UIKit)
    public func loadUIImageFromAppGroup() -> UIImage? {
        AppGroup.loadUIImage(fileName: fileName)
    }

    #if canImport(WidgetKit)
    public func loadUIImageFromAppGroup(for family: WidgetFamily) -> UIImage? {
        AppGroup.loadUIImage(fileName: fileNameForRender(family: family))
    }
    #endif
    #endif
}
