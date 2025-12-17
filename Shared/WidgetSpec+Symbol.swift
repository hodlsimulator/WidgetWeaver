//
//  WidgetSpec+Symbol.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI

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

public enum SymbolPlacementToken: String, Codable, CaseIterable, Hashable, Identifiable {
    case aboveName
    case beforeName

    public var id: String { rawValue }
}

public enum SymbolTintToken: String, Codable, CaseIterable, Hashable, Identifiable {
    case accent
    case primary
    case secondary

    public var id: String { rawValue }

    public var swiftUIColor: Color {
        switch self {
        case .accent:
            return .accentColor
        case .primary:
            return .primary
        case .secondary:
            return .secondary
        }
    }
}

public enum SymbolRenderingModeToken: String, Codable, CaseIterable, Hashable, Identifiable {
    case monochrome
    case hierarchical
    case multicolor

    public var id: String { rawValue }

    public var swiftUISymbolRenderingMode: SymbolRenderingMode {
        switch self {
        case .monochrome:
            return .monochrome
        case .hierarchical:
            return .hierarchical
        case .multicolor:
            return .multicolor
        }
    }
}

public enum SymbolWeightToken: String, Codable, CaseIterable, Hashable, Identifiable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    public var id: String { rawValue }

    public var swiftUIFontWeight: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}
