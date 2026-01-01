//
//  WidgetWeaverRemixEngine+Looks+Bold.swift
//  WidgetWeaver
//
//  Created by . . on 1/1/26.
//

import Foundation

extension WidgetWeaverRemixEngine {

    // MARK: - Bold looks

    static func makeBoldLooks(context _: RemixContext) -> [Look] {
        var looks: [Look] = []

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
}
