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

        // Polished / subtle
        looks.append(
            Look(
                kind: .subtle,
                title: "Polished",
                subtitle: "Subtle Material + restrained accent",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = ctx.baseTemplate
                    r.alignment = .leading
                    r.showsAccentBar = true
                    r.spacing = Double(rng.int(in: 6...12))

                    r.background = .subtleMaterial
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = .title3
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...20))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 30...38)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .subtle,
                title: "Clean",
                subtitle: "Plain base + soft glow overlay",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = ctx.baseTemplate
                    r.alignment = rng.pick(from: [.leading, .centre])
                    r.showsAccentBar = rng.bool(probability: 0.55)
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = .plain
                    r.backgroundOverlay = rng.pick(from: [.radialGlow, .accentGlow])
                    r.backgroundOverlayOpacity = Double(rng.int(in: 10...22)) / 100.0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.headline, .title3])
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...22))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 30...40)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .subtle,
                title: "Muted",
                subtitle: "Low-contrast accent + tidy type",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = ctx.baseTemplate
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 6...12))

                    r.background = .subtleMaterial
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: [.gray, .indigo, .blue])

                    r.nameTextStyle = .caption2
                    r.primaryTextStyle = .headline
                    r.secondaryTextStyle = .footnote

                    r.padding = Double(rng.int(in: 12...18))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 26...34)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        // Colour-forward
        looks.append(
            Look(
                kind: .colour,
                title: "Aurora",
                subtitle: "Cool gradient wash",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = rng.pick(from: [.leading, .centre])
                    r.showsAccentBar = rng.bool(probability: 0.40)
                    r.spacing = Double(rng.int(in: 8...16))

                    r.background = .aurora
                    r.backgroundOverlay = rng.pick(from: [.plain, .radialGlow])
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? 0 : Double(rng.int(in: 6...16)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.35)

                    r.accent = rng.pick(from: [.teal, .blue, .indigo, .green, .purple])

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.title3, .headline])
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...24))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 30...44)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .colour,
                title: "Sunset",
                subtitle: "Warm gradient with bold accent",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = .leading
                    r.showsAccentBar = rng.bool(probability: 0.60)
                    r.spacing = Double(rng.int(in: 8...16))

                    r.background = .sunset
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.25)

                    r.accent = rng.pick(from: [.orange, .pink, .red, .yellow, .purple])

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.headline, .title3])
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...24))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 30...44)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .colour,
                title: "Candy",
                subtitle: "Playful gradient pop",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = rng.pick(from: [.leading, .centre])
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 10...18))

                    r.background = .candy
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.35)

                    r.accent = rng.pick(from: [.pink, .teal, .blue, .purple])

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.headline, .title3])
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...24))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 28...44)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .colour,
                title: "Solid",
                subtitle: "Solid Accent backdrop",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = .leading
                    r.showsAccentBar = rng.bool(probability: 0.35)
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = .solidAccent
                    r.backgroundOverlay = rng.bool(probability: 0.35) ? .accentGlow : .plain
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? 0 : Double(rng.int(in: 8...18)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.25)

                    r.accent = rng.pick(from: AccentToken.allCases)

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = .headline
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 12...20))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 28...42)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        // Layout-forward
        looks.append(
            Look(
                kind: .layout,
                title: "Hero",
                subtitle: "Big symbol + content-first",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .hero
                    r.alignment = rng.pick(from: [.leading, .trailing])
                    r.showsAccentBar = rng.bool(probability: 0.25)
                    r.spacing = Double(rng.int(in: 10...18))

                    r.background = rng.pick(from: [.radialGlow, .subtleMaterial, .aurora])
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.20)

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.title3, .headline])
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...22))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 36...52)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .layout,
                title: "Classic",
                subtitle: "Accent bar + tidy stack",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .classic
                    r.alignment = .leading
                    r.showsAccentBar = true
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = rng.pick(from: [.radialGlow, .subtleMaterial, .accentGlow])
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.headline, .title3])
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...22))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 30...46)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .layout,
                title: "Centred",
                subtitle: "Centre alignment + airy spacing",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = .centre
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 12...22))

                    r.background = rng.pick(from: [.radialGlow, .plain, .subtleMaterial])
                    r.backgroundOverlay = (r.background == .plain) ? .radialGlow : .plain
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? 0 : Double(rng.int(in: 8...18)) / 100.0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: AccentToken.allCases)

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.headline, .title3])
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 16...26))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 28...44)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        // Typography-forward
        looks.append(
            Look(
                kind: .typography,
                title: "Big Type",
                subtitle: "More emphasis on primary text",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = .leading
                    r.showsAccentBar = rng.bool(probability: 0.35)
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = rng.pick(from: [.subtleMaterial, .radialGlow, .accentGlow])
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.title2, .title3])
                    r.secondaryTextStyle = rng.pick(from: [.footnote, .subheadline])

                    r.padding = Double(rng.int(in: 14...22))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 30...44)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .typography,
                title: "Editorial",
                subtitle: "Neutral accent + balanced text",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 6...12))

                    r.background = rng.pick(from: [.plain, .subtleMaterial])
                    r.backgroundOverlay = (r.background == .plain) ? .plain : .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: [.gray, .indigo])

                    r.nameTextStyle = .caption2
                    r.primaryTextStyle = .headline
                    r.secondaryTextStyle = .footnote

                    r.padding = Double(rng.int(in: 12...18))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 26...36)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .typography,
                title: "Compact Type",
                subtitle: "Smaller text + more room",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = .leading
                    r.showsAccentBar = rng.bool(probability: 0.35)
                    r.spacing = Double(rng.int(in: 6...10))

                    r.background = rng.pick(from: [.subtleMaterial, .plain])
                    r.backgroundOverlay = (r.background == .plain) ? .radialGlow : .plain
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? 0 : Double(rng.int(in: 8...16)) / 100.0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption2
                    r.primaryTextStyle = .subheadline
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 12...18))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 24...34)) : r.symbolSize

                    r.primaryLineLimitSmall = 2
                    r.primaryLineLimit = 3
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        // Poster variants (use image if available)
        looks.append(
            Look(
                kind: .poster,
                title: "Poster — Dark",
                subtitle: "Image-forward with dark overlay",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .poster
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = 10

                    r.background = .plain
                    r.backgroundOverlay = .midnight
                    r.backgroundOverlayOpacity = Double(rng.int(in: 14...28)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.15)

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.title2, .title3])
                    r.secondaryTextStyle = .footnote

                    r.padding = Double(rng.int(in: 14...24))
                    r.symbolSize = r.symbolSize

                    r.primaryLineLimitSmall = 2
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 2
                    r.secondaryLineLimit = 3

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .poster,
                title: "Poster — Tint",
                subtitle: "Accent-tinted overlay",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .poster
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = 10

                    r.background = .plain
                    r.backgroundOverlay = rng.pick(from: [.solidAccent, .accentGlow, .radialGlow])
                    r.backgroundOverlayOpacity = Double(rng.int(in: 10...22)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.10)

                    r.accent = rng.pick(from: AccentToken.allCases)

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.title2, .title3, .headline])
                    r.secondaryTextStyle = .footnote

                    r.padding = Double(rng.int(in: 14...26))
                    r.symbolSize = r.symbolSize

                    r.primaryLineLimitSmall = 2
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 2
                    r.secondaryLineLimit = 3

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .poster,
                title: "Poster — Soft",
                subtitle: "Gentle glow with light overlay",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .poster
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = 10

                    r.background = .plain
                    r.backgroundOverlay = rng.pick(from: [.plain, .radialGlow])
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? Double(rng.int(in: 8...16)) / 100.0 : Double(rng.int(in: 8...18)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.18)

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.title3, .headline])
                    r.secondaryTextStyle = .footnote

                    r.padding = Double(rng.int(in: 14...26))
                    r.symbolSize = r.symbolSize

                    r.primaryLineLimitSmall = 2
                    r.primaryLineLimit = 3
                    r.secondaryLineLimitSmall = 2
                    r.secondaryLineLimit = 3

                    return r
                }
            )
        )

        // Bold / experimental
        looks.append(
            Look(
                kind: .bold,
                title: "Neon",
                subtitle: "Midnight + glow",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 10...18))

                    r.background = .midnight
                    r.backgroundOverlay = rng.pick(from: [.accentGlow, .radialGlow])
                    r.backgroundOverlayOpacity = Double(rng.int(in: 12...26)) / 100.0
                    r.backgroundGlowEnabled = true

                    r.accent = rng.pick(from: [.teal, .pink, .purple, .indigo])

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.title3, .headline])
                    r.secondaryTextStyle = .footnote

                    r.padding = Double(rng.int(in: 14...22))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 34...52)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .bold,
                title: "High Contrast",
                subtitle: "Solid Accent + sharp type",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = rng.pick(from: [.leading, .trailing])
                    r.showsAccentBar = rng.bool(probability: 0.30)
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = .solidAccent
                    r.backgroundOverlay = rng.pick(from: [.plain, .accentGlow])
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? Double(rng.int(in: 10...18)) / 100.0 : Double(rng.int(in: 8...16)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.35)

                    r.accent = rng.pick(from: AccentToken.allCases)

                    r.nameTextStyle = .caption2
                    r.primaryTextStyle = .headline
                    r.secondaryTextStyle = .caption

                    r.padding = Double(rng.int(in: 12...20))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 30...46)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .bold,
                title: "Radial Pop",
                subtitle: "Radial glow + bold accent",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = rng.pick(from: ctx.allowedTemplates.filter { $0 != .poster })
                    r.alignment = rng.pick(from: [.leading, .centre])
                    r.showsAccentBar = rng.bool(probability: 0.55)
                    r.spacing = Double(rng.int(in: 10...18))

                    r.background = .radialGlow
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.20)

                    r.accent = rng.pick(from: AccentToken.allCases)

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = rng.pick(from: [.headline, .title3])
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...24))
                    r.symbolSize = ctx.hasSymbol ? Double(rng.int(in: 30...50)) : r.symbolSize

                    r.primaryLineLimitSmall = 1
                    r.primaryLineLimit = 2
                    r.secondaryLineLimitSmall = 1
                    r.secondaryLineLimit = 2

                    return r
                }
            )
        )

        return looks
    }

    static func makeWeatherLooks(context: RemixContext) -> [Look] {
        var looks: [Look] = []

        looks.append(
            Look(
                kind: .subtle,
                title: "Weather Glass",
                subtitle: "Subtle Material backdrop",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = 8

                    r.background = .subtleMaterial
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 14...20))
                    r.cornerRadius = Double(rng.int(in: 18...28))
                    r.symbolSize = Double(rng.int(in: 32...40))
                    r.weatherScale = Double(rng.int(in: 92...110)) / 100.0

                    r.primaryLineLimitSmall = ctx.base.layout.primaryLineLimitSmall
                    r.primaryLineLimit = ctx.base.layout.primaryLineLimit
                    r.secondaryLineLimitSmall = ctx.base.layout.secondaryLineLimitSmall
                    r.secondaryLineLimit = ctx.base.layout.secondaryLineLimit

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .colour,
                title: "Weather Aurora",
                subtitle: "Gradient wash + overlay",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = 8

                    r.background = rng.pick(from: [.aurora, .radialGlow, .accentGlow])
                    r.backgroundOverlay = rng.pick(from: [.plain, .radialGlow])
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? 0 : Double(rng.int(in: 8...18)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.25)

                    r.accent = rng.pick(from: [.teal, .blue, .indigo, .purple, .green])

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 14...22))
                    r.cornerRadius = Double(rng.int(in: 18...30))
                    r.symbolSize = Double(rng.int(in: 32...44))
                    r.weatherScale = Double(rng.int(in: 92...116)) / 100.0

                    r.primaryLineLimitSmall = ctx.base.layout.primaryLineLimitSmall
                    r.primaryLineLimit = ctx.base.layout.primaryLineLimit
                    r.secondaryLineLimitSmall = ctx.base.layout.secondaryLineLimitSmall
                    r.secondaryLineLimit = ctx.base.layout.secondaryLineLimit

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .bold,
                title: "Weather Neon",
                subtitle: "Midnight + glow",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = 8

                    r.background = .midnight
                    r.backgroundOverlay = rng.pick(from: [.accentGlow, .radialGlow])
                    r.backgroundOverlayOpacity = Double(rng.int(in: 10...22)) / 100.0
                    r.backgroundGlowEnabled = true

                    r.accent = rng.pick(from: [.teal, .pink, .purple, .indigo])

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 14...22))
                    r.cornerRadius = Double(rng.int(in: 18...30))
                    r.symbolSize = Double(rng.int(in: 34...50))
                    r.weatherScale = Double(rng.int(in: 98...124)) / 100.0

                    r.primaryLineLimitSmall = ctx.base.layout.primaryLineLimitSmall
                    r.primaryLineLimit = ctx.base.layout.primaryLineLimit
                    r.secondaryLineLimitSmall = ctx.base.layout.secondaryLineLimitSmall
                    r.secondaryLineLimit = ctx.base.layout.secondaryLineLimit

                    return r
                }
            )
        )

        return looks
    }

    static func makeNextUpLooks(context: RemixContext) -> [Look] {
        var looks: [Look] = []

        looks.append(
            Look(
                kind: .subtle,
                title: "Next Up — Glass",
                subtitle: "Material base + restrained accent",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .nextUpCalendar
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = .subtleMaterial
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = .headline
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...20))
                    r.symbolSize = Double(rng.int(in: 30...40))

                    r.primaryLineLimitSmall = ctx.base.layout.primaryLineLimitSmall
                    r.primaryLineLimit = ctx.base.layout.primaryLineLimit
                    r.secondaryLineLimitSmall = ctx.base.layout.secondaryLineLimitSmall
                    r.secondaryLineLimit = ctx.base.layout.secondaryLineLimit

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .colour,
                title: "Next Up — Aurora",
                subtitle: "Gradient wash",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .nextUpCalendar
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = rng.pick(from: [.aurora, .radialGlow])
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.20)

                    r.accent = rng.pick(from: [.blue, .teal, .indigo, .purple])

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = .headline
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...22))
                    r.symbolSize = Double(rng.int(in: 30...44))

                    r.primaryLineLimitSmall = ctx.base.layout.primaryLineLimitSmall
                    r.primaryLineLimit = ctx.base.layout.primaryLineLimit
                    r.secondaryLineLimitSmall = ctx.base.layout.secondaryLineLimitSmall
                    r.secondaryLineLimit = ctx.base.layout.secondaryLineLimit

                    return r
                }
            )
        )

        looks.append(
            Look(
                kind: .bold,
                title: "Next Up — Midnight",
                subtitle: "Dark base + glow",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .nextUpCalendar
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = .midnight
                    r.backgroundOverlay = rng.pick(from: [.accentGlow, .radialGlow])
                    r.backgroundOverlayOpacity = Double(rng.int(in: 10...22)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.30)

                    r.accent = rng.pick(from: [.indigo, .purple, .teal, .pink])

                    r.nameTextStyle = .caption
                    r.primaryTextStyle = .headline
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...22))
                    r.symbolSize = Double(rng.int(in: 32...48))

                    r.primaryLineLimitSmall = ctx.base.layout.primaryLineLimitSmall
                    r.primaryLineLimit = ctx.base.layout.primaryLineLimit
                    r.secondaryLineLimitSmall = ctx.base.layout.secondaryLineLimitSmall
                    r.secondaryLineLimit = ctx.base.layout.secondaryLineLimit

                    return r
                }
            )
        )

        return looks
    }
}
