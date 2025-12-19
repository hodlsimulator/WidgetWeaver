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

public struct ImageSpec: Hashable, Codable, Sendable {
    public var fileName: String
    public var crop: ImageCropToken

    public init(fileName: String, crop: ImageCropToken = .fill) {
        self.fileName = fileName
        self.crop = crop
    }

    public func normalised() -> ImageSpec {
        var s = self

        // Trim + strip any path components (defensive against imported specs).
        let trimmed = s.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        s.fileName = String(last.prefix(256))

        return s
    }

    // MARK: Codable compatibility (older specs may omit newer keys)

    private enum CodingKeys: String, CodingKey {
        case fileName
        case crop
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let fileName = (try? c.decode(String.self, forKey: .fileName)) ?? ""
        let crop = (try? c.decode(ImageCropToken.self, forKey: .crop)) ?? .fill

        self.init(fileName: fileName, crop: crop)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fileName, forKey: .fileName)
        try c.encode(crop, forKey: .crop)
    }
}

public enum ImageCropToken: String, CaseIterable, Codable, Hashable, Sendable {
    case fill
    case fit
}

#if canImport(UIKit)
public extension ImageSpec {
    func loadUIImageFromAppGroup() -> UIImage? {
        AppGroup.loadUIImage(fileName: fileName)
    }
}
#endif
