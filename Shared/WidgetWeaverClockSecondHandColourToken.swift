//
//  WidgetWeaverClockSecondHandColourToken.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import Foundation

/// Curated tokens for the Clock "Icon" face seconds-hand colour.
///
/// Notes:
/// - Stable raw strings so persisted configs remain forward-compatible.
/// - Colour resolution must flow through the shared appearance resolver/palette.
/// - Step 5 constrains these tokens based on the selected dial colour.
public enum WidgetWeaverClockSecondHandColourToken: String, CaseIterable, Codable, Hashable, Sendable {
    case red = "red"
    case orange = "orange"
    case ocean = "ocean"
    case mint = "mint"
    case orchid = "orchid"
    case sunset = "sunset"
    case graphite = "graphite"
    case white = "white"

    /// Returns a canonical token for a raw persisted string.
    ///
    /// - Returns: `nil` if the input is missing/empty/unknown (meaning: no override).
    public static func canonical(from raw: String?) -> WidgetWeaverClockSecondHandColourToken? {
        guard let raw else { return nil }

        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !cleaned.isEmpty else { return nil }

        return WidgetWeaverClockSecondHandColourToken(rawValue: cleaned)
    }

    /// Human-friendly name for presentation in the UI.
    public var displayName: String {
        switch self {
        case .red:
            return "Red"
        case .orange:
            return "Orange"
        case .ocean:
            return "Ocean"
        case .mint:
            return "Mint"
        case .orchid:
            return "Orchid"
        case .sunset:
            return "Sunset"
        case .graphite:
            return "Graphite"
        case .white:
            return "White"
        }
    }

    /// Sort index used to keep pickers stable and scalable.
    public var pickerSortIndex: Int {
        switch self {
        case .red: return 0
        case .orange: return 1
        case .ocean: return 2
        case .mint: return 3
        case .orchid: return 4
        case .sunset: return 5
        case .graphite: return 6
        case .white: return 7
        }
    }

    /// Tokens ordered for presentation in pickers and swatch grids.
    public static var orderedForPicker: [WidgetWeaverClockSecondHandColourToken] {
        Self.allCases.sorted { $0.pickerSortIndex < $1.pickerSortIndex }
    }
}
