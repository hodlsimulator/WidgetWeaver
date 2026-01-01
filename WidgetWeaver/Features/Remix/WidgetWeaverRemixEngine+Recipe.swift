//
//  WidgetWeaverRemixEngine+Recipe.swift
//  WidgetWeaver
//
//  Created by . . on 1/1/26.
//

import Foundation

extension WidgetWeaverRemixEngine {

    // MARK: - Recipe

    struct Recipe: Hashable {
        var template: LayoutTemplateToken

        var axis: LayoutAxisToken
        var alignment: LayoutAlignmentToken
        var showsAccentBar: Bool
        var spacing: Double

        var primaryLineLimitSmall: Int
        var primaryLineLimit: Int
        var secondaryLineLimitSmall: Int
        var secondaryLineLimit: Int

        var padding: Double
        var cornerRadius: Double

        var background: BackgroundToken
        var backgroundOverlay: BackgroundToken
        var backgroundOverlayOpacity: Double
        var backgroundGlowEnabled: Bool

        var accent: AccentToken

        var nameTextStyle: TextStyleToken
        var primaryTextStyle: TextStyleToken
        var secondaryTextStyle: TextStyleToken

        var symbolSize: Double
        var weatherScale: Double

        init(base: WidgetSpec) {
            self.template = base.layout.template
            self.axis = base.layout.axis
            self.alignment = base.layout.alignment
            self.showsAccentBar = base.layout.showsAccentBar
            self.spacing = base.layout.spacing

            self.primaryLineLimitSmall = base.layout.primaryLineLimitSmall
            self.primaryLineLimit = base.layout.primaryLineLimit
            self.secondaryLineLimitSmall = base.layout.secondaryLineLimitSmall
            self.secondaryLineLimit = base.layout.secondaryLineLimit

            self.padding = base.style.padding
            self.cornerRadius = base.style.cornerRadius

            self.background = base.style.background
            self.backgroundOverlay = base.style.backgroundOverlay
            self.backgroundOverlayOpacity = base.style.backgroundOverlayOpacity
            self.backgroundGlowEnabled = base.style.backgroundGlowEnabled

            self.accent = base.style.accent

            self.nameTextStyle = base.style.nameTextStyle
            self.primaryTextStyle = base.style.primaryTextStyle
            self.secondaryTextStyle = base.style.secondaryTextStyle

            self.symbolSize = base.style.symbolSize
            self.weatherScale = base.style.weatherScale
        }
    }
}

extension WidgetWeaverRemixEngine {

    static func apply(recipe: Recipe, to base: WidgetSpec) -> WidgetSpec {
        var out = base

        // Text + content is preserved.
        out.name = base.name
        out.primaryText = base.primaryText
        out.secondaryText = base.secondaryText
        out.symbol = base.symbol
        out.image = base.image
        out.actionBar = base.actionBar
        out.matchedSet = base.matchedSet

        // Layout
        out.layout.template = recipe.template
        out.layout.axis = recipe.axis
        out.layout.alignment = recipe.alignment
        out.layout.showsAccentBar = recipe.showsAccentBar
        out.layout.spacing = recipe.spacing
        out.layout.primaryLineLimitSmall = recipe.primaryLineLimitSmall
        out.layout.primaryLineLimit = recipe.primaryLineLimit
        out.layout.secondaryLineLimitSmall = recipe.secondaryLineLimitSmall
        out.layout.secondaryLineLimit = recipe.secondaryLineLimit

        // Style
        out.style.padding = recipe.padding

        // `cornerRadius` is currently used by the Weather template's glass.
        if out.layout.template == .weather {
            out.style.cornerRadius = recipe.cornerRadius
        } else {
            out.style.cornerRadius = base.style.cornerRadius
        }

        out.style.background = recipe.background
        out.style.backgroundOverlay = recipe.backgroundOverlay
        out.style.backgroundOverlayOpacity = recipe.backgroundOverlayOpacity
        out.style.backgroundGlowEnabled = recipe.backgroundGlowEnabled
        out.style.accent = recipe.accent

        out.style.nameTextStyle = recipe.nameTextStyle
        out.style.primaryTextStyle = recipe.primaryTextStyle
        out.style.secondaryTextStyle = recipe.secondaryTextStyle

        out.style.symbolSize = recipe.symbolSize
        out.style.weatherScale = recipe.weatherScale

        return out.normalised()
    }

    static func randomRecipe(using rng: inout SeededRNG, context: RemixContext) -> Recipe {
        var r = Recipe(base: context.base)

        r.template = rng.pick(from: context.allowedTemplates)

        r.axis = context.base.layout.axis
        r.alignment = rng.pick(from: LayoutAlignmentToken.allCases)
        r.showsAccentBar = rng.bool(probability: 0.50)
        r.spacing = Double(rng.int(in: 6...20))

        r.padding = Double(rng.int(in: 12...26))
        r.cornerRadius = Double(rng.int(in: 16...34))

        let backgrounds: [BackgroundToken] = [.plain, .subtleMaterial, .radialGlow, .accentGlow, .solidAccent, .aurora, .sunset, .midnight, .candy]
        r.background = rng.pick(from: backgrounds)

        let overlayCandidates: [BackgroundToken] = [.plain, .radialGlow, .accentGlow, .solidAccent, .midnight]
        if rng.bool(probability: 0.35) {
            r.backgroundOverlay = rng.pick(from: overlayCandidates)
            r.backgroundOverlayOpacity = Double(rng.int(in: 6...24)) / 100.0
        } else {
            r.backgroundOverlay = .plain
            r.backgroundOverlayOpacity = 0
        }

        r.backgroundGlowEnabled = rng.bool(probability: 0.25)

        r.accent = rng.pick(from: AccentToken.allCases)

        let nameStyles: [TextStyleToken] = [.automatic, .caption2, .caption]
        let primaryStyles: [TextStyleToken] = [.automatic, .headline, .title3, .title2]
        let secondaryStyles: [TextStyleToken] = [.automatic, .caption2, .caption, .footnote, .subheadline]

        r.nameTextStyle = rng.pick(from: nameStyles)
        r.primaryTextStyle = rng.pick(from: primaryStyles)
        r.secondaryTextStyle = rng.pick(from: secondaryStyles)

        r.symbolSize = context.hasSymbol ? Double(rng.int(in: 26...54)) : r.symbolSize
        r.weatherScale = (r.template == .weather) ? Double(rng.int(in: 85...125)) / 100.0 : r.weatherScale

        // Line limits tuned for visible variety, without making small widgets unreadable.
        if r.primaryTextStyle == .title2 || r.primaryTextStyle == .title {
            r.primaryLineLimitSmall = 1
            r.primaryLineLimit = 2
        } else {
            r.primaryLineLimitSmall = rng.int(in: 1...2)
            r.primaryLineLimit = rng.int(in: 2...3)
        }

        r.secondaryLineLimitSmall = rng.int(in: 1...2)
        r.secondaryLineLimit = rng.int(in: 2...3)

        if r.template == .poster {
            r.primaryLineLimitSmall = max(2, r.primaryLineLimitSmall)
            r.primaryLineLimit = max(2, r.primaryLineLimit)
            r.secondaryLineLimitSmall = max(2, r.secondaryLineLimitSmall)
            r.secondaryLineLimit = max(2, r.secondaryLineLimit)
        }

        return r
    }
}
