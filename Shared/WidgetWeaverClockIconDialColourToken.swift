//
//  WidgetWeaverClockIconDialColourToken.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import Foundation

/// Curated face-colour tokens for the Clock "Icon" face dial fill.
///
/// Notes:
/// - Stable raw strings so persisted configs remain forward-compatible.
/// - The raw token does NOT directly map to UI colours here; colour resolution must flow through
///   the shared appearance resolver/palette so the editor preview and widget extension cannot drift.
public enum WidgetWeaverClockIconDialColourToken: String, CaseIterable, Codable, Hashable, Sendable {
    /// Steel blue (default Classic dial family).
    case classic = "classic"

    /// Ocean blue.
    case ocean = "ocean"

    /// Mint green.
    case mint = "mint"

    /// Orchid purple.
    case orchid = "orchid"

    /// Sunset pink.
    case sunset = "sunset"

    /// Ember red-brown.
    case ember = "ember"

    /// Graphite grey.
    case graphite = "graphite"

    /// Returns a canonical token for a raw persisted string.
    ///
    /// - Returns: `nil` if the input is missing/empty/unknown (meaning: no override).
    public static func canonical(from raw: String?) -> WidgetWeaverClockIconDialColourToken? {
        guard let raw else { return nil }

        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !cleaned.isEmpty else { return nil }

        return WidgetWeaverClockIconDialColourToken(rawValue: cleaned)
    }

    /// Human-friendly name for presentation in the UI.
    public var displayName: String {
        switch self {
        case .classic:
            return "Classic"
        case .ocean:
            return "Ocean"
        case .mint:
            return "Mint"
        case .orchid:
            return "Orchid"
        case .sunset:
            return "Sunset"
        case .ember:
            return "Ember"
        case .graphite:
            return "Graphite"
        }
    }

    /// Sort index used to keep the picker stable and intentional.
    public var pickerSortIndex: Int {
        switch self {
        case .classic: return 0
        case .ocean: return 1
        case .mint: return 2
        case .orchid: return 3
        case .sunset: return 4
        case .ember: return 5
        case .graphite: return 6
        }
    }

    /// Tokens ordered for presentation in pickers and swatch grids.
    public static var orderedForPicker: [WidgetWeaverClockIconDialColourToken] {
        Self.allCases.sorted { $0.pickerSortIndex < $1.pickerSortIndex }
    }
}
