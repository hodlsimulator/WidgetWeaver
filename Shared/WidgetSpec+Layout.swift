//
//  WidgetSpec+Layout.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI

// MARK: - Layout

public struct LayoutSpec: Codable, Hashable {
    public var axis: LayoutAxisToken
    public var alignment: LayoutAlignmentToken
    public var spacing: Double

    public var primaryLineLimitSmall: Int
    public var primaryLineLimit: Int
    public var secondaryLineLimit: Int

    public static let defaultLayout = LayoutSpec(
        axis: .vertical,
        alignment: .leading,
        spacing: 8,
        primaryLineLimitSmall: 1,
        primaryLineLimit: 2,
        secondaryLineLimit: 2
    )

    public init(
        axis: LayoutAxisToken = .vertical,
        alignment: LayoutAlignmentToken = .leading,
        spacing: Double = 8,
        primaryLineLimitSmall: Int = 1,
        primaryLineLimit: Int = 2,
        secondaryLineLimit: Int = 2
    ) {
        self.axis = axis
        self.alignment = alignment
        self.spacing = spacing
        self.primaryLineLimitSmall = primaryLineLimitSmall
        self.primaryLineLimit = primaryLineLimit
        self.secondaryLineLimit = secondaryLineLimit
    }

    public func normalised() -> LayoutSpec {
        var l = self
        l.spacing = l.spacing.clamped(to: 0...32)
        l.primaryLineLimitSmall = l.primaryLineLimitSmall.clamped(to: 1...8)
        l.primaryLineLimit = l.primaryLineLimit.clamped(to: 1...10)
        l.secondaryLineLimit = l.secondaryLineLimit.clamped(to: 1...10)
        return l
    }
}

public enum LayoutAxisToken: String, Codable, CaseIterable, Hashable, Identifiable {
    case vertical
    case horizontal

    public var id: String { rawValue }
}

public enum LayoutAlignmentToken: String, Codable, CaseIterable, Hashable, Identifiable {
    case leading
    case center
    case trailing

    public var id: String { rawValue }

    public var swiftUIAlignment: Alignment {
        switch self {
        case .leading: return .topLeading
        case .center: return .top
        case .trailing: return .topTrailing
        }
    }
}
