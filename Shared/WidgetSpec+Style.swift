//
//  WidgetSpec+Style.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI

// MARK: - Style

public struct StyleSpec: Codable, Hashable, Sendable {
    public var padding: Double
    public var cornerRadius: Double
    public var background: BackgroundToken
    public var accent: AccentToken
    public var nameTextStyle: TextStyleToken
    public var primaryTextStyle: TextStyleToken
    public var secondaryTextStyle: TextStyleToken

    public static let defaultStyle = StyleSpec(
        padding: 16,
        cornerRadius: 20,
        background: .accentGlow,
        accent: .blue,
        nameTextStyle: .automatic,
        primaryTextStyle: .automatic,
        secondaryTextStyle: .automatic
    )

    public init(
        padding: Double = 16,
        cornerRadius: Double = 20,
        background: BackgroundToken = .accentGlow,
        accent: AccentToken = .blue,
        nameTextStyle: TextStyleToken = .automatic,
        primaryTextStyle: TextStyleToken = .automatic,
        secondaryTextStyle: TextStyleToken = .automatic
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.background = background
        self.accent = accent
        self.nameTextStyle = nameTextStyle
        self.primaryTextStyle = primaryTextStyle
        self.secondaryTextStyle = secondaryTextStyle
    }

    public func normalised() -> StyleSpec {
        var s = self
        s.padding = s.padding.clamped(to: 0...32)
        s.cornerRadius = s.cornerRadius.clamped(to: 0...44)
        return s
    }
}

public enum BackgroundToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case plain
    case accentGlow
    case subtleMaterial

    public var id: String { rawValue }

    public func shapeStyle(accent: Color) -> AnyShapeStyle {
        switch self {
        case .plain:
            return AnyShapeStyle(.background)
        case .accentGlow:
            return AnyShapeStyle(
                .linearGradient(
                    colors: [accent.opacity(0.35), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        case .subtleMaterial:
            return AnyShapeStyle(.ultraThinMaterial)
        }
    }
}

public enum AccentToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case blue
    case teal
    case green
    case orange
    case pink
    case purple
    case red
    case gray

    public var id: String { rawValue }

    public var swiftUIColor: Color {
        switch self {
        case .blue: return .blue
        case .teal: return .teal
        case .green: return .green
        case .orange: return .orange
        case .pink: return .pink
        case .purple: return .purple
        case .red: return .red
        case .gray: return .gray
        }
    }
}

public enum TextStyleToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case automatic
    case caption2
    case caption
    case footnote
    case subheadline
    case headline
    case title3
    case title2

    public var id: String { rawValue }

    public func font(fallback: Font) -> Font {
        switch self {
        case .automatic: return fallback
        case .caption2: return .caption2
        case .caption: return .caption
        case .footnote: return .footnote
        case .subheadline: return .subheadline
        case .headline: return .headline
        case .title3: return .title3
        case .title2: return .title2
        }
    }
}
