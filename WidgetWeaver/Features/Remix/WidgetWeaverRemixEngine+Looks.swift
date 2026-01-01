//
//  WidgetWeaverRemixEngine+Looks.swift
//  WidgetWeaver
//
//  Created by . . on 1/1/26.
//

import Foundation

extension WidgetWeaverRemixEngine {

    // MARK: - Looks

    struct Look {
        let kind: Kind
        let title: String
        let subtitle: String
        let makeRecipe: (inout SeededRNG, RemixContext) -> Recipe
    }
}

extension WidgetWeaverRemixEngine {

    static func selectionCycle(context: RemixContext) -> [Kind] {
        if context.isWeatherTemplate {
            return [.subtle, .colour, .typography, .bold]
        }
        if context.isNextUpTemplate {
            return [.subtle, .typography, .colour, .bold]
        }
        if context.hasImage {
            return [.subtle, .poster, .colour, .layout, .typography, .bold]
        }
        return [.subtle, .colour, .layout, .typography, .poster, .bold]
    }

    static func makeLooks(context: RemixContext) -> [Look] {
        if context.isWeatherTemplate {
            return makeWeatherLooks(context: context)
        }
        if context.isNextUpTemplate {
            return makeNextUpLooks(context: context)
        }

        var looks: [Look] = []
        looks.append(contentsOf: makeSubtleLooks(context: context))
        looks.append(contentsOf: makeColourLooks(context: context))
        looks.append(contentsOf: makeLayoutLooks(context: context))
        looks.append(contentsOf: makeTypographyLooks(context: context))
        looks.append(contentsOf: makePosterLooks(context: context))
        looks.append(contentsOf: makeBoldLooks(context: context))
        return looks
    }
}
