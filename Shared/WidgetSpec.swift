//
//  WidgetSpec.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI
import WidgetKit

public struct WidgetSpec: Codable, Hashable, Identifiable {
    public var version: Int
    public var id: UUID
    public var name: String
    public var primaryText: String
    public var secondaryText: String?
    public var updatedAt: Date

    public var symbol: SymbolSpec?

    public var layout: LayoutSpec
    public var style: StyleSpec

    public init(
        version: Int = 2,
        id: UUID = UUID(),
        name: String,
        primaryText: String,
        secondaryText: String?,
        updatedAt: Date = Date(),
        symbol: SymbolSpec? = nil,
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
            layout: .defaultLayout,
            style: .defaultStyle
        )
    }

    public func normalised() -> WidgetSpec {
        var s = self

        s.version = max(1, s.version)

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
        try c.encode(layout, forKey: .layout)
        try c.encode(style, forKey: .style)
    }
}

// MARK: - Components (v0)

public struct SymbolSpec: Codable, Hashable {
    public var name: String
    public var size: Double
    public var weight: SymbolWeightToken
    public var renderingMode: SymbolRenderingModeToken
    public var tint: SymbolTintToken
    public var placement: SymbolPlacementToken

    public init(
        name: String,
        size: Double = 18,
        weight: SymbolWeightToken = .regular,
        renderingMode: SymbolRenderingModeToken = .monochrome,
        tint: SymbolTintToken = .accent,
        placement: SymbolPlacementToken = .beforeName
    ) {
        self.name = name
        self.size = size
        self.weight = weight
        self.renderingMode = renderingMode
        self.tint = tint
        self.placement = placement
    }

    public func normalised() -> SymbolSpec {
        var s = self

        s.name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.size = s.size.clamped(to: 8...96)

        return s
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case size
        case weight
        case renderingMode
        case tint
        case placement
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let name = (try? c.decode(String.self, forKey: .name)) ?? ""
        let size = (try? c.decode(Double.self, forKey: .size)) ?? 18
        let weight = (try? c.decode(SymbolWeightToken.self, forKey: .weight)) ?? .regular
        let renderingMode = (try? c.decode(SymbolRenderingModeToken.self, forKey: .renderingMode)) ?? .monochrome
        let tint = (try? c.decode(SymbolTintToken.self, forKey: .tint)) ?? .accent
        let placement = (try? c.decode(SymbolPlacementToken.self, forKey: .placement)) ?? .beforeName

        self.init(
            name: name,
            size: size,
            weight: weight,
            renderingMode: renderingMode,
            tint: tint,
            placement: placement
        )
    }
}

public enum SymbolPlacementToken: String, Codable, Hashable, CaseIterable, Identifiable {
    case beforeName
    case aboveName

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .beforeName: return "Before Name"
        case .aboveName: return "Above Name"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        self = SymbolPlacementToken(rawValue: raw) ?? .beforeName
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum SymbolTintToken: String, Codable, Hashable, CaseIterable, Identifiable {
    case accent
    case primary
    case secondary

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .accent: return "Accent"
        case .primary: return "Primary"
        case .secondary: return "Secondary"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        self = SymbolTintToken(rawValue: raw) ?? .accent
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum SymbolRenderingModeToken: String, Codable, Hashable, CaseIterable, Identifiable {
    case monochrome
    case hierarchical
    case multicolor

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .monochrome: return "Monochrome"
        case .hierarchical: return "Hierarchical"
        case .multicolor: return "Multicolour"
        }
    }

