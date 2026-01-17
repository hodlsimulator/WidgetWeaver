//
//  WidgetWeaverClockDesignConfig.swift
//  WidgetWeaver
//
//  Created by . . on 1/17/26.
//

import Foundation

public struct WidgetWeaverClockDesignConfig: Codable, Hashable, Sendable {
    public static let supportedThemes: Set<String> = [
        "classic",
        "ocean",
        "graphite"
    ]

    public static let defaultTheme: String = "classic"

    public var theme: String

    public init(theme: String = Self.defaultTheme) {
        self.theme = theme
        self = self.normalised()
    }

    public static var `default`: WidgetWeaverClockDesignConfig {
        WidgetWeaverClockDesignConfig(theme: Self.defaultTheme)
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
