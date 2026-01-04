//
//  WidgetWeaverRemixEngine.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import Foundation

/// Produces style/layout variations of a `WidgetSpec` while keeping user content intact.
///
/// - Preserved: name, primary/secondary text, symbol, image, actions, matched-set metadata.
/// - Remixed: layout + style knobs (template, alignment, spacing, padding, background, accent, typography, etc.).
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
