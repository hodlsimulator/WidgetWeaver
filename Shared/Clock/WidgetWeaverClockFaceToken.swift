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
    /// Legacy face (4 numerals).
    ///
    /// This remains the backwards-compatibility default when a saved design does not
    /// explicitly persist a face.
    case ceramic

    /// Primary face (12 numerals).
    ///
    /// This is the default for newly created clock designs.
    case icon

    /// Returns the canonical face token for a raw persisted string.
    ///
    /// Unknown, missing, or empty inputs fall back to `.ceramic` to preserve legacy designs.
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

    /// Sort index used to keep face pickers stable and scalable as more faces are added.
    public var pickerSortIndex: Int {
        switch self {
        case .icon:
            return 0
        case .ceramic:
            return 1
        }
    }

    /// Face tokens ordered for presentation in pickers and catalogue UIs.
    public static var orderedForPicker: [WidgetWeaverClockFaceToken] {
        Self.allCases.sorted { $0.pickerSortIndex < $1.pickerSortIndex }
    }
}
