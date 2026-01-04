//
//  WidgetWeaverRemixEngine+Looks+Special.swift
//  WidgetWeaver
//
//  Created by . . on 1/1/26.
//

import Foundation

extension WidgetWeaverRemixEngine {

    // MARK: - Special templates (Weather / Next Up)

    static func makeWeatherLooks(context _: RemixContext) -> [Look] {
        var looks: [Look] = []

        // MARK: Subtle

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
                kind: .subtle,
                title: "Weather Clean",
                subtitle: "Plain base + soft overlay",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = rng.pick(from: [.leading, .centre])
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = .plain
                    r.backgroundOverlay = rng.pick(from: [.radialGlow, .accentGlow])
                    r.backgroundOverlayOpacity = Double(rng.int(in: 10...22)) / 100.0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 14...22))
                    r.cornerRadius = Double(rng.int(in: 18...30))
                    r.symbolSize = Double(rng.int(in: 32...46))
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
                kind: .subtle,
                title: "Weather Frost",
                subtitle: "Material base + dark tint",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...12))

                    r.background = .subtleMaterial
                    r.backgroundOverlay = .midnight
                    r.backgroundOverlayOpacity = Double(rng.int(in: 6...14)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.15)

                    r.accent = rng.pick(from: [.gray, .indigo, .blue, .teal])

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 14...22))
                    r.cornerRadius = Double(rng.int(in: 18...30))
                    r.symbolSize = Double(rng.int(in: 32...44))
                    r.weatherScale = Double(rng.int(in: 92...114)) / 100.0

                    r.primaryLineLimitSmall = ctx.base.layout.primaryLineLimitSmall
                    r.primaryLineLimit = ctx.base.layout.primaryLineLimit
                    r.secondaryLineLimitSmall = ctx.base.layout.secondaryLineLimitSmall
                    r.secondaryLineLimit = ctx.base.layout.secondaryLineLimit

                    return r
                }
            )
        )

        // MARK: Layout

        looks.append(
            Look(
                kind: .layout,
                title: "Weather Airy",
                subtitle: "More padding + breathing room",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = rng.pick(from: [.leading, .centre])
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 12...20))

                    r.background = rng.pick(from: [.subtleMaterial, .plain])
                    r.backgroundOverlay = (r.background == .plain) ? .radialGlow : .plain
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? 0 : Double(rng.int(in: 8...16)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.15)

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 20...30))
                    r.cornerRadius = Double(rng.int(in: 22...34))
                    r.symbolSize = Double(rng.int(in: 36...54))
                    r.weatherScale = Double(rng.int(in: 100...124)) / 100.0

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
                kind: .layout,
                title: "Weather Compact",
                subtitle: "Tighter spacing + smaller padding",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 6...10))

                    r.background = rng.pick(from: [.subtleMaterial, .plain])
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 12...18))
                    r.cornerRadius = Double(rng.int(in: 18...28))
                    r.symbolSize = Double(rng.int(in: 30...44))
                    r.weatherScale = Double(rng.int(in: 90...112)) / 100.0

                    r.primaryLineLimitSmall = ctx.base.layout.primaryLineLimitSmall
                    r.primaryLineLimit = ctx.base.layout.primaryLineLimit
                    r.secondaryLineLimitSmall = ctx.base.layout.secondaryLineLimitSmall
                    r.secondaryLineLimit = ctx.base.layout.secondaryLineLimit

                    return r
                }
            )
        )

        // MARK: Colour

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
                kind: .colour,
                title: "Weather Sunset",
                subtitle: "Warm gradient with glow",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = .sunset
                    r.backgroundOverlay = rng.pick(from: [.plain, .radialGlow])
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? 0 : Double(rng.int(in: 6...14)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.25)

                    r.accent = rng.pick(from: [.orange, .pink, .red, .yellow, .purple])

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 14...24))
                    r.cornerRadius = Double(rng.int(in: 18...30))
                    r.symbolSize = Double(rng.int(in: 32...48))
                    r.weatherScale = Double(rng.int(in: 92...120)) / 100.0

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
                title: "Weather Solid",
                subtitle: "Solid accent + overlay",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = rng.pick(from: [.leading, .centre])
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = .solidAccent
                    r.backgroundOverlay = rng.pick(from: [.plain, .accentGlow, .radialGlow])
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? Double(rng.int(in: 8...16)) / 100.0 : Double(rng.int(in: 8...18)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.20)

                    r.accent = rng.pick(from: AccentToken.allCases)

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 14...24))
                    r.cornerRadius = Double(rng.int(in: 18...30))
                    r.symbolSize = Double(rng.int(in: 34...52))
                    r.weatherScale = Double(rng.int(in: 94...122)) / 100.0

                    r.primaryLineLimitSmall = ctx.base.layout.primaryLineLimitSmall
                    r.primaryLineLimit = ctx.base.layout.primaryLineLimit
                    r.secondaryLineLimitSmall = ctx.base.layout.secondaryLineLimitSmall
                    r.secondaryLineLimit = ctx.base.layout.secondaryLineLimit

                    return r
                }
            )
        )

        // MARK: Typography

        looks.append(
            Look(
                kind: .typography,
                title: "Weather Big Type",
                subtitle: "Larger primary text",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...12))

                    r.background = rng.pick(from: [.subtleMaterial, .plain])
                    r.backgroundOverlay = (r.background == .plain && rng.bool(probability: 0.45)) ? .radialGlow : .plain
                    r.backgroundOverlayOpacity = (r.backgroundOverlay == .plain) ? 0 : Double(rng.int(in: 8...16)) / 100.0
                    r.backgroundGlowEnabled = rng.bool(probability: 0.10)

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption2
                    r.primaryTextStyle = rng.pick(from: [.title2, .title3])
                    r.secondaryTextStyle = rng.pick(from: [.footnote, .caption])

                    r.padding = Double(rng.int(in: 14...22))
                    r.cornerRadius = Double(rng.int(in: 18...30))
                    r.symbolSize = Double(rng.int(in: 40...58))
                    r.weatherScale = Double(rng.int(in: 98...124)) / 100.0

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
                kind: .typography,
                title: "Weather Compact Type",
                subtitle: "Tighter type scale",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = rng.pick(from: [.leading, .centre])
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...12))

                    r.background = .subtleMaterial
                    r.backgroundOverlay = .plain
                    r.backgroundOverlayOpacity = 0
                    r.backgroundGlowEnabled = false

                    r.accent = rng.pick(from: ctx.nearAccents())

                    r.nameTextStyle = .caption2
                    r.primaryTextStyle = rng.pick(from: [.headline, .subheadline, .body])
                    r.secondaryTextStyle = .caption2

                    r.padding = Double(rng.int(in: 14...20))
                    r.cornerRadius = Double(rng.int(in: 18...28))
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

        // MARK: Bold

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

        looks.append(
            Look(
                kind: .bold,
                title: "Weather Storm",
                subtitle: "Solid accent + glow",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = .leading
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = rng.pick(from: [.midnight, .solidAccent])
                    r.backgroundOverlay = rng.pick(from: [.accentGlow, .radialGlow])
                    r.backgroundOverlayOpacity = Double(rng.int(in: 12...26)) / 100.0
                    r.backgroundGlowEnabled = true

                    r.accent = rng.pick(from: [.blue, .teal, .indigo, .purple])

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 14...24))
                    r.cornerRadius = Double(rng.int(in: 18...30))
                    r.symbolSize = Double(rng.int(in: 36...56))
                    r.weatherScale = Double(rng.int(in: 100...126)) / 100.0

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
                title: "Weather Pop",
                subtitle: "Accent glow focus",
                makeRecipe: { rng, ctx in
                    var r = Recipe(base: ctx.base)
                    r.template = .weather
                    r.alignment = rng.pick(from: [.leading, .centre])
                    r.showsAccentBar = false
                    r.spacing = Double(rng.int(in: 8...14))

                    r.background = rng.pick(from: [.accentGlow, .radialGlow])
                    r.backgroundOverlay = .midnight
                    r.backgroundOverlayOpacity = Double(rng.int(in: 6...14)) / 100.0
                    r.backgroundGlowEnabled = true

                    r.accent = rng.pick(from: [.teal, .pink, .purple, .indigo, .orange])

                    r.nameTextStyle = .automatic
                    r.primaryTextStyle = .automatic
                    r.secondaryTextStyle = .automatic

                    r.padding = Double(rng.int(in: 14...24))
                    r.cornerRadius = Double(rng.int(in: 18...30))
                    r.symbolSize = Double(rng.int(in: 34...54))
                    r.weatherScale = Double(rng.int(in: 96...124)) / 100.0

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

    static func makeNextUpLooks(context _: RemixContext) -> [Look] {
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
