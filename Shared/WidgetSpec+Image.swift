//
//  WidgetSpec+Image.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI

// MARK: - Image component (v0)

public struct ImageSpec: Codable, Hashable {
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
        var i = self
        i.fileName = i.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        i.height = i.height.clamped(to: 40...240)
        i.cornerRadius = i.cornerRadius.clamped(to: 0...44)
        return i
    }
}

public enum ImageContentModeToken: String, Codable, CaseIterable, Hashable, Identifiable {
    case fill
    case fit

    public var id: String { rawValue }

    public var swiftUIContentMode: ContentMode {
        switch self {
        case .fill: return .fill
        case .fit: return .fit
        }
    }
}
