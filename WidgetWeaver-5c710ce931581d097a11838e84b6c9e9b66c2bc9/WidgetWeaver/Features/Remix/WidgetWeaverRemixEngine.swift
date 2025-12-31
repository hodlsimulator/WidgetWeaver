//
//  WidgetWeaverRemixEngine.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import Foundation

enum WidgetWeaverRemixEngine {

    struct Variant: Hashable, Identifiable {
        let id: UUID
        let spec: WidgetSpec

        init(id: UUID = UUID(), spec: WidgetSpec) {
            self.id = id
            self.spec = spec
        }
    }

    static func generateVariants(from base: WidgetSpec, count: Int = 5) -> [Variant] {
        let base = base.normalised()

        // Recipes are designed to look obviously different at a glance.
        // Randomness is intentionally bounded so results stay coherent.
        let recipes = makeDefaultRecipes(hasImage: base.image != nil)
        var out: [Variant] = []
        out.reserveCapacity(min(count, recipes.count))

        for recipe in recipes.prefix(count) {
            out.append(Variant(spec: apply(recipe: recipe, to: base)))
        }

        if out.count < count {
            // Fallback: expand by shuffling a few knobs while keeping text intact.
            var rng = SeededRNG(seed: UInt64(Date().timeIntervalSince1970 * 1000.0))
            while out.count < count {
                let r = RandomRecipe.random(using: &rng, hasImage: base.image != nil)
                out.append(Variant(spec: apply(recipe: r, to: base)))
            }
        }

        return out
    }
}

// MARK: - Recipes

private struct RandomRecipe: Hashable {
    var template: LayoutTemplateToken
    var axis: LayoutAxisToken
    var alignment: LayoutAlignmentToken
    var showsAccentBar: Bool
    var spacing: Double

    var padding: Double
    var cornerRadius: Double
    var background: BackgroundToken
    var accent: AccentToken

    var nameTextStyle: TextStyleToken
    var primaryTextStyle: TextStyleToken
    var secondaryTextStyle: TextStyleToken

    static func random(using rng: inout SeededRNG, hasImage: Bool) -> RandomRecipe {
        let templates: [LayoutTemplateToken] = hasImage ? [.classic, .hero, .poster] : [.classic, .hero, .poster]

        let backgrounds: [BackgroundToken] = [.aurora, .sunset, .midnight, .radialGlow, .accentGlow, .candy, .subtleMaterial]
        let accents: [AccentToken] = [.blue, .teal, .green, .orange, .pink, .purple, .red, .yellow, .indigo]

        let primaryStyles: [TextStyleToken] = [.automatic, .title2, .title3, .headline, .subheadline]
        let secondaryStyles: [TextStyleToken] = [.automatic, .footnote, .subheadline, .caption, .caption2]

        return RandomRecipe(
            template: rng.pick(from: templates),
            axis: rng.pick(from: LayoutAxisToken.allCases),
            alignment: rng.pick(from: LayoutAlignmentToken.allCases),
            showsAccentBar: rng.bool(probability: 0.55),
            spacing: Double(rng.int(in: 6...18)),
            padding: Double(rng.int(in: 10...22)),
            cornerRadius: Double(rng.int(in: 16...34)),
            background: rng.pick(from: backgrounds),
            accent: rng.pick(from: accents),
            nameTextStyle: .automatic,
            primaryTextStyle: rng.pick(from: primaryStyles),
            secondaryTextStyle: rng.pick(from: secondaryStyles)
        )
    }
}

private extension WidgetWeaverRemixEngine {
    static func makeDefaultRecipes(hasImage: Bool) -> [RandomRecipe] {
        // Five distinct looks:
        // 1) Clean Classic
        // 2) Hero / Bold
        // 3) Poster / Image-forward
        // 4) Minimal Midnight
        // 5) Playful Candy

        let classic = RandomRecipe(
            template: .classic,
            axis: .vertical,
            alignment: .leading,
            showsAccentBar: true,
            spacing: 10,
            padding: 16,
            cornerRadius: 22,
            background: .radialGlow,
            accent: .blue,
            nameTextStyle: .automatic,
            primaryTextStyle: .headline,
            secondaryTextStyle: .caption2
        )

        let hero = RandomRecipe(
            template: .hero,
            axis: .vertical,
            alignment: .leading,
            showsAccentBar: false,
            spacing: 12,
            padding: 16,
            cornerRadius: 24,
            background: .aurora,
            accent: .teal,
            nameTextStyle: .automatic,
            primaryTextStyle: .title2,
            secondaryTextStyle: .footnote
        )

        let poster = RandomRecipe(
            template: .poster,
            axis: .vertical,
            alignment: .leading,
            showsAccentBar: false,
            spacing: 10,
            padding: 14,
            cornerRadius: 22,
            background: hasImage ? .plain : .sunset,
            accent: .orange,
            nameTextStyle: .headline,
            primaryTextStyle: .title2,
            secondaryTextStyle: .footnote
        )

        let midnight = RandomRecipe(
            template: .classic,
            axis: .horizontal,
            alignment: .leading,
            showsAccentBar: true,
            spacing: 12,
            padding: 16,
            cornerRadius: 28,
            background: .midnight,
            accent: .indigo,
            nameTextStyle: .automatic,
            primaryTextStyle: .title3,
            secondaryTextStyle: .caption
        )

        let candy = RandomRecipe(
            template: .hero,
            axis: .vertical,
            alignment: .leading,
            showsAccentBar: false,
            spacing: 10,
            padding: 16,
            cornerRadius: 20,
            background: .candy,
            accent: .pink,
            nameTextStyle: .automatic,
            primaryTextStyle: .headline,
            secondaryTextStyle: .caption2
        )

        return [classic, hero, poster, midnight, candy]
    }

    static func apply(recipe: RandomRecipe, to base: WidgetSpec) -> WidgetSpec {
        var out = base

        // Text stays untouched.
        out.name = base.name
        out.primaryText = base.primaryText
        out.secondaryText = base.secondaryText

        // Layout.
        out.layout.template = recipe.template
        out.layout.axis = recipe.axis
        out.layout.alignment = recipe.alignment
        out.layout.showsAccentBar = recipe.showsAccentBar
        out.layout.spacing = recipe.spacing

        // Style.
        out.style.padding = recipe.padding
        out.style.cornerRadius = recipe.cornerRadius
        out.style.background = recipe.background
        out.style.accent = recipe.accent
        out.style.nameTextStyle = recipe.nameTextStyle
        out.style.primaryTextStyle = recipe.primaryTextStyle
        out.style.secondaryTextStyle = recipe.secondaryTextStyle

        return out.normalised()
    }
}

// MARK: - Deterministic RNG

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0xDEADBEEFCAFEBABE : seed
    }

    mutating func nextUInt64() -> UInt64 {
        // LCG (Numerical Recipes). Simple and fine for UI variety.
        state = 6364136223846793005 &* state &+ 1442695040888963407
        return state
    }

    mutating func int(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        let value = nextUInt64() % max(1, span)
        return range.lowerBound + Int(value)
    }

    mutating func bool(probability: Double) -> Bool {
        let p = max(0.0, min(1.0, probability))
        let x = Double(nextUInt64() % 10_000) / 10_000.0
        return x < p
    }

    mutating func pick<T>(from array: [T]) -> T {
        if array.isEmpty {
            fatalError("SeededRNG.pick called with empty array")
        }
        let idx = int(in: 0...(array.count - 1))
        return array[idx]
    }
}
