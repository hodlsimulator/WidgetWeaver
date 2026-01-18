//
//  WidgetWeaverClockColourScheme.swift
//  WidgetWeaver
//
//  Created by . . on 1/18/26.
//

import AppIntents
import Foundation
import SwiftUI

public enum WidgetWeaverClockColourScheme: Int, AppEnum, CaseIterable, Sendable {
    case classic = 0
    case ocean = 1
    case mint = 2
    case orchid = 3
    case sunset = 4
    case ember = 5
    case graphite = 6

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Clock Colour Scheme")
    }

    public static var caseDisplayRepresentations: [WidgetWeaverClockColourScheme: DisplayRepresentation] {
        [
            .classic: DisplayRepresentation(title: "Classic"),
            .ocean: DisplayRepresentation(title: "Ocean"),
            .mint: DisplayRepresentation(title: "Mint"),
            .orchid: DisplayRepresentation(title: "Orchid"),
            .sunset: DisplayRepresentation(title: "Sunset"),
            .ember: DisplayRepresentation(title: "Ember"),
            .graphite: DisplayRepresentation(title: "Graphite"),
        ]
    }
}
