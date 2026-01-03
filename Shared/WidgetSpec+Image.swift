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

// MARK: - Smart Photo metadata

public struct PixelSize: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    public func normalised() -> PixelSize {
        PixelSize(width: max(1, width), height: max(1, height))
    }
}

/// A rectangle in normalised 0...1 space, with origin at the top-left.
public struct NormalisedRect: Codable, Hashable, Sendable {
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

    public func normalised() -> NormalisedRect {
        func clamp01(_ v: Double) -> Double { min(1.0, max(0.0, v)) }

        let nx = clamp01(x)
        let ny = clamp01(y)
        var nw = max(0.0, clamp01(width))
        var nh = max(0.0, clamp01(height))

        if nx + nw > 1.0 {
            nw = max(0.0, 1.0 - nx)
        }
        if ny + nh > 1.0 {
            nh = max(0.0, 1.0 - ny)
        }

        // Avoid degenerate rects which can cause downstream crop failures.
        if nw == 0.0 { nw = min(1.0, 0.0001) }
        if nh == 0.0 { nh = min(1.0, 0.0001) }

        return NormalisedRect(x: nx, y: ny, width: nw, height: nh)
    }
}

public struct SmartPhotoVariantSpec: Codable, Hashable, Sendable {
    public var renderFileName: String
    public var cropRect: NormalisedRect
    public var pixelSize: PixelSize

    public init(renderFileName: String, cropRect: NormalisedRect, pixelSize: PixelSize) {
        self.renderFileName = renderFileName
        self.cropRect = cropRect
        self.pixelSize = pixelSize
    }

    public func normalised() -> SmartPhotoVariantSpec {
        SmartPhotoVariantSpec(
            renderFileName: SmartPhotoSpec.sanitisedFileName(renderFileName),
            cropRect: cropRect.normalised(),
            pixelSize: pixelSize.normalised()
        )
    }
}

public struct SmartPhotoSpec: Codable, Hashable, Sendable {
    public var masterFileName: String

    public var small: SmartPhotoVariantSpec?
    public var medium: SmartPhotoVariantSpec?
    public var large: SmartPhotoVariantSpec?

    public var algorithmVersion: Int
    public var preparedAt: Date

    public init(
        masterFileName: String,
        small: SmartPhotoVariantSpec?,
        medium: SmartPhotoVariantSpec?,
        large: SmartPhotoVariantSpec?,
        algorithmVersion: Int,
        preparedAt: Date
    ) {
        self.masterFileName = masterFileName
        self.small = small
        self.medium = medium
        self.large = large
        self.algorithmVersion = algorithmVersion
        self.preparedAt = preparedAt
    }

    public func normalised() -> SmartPhotoSpec {
        SmartPhotoSpec(
            masterFileName: Self.sanitisedFileName(masterFileName),
            small: small?.normalised(),
            medium: medium?.normalised(),
            large: large?.normalised(),
            algorithmVersion: max(0, algorithmVersion),
            preparedAt: preparedAt
        )
    }

    public static func sanitisedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        return String(last.prefix(256))
    }
}

// MARK: - Image spec

public struct ImageSpec: Hashable, Codable, Sendable {
    public var fileName: String
    public var contentMode: ImageContentModeToken
    public var height: Double
    public var cornerRadius: Double

    /// Optional smart photo payload (master + per-family renders).
    /// - Backwards compatible: older stored specs will not contain this key.
    public var smartPhoto: SmartPhotoSpec?

    public init(
        fileName: String,
        contentMode: ImageContentModeToken = .fill,
        height: Double = 120,
        cornerRadius: Double = 16,
        smartPhoto: SmartPhotoSpec? = nil
    ) {
        self.fileName = fileName
        self.contentMode = contentMode
        self.height = height
        self.cornerRadius = cornerRadius
        self.smartPhoto = smartPhoto
    }

    public func normalised() -> ImageSpec {
        var s = self

        // Trim + strip any path components (defensive against imported specs).
        let trimmed = s.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        s.fileName = String(last.prefix(256))

        // Keep values in a sane range.
        s.height = s.height.clamped(to: 0...512)
        s.cornerRadius = s.cornerRadius.clamped(to: 0...128)

        s.smartPhoto = s.smartPhoto?.normalised()

        return s
    }

    /// Base fileName + smart master + all render variants, sanitised and de-duped.
    public func allReferencedFileNames() -> [String] {
        var set = Set<String>()

        func insert(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let last = (trimmed as NSString).lastPathComponent
            let safe = String(last.prefix(256))
            guard !safe.isEmpty else { return }
            set.insert(safe)
        }

        insert(fileName)

        if let sp = smartPhoto {
            insert(sp.masterFileName)
            if let v = sp.small { insert(v.renderFileName) }
            if let v = sp.medium { insert(v.renderFileName) }
            if let v = sp.large { insert(v.renderFileName) }
        }

        return Array(set).sorted()
    }

    #if canImport(WidgetKit)
    public func fileNameForFamily(_ family: WidgetFamily) -> String {
        if let sp = smartPhoto {
            let candidate: String?

            switch family {
            case .systemSmall:
                candidate = sp.small?.renderFileName
            case .systemMedium:
                candidate = sp.medium?.renderFileName
            case .systemLarge:
                candidate = sp.large?.renderFileName
            default:
                candidate = nil
            }

            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let last = (trimmed as NSString).lastPathComponent
                return String(last.prefix(256))
            }
        }

        let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        return String(last.prefix(256))
    }
    #endif

    // MARK: Codable compatibility (older specs may omit newer keys)

    private enum CodingKeys: String, CodingKey {
        case fileName
        case contentMode
        case height
        case cornerRadius

        // Older key name used by an earlier schema.
        case crop

        // New optional payload.
        case smartPhoto
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

        let smart = try? c.decode(SmartPhotoSpec.self, forKey: .smartPhoto)

        self.init(
            fileName: fileName,
            contentMode: mode,
            height: height,
            cornerRadius: cornerRadius,
            smartPhoto: smart
        )

        self = self.normalised()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(fileName, forKey: .fileName)
        try c.encode(contentMode, forKey: .contentMode)
        try c.encode(height, forKey: .height)
        try c.encode(cornerRadius, forKey: .cornerRadius)

        if let smartPhoto {
            try c.encode(smartPhoto, forKey: .smartPhoto)
        }

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
    func loadUIImageFromAppGroup(family: WidgetFamily) -> UIImage? {
        AppGroup.loadUIImage(fileName: fileNameForFamily(family))
    }
    #endif
}
#endif