    public var swiftUISymbolRenderingMode: SymbolRenderingMode {
        switch self {
        case .monochrome: return .monochrome
        case .hierarchical: return .hierarchical
        case .multicolor: return .multicolor
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        self = SymbolRenderingModeToken(rawValue: raw) ?? .monochrome
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum SymbolWeightToken: String, Codable, Hashable, CaseIterable, Identifiable {
    case regular
    case medium
    case semibold
    case bold

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        }
    }

    public var fontWeight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        self = SymbolWeightToken(rawValue: raw) ?? .regular
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Layout

public struct LayoutSpec: Codable, Hashable {
    public var axis: LayoutAxisToken
    public var alignment: LayoutAlignmentToken
    public var spacing: Double

    public var showSecondaryInSmall: Bool
    public var primaryLineLimitSmall: Int
    public var primaryLineLimit: Int
    public var secondaryLineLimit: Int

    public init(
        axis: LayoutAxisToken = .vertical,
        alignment: LayoutAlignmentToken = .topLeading,
        spacing: Double = 6,
        showSecondaryInSmall: Bool = false,
        primaryLineLimitSmall: Int = 2,
        primaryLineLimit: Int = 3,
        secondaryLineLimit: Int = 2
    ) {
        self.axis = axis
        self.alignment = alignment
        self.spacing = spacing
        self.showSecondaryInSmall = showSecondaryInSmall
        self.primaryLineLimitSmall = primaryLineLimitSmall
        self.primaryLineLimit = primaryLineLimit
        self.secondaryLineLimit = secondaryLineLimit
    }

    public static var defaultLayout: LayoutSpec { LayoutSpec() }

    public func normalised() -> LayoutSpec {
        var l = self

        l.spacing = l.spacing.clamped(to: 0...32)

        l.primaryLineLimitSmall = l.primaryLineLimitSmall.clamped(to: 1...8)
        l.primaryLineLimit = l.primaryLineLimit.clamped(to: 1...10)
        l.secondaryLineLimit = l.secondaryLineLimit.clamped(to: 1...10)

        return l
    }

    private enum CodingKeys: String, CodingKey {
        case axis
        case alignment
        case spacing
        case showSecondaryInSmall
        case primaryLineLimitSmall
        case primaryLineLimit
        case secondaryLineLimit
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let axis = (try? c.decode(LayoutAxisToken.self, forKey: .axis)) ?? .vertical
        let alignment = (try? c.decode(LayoutAlignmentToken.self, forKey: .alignment)) ?? .topLeading
        let spacing = (try? c.decode(Double.self, forKey: .spacing)) ?? 6

        let showSecondaryInSmall = (try? c.decode(Bool.self, forKey: .showSecondaryInSmall)) ?? false
        let primaryLineLimitSmall = (try? c.decode(Int.self, forKey: .primaryLineLimitSmall)) ?? 2
        let primaryLineLimit = (try? c.decode(Int.self, forKey: .primaryLineLimit)) ?? 3
        let secondaryLineLimit = (try? c.decode(Int.self, forKey: .secondaryLineLimit)) ?? 2

        self.init(
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            showSecondaryInSmall: showSecondaryInSmall,
            primaryLineLimitSmall: primaryLineLimitSmall,
            primaryLineLimit: primaryLineLimit,
            secondaryLineLimit: secondaryLineLimit
        )
    }
}

public enum LayoutAxisToken: String, Codable, Hashable, CaseIterable, Identifiable {
    case vertical
    case horizontal

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .vertical: return "Vertical"
        case .horizontal: return "Horizontal"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        self = LayoutAxisToken(rawValue: raw) ?? .vertical
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum LayoutAlignmentToken: String, Codable, Hashable, CaseIterable, Identifiable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .topLeading: return "Top Leading"
        case .top: return "Top"
        case .topTrailing: return "Top Trailing"
        case .leading: return "Leading"
        case .center: return "Center"
        case .trailing: return "Trailing"
        case .bottomLeading: return "Bottom Leading"
        case .bottom: return "Bottom"
        case .bottomTrailing: return "Bottom Trailing"
        }
    }

    public var swiftUIAlignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        self = LayoutAlignmentToken(rawValue: raw) ?? .topLeading
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Style

public struct StyleSpec: Codable, Hashable {
    public var padding: Double
    public var cornerRadius: Double

    public var background: BackgroundToken
    public var accent: AccentToken

    public var nameTextStyle: TextStyleToken
    public var primaryTextStyle: TextStyleToken
    public var secondaryTextStyle: TextStyleToken

    public init(
        padding: Double = 12,
        cornerRadius: Double = 22,
        background: BackgroundToken = .fillTertiary,
        accent: AccentToken = .blue,
        nameTextStyle: TextStyleToken = .caption,
        primaryTextStyle: TextStyleToken = .auto,
        secondaryTextStyle: TextStyleToken = .auto
    ) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.background = background
        self.accent = accent
        self.nameTextStyle = nameTextStyle
        self.primaryTextStyle = primaryTextStyle
        self.secondaryTextStyle = secondaryTextStyle
    }

    public static var defaultStyle: StyleSpec { StyleSpec() }

    public func normalised() -> StyleSpec {
        var s = self
        s.padding = s.padding.clamped(to: 0...32)
        s.cornerRadius = s.cornerRadius.clamped(to: 0...44)
        return s
    }

