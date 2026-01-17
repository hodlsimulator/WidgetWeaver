//
//  WidgetWeaverClockDesignConfig.swift
//  WidgetWeaver
//
//  Created by . . on 1/17/26.
//

import Foundation

// MARK: - Clock design configuration (schema-only)

/// Configuration for the `.clockIcon` layout template.
///
/// Notes:
/// - This is intentionally minimal (v1): a single theme token.
/// - Theme values are stable string tokens (lowercased) to keep future migrations simple.
public struct WidgetWeaverClockDesignConfig: Codable, Hashable, Sendable {
    /// Supported theme identifier tokens.
    public static let supportedThemes: Set<String> = [
        "classic",
        "ocean",
        "graphite",
    ]

    /// Default theme token used when missing/invalid.
    public static let defaultTheme: String = "classic"

    /// The selected theme token (e.g. "classic", "ocean", "graphite").
    public var theme: String

    public init(theme: String = WidgetWeaverClockDesignConfig.defaultTheme) {
        self.theme = theme
        self = self.normalised()
    }

    public static var `default`: WidgetWeaverClockDesignConfig {
        WidgetWeaverClockDesignConfig()
    }

    public func normalised() -> WidgetWeaverClockDesignConfig {
        var c = self
        let cleaned = c.theme
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if Self.supportedThemes.contains(cleaned) {
            c.theme = cleaned
        } else {
            c.theme = Self.defaultTheme
        }

        return c
    }

    // MARK: Codable compatibility (future-proofing)

    private enum CodingKeys: String, CodingKey {
        case theme
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let theme = (try? c.decode(String.self, forKey: .theme)) ?? Self.defaultTheme
        self.init(theme: theme)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(theme, forKey: .theme)
    }
}
