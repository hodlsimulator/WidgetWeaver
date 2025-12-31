//
//  WidgetWeaverRemixEngine.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import Foundation

enum WidgetWeaverRemixEngine {

    enum Kind: String, Hashable, CaseIterable, Identifiable, Sendable {
        case subtle
        case colour
        case layout
        case typography
        case poster
        case bold

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .subtle: return "Polished"
            case .colour: return "Colour"
            case .layout: return "Layout"
            case .typography: return "Type"
            case .poster: return "Poster"
            case .bold: return "Bold"
            }
        }

        var systemImageName: String {
            switch self {
            case .subtle: return "sparkles"
            case .colour: return "paintpalette"
            case .layout: return "square.grid.2x2"
            case .typography: return "textformat"
            case .poster: return "photo"
            case .bold: return "bolt.fill"
            }
        }

        var sortOrder: Int {
            switch self {
            case .subtle: return 0
            case .colour: return 1
            case .layout: return 2
            case .typography: return 3
            case .poster: return 4
            case .bold: return 5
            }
        }
    }

    struct Variant: Hashable, Identifiable {
        let id: UUID
        let title: String
        let subtitle: String
        let kind: Kind
        let spec: WidgetSpec

        init(
            id: UUID = UUID(),
            title: String,
            subtitle: String,
            kind: Kind,
            spec: WidgetSpec
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.kind = kind
            self.spec = spec
        }
    }

    /// Generates a curated set of variants that preserve text and content.
    ///
    /// - Notes:
    ///   - Each call uses a fresh seed by default (so "Again" actually changes the results).
    ///   - For Weather / Next Up templates, the template is kept stable and only style/typography are remixed.
    static func generateVariants(from base: WidgetSpec, count: Int = 12, seed: UInt64? = nil) -> [Variant] {
        let base = base.normalised()
        let context = RemixContext(base: base)

        var rng = SeededRNG(seed: seed ?? UInt64.random(in: 0...UInt64.max))

        let looks = makeLooks(context: context)
        var looksByKind = Dictionary(grouping: looks, by: { $0.kind })

        var out: [Variant] = []
        out.reserveCapacity(max(0, count))

        var usedSpecs = Set<WidgetSpec>()

        let kindCycle = selectionCycle(context: context)
        var guardCounter = 0

        while out.count < count && guardCounter < 500 {
            guardCounter += 1

            let desiredKind = kindCycle[out.count % kindCycle.count]

            if var bucket = looksByKind[desiredKind], !bucket.isEmpty {
                let idx = rng.int(in: 0...(bucket.count - 1))
                let look = bucket.remove(at: idx)
                looksByKind[desiredKind] = bucket

                let recipe = look.makeRecipe(&rng, context)
                let spec = apply(recipe: recipe, to: base)

                if spec == base { continue }
                if usedSpecs.insert(spec).inserted {
                    out.append(
                        Variant(
                            title: look.title,
                            subtitle: look.subtitle,
                            kind: desiredKind,
                            spec: spec
                        )
                    )
                }
                continue
            }

            // Bucket empty; try any remaining bucket.
            let remainingKinds = looksByKind
                .filter { !$0.value.isEmpty }
                .map { $0.key }

            guard let fallbackKind = remainingKinds.min(by: { $0.sortOrder < $1.sortOrder }) else {
                break
            }

            if var bucket = looksByKind[fallbackKind], !bucket.isEmpty {
                let idx = rng.int(in: 0...(bucket.count - 1))
                let look = bucket.remove(at: idx)
                looksByKind[fallbackKind] = bucket

                let recipe = look.makeRecipe(&rng, context)
                let spec = apply(recipe: recipe, to: base)

                if spec == base { continue }
                if usedSpecs.insert(spec).inserted {
                    out.append(
                        Variant(
                            title: look.title,
                            subtitle: look.subtitle,
                            kind: fallbackKind,
                            spec: spec
                        )
                    )
                }
            }
        }

        if out.count < count {
            // Fallback: bounded random recipes so the sheet always fills.
            while out.count < count {
                let recipe = randomRecipe(using: &rng, context: context)
                let spec = apply(recipe: recipe, to: base)
                if spec == base { continue }
                if usedSpecs.insert(spec).inserted {
                    out.append(
                        Variant(
                            title: "Wildcard",
                            subtitle: "Bounded random knobs",
                            kind: .bold,
                            spec: spec
                        )
                    )
                }
            }
        }

        return out
    }
}

// MARK: - Remix Context

private struct RemixContext {
    let base: WidgetSpec

    let baseTemplate: LayoutTemplateToken
    let baseAccent: AccentToken

    let hasImage: Bool
    let hasSymbol: Bool
    let hasSecondaryText: Bool

    let isWeatherTemplate: Bool
    let isNextUpTemplate: Bool

    init(base: WidgetSpec) {
        self.base = base
        self.baseTemplate = base.layout.template
        self.baseAccent = base.style.accent

        self.hasImage = base.image != nil
        self.hasSymbol = base.symbol != nil
        self.hasSecondaryText = (base.secondaryText != nil) && !(base.secondaryText?.isEmpty ?? true)

        self.isWeatherTemplate = base.layout.template == .weather
        self.isNextUpTemplate = base.layout.template == .nextUpCalendar
    }

    var isSpecialTemplate: Bool {
        isWeatherTemplate || isNextUpTemplate
    }

    var allowedTemplates: [LayoutTemplateToken] {
        if isWeatherTemplate { return [.weather] }
        if isNextUpTemplate { return [.nextUpCalendar] }

        // Keep remix within the "content templates". Weather/NextUp can be selected explicitly elsewhere.
        if hasImage {
            return [.poster, .classic, .hero]
        }
        return [.classic, .hero, .poster]
    }

    func nearAccents() -> [AccentToken] {
        switch baseAccent {
        case .blue:
            return [.blue, .teal, .indigo, .purple]
        case .teal:
            return [.teal, .blue, .green, .indigo]
        case .green:
            return [.green, .teal, .yellow, .blue]
        case .orange:
            return [.orange, .yellow, .red, .pink]
        case .pink:
            return [.pink, .purple, .red, .orange]
        case .purple:
            return [.purple, .indigo, .pink, .blue]
        case .red:
            return [.red, .orange, .pink, .yellow]
        case .yellow:
            return [.yellow, .orange, .green]
        case .gray:
            return [.gray, .indigo, .blue]
        case .indigo:
            return [.indigo, .blue, .purple, .teal]
        }
    }
}

// MARK: - Looks

private struct Look {
    let kind: WidgetWeaverRemixEngine.Kind
    let title: String
    let subtitle: String
    let makeRecipe: (inout SeededRNG, RemixContext) -> Recipe
}

private extension WidgetWeaverRemixEngine {

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

// MARK: - Recipe

private struct Recipe: Hashable {
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

private extension WidgetWeaverRemixEngine {

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
