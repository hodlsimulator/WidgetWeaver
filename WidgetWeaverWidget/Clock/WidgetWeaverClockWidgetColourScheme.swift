//
//  WidgetWeaverClockWidgetColourScheme.swift
//  WidgetWeaver
//
//  Created by . . on 1/18/26.
//

import AppIntents
import Foundation

enum WidgetWeaverClockWidgetColourScheme: Int, AppEnum, CaseIterable, Sendable {
    case classic = 0
    case ocean = 1
    case mint = 2
    case orchid = 3
    case sunset = 4
    case ember = 5
    case graphite = 6

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Clock Colour Scheme" }

    static var caseDisplayRepresentations: [WidgetWeaverClockWidgetColourScheme: DisplayRepresentation] {
        [
            .classic: "Classic",
            .ocean: "Ocean",
            .mint: "Mint",
            .orchid: "Orchid",
            .sunset: "Sunset",
            .ember: "Ember",
            .graphite: "Graphite",
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
