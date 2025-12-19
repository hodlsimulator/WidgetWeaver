//
//  WidgetSpec+Style.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import SwiftUI

// MARK: - Style

public struct StyleSpec: Hashable, Codable, Sendable {
    public var padding: Double
    public var cornerRadius: Double

    public var background: BackgroundToken

    /// Optional overlay painted above `background` (and above a banner image, if present).
    public var backgroundOverlay: BackgroundToken
    public var backgroundOverlayOpacity: Double
    public var backgroundGlowEnabled: Bool

    public var accent: AccentToken

    public var nameTextStyle: TextStyleToken
    public var primaryTextStyle: TextStyleToken
    public var secondaryTextStyle: TextStyleToken

    /// Default symbol point size used by some templates.
    public var symbolSize: Double

    /// Scales the built-in Weather template's typography + spacing.
    /// 1.0 is the default.
    public var weatherScale: Double


    public init(
        padding: Double = 16,
        cornerRadius: Double = 18,
        background: BackgroundToken = .subtleMaterial,
        backgroundOverlay: BackgroundToken = .plain,
        backgroundOverlayOpacity: Double = 0,
        backgroundGlowEnabled: Bool = false,
        accent: AccentToken = .blue,
        nameTextStyle: TextStyleToken = .caption,
        primaryTextStyle: TextStyleToken = .title3,
        secondaryTextStyle: TextStyleToken = .caption2,
        symbolSize: Double = 34,
        weatherScale: Double = 1.0
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.background = background
        self.backgroundOverlay = backgroundOverlay
        self.backgroundOverlayOpacity = backgroundOverlayOpacity
        self.backgroundGlowEnabled = backgroundGlowEnabled
        self.accent = accent
        self.nameTextStyle = nameTextStyle
        self.primaryTextStyle = primaryTextStyle
        self.secondaryTextStyle = secondaryTextStyle
        self.symbolSize = symbolSize
        self.weatherScale = weatherScale
    }

    public func normalised() -> StyleSpec {
        StyleSpec(
            padding: max(0, padding),
            cornerRadius: max(0, cornerRadius),
            background: background,
            backgroundOverlay: backgroundOverlay,
            backgroundOverlayOpacity: max(0, min(1, backgroundOverlayOpacity)),
            backgroundGlowEnabled: backgroundGlowEnabled,
            accent: accent,
            nameTextStyle: nameTextStyle,
            primaryTextStyle: primaryTextStyle,
            secondaryTextStyle: secondaryTextStyle,
            symbolSize: max(0, symbolSize),
            weatherScale: max(0.6, min(1.4, weatherScale))
        )
    }

    private enum CodingKeys: String, CodingKey {
        case padding
        case cornerRadius
        case background
        case backgroundOverlay
        case backgroundOverlayOpacity
        case backgroundGlowEnabled
        case accent
        case nameTextStyle
        case primaryTextStyle
        case secondaryTextStyle
        case symbolSize
        case weatherScale
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = StyleSpec.defaultStyle

        self.padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? defaults.padding
        self.cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? defaults.cornerRadius
        self.background = try c.decodeIfPresent(BackgroundToken.self, forKey: .background) ?? defaults.background
        self.backgroundOverlay = try c.decodeIfPresent(BackgroundToken.self, forKey: .backgroundOverlay) ?? defaults.backgroundOverlay
        self.backgroundOverlayOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOverlayOpacity) ?? defaults.backgroundOverlayOpacity
        self.backgroundGlowEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundGlowEnabled) ?? defaults.backgroundGlowEnabled
        self.accent = try c.decodeIfPresent(AccentToken.self, forKey: .accent) ?? defaults.accent
        self.nameTextStyle = try c.decodeIfPresent(TextStyleToken.self, forKey: .nameTextStyle) ?? defaults.nameTextStyle
        self.primaryTextStyle = try c.decodeIfPresent(TextStyleToken.self, forKey: .primaryTextStyle) ?? defaults.primaryTextStyle
        self.secondaryTextStyle = try c.decodeIfPresent(TextStyleToken.self, forKey: .secondaryTextStyle) ?? defaults.secondaryTextStyle
        self.symbolSize = try c.decodeIfPresent(Double.self, forKey: .symbolSize) ?? defaults.symbolSize
        self.weatherScale = try c.decodeIfPresent(Double.self, forKey: .weatherScale) ?? defaults.weatherScale
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(padding, forKey: .padding)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(background, forKey: .background)
        try c.encode(backgroundOverlay, forKey: .backgroundOverlay)
        try c.encode(backgroundOverlayOpacity, forKey: .backgroundOverlayOpacity)
        try c.encode(backgroundGlowEnabled, forKey: .backgroundGlowEnabled)
        try c.encode(accent, forKey: .accent)
        try c.encode(nameTextStyle, forKey: .nameTextStyle)
        try c.encode(primaryTextStyle, forKey: .primaryTextStyle)
        try c.encode(secondaryTextStyle, forKey: .secondaryTextStyle)
        try c.encode(symbolSize, forKey: .symbolSize)
        try c.encode(weatherScale, forKey: .weatherScale)
    }

    public static var defaultStyle: StyleSpec {
        StyleSpec(
            padding: 16,
            cornerRadius: 20,
            background: .subtleMaterial,
            backgroundOverlay: .plain,
            backgroundOverlayOpacity: 0,
            backgroundGlowEnabled: false,
            accent: .blue,
            nameTextStyle: .caption,
            primaryTextStyle: .title3,
            secondaryTextStyle: .caption2,
            symbolSize: 34,
            weatherScale: 1.0
        )
    }
}

