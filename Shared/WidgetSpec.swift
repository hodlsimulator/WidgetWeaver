//
//  WidgetSpec.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

public struct WidgetSpec: Codable, Hashable, Identifiable {
    public static let currentVersion: Int = 3

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
        style: StyleSpec = .defaultStyle
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
            style: .defaultStyle
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
        return s
    }

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
            style: style
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
    }
}
