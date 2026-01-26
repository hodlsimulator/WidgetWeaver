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
        "mint",
        "orchid",
        "sunset",
        "ember",
        "graphite"
    ]

    public static let defaultTheme: String = "classic"

    public static var supportedFaces: Set<String> {
        Set(WidgetWeaverClockFaceToken.allCases.map { $0.rawValue })
    }


    /// Default face for newly created Clock (Designer) configurations.
    public static let defaultFace: String = WidgetWeaverClockFaceToken.icon.rawValue

    /// Legacy default face used when older saved designs do not persist `face`.
    public static let legacyDefaultFace: String = WidgetWeaverClockFaceToken.ceramic.rawValue

    public var theme: String
        public var face: String

        /// Optional override for the Icon face dial fill.
        ///
        /// Stored as a raw string so unknown future tokens can be ignored safely.
        public var iconDialColourToken: String?

        /// Optional override for the Icon face seconds-hand colour.
        ///
        /// Stored as a raw string so unknown future tokens can be ignored safely.
        public var iconSecondHandColourToken: String?

        public init(
            theme: String = Self.defaultTheme,
            face: String = Self.defaultFace,
            iconDialColourToken: String? = nil,
            iconSecondHandColourToken: String? = nil
        ) {
            self.theme = theme
            self.face = face
            self.iconDialColourToken = iconDialColourToken
            self.iconSecondHandColourToken = iconSecondHandColourToken
            self = self.normalised()
        }

    public static var `default`: WidgetWeaverClockDesignConfig {
        WidgetWeaverClockDesignConfig(theme: Self.defaultTheme, face: Self.defaultFace)
    }

    public static var legacyDefault: WidgetWeaverClockDesignConfig {
        WidgetWeaverClockDesignConfig(theme: Self.defaultTheme, face: Self.legacyDefaultFace)
    }

    public func normalised() -> WidgetWeaverClockDesignConfig {
        var c = self

        let cleanedTheme = c.theme
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if Self.supportedThemes.contains(cleanedTheme) {
            c.theme = cleanedTheme
        } else {
            c.theme = Self.defaultTheme
        }

        c.face = WidgetWeaverClockFaceToken.canonical(from: c.face).rawValue

        if !Self.supportedFaces.contains(c.face) {
            c.face = Self.defaultFace
        }

        if let token = WidgetWeaverClockIconDialColourToken.canonical(from: c.iconDialColourToken) {
                    c.iconDialColourToken = token.rawValue
                } else {
                    c.iconDialColourToken = nil
                }

                if let token = WidgetWeaverClockSecondHandColourToken.canonical(from: c.iconSecondHandColourToken) {
                    c.iconSecondHandColourToken = token.rawValue
                } else {
                    c.iconSecondHandColourToken = nil
                }


        // Step 5B: Constrain seconds-hand colours to curated matching sets (Icon face only).
        if WidgetWeaverClockFaceToken.canonical(from: c.face) == .icon {
            let dialToken = WidgetWeaverClockIconDialColourToken.effectiveToken(
                themeRaw: c.theme,
                overrideRaw: c.iconDialColourToken
            )

            let compatibility = dialToken.secondHandCompatibility

            let currentToken: WidgetWeaverClockSecondHandColourToken = {
                if let token = WidgetWeaverClockSecondHandColourToken.canonical(from: c.iconSecondHandColourToken) {
                    return token
                }
                return .red
            }()

            if !compatibility.allowed.contains(currentToken) {
                let recommended = compatibility.recommended
                c.iconSecondHandColourToken = (recommended == .red) ? nil : recommended.rawValue
            } else if currentToken == .red {
                // Keep "red" represented as the default (nil) so selection stays stable in the editor.
                c.iconSecondHandColourToken = nil
            }
        }

        return c
    }

    private enum CodingKeys: String, CodingKey {
            case theme
            case face
            case iconDialColourToken
            case iconSecondHandColourToken
        }

    public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)

            let theme = (try? c.decode(String.self, forKey: .theme)) ?? Self.defaultTheme
            let face = (try? c.decodeIfPresent(String.self, forKey: .face)) ?? Self.legacyDefaultFace

            let iconDialColourToken = (try? c.decodeIfPresent(String.self, forKey: .iconDialColourToken)) ?? nil
            let iconSecondHandColourToken = (try? c.decodeIfPresent(String.self, forKey: .iconSecondHandColourToken)) ?? nil

            self.init(
                theme: theme,
                face: face,
                iconDialColourToken: iconDialColourToken,
                iconSecondHandColourToken: iconSecondHandColourToken
            )
        }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(theme, forKey: .theme)
        try c.encode(face, forKey: .face)
        try c.encodeIfPresent(iconDialColourToken, forKey: .iconDialColourToken)
                try c.encodeIfPresent(iconSecondHandColourToken, forKey: .iconSecondHandColourToken)
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
