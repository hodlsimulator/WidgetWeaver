//
//  WidgetWeaverAppAppearance.swift
//  WidgetWeaver
//
//  Created by . . on 1/30/26.
//

import Foundation
import SwiftUI

enum WidgetWeaverAppAppearanceKeys {
    static let theme: String = "widgetweaver.appearance.theme"
}

enum WidgetWeaverAppTheme: String, CaseIterable, Identifiable {
    case orchid
    case graphite
    case ocean
    case mint
    case ember
    case paper

    case obsidian
    case midnight
    case aurora
    case evergreen
    case cinder
    case signal

    static var defaultTheme: WidgetWeaverAppTheme { .orchid }

    static func resolve(_ rawValue: String) -> WidgetWeaverAppTheme {
        WidgetWeaverAppTheme(rawValue: rawValue) ?? defaultTheme
    }

    var id: String { rawValue }

    private static func srgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(red: r / 255.0, green: g / 255.0, blue: b / 255.0)
    }

    var displayName: String {
        switch self {
        case .obsidian:
            return "Obsidian"
        case .midnight:
            return "Midnight"
        case .graphite:
            return "Graphite"
        case .ocean:
            return "Ocean"
        case .aurora:
            return "Aurora"
        case .evergreen:
            return "Evergreen"
        case .mint:
            return "Mint"
        case .cinder:
            return "Cinder"
        case .ember:
            return "Ember"
        case .signal:
            return "Signal"
        case .orchid:
            return "Orchid"
        case .paper:
            return "Paper"
        }
    }

    var detail: String {
        switch self {
        case .obsidian:
            return "True black base with icy cyan and teal glows."
        case .midnight:
            return "Deep navy base with indigo and cyan glows."
        case .graphite:
            return "Charcoal neutrals with steel-blue highlights."
        case .ocean:
            return "Clean blues with a cool teal lift."
        case .aurora:
            return "Teal, lime and rose—balanced and low-saturation."
        case .evergreen:
            return "Forest greens with a subtle teal glow."
        case .mint:
            return "Soft mint and teal with a clean, modern feel."
        case .cinder:
            return "Warm charcoal with brass highlights."
        case .ember:
            return "Warm reds and oranges—higher energy."
        case .signal:
            return "High-contrast accents on true black."
        case .orchid:
            return "Pink + orange glow with a purple highlight."
        case .paper:
            return "Always light appearance (ignores system Dark Mode)."
        }
    }

    var tint: Color {
        switch self {
        case .orchid, .paper:
            return Color("AccentColor")

        case .graphite:
            return Self.srgb(147, 197, 253) // soft blue

        case .ocean:
            return Self.srgb(56, 189, 248) // sky

        case .mint:
            return Self.srgb(94, 234, 212) // mint-teal

        case .ember:
            return Self.srgb(251, 146, 60) // warm orange

        case .obsidian:
            return Self.srgb(34, 211, 238) // cyan

        case .midnight:
            return Self.srgb(165, 180, 252) // indigo

        case .aurora:
            return Self.srgb(45, 212, 191) // teal

        case .evergreen:
            return Self.srgb(52, 211, 153) // emerald

        case .cinder:
            return Self.srgb(251, 191, 36) // amber

        case .signal:
            return Self.srgb(163, 230, 53) // lime
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .paper:
            return .light
        default:
            return nil
        }
    }

    struct HighlightTrio {
        let first: Color
        let second: Color
        let third: Color
    }

    struct GlowOpacities {
        let first: Double
        let second: Double
        let third: Double
    }

    func backgroundBase(for scheme: ColorScheme) -> Color {
        let systemGrouped = Color(uiColor: .systemGroupedBackground)

        switch (self, scheme) {
        case (.obsidian, .dark), (.signal, .dark):
            return .black

        case (.midnight, .dark):
            return Self.srgb(8, 12, 24)

        default:
            return systemGrouped
        }
    }

    var darkGlowOpacities: GlowOpacities {
        switch self {
        case .obsidian:
            return GlowOpacities(first: 0.14, second: 0.12, third: 0.10)

        case .signal:
            return GlowOpacities(first: 0.13, second: 0.11, third: 0.09)

        case .midnight:
            return GlowOpacities(first: 0.16, second: 0.14, third: 0.12)

        case .graphite, .evergreen, .mint:
            return GlowOpacities(first: 0.16, second: 0.14, third: 0.12)

        case .ocean, .aurora, .cinder:
            return GlowOpacities(first: 0.17, second: 0.15, third: 0.13)

        case .ember, .orchid:
            return GlowOpacities(first: 0.18, second: 0.16, third: 0.14)

        case .paper:
            return GlowOpacities(first: 0.00, second: 0.00, third: 0.00)
        }
    }

    var lightGlowOpacities: GlowOpacities {
        switch self {
        case .obsidian, .signal:
            return GlowOpacities(first: 0.14, second: 0.10, third: 0.08)

        case .midnight:
            return GlowOpacities(first: 0.16, second: 0.10, third: 0.08)

        case .graphite, .evergreen, .mint:
            return GlowOpacities(first: 0.16, second: 0.10, third: 0.08)

        case .ocean, .aurora, .cinder, .ember, .orchid:
            return GlowOpacities(first: 0.18, second: 0.12, third: 0.10)

        case .paper:
            return GlowOpacities(first: 0.10, second: 0.06, third: 0.04)
        }
    }

    var darkHighlights: HighlightTrio {
        let cyan = Self.srgb(34, 211, 238)
        let blue = Self.srgb(96, 165, 250)
        let teal = Self.srgb(45, 212, 191)

        let slate = Self.srgb(148, 163, 184)
        let indigo = Self.srgb(129, 140, 248)

        let lime = Self.srgb(163, 230, 53)
        let rose = Self.srgb(251, 113, 133)

        let emerald = Self.srgb(52, 211, 153)
        let green = Self.srgb(34, 197, 94)
        let tealDeeper = Self.srgb(20, 184, 166)

        let amber = Self.srgb(251, 191, 36)
        let orange = Self.srgb(251, 146, 60)

        switch self {
        case .obsidian:
            return HighlightTrio(first: cyan, second: blue, third: teal)

        case .midnight:
            return HighlightTrio(first: indigo, second: blue, third: cyan)

        case .graphite:
            return HighlightTrio(first: slate, second: blue, third: cyan)

        case .ocean:
            return HighlightTrio(first: Self.srgb(56, 189, 248), second: blue, third: teal)

        case .aurora:
            return HighlightTrio(first: teal, second: lime, third: rose)

        case .evergreen:
            return HighlightTrio(first: green, second: emerald, third: tealDeeper)

        case .mint:
            return HighlightTrio(first: Self.srgb(94, 234, 212), second: emerald, third: teal)

        case .cinder:
            return HighlightTrio(first: orange, second: amber, third: slate)

        case .ember:
            return HighlightTrio(first: Self.srgb(248, 113, 113), second: orange, third: amber)

        case .signal:
            return HighlightTrio(first: lime, second: cyan, third: blue)

        case .orchid:
            return HighlightTrio(first: .pink, second: .orange, third: .purple)

        case .paper:
            return HighlightTrio(first: .white, second: .gray, third: .clear)
        }
    }

    var lightHighlights: HighlightTrio {
        let cyan = Self.srgb(34, 211, 238)
        let blue = Self.srgb(96, 165, 250)
        let sky = Self.srgb(56, 189, 248)
        let teal = Self.srgb(45, 212, 191)

        let slate = Self.srgb(148, 163, 184)
        let indigoLight = Self.srgb(165, 180, 252)

        let lime = Self.srgb(163, 230, 53)
        let rose = Self.srgb(251, 113, 133)

        let emerald = Self.srgb(52, 211, 153)
        let green = Self.srgb(34, 197, 94)
        let tealDeeper = Self.srgb(20, 184, 166)

        let amber = Self.srgb(251, 191, 36)
        let orange = Self.srgb(251, 146, 60)

        switch self {
        case .obsidian:
            return HighlightTrio(first: cyan, second: blue, third: teal)

        case .midnight:
            return HighlightTrio(first: indigoLight, second: sky, third: cyan)

        case .graphite:
            return HighlightTrio(first: Self.srgb(147, 197, 253), second: slate, third: sky)

        case .ocean:
            return HighlightTrio(first: sky, second: blue, third: teal)

        case .aurora:
            return HighlightTrio(first: teal, second: lime, third: rose)

        case .evergreen:
            return HighlightTrio(first: emerald, second: green, third: tealDeeper)

        case .mint:
            return HighlightTrio(first: Self.srgb(94, 234, 212), second: teal, third: emerald)

        case .cinder:
            return HighlightTrio(first: orange, second: amber, third: slate)

        case .ember:
            return HighlightTrio(first: orange, second: Self.srgb(248, 113, 113), third: amber)

        case .signal:
            return HighlightTrio(first: lime, second: cyan, third: blue)

        case .orchid:
            return HighlightTrio(first: Color("AccentColor"), second: .blue, third: .purple)

        case .paper:
            return HighlightTrio(first: Color("AccentColor"), second: .blue, third: .gray)
        }
    }

    static var ordered: [WidgetWeaverAppTheme] {
        [
            .obsidian,
            .midnight,
            .graphite,
            .ocean,
            .aurora,
            .evergreen,
            .mint,
            .cinder,
            .ember,
            .signal,
            .orchid,
            .paper,
        ]
    }
}

enum WidgetWeaverAppThemeReader {
    static func selectedTheme() -> WidgetWeaverAppTheme {
        let raw = UserDefaults.standard.string(forKey: WidgetWeaverAppAppearanceKeys.theme) ?? WidgetWeaverAppTheme.defaultTheme.rawValue
        return WidgetWeaverAppTheme.resolve(raw)
    }
}
