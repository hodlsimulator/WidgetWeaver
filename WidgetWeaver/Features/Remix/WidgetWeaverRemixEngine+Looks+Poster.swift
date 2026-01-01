//
//  WidgetWeaverRemixEngine+Looks+Poster.swift
//  WidgetWeaver
//
//  Created by . . on 1/1/26.
//

import Foundation

extension WidgetWeaverRemixEngine {

    // MARK: - Poster looks

    static func makePosterLooks(context _: RemixContext) -> [Look] {
        var looks: [Look] = []

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

        return looks
    }
}
