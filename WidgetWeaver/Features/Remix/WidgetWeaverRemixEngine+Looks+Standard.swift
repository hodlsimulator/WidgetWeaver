//
//  WidgetWeaverRemixEngine+Looks+Standard.swift
//  WidgetWeaver
//
//  Created by . . on 1/1/26.
//

import Foundation

extension WidgetWeaverRemixEngine {

    // MARK: - Standard looks (Subtle / Colour / Layout / Typography)

    static func makeSubtleLooks(context _: RemixContext) -> [Look] {
        var looks: [Look] = []

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

        return looks
    }

    static func makeColourLooks(context _: RemixContext) -> [Look] {
        var looks: [Look] = []

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

        return looks
    }

    static func makeLayoutLooks(context _: RemixContext) -> [Look] {
        var looks: [Look] = []

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

        return looks
    }

    static func makeTypographyLooks(context _: RemixContext) -> [Look] {
        var looks: [Look] = []

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

        return looks
    }
}
