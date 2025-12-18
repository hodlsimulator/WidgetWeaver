//
//  WidgetSpec.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

public struct WidgetSpec: Codable, Hashable, Identifiable {
    // Bump when the schema changes.
    public static let currentVersion: Int = 6

    public var version: Int
    public var id: UUID
    public var name: String
    public var primaryText: String
    public var secondaryText: String?
    public var updatedAt: Date

    public var symbol: SymbolSpec?
    public var image: ImageSpec?
    public var layout: LayoutSpec
    public var style: StyleSpec

    public var actionBar: WidgetActionBarSpec?

    /// Optional per-size overrides.
    /// Convention in this milestone:
    /// - Medium is the base spec fields.
    /// - Small + Large live in `matchedSet` (Medium override is typically nil).
    public var matchedSet: WidgetSpecMatchedSet?

    public init(
        version: Int = WidgetSpec.currentVersion,
        id: UUID = UUID(),
        name: String,
        primaryText: String,
        secondaryText: String?,
        updatedAt: Date = Date(),
        symbol: SymbolSpec? = nil,
        image: ImageSpec? = nil,
        layout: LayoutSpec = .defaultLayout,
        style: StyleSpec = .defaultStyle,
        actionBar: WidgetActionBarSpec? = nil,
        matchedSet: WidgetSpecMatchedSet? = nil
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.updatedAt = updatedAt
        self.symbol = symbol
        self.image = image
        self.layout = layout
        self.style = style
        self.actionBar = actionBar
        self.matchedSet = matchedSet
    }

    public static func defaultSpec() -> WidgetSpec {
        WidgetSpec(
            name: "WidgetWeaver",
            primaryText: "Hello",
            secondaryText: "Saved spec → widget",
            updatedAt: Date(),
            symbol: SymbolSpec(
                name: "sparkles",
                size: 18,
                weight: .semibold,
                renderingMode: .hierarchical,
                tint: .accent,
                placement: .beforeName
            ),
            image: nil,
            layout: .defaultLayout,
            style: .defaultStyle,
            matchedSet: nil
        )
    }

    public func normalised() -> WidgetSpec {
        var s = self

        s.version = max(WidgetSpec.currentVersion, s.version)

        let trimmedName = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.name = trimmedName.isEmpty ? "WidgetWeaver" : trimmedName

        let trimmedPrimary = s.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        s.primaryText = trimmedPrimary.isEmpty ? "Hello" : trimmedPrimary

        if let secondary = s.secondaryText?.trimmingCharacters(in: .whitespacesAndNewlines), !secondary.isEmpty {
            s.secondaryText = secondary
        } else {
            s.secondaryText = nil
        }

        if let sym = s.symbol?.normalised() {
            if sym.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s.symbol = nil
            } else {
                s.symbol = sym
            }
        } else {
            s.symbol = nil
        }

