//
//  WidgetWeaverClockAppearanceResolver.swift
//  WidgetWeaver
//
//  Created by . . on 1/24/26.
//

import SwiftUI

/// Single source of truth for resolving clock appearance.
///
/// The editor preview and Widget extension must route all theme/scheme/palette selection
/// through this resolver so there is no preview↔Home Screen drift.
enum WidgetWeaverClockAppearanceResolver {
    struct Resolved {
        let scheme: WidgetWeaverClockColourScheme
        let palette: WidgetWeaverClockPalette

        var schemeDisplayName: String {
            WidgetWeaverClockAppearanceResolver.displayName(for: scheme)
        }
    }

    static func resolve(config: WidgetWeaverClockDesignConfig, mode: ColorScheme) -> Resolved {
        let c = config.normalised()
        let scheme = resolveScheme(theme: c.theme)
        var palette = WidgetWeaverClockPalette.resolve(scheme: scheme, mode: mode)
            palette.applyIconOverrides(config: c, mode: mode)
            return Resolved(scheme: scheme, palette: palette)
    }

    static func resolveScheme(theme rawTheme: String) -> WidgetWeaverClockColourScheme {
        let theme = rawTheme
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch theme {
        case "classic":
            return .classic
        case "ocean":
            return .ocean
        case "mint":
            return .mint
        case "orchid":
            return .orchid
        case "sunset":
            return .sunset
        case "ember":
            return .ember
        case "graphite":
            return .graphite
        default:
            return .classic
        }
    }

    static func displayName(for scheme: WidgetWeaverClockColourScheme) -> String {
        switch scheme {
        case .classic:
            return "Classic"
        case .ocean:
            return "Ocean"
        case .mint:
            return "Mint"
        case .orchid:
            return "Orchid"
        case .sunset:
            return "Sunset"
        case .ember:
            return "Ember"
        case .graphite:
            return "Graphite"
        }
    }
}
