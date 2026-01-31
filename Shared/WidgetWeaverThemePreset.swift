//
//  WidgetWeaverThemePreset.swift
//  WidgetWeaver
//
//  Created by . . on 1/31/26.
//

import Foundation

/// Curated style presets used by theme selection.
///
/// A theme is a deterministic `StyleSpec` overwrite, layered on top of the existing styling
/// pipeline (`StyleSpec` ⇄ `StyleDraft`).
public struct WidgetWeaverThemePreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let detail: String
    public let style: StyleSpec

    /// Optional Clock (Designer) theme string to apply when the layout template is `.clockIcon`.
    ///
    /// Stored as a raw string to remain consistent with `WidgetWeaverClockDesignConfig`.
    public let clockThemeRaw: String?

    public init(
        id: String,
        displayName: String,
        detail: String,
        style: StyleSpec,
        clockThemeRaw: String? = nil,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        let cleanedID = id
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        precondition(!cleanedID.isEmpty, "Theme preset id must not be empty.", file: file, line: line)

        self.id = cleanedID
        self.displayName = displayName
        self.detail = detail
        self.style = style.normalised()
        self.clockThemeRaw = Self.validatedClockThemeRaw(clockThemeRaw, file: file, line: line)
    }

    private static func validatedClockThemeRaw(
        _ raw: String?,
        file: StaticString,
        line: UInt
    ) -> String? {
        guard let raw else { return nil }

        let cleaned = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        precondition(!cleaned.isEmpty, "clockThemeRaw must not be an empty string.", file: file, line: line)

        // Validate against the canonicalisation behaviour in `WidgetWeaverClockDesignConfig.normalised()`.
        // If an unsupported theme is passed, normalisation falls back to `defaultTheme`.
        let canonicalised = WidgetWeaverClockDesignConfig(
            theme: cleaned,
            face: WidgetWeaverClockDesignConfig.defaultFace
        ).theme

        precondition(
            canonicalised == cleaned,
            "Unsupported clockThemeRaw: \(raw). Supported themes: \(Array(WidgetWeaverClockDesignConfig.supportedThemes).sorted()).",
            file: file,
            line: line
        )

        return canonicalised
    }
}

public enum WidgetWeaverThemeCatalog {
    public static let ordered: [WidgetWeaverThemePreset] = [
        WidgetWeaverThemePreset(
            id: "classic",
            displayName: "Classic",
            detail: "System glass with a calm blue accent.",
            style: StyleSpec.defaultStyle,
            clockThemeRaw: "classic"
        ),
        WidgetWeaverThemePreset(
            id: "ocean-glass",
            displayName: "Ocean Glass",
            detail: "Frosted teal glow with higher contrast text.",
            style: StyleSpec(
                padding: 16,
                cornerRadius: 20,
                background: .subtleMaterial,
                backgroundOverlay: .radialGlow,
                backgroundOverlayOpacity: 0.33,
                backgroundGlowEnabled: true,
                accent: .teal,
                nameTextStyle: .caption2,
                primaryTextStyle: .headline,
                secondaryTextStyle: .caption,
                symbolSize: 34,
                weatherScale: 1.0
            ),
            clockThemeRaw: "ocean"
        ),
        WidgetWeaverThemePreset(
            id: "mint-aurora",
            displayName: "Mint Aurora",
            detail: "Aurora gradient with a fresh, cool accent.",
            style: StyleSpec(
                padding: 16,
                cornerRadius: 20,
                background: .aurora,
                backgroundOverlay: .accentGlow,
                backgroundOverlayOpacity: 0.18,
                backgroundGlowEnabled: true,
                accent: .teal,
                nameTextStyle: .caption2,
                primaryTextStyle: .title3,
                secondaryTextStyle: .footnote,
                symbolSize: 34,
                weatherScale: 1.0
            ),
            clockThemeRaw: "mint"
        ),
        WidgetWeaverThemePreset(
            id: "orchid-pop",
            displayName: "Orchid Pop",
            detail: "Candy gradient with purple emphasis.",
            style: StyleSpec(
                padding: 16,
                cornerRadius: 20,
                background: .candy,
                backgroundOverlay: .radialGlow,
                backgroundOverlayOpacity: 0.22,
                backgroundGlowEnabled: false,
                accent: .purple,
                nameTextStyle: .caption2,
                primaryTextStyle: .title3,
                secondaryTextStyle: .caption2,
                symbolSize: 34,
                weatherScale: 1.0
            ),
            clockThemeRaw: "orchid"
        ),
        WidgetWeaverThemePreset(
            id: "sunset-warmth",
            displayName: "Sunset Warmth",
            detail: "Warm gradients with a bright accent glow.",
            style: StyleSpec(
                padding: 16,
                cornerRadius: 20,
                background: .sunset,
                backgroundOverlay: .accentGlow,
                backgroundOverlayOpacity: 0.20,
                backgroundGlowEnabled: true,
                accent: .orange,
                nameTextStyle: .caption2,
                primaryTextStyle: .title3,
                secondaryTextStyle: .caption2,
                symbolSize: 34,
                weatherScale: 1.0
            ),
            clockThemeRaw: "sunset"
        ),
        WidgetWeaverThemePreset(
            id: "ember-night",
            displayName: "Ember Night",
            detail: "Midnight backdrop with ember-red highlights.",
            style: StyleSpec(
                padding: 16,
                cornerRadius: 20,
                background: .midnight,
                backgroundOverlay: .radialGlow,
                backgroundOverlayOpacity: 0.30,
                backgroundGlowEnabled: true,
                accent: .red,
                nameTextStyle: .caption2,
                primaryTextStyle: .headline,
                secondaryTextStyle: .caption2,
                symbolSize: 34,
                weatherScale: 1.0
            ),
            clockThemeRaw: "ember"
        ),
        WidgetWeaverThemePreset(
            id: "graphite-minimal",
            displayName: "Graphite Minimal",
            detail: "Clean, restrained greys for a minimal look.",
            style: StyleSpec(
                padding: 16,
                cornerRadius: 20,
                background: .subtleMaterial,
                backgroundOverlay: .plain,
                backgroundOverlayOpacity: 0,
                backgroundGlowEnabled: false,
                accent: .gray,
                nameTextStyle: .caption2,
                primaryTextStyle: .headline,
                secondaryTextStyle: .caption2,
                symbolSize: 34,
                weatherScale: 1.0
            ),
            clockThemeRaw: "graphite"
        )
    ]

    public static let defaultPresetID: String = "classic"

    public static func preset(matching id: String) -> WidgetWeaverThemePreset? {
        let cleaned = id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleaned.isEmpty else { return nil }
        return ordered.first(where: { $0.id.lowercased() == cleaned })
    }
}