public extension BackgroundToken {
    /// Convenience alias used by overlay APIs.
    static var none: BackgroundToken { .plain }
}

public enum BackgroundToken: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case plain
    case accentGlow
    case radialGlow
    case solidAccent
    case subtleMaterial
    case aurora
    case sunset
    case midnight
    case candy

    public var id: String { rawValue }

    public var uiLabel: String {
        switch self {
        case .plain: return "Plain"
        case .accentGlow: return "Accent Glow"
        case .radialGlow: return "Radial Glow"
        case .solidAccent: return "Solid Accent"
        case .subtleMaterial: return "Subtle Material"
        case .aurora: return "Aurora"
        case .sunset: return "Sunset"
        case .midnight: return "Midnight"
        case .candy: return "Candy"
        }
    }

    /// Backwards-compatible alias.
    public var displayName: String { uiLabel }

    public func shapeStyle(accent: Color) -> AnyShapeStyle {
        switch self {
        case .plain:
            return AnyShapeStyle(Color(.systemBackground))

        case .accentGlow:
            return AnyShapeStyle(
                LinearGradient(
                    colors: [accent.opacity(0.35), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        case .radialGlow:
            return AnyShapeStyle(
                RadialGradient(
                    colors: [
                        accent.opacity(0.42),
                        accent.opacity(0.12),
                        .clear,
                    ],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 320
                )
            )

        case .solidAccent:
            return AnyShapeStyle(accent.opacity(0.18))

        case .subtleMaterial:
            return AnyShapeStyle(.ultraThinMaterial)

        case .aurora:
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: accent.opacity(0.45), location: 0.0),
                        .init(color: Color.green.opacity(0.25), location: 0.55),
                        .init(color: Color.blue.opacity(0.25), location: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        case .sunset:
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color.orange.opacity(0.35), location: 0.0),
                        .init(color: Color.pink.opacity(0.25), location: 0.5),
                        .init(color: Color.purple.opacity(0.25), location: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        case .midnight:
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.35), location: 0.0),
                        .init(color: Color.blue.opacity(0.25), location: 0.6),
                        .init(color: Color.purple.opacity(0.25), location: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

        case .candy:
            return AnyShapeStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color.pink.opacity(0.35), location: 0.0),
                        .init(color: Color.blue.opacity(0.25), location: 0.55),
                        .init(color: Color.mint.opacity(0.25), location: 1.0),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

public enum AccentToken: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case blue
    case purple
    case pink
    case orange
    case green
    case teal
    case red
    case yellow
    case gray
    case indigo

    public var id: String { rawValue }

    public var uiLabel: String {
        switch self {
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .green: return "Green"
        case .teal: return "Teal"
        case .red: return "Red"
        case .yellow: return "Yellow"
        case .gray: return "Grey"
        case .indigo: return "Indigo"
        }
    }

    /// Backwards-compatible alias.
    public var displayName: String { uiLabel }

    public func color() -> Color {
        switch self {
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .teal: return .teal
        case .red: return .red
        case .yellow: return .yellow
        case .gray: return .gray
        case .indigo: return .indigo
        }
    }

    /// Backwards-compatible alias.
    public var swiftUIColor: Color { color() }
}

public enum TextStyleToken: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case automatic
    case caption2
    case caption
    case footnote
    case subheadline
    case body
    case headline
    case title3
    case title2
    case title

    public var id: String { rawValue }

    public var uiLabel: String {
        switch self {
        case .automatic: return "Automatic"
        case .caption2: return "Caption 2"
        case .caption: return "Caption"
        case .footnote: return "Footnote"
        case .subheadline: return "Subheadline"
        case .body: return "Body"
        case .headline: return "Headline"
        case .title3: return "Title 3"
        case .title2: return "Title 2"
        case .title: return "Title"
        }
    }

    /// Backwards-compatible alias.
    public var displayName: String { uiLabel }

    /// Convenience for places that just need a `Font` and don't care about fallback behaviour.
    public var font: Font { font(fallback: .body) }

    public func font(fallback: Font) -> Font {
        switch self {
        case .automatic: return fallback
        case .caption2: return .caption2
        case .caption: return .caption
        case .footnote: return .footnote
        case .subheadline: return .subheadline
        case .body: return .body
        case .headline: return .headline
        case .title3: return .title3
        case .title2: return .title2
        case .title: return .title
        }
    }
}