        if let img = s.image?.normalised() {
            if img.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                s.image = nil
            } else {
                s.image = img
            }
        } else {
            s.image = nil
        }

        s.layout = s.layout.normalised()
        s.style = s.style.normalised()

        if let bar = s.actionBar?.normalisedOrNil() {
            s.actionBar = bar
        } else {
            s.actionBar = nil
        }

        if let m = s.matchedSet?.normalisedOrNil() {
            s.matchedSet = m
        } else {
            s.matchedSet = nil
        }

        return s
    }

    #if canImport(WidgetKit)
    /// Returns a flat spec suitable for rendering in a specific `WidgetFamily`.
    /// This drops `matchedSet` in the returned value to keep the render path simple.
    ///
    /// Milestone 8: Matched sets are Pro-only. Without Pro, matched variants are ignored.
    public func resolved(for family: WidgetFamily) -> WidgetSpec {
        let base = self.normalised()

        guard
            WidgetWeaverEntitlements.isProUnlocked,
            let variant = base.matchedSet?.variant(for: family)?.normalised()
        else {
            var out = base
            out.matchedSet = nil
            return out
        }

        var out = base
        out.primaryText = variant.primaryText
        out.secondaryText = variant.secondaryText
        out.symbol = variant.symbol
        out.image = variant.image
        out.layout = variant.layout
        out.matchedSet = nil
        return out.normalised()
    }
    #endif

    private enum CodingKeys: String, CodingKey {
        case version
        case id
        case name
        case primaryText
        case secondaryText
        case updatedAt
        case symbol
        case image
        case layout
        case style
        case actionBar
        case matchedSet
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        let id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        let name = (try? c.decode(String.self, forKey: .name)) ?? "WidgetWeaver"
        let primaryText = (try? c.decode(String.self, forKey: .primaryText)) ?? "Hello"
        let secondaryText = try? c.decodeIfPresent(String.self, forKey: .secondaryText)
        let updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
        let symbol = (try? c.decodeIfPresent(SymbolSpec.self, forKey: .symbol)) ?? nil
        let image = (try? c.decodeIfPresent(ImageSpec.self, forKey: .image)) ?? nil
        let layout = (try? c.decode(LayoutSpec.self, forKey: .layout)) ?? .defaultLayout
        let style = (try? c.decode(StyleSpec.self, forKey: .style)) ?? .defaultStyle
        let actionBar = (try? c.decodeIfPresent(WidgetActionBarSpec.self, forKey: .actionBar)) ?? nil
        let matchedSet = (try? c.decodeIfPresent(WidgetSpecMatchedSet.self, forKey: .matchedSet)) ?? nil

        self.init(
            version: version,
            id: id,
            name: name,
            primaryText: primaryText,
            secondaryText: secondaryText,
            updatedAt: updatedAt,
            symbol: symbol,
            image: image,
            layout: layout,
            style: style,
            actionBar: actionBar,
            matchedSet: matchedSet
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(version, forKey: .version)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(primaryText, forKey: .primaryText)
        try c.encodeIfPresent(secondaryText, forKey: .secondaryText)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(symbol, forKey: .symbol)
        try c.encodeIfPresent(image, forKey: .image)
        try c.encode(layout, forKey: .layout)
        try c.encode(style, forKey: .style)
        try c.encodeIfPresent(actionBar, forKey: .actionBar)
        try c.encodeIfPresent(matchedSet, forKey: .matchedSet)
    }
}


// MARK: - Quick Actions

/// A lightweight spec for interactive widget buttons.
///
/// Notes:
/// - Buttons only show up in the widget (iOS 17+ interactive widgets).
/// - Actions currently target the Pro variable store (App Group).
public struct WidgetActionBarSpec: Codable, Hashable, Sendable {
    public static let maxActions: Int = 2

    public var actions: [WidgetActionSpec]
    public var style: WidgetActionButtonStyleToken

    public init(
        actions: [WidgetActionSpec] = [],
        style: WidgetActionButtonStyleToken = .prominent
    ) {
        self.actions = actions
        self.style = style
    }

    public func normalisedOrNil() -> WidgetActionBarSpec? {
        var out = self

        let cleaned = out.actions.compactMap { $0.normalisedOrNil() }
        out.actions = Array(cleaned.prefix(Self.maxActions))

        if out.actions.isEmpty {
            return nil
        }
        return out
    }
}

public struct WidgetActionSpec: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var systemImage: String?
    public var kind: WidgetActionKindToken
    public var variableKey: String

    /// Used when `kind == .incrementVariable`.
    public var incrementAmount: Int

    /// Used when `kind == .setVariableToNow`.
    public var nowFormat: WidgetNowFormatToken

    public init(
        id: UUID = UUID(),
        title: String,
        systemImage: String? = nil,
        kind: WidgetActionKindToken,
        variableKey: String,
        incrementAmount: Int = 1,
        nowFormat: WidgetNowFormatToken = .iso8601
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.variableKey = variableKey
        self.incrementAmount = incrementAmount
        self.nowFormat = nowFormat
    }

    public func normalisedOrNil() -> WidgetActionSpec? {
        var a = self

        let key = WidgetWeaverVariableStore.canonicalKey(a.variableKey)
        guard !key.isEmpty else { return nil }
        a.variableKey = key

        let t = a.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty {
            switch a.kind {
            case .incrementVariable:
                a.title = "+1"
            case .setVariableToNow:
                a.title = "Done"
            }
        } else {
            a.title = String(t.prefix(24))
        }

        if let img = a.systemImage?.trimmingCharacters(in: .whitespacesAndNewlines), !img.isEmpty {
            a.systemImage = String(img.prefix(64))
        } else {
            a.systemImage = nil
        }

        a.incrementAmount = a.incrementAmount.clamped(to: -99...99)
        if a.incrementAmount == 0 {
            a.incrementAmount = 1
        }

        return a
    }
}

