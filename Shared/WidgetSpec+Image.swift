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

public struct ImageSpec: Hashable, Codable, Sendable {
    public var fileName: String
    public var contentMode: ImageContentModeToken
    public var height: Double
    public var cornerRadius: Double

    public init(
        fileName: String,
        contentMode: ImageContentModeToken = .fill,
        height: Double = 120,
        cornerRadius: Double = 16
    ) {
        self.fileName = fileName
        self.contentMode = contentMode
        self.height = height
        self.cornerRadius = cornerRadius
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

        return s
    }

    // MARK: Codable compatibility (older specs may omit newer keys)

    private enum CodingKeys: String, CodingKey {
        case fileName
        case contentMode
        case height
        case cornerRadius

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

        self.init(
            fileName: fileName,
            contentMode: mode,
            height: height,
            cornerRadius: cornerRadius
        )
        self = self.normalised()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(fileName, forKey: .fileName)
        try c.encode(contentMode, forKey: .contentMode)
        try c.encode(height, forKey: .height)
        try c.encode(cornerRadius, forKey: .cornerRadius)

        // Backwards compatibility for older readers.
        try c.encode(contentMode, forKey: .crop)
    }
}

#if canImport(UIKit)
public extension ImageSpec {
    func loadUIImageFromAppGroup() -> UIImage? {
        AppGroup.loadUIImage(fileName: fileName)
    }
}
#endif
