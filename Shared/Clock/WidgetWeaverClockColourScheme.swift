//
//  WidgetWeaverClockColourScheme.swift
//  WidgetWeaver
//
//  Created by . . on 1/18/26.
//

import AppIntents
import Foundation
import SwiftUI

enum WidgetWeaverClockColourScheme: Int, AppEnum, CaseIterable {
    case classic
    case ocean
    case mint
    case orchid
    case sunset
    case ember
    case graphite

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Clock Colour Scheme" }

    static var caseDisplayRepresentations: [WidgetWeaverClockColourScheme: DisplayRepresentation] {
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
}