public enum WidgetActionKindToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case incrementVariable
    case setVariableToNow

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .incrementVariable: return "Increment Variable"
        case .setVariableToNow: return "Set Variable to Now"
        }
    }
}

public enum WidgetActionButtonStyleToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case prominent
    case subtle

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .prominent: return "Prominent"
        case .subtle: return "Subtle"
        }
    }
}

public enum WidgetNowFormatToken: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case iso8601
    case unixSeconds
    case unixMilliseconds
    case dateOnly
    case timeOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .iso8601: return "ISO 8601"
        case .unixSeconds: return "Unix (Seconds)"
        case .unixMilliseconds: return "Unix (Milliseconds)"
        case .dateOnly: return "Date (YYYY-MM-DD)"
        case .timeOnly: return "Time (HH:mm)"
        }
    }
}

// MARK: - Matched Set

public struct WidgetSpecMatchedSet: Codable, Hashable {
    public var small: WidgetSpecVariant?
    public var medium: WidgetSpecVariant?
    public var large: WidgetSpecVariant?

    public init(
        small: WidgetSpecVariant? = nil,
        medium: WidgetSpecVariant? = nil,
        large: WidgetSpecVariant? = nil
    ) {
        self.small = small
        self.medium = medium
        self.large = large
    }

    public func normalisedOrNil() -> WidgetSpecMatchedSet? {
        var m = self
        m.small = m.small?.normalised()
        m.medium = m.medium?.normalised()
        m.large = m.large?.normalised()

        if m.small == nil && m.medium == nil && m.large == nil {
            return nil
        }
        return m
    }

    #if canImport(WidgetKit)
    public func variant(for family: WidgetFamily) -> WidgetSpecVariant? {
        switch family {
        case .systemSmall:
            return small
        case .systemMedium:
            return medium
        case .systemLarge:
            return large
        default:
            return medium ?? small ?? large
        }
    }
    #endif
}

public struct WidgetSpecVariant: Codable, Hashable {
    public var primaryText: String
    public var secondaryText: String?
    public var symbol: SymbolSpec?
    public var image: ImageSpec?
    public var layout: LayoutSpec

    public init(
        primaryText: String,
        secondaryText: String?,
        symbol: SymbolSpec?,
        image: ImageSpec?,
        layout: LayoutSpec
    ) {
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.symbol = symbol
        self.image = image
        self.layout = layout
    }

    public static func fromBaseSpec(_ spec: WidgetSpec) -> WidgetSpecVariant {
        let s = spec.normalised()
        return WidgetSpecVariant(
            primaryText: s.primaryText,
            secondaryText: s.secondaryText,
            symbol: s.symbol,
            image: s.image,
            layout: s.layout
        )
    }

    public func normalised() -> WidgetSpecVariant {
        var v = self

        let trimmedPrimary = v.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        v.primaryText = trimmedPrimary.isEmpty ? "Hello" : trimmedPrimary

        if let secondary = v.secondaryText?.trimmingCharacters(in: .whitespacesAndNewlines), !secondary.isEmpty {
            v.secondaryText = secondary
        } else {
            v.secondaryText = nil
        }

        if let sym = v.symbol?.normalised() {
            if sym.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                v.symbol = nil
            } else {
                v.symbol = sym
            }
        } else {
            v.symbol = nil
        }

        if let img = v.image?.normalised() {
            if img.fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                v.image = nil
            } else {
                v.image = img
            }
        } else {
            v.image = nil
        }

        v.layout = v.layout.normalised()
        return v
    }
}
