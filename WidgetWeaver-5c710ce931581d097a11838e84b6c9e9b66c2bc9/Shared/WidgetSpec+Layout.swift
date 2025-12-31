//
//  WidgetSpec+Layout.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI

// MARK: - Layout

public struct LayoutSpec: Codable, Hashable, Sendable {
    public var template: LayoutTemplateToken
    public var showsAccentBar: Bool
    public var axis: LayoutAxisToken
    public var alignment: LayoutAlignmentToken
    public var spacing: Double
    public var primaryLineLimitSmall: Int
    public var primaryLineLimit: Int
    public var secondaryLineLimitSmall: Int
    public var secondaryLineLimit: Int

    public static let defaultLayout = LayoutSpec(
        template: .classic,
        showsAccentBar: true,
        axis: .vertical,
        alignment: .leading,
        spacing: 8,
        primaryLineLimitSmall: 1,
        primaryLineLimit: 2,
        secondaryLineLimitSmall: 1,
        secondaryLineLimit: 2
    )

    public init(
        template: LayoutTemplateToken = .classic,
        showsAccentBar: Bool = true,
        axis: LayoutAxisToken = .vertical,
        alignment: LayoutAlignmentToken = .leading,
        spacing: Double = 8,
        primaryLineLimitSmall: Int = 1,
        primaryLineLimit: Int = 2,
        secondaryLineLimitSmall: Int = 1,
        secondaryLineLimit: Int = 2
    ) {
        self.template = template
        self.showsAccentBar = showsAccentBar
        self.axis = axis
        self.alignment = alignment
        self.spacing = spacing
        self.primaryLineLimitSmall = primaryLineLimitSmall
        self.primaryLineLimit = primaryLineLimit
        self.secondaryLineLimitSmall = secondaryLineLimitSmall
        self.secondaryLineLimit = secondaryLineLimit
    }

    public func normalised() -> LayoutSpec {
        var l = self
        l.spacing = l.spacing.clamped(to: 0...32)
        l.primaryLineLimitSmall = l.primaryLineLimitSmall.clamped(to: 1...8)
        l.primaryLineLimit = l.primaryLineLimit.clamped(to: 1...10)
        l.secondaryLineLimitSmall = l.secondaryLineLimitSmall.clamped(to: 1...8)
        l.secondaryLineLimit = l.secondaryLineLimit.clamped(to: 1...10)

        // Small limits should not exceed the corresponding non-small limits.
        l.primaryLineLimitSmall = min(l.primaryLineLimitSmall, l.primaryLineLimit)
        l.secondaryLineLimitSmall = min(l.secondaryLineLimitSmall, l.secondaryLineLimit)
        return l
    }

    // MARK: Codable compatibility (older specs missing newer keys)

    private enum CodingKeys: String, CodingKey {
        case template
        case showsAccentBar
        case axis
        case alignment
        case spacing
        case primaryLineLimitSmall
        case primaryLineLimit
        case secondaryLineLimitSmall
        case secondaryLineLimit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.template = (try? c.decode(LayoutTemplateToken.self, forKey: .template)) ?? .classic
        self.showsAccentBar = (try? c.decode(Bool.self, forKey: .showsAccentBar)) ?? true
        self.axis = (try? c.decode(LayoutAxisToken.self, forKey: .axis)) ?? .vertical
        self.alignment = (try? c.decode(LayoutAlignmentToken.self, forKey: .alignment)) ?? .leading
        self.spacing = (try? c.decode(Double.self, forKey: .spacing)) ?? 8
        self.primaryLineLimitSmall = (try? c.decode(Int.self, forKey: .primaryLineLimitSmall)) ?? 1
        self.primaryLineLimit = (try? c.decode(Int.self, forKey: .primaryLineLimit)) ?? 2

        let decodedSecondary = (try? c.decode(Int.self, forKey: .secondaryLineLimit)) ?? 2
        self.secondaryLineLimit = decodedSecondary

        // Older specs only had `secondaryLineLimit`. Default small to 1 (or less if decodedSecondary < 1).
        let decodedSecondarySmall = try? c.decode(Int.self, forKey: .secondaryLineLimitSmall)
        self.secondaryLineLimitSmall = decodedSecondarySmall ?? max(1, min(decodedSecondary, 1))

        self = self.normalised()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(template, forKey: .template)
        try c.encode(showsAccentBar, forKey: .showsAccentBar)
        try c.encode(axis, forKey: .axis)
        try c.encode(alignment, forKey: .alignment)
        try c.encode(spacing, forKey: .spacing)
        try c.encode(primaryLineLimitSmall, forKey: .primaryLineLimitSmall)
        try c.encode(primaryLineLimit, forKey: .primaryLineLimit)
        try c.encode(secondaryLineLimitSmall, forKey: .secondaryLineLimitSmall)
        try c.encode(secondaryLineLimit, forKey: .secondaryLineLimit)
    }
}

public enum LayoutTemplateToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case classic
    case hero
    case poster
    case weather

    // NEW:
    case nextUpCalendar

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .hero: return "Hero"
        case .poster: return "Poster"
        case .weather: return "Weather"
        case .nextUpCalendar: return "Next Up (Calendar)"
        }
    }
}

public enum LayoutAxisToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case vertical
    case horizontal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        }
    }
}

public enum LayoutAlignmentToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case leading
    case centre
    case trailing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .leading: return "Leading"
        case .centre: return "Centre"
        case .trailing: return "Trailing"
        }
    }

    /// HorizontalAlignment for VStack/HStack.
    public var alignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .centre: return .center
        case .trailing: return .trailing
        }
    }

    /// Alignment for frames/overlays.
    public var swiftUIAlignment: Alignment {
        switch self {
        case .leading: return .topLeading
        case .centre: return .top
        case .trailing: return .topTrailing
        }
    }

    // Accept both "center" and "centre" when decoding older/newer specs.
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? LayoutAlignmentToken.leading.rawValue
        switch raw.lowercased() {
        case "leading": self = .leading
        case "centre", "center": self = .centre
        case "trailing": self = .trailing
        default: self = .leading
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(self.rawValue)
    }
}

public extension LayoutAlignmentToken {
    /// American spelling convenience.
    static var center: LayoutAlignmentToken { .centre }
}
