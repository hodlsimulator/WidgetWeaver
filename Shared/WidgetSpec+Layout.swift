//
//  WidgetSpec+Layout.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

public enum LayoutTemplateToken: String, CaseIterable, Codable, Hashable, Sendable {
    case classic
    case hero
    case poster
}

public enum LayoutAxisToken: String, CaseIterable, Codable, Hashable, Sendable {
    case vertical
    case horizontal
}

public enum LayoutAlignmentToken: String, CaseIterable, Codable, Hashable, Sendable {
    case leading
    case centre
    case trailing
}

public struct LayoutSpec: Hashable, Codable, Sendable {
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
            showsAccentBar: true,
            axis: .vertical,
            alignment: .leading,
            spacing: 8,
            primaryLineLimitSmall: 1,
            primaryLineLimit: 2,
            secondaryLineLimitSmall: 1,
            secondaryLineLimit: 2
        )
    }
}

public extension LayoutAlignmentToken {
    /// American spelling convenience.
    static var center: LayoutAlignmentToken { .centre }
}
