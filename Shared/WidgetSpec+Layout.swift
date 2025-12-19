//
//  WidgetSpec+Layout.swift
//  WidgetWeaver
//
//  Created by Conor on 12/17/25.
//

import SwiftUI

public enum LayoutAxisToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case vertical
    case horizontal

    public var id: String { rawValue }

    public var axis: Axis {
        switch self {
        case .vertical: return .vertical
        case .horizontal: return .horizontal
        }
    }

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

    public var alignment: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .centre: return .center
        case .trailing: return .trailing
        }
    }

    public var displayName: String {
        switch self {
        case .leading: return "Leading"
        case .centre: return "Centre"
        case .trailing: return "Trailing"
        }
    }
}

public enum LayoutTemplateToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case classic
    case hero
    case poster
    case weather

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .hero: return "Hero"
        case .poster: return "Poster"
        case .weather: return "Weather"
        }
    }
}

public struct LayoutSpec: Codable, Hashable, Sendable {
    public var template: LayoutTemplateToken
    public var axis: LayoutAxisToken
    public var alignment: LayoutAlignmentToken

    public var spacing: Double
    public var primaryLineLimitSmall: Int
    public var primaryLineLimit: Int
    public var secondaryLineLimitSmall: Int
    public var secondaryLineLimit: Int

    public var showsAccentBar: Bool

    public init(
        template: LayoutTemplateToken,
        axis: LayoutAxisToken,
        alignment: LayoutAlignmentToken,
        spacing: Double,
        primaryLineLimitSmall: Int,
        primaryLineLimit: Int,
        secondaryLineLimitSmall: Int,
        secondaryLineLimit: Int,
        showsAccentBar: Bool
    ) {
        self.template = template
        self.axis = axis
        self.alignment = alignment
        self.spacing = spacing
        self.primaryLineLimitSmall = primaryLineLimitSmall
        self.primaryLineLimit = primaryLineLimit
        self.secondaryLineLimitSmall = secondaryLineLimitSmall
        self.secondaryLineLimit = secondaryLineLimit
        self.showsAccentBar = showsAccentBar
    }

    public static var defaultLayout: LayoutSpec {
        LayoutSpec(
            template: .classic,
            axis: .vertical,
            alignment: .leading,
            spacing: 12,
            primaryLineLimitSmall: 2,
            primaryLineLimit: 3,
            secondaryLineLimitSmall: 1,
            secondaryLineLimit: 2,
            showsAccentBar: true
        )
    }
}
