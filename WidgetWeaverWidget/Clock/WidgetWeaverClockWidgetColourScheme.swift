//
//  WidgetWeaverClockWidgetColourScheme.swift
//  WidgetWeaver
//
//  Created by . . on 1/18/26.
//

import AppIntents
import Foundation

/// AppIntent-facing colour scheme selector for the standalone Clock (Icon) widget.
///
/// This type is intentionally widget-extension-only to avoid AppIntent type name collisions with the main app target.
public enum WidgetWeaverClockWidgetColourScheme: String, AppEnum, CaseIterable, Sendable {
    case classic
    case ocean
    case mint
    case orchid
    case sunset
    case ember
    case graphite

    public static var typeDisplayRepresentation: TypeDisplayRepresentation { "Clock Colour Scheme" }

    public static var caseDisplayRepresentations: [WidgetWeaverClockWidgetColourScheme: DisplayRepresentation] {
        [
            .classic: "Classic",
            .ocean: "Ocean",
            .mint: "Mint",
            .orchid: "Orchid",
            .sunset: "Sunset",
            .ember: "Ember",
            .graphite: "Graphite"
        ]
    }

    var paletteScheme: WidgetWeaverClockColourScheme {
        switch self {
        case .classic: return .classic
        case .ocean: return .ocean
        case .mint: return .mint
        case .orchid: return .orchid
        case .sunset: return .sunset
        case .ember: return .ember
        case .graphite: return .graphite
        }
    }
}
