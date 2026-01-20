//
//  WidgetWeaverClockDesignConfig.swift
//  WidgetWeaver
//
//  Created by . . on 1/18/26.
//

import Foundation

/// Saved-design configuration for the `.clockIcon` layout template.
///
/// Intentionally string-backed to keep the schema stable and forward-compatible.
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

// MARK: - Clock (Designer) funnel metrics (App Group)

/// Lightweight metrics persisted in the App Group for:
/// - tracking which Clock (Designer) designs were created via the clock funnel
/// - detecting when one of those designs is later applied to a widget instance
///
/// De-duplication is keyed by design UUID so widget timeline refreshes do not inflate counts.
public enum WidgetWeaverClockDesignerMetrics {
    // Designs created via the clock funnel (UUID strings).
    private static let createdDesignIDsKey = "widgetweaver.clockDesigner.createdDesignIDs"

    // Count of created designs that were later observed as applied to a widget instance.
    private static let appliedCountKey = "widgetweaver.clockDesigner.applied.count"
    private static let appliedLastKey = "widgetweaver.clockDesigner.applied.last"
    private static let appliedLastDesignIDKey = "widgetweaver.clockDesigner.applied.last.designID"

    // Per-design de-dup marker.
    private static let appliedDesignPrefix = "widgetweaver.clockDesigner.applied.designID."

    public static func recordCreatedDesignID(_ id: UUID, now: Date = Date(), maxStored: Int = 200) {
        let defaults = AppGroup.userDefaults
        let idString = id.uuidString

        var ids = defaults.stringArray(forKey: createdDesignIDsKey) ?? []
        ids = ids.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }

        // Keep the most-recent occurrence at the end.
        ids.removeAll(where: { $0.caseInsensitiveCompare(idString) == .orderedSame })
        ids.append(idString)

        if maxStored > 0 && ids.count > maxStored {
            ids = Array(ids.suffix(maxStored))
        }

        defaults.set(ids, forKey: createdDesignIDsKey)

        // `now` is accepted to keep the call-site stable for future expansion.
        _ = now
    }

    /// Records a single “applied” event for a design created via the clock funnel.
    ///
    /// Returns `true` if an applied event was recorded; returns `false` if the design is not tracked
    /// or has already been recorded.
    @discardableResult
    public static func recordAppliedIfNeeded(designID: UUID, now: Date = Date()) -> Bool {
        let defaults = AppGroup.userDefaults
        let idString = designID.uuidString

        let tracked = Set((defaults.stringArray(forKey: createdDesignIDsKey) ?? []).map { $0.lowercased() })
        guard tracked.contains(idString.lowercased()) else { return false }

        let markerKey = appliedDesignPrefix + idString
        if defaults.bool(forKey: markerKey) { return false }

        defaults.set(true, forKey: markerKey)
        defaults.set(now, forKey: appliedLastKey)
        defaults.set(idString, forKey: appliedLastDesignIDKey)
        defaults.set(defaults.integer(forKey: appliedCountKey) + 1, forKey: appliedCountKey)

        return true
    }
}
