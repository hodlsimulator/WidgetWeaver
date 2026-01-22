//
//  WidgetWeaverClockFaceToken.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import Foundation

/// Canonical identifier for the visual clock "face".
///
/// This type is intentionally stable and string-backed so persisted configurations can remain
/// forward-compatible.
public enum WidgetWeaverClockFaceToken: String, CaseIterable, Codable, Hashable, Sendable {
    /// The current shipped face. Treated as the default until other variants are implemented.
    case ceramic

    /// The new "Icon" face.
    case icon

    /// Returns the canonical face token for a raw persisted string.
    ///
    /// Unknown, missing, or empty inputs fall back to `.ceramic`.
    public static func canonical(from raw: String?) -> WidgetWeaverClockFaceToken {
        guard let raw else { return .ceramic }

        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !cleaned.isEmpty else { return .ceramic }

        return WidgetWeaverClockFaceToken(rawValue: cleaned) ?? .ceramic
    }

    /// Human-friendly name for presentation in the UI.
    public var displayName: String {
        switch self {
        case .ceramic:
            return "Ceramic"
        case .icon:
            return "Icon"
        }
    }

    /// Short descriptor that makes the visual difference obvious in pickers.
    public var numeralsDescriptor: String {
        switch self {
        case .ceramic:
            return "4 numerals"
        case .icon:
            return "12 numerals"
        }
    }
}
