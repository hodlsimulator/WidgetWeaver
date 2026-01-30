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

    static var defaultTheme: WidgetWeaverAppTheme { .orchid }

    static func resolve(_ rawValue: String) -> WidgetWeaverAppTheme {
        WidgetWeaverAppTheme(rawValue: rawValue) ?? defaultTheme
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .orchid:
            return "Orchid"
        case .graphite:
            return "Graphite"
        case .ocean:
            return "Ocean"
        case .mint:
            return "Mint"
        case .ember:
            return "Ember"
        case .paper:
            return "Paper"
        }
    }

    var detail: String {
        switch self {
        case .orchid:
            return "Pink + orange glow with a purple highlight."
        case .graphite:
            return "Neutral dark with subtle cool tones."
        case .ocean:
            return "Blue and teal glow."
        case .mint:
            return "Fresh greens with a soft mint glow."
        case .ember:
            return "Warm orange and red glow."
        case .paper:
            return "Always light appearance (ignores system Dark Mode)."
        }
    }

    var tint: Color {
        switch self {
        case .orchid, .graphite, .paper:
            return Color("AccentColor")
        case .ocean:
            return .blue
        case .mint:
            return .mint
        case .ember:
            return .orange
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

    var darkHighlights: HighlightTrio {
        switch self {
        case .orchid:
            return HighlightTrio(first: .pink, second: .orange, third: .purple)

        case .graphite:
            return HighlightTrio(first: .gray, second: .blue, third: .teal)

        case .ocean:
            return HighlightTrio(first: .cyan, second: .blue, third: .teal)

        case .mint:
            return HighlightTrio(first: .mint, second: .green, third: .teal)

        case .ember:
            return HighlightTrio(first: .red, second: .orange, third: .yellow)

        case .paper:
            return HighlightTrio(first: .white, second: .gray, third: .clear)
        }
    }

    var lightHighlights: HighlightTrio {
        switch self {
        case .orchid:
            return HighlightTrio(first: Color("AccentColor"), second: .blue, third: .purple)

        case .graphite:
            return HighlightTrio(first: Color("AccentColor"), second: .gray, third: .blue)

        case .ocean:
            return HighlightTrio(first: .cyan, second: .blue, third: .teal)

        case .mint:
            return HighlightTrio(first: .mint, second: .green, third: .teal)

        case .ember:
            return HighlightTrio(first: .orange, second: .red, third: .yellow)

        case .paper:
            return HighlightTrio(first: Color("AccentColor"), second: .blue, third: .gray)
        }
    }

    static var ordered: [WidgetWeaverAppTheme] {
        [
            .orchid,
            .graphite,
            .ocean,
            .mint,
            .ember,
            .paper
        ]
    }
}

enum WidgetWeaverAppThemeReader {
    static func selectedTheme() -> WidgetWeaverAppTheme {
        let raw = UserDefaults.standard.string(forKey: WidgetWeaverAppAppearanceKeys.theme) ?? WidgetWeaverAppTheme.defaultTheme.rawValue
        return WidgetWeaverAppTheme.resolve(raw)
    }
}