    private enum CodingKeys: String, CodingKey {
        case padding
        case cornerRadius
        case background
        case accent
        case nameTextStyle
        case primaryTextStyle
        case secondaryTextStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let padding = (try? c.decode(Double.self, forKey: .padding)) ?? 12
        let cornerRadius = (try? c.decode(Double.self, forKey: .cornerRadius)) ?? 22

        let background = (try? c.decode(BackgroundToken.self, forKey: .background)) ?? .fillTertiary
        let accent = (try? c.decode(AccentToken.self, forKey: .accent)) ?? .blue

        let nameTextStyle = (try? c.decode(TextStyleToken.self, forKey: .nameTextStyle)) ?? .caption
        let primaryTextStyle = (try? c.decode(TextStyleToken.self, forKey: .primaryTextStyle)) ?? .auto
        let secondaryTextStyle = (try? c.decode(TextStyleToken.self, forKey: .secondaryTextStyle)) ?? .auto

        self.init(
            padding: padding,
            cornerRadius: cornerRadius,
            background: background,
            accent: accent,
            nameTextStyle: nameTextStyle,
            primaryTextStyle: primaryTextStyle,
            secondaryTextStyle: secondaryTextStyle
        )
    }
}

public enum BackgroundToken: String, Codable, Hashable, CaseIterable, Identifiable {
    case fillSecondary
    case fillTertiary
    case fillQuaternary
    case accent
    case clear

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fillSecondary: return "Fill Secondary"
        case .fillTertiary: return "Fill Tertiary"
        case .fillQuaternary: return "Fill Quaternary"
        case .accent: return "Accent"
        case .clear: return "Clear"
        }
    }

    public func shapeStyle(accent: Color) -> AnyShapeStyle {
        switch self {
        case .fillSecondary:
            return AnyShapeStyle(.fill.secondary)
        case .fillTertiary:
            return AnyShapeStyle(.fill.tertiary)
        case .fillQuaternary:
            return AnyShapeStyle(.fill.quaternary)
        case .accent:
            return AnyShapeStyle(accent)
        case .clear:
            return AnyShapeStyle(Color.clear)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        self = BackgroundToken(rawValue: raw) ?? .fillTertiary
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum AccentToken: String, Codable, Hashable, CaseIterable, Identifiable {
    case auto
    case blue
    case teal
    case mint
    case green
    case yellow
    case orange
    case red
    case pink
    case purple
    case indigo
    case brown
    case gray

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .blue: return "Blue"
        case .teal: return "Teal"
        case .mint: return "Mint"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .orange: return "Orange"
        case .red: return "Red"
        case .pink: return "Pink"
        case .purple: return "Purple"
        case .indigo: return "Indigo"
        case .brown: return "Brown"
        case .gray: return "Gray"
        }
    }

    public var swiftUIColor: Color {
        switch self {
        case .auto: return .accentColor
        case .blue: return .blue
        case .teal: return .teal
        case .mint: return .mint
        case .green: return .green
        case .yellow: return .yellow
        case .orange: return .orange
        case .red: return .red
        case .pink: return .pink
        case .purple: return .purple
        case .indigo: return .indigo
        case .brown: return .brown
        case .gray: return .gray
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        self = AccentToken(rawValue: raw) ?? .blue
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public enum TextStyleToken: String, Codable, Hashable, CaseIterable, Identifiable {
    case auto
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case subheadline
    case body
    case callout
    case footnote
    case caption
    case caption2

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .largeTitle: return "Large Title"
        case .title: return "Title"
        case .title2: return "Title 2"
        case .title3: return "Title 3"
        case .headline: return "Headline"
        case .subheadline: return "Subheadline"
        case .body: return "Body"
        case .callout: return "Callout"
        case .footnote: return "Footnote"
        case .caption: return "Caption"
        case .caption2: return "Caption 2"
        }
    }

    public func font(fallback: Font) -> Font {
        switch self {
        case .auto: return fallback
        case .largeTitle: return .largeTitle
        case .title: return .title
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption
        case .caption2: return .caption2
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        self = TextStyleToken(rawValue: raw) ?? .auto
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

// MARK: - Renderer

public enum WidgetWeaverRenderContext: String, Codable, Hashable {
    case widget
    case preview
}

public struct WidgetWeaverSpecView: View {
    public let spec: WidgetSpec
    public let family: WidgetFamily
    public let context: WidgetWeaverRenderContext

    public init(
        spec: WidgetSpec,
        family: WidgetFamily,
        context: WidgetWeaverRenderContext = .widget
    ) {
        self.spec = spec
        self.family = family
        self.context = context
    }

    public var body: some View {
        let spec = spec.normalised()
        let layout = spec.layout
        let style = spec.style

        let accent = style.accent.swiftUIColor
        let background = style.background.shapeStyle(accent: accent)

        Group {
            if layout.axis == .horizontal {
                HStack(alignment: .top, spacing: layout.spacing) {
                    accentBar(isHorizontal: true, accent: accent)
                    contentStack(spec: spec, layout: layout, style: style, accent: accent)
                }
            } else {
                VStack(alignment: .leading, spacing: layout.spacing) {
                    accentBar(isHorizontal: false, accent: accent)
                    contentStack(spec: spec, layout: layout, style: style, accent: accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.alignment.swiftUIAlignment)
        .padding(style.padding)
        .modifier(
            WidgetWeaverBackgroundModifier(
                context: context,
                background: background,
                cornerRadius: style.cornerRadius
            )
        )
    }

    private func contentStack(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: layout.spacing) {
            header(spec: spec, style: style, accent: accent)

            Text(spec.primaryText)
                .font(style.primaryTextStyle.font(fallback: defaultPrimaryFont(for: family)))
                .foregroundStyle(.primary)
                .lineLimit(primaryLineLimit(layout: layout))

            if let secondary = spec.secondaryText, shouldShowSecondary(layout: layout) {
                Text(secondary)
                    .font(style.secondaryTextStyle.font(fallback: .caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(layout.secondaryLineLimit)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func header(spec: WidgetSpec, style: StyleSpec, accent: Color) -> some View {
        let nameView =
            Text(spec.name)
                .font(style.nameTextStyle.font(fallback: .caption))
                .foregroundStyle(.secondary)
                .lineLimit(1)

        if let symbol = spec.symbol {
            switch symbol.placement {
            case .aboveName:
                VStack(alignment: .leading, spacing: 6) {
                    symbolView(symbol, accent: accent)
                    nameView
                }

            case .beforeName:
                HStack(alignment: .center, spacing: 6) {
                    symbolView(symbol, accent: accent)
                    nameView
                }
            }
        } else {
            nameView
        }
    }

    @ViewBuilder
    private func symbolView(_ symbol: SymbolSpec, accent: Color) -> some View {
        let base =
            Image(systemName: symbol.name)
                .symbolRenderingMode(symbol.renderingMode.swiftUISymbolRenderingMode)
                .font(.system(size: symbol.size, weight: symbol.weight.fontWeight))

        switch symbol.tint {
        case .accent:
            base.foregroundStyle(accent)
        case .primary:
            base.foregroundStyle(.primary)
        case .secondary:
            base.foregroundStyle(.secondary)
        }
    }

    private func accentBar(isHorizontal: Bool, accent: Color) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(accent)
            .frame(width: isHorizontal ? 4 : 28, height: isHorizontal ? 28 : 4)
            .padding(.top, 1)
    }

    private func shouldShowSecondary(layout: LayoutSpec) -> Bool {
        if family == .systemSmall {
            return layout.showSecondaryInSmall
        }
        return true
    }

    private func primaryLineLimit(layout: LayoutSpec) -> Int {
        if family == .systemSmall {
            return layout.primaryLineLimitSmall
        }
        return layout.primaryLineLimit
    }

    private func defaultPrimaryFont(for family: WidgetFamily) -> Font {
        switch family {
        case .systemSmall:
            return .headline
        case .systemMedium:
            return .title3
        case .systemLarge:
            return .title2
        default:
            return .headline
        }
    }
}

private struct WidgetWeaverBackgroundModifier: ViewModifier {
    let context: WidgetWeaverRenderContext
    let background: AnyShapeStyle
    let cornerRadius: Double

    func body(content: Content) -> some View {
        switch context {
        case .widget:
            content
                .containerBackground(background, for: .widget)

        case .preview:
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            content
                .background(shape.fill(background))
                .clipShape(shape)
        }
    }
}

// MARK: - Utilities

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        if self < range.lowerBound { return range.lowerBound }
        if self > range.upperBound { return range.upperBound }
        return self
    }
}
