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

// MARK: - Icon seconds-hand compatibility (curated)

public extension WidgetWeaverClockIconDialColourToken {

    /// Curated compatibility constraints for pairing a seconds-hand colour with an Icon dial family.
    ///
    /// These constraints intentionally limit options to avoid clashing combinations.
    struct SecondHandCompatibility: Hashable, Sendable {
        public let allowed: Set<WidgetWeaverClockSecondHandColourToken>
        public let recommended: WidgetWeaverClockSecondHandColourToken

        public init(
            allowed: Set<WidgetWeaverClockSecondHandColourToken>,
            recommended: WidgetWeaverClockSecondHandColourToken
        ) {
            self.allowed = allowed
            self.recommended = recommended
        }
    }

    /// Returns the effective dial family used for Icon compatibility:
    /// - `overrideRaw` if present and recognised
    /// - otherwise the current theme (scheme) when it matches a dial family
    /// - otherwise `.classic`
    static func effectiveToken(
        themeRaw: String,
        overrideRaw: String?
    ) -> WidgetWeaverClockIconDialColourToken {
        if let override = WidgetWeaverClockIconDialColourToken.canonical(from: overrideRaw) {
            return override
        }

        if let theme = WidgetWeaverClockIconDialColourToken.canonical(from: themeRaw) {
            return theme
        }

        return .classic
    }

    /// Compatibility rule for the dial family.
    var secondHandCompatibility: SecondHandCompatibility {
        switch self {
        case .classic:
            return SecondHandCompatibility(
                allowed: [.red, .orange, .ocean, .graphite, .white],
                recommended: .red
            )

        case .ocean:
            return SecondHandCompatibility(
                allowed: [.red, .ocean, .orange, .graphite, .white],
                recommended: .ocean
            )

        case .mint:
            return SecondHandCompatibility(
                allowed: [.red, .mint, .orange, .graphite, .white],
                recommended: .mint
            )

        case .orchid:
            return SecondHandCompatibility(
                allowed: [.red, .orchid, .sunset, .graphite, .white],
                recommended: .orchid
            )

        case .sunset:
            return SecondHandCompatibility(
                allowed: [.red, .sunset, .orchid, .graphite, .white],
                recommended: .sunset
            )

        case .ember:
            return SecondHandCompatibility(
                allowed: [.red, .orange, .sunset, .graphite, .white],
                recommended: .orange
            )

        case .graphite:
            return SecondHandCompatibility(
                allowed: [.red, .graphite, .orange, .ocean, .white],
                recommended: .graphite
            )
        }
    }
}
