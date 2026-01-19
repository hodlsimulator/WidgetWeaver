//
//  WidgetWeaverClockWidgetColourScheme.swift
//  WidgetWeaver
//
//  Created by . . on 1/18/26.
//

import AppIntents
import Foundation

public enum WidgetWeaverClockWidgetColourScheme: String, AppEnum, CaseIterable, Sendable {
    case classic
    case ocean
    case mint
    case orchid
    case sunset
    case ember
    case graphite

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Clock Colour Scheme")
    }

    public static var caseDisplayRepresentations: [WidgetWeaverClockWidgetColourScheme: DisplayRepresentation] {
        [
            .classic: DisplayRepresentation(title: "Classic"),
            .ocean: DisplayRepresentation(title: "Ocean"),
            .mint: DisplayRepresentation(title: "Mint"),
            .orchid: DisplayRepresentation(title: "Orchid"),
            .sunset: DisplayRepresentation(title: "Sunset"),
            .ember: DisplayRepresentation(title: "Ember"),
            .graphite: DisplayRepresentation(title: "Graphite")
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
