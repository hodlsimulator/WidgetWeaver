//
//  EditorDraftModels.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import WidgetKit

struct EditorDraft: Hashable {
    var id: UUID
    var name: String

    var style: StyleDraft
    var base: FamilyDraft

    // Matched variants (Pro only)
    var hasMatchedVariants: Bool
    var small: FamilyDraft
    var medium: FamilyDraft
    var large: FamilyDraft

    var updatedAt: Date

    static func makeNew() -> EditorDraft {
        EditorDraft(
            id: UUID(),
            name: "New Design",
            style: StyleDraft(from: StyleSpec.defaultSpec()),
            base: FamilyDraft(from: WidgetSpec.defaultSpec()),
            hasMatchedVariants: false,
            small: FamilyDraft(from: WidgetSpec.defaultSpec()),
            medium: FamilyDraft(from: WidgetSpec.defaultSpec()),
            large: FamilyDraft(from: WidgetSpec.defaultSpec()),
            updatedAt: Date()
        )
    }

    init(from spec: WidgetSpec) {
        let s = spec.normalised()
        self.id = s.id
        self.name = s.name
        self.style = StyleDraft(from: s.style)
        self.base = FamilyDraft(from: s)

        if let matched = s.matchedSet {
            self.hasMatchedVariants = true
            self.small = FamilyDraft(from: matched.small?.toSpecFallbacking(base: s) ?? s)
            self.medium = FamilyDraft(from: matched.medium?.toSpecFallbacking(base: s) ?? s)
            self.large = FamilyDraft(from: matched.large?.toSpecFallbacking(base: s) ?? s)
        } else {
            self.hasMatchedVariants = false
            self.small = FamilyDraft(from: s)
            self.medium = FamilyDraft(from: s)
            self.large = FamilyDraft(from: s)
        }

        self.updatedAt = s.updatedAt
    }

    func toWidgetSpec() -> WidgetSpec {
        let now = Date()

        let flat = base.toFlatSpec(
            id: id,
            name: name,
            style: style.toStyleSpec(),
            updatedAt: now
        )

        if hasMatchedVariants, WidgetWeaverEntitlements.isProUnlocked {
            var matched = MatchedSetSpec(
                small: small.toVariantSpec(for: .systemSmall),
                medium: medium.toVariantSpec(for: .systemMedium),
                large: large.toVariantSpec(for: .systemLarge)
            ).normalised()

            // Do not store variants identical to base (saves space, simplifies export).
            if matched.small == nil, matched.medium == nil, matched.large == nil {
                matched = MatchedSetSpec(small: nil, medium: nil, large: nil)
            }

            var out = flat
            if matched.small != nil || matched.medium != nil || matched.large != nil {
                out.matchedSet = matched
            } else {
                out.matchedSet = nil
            }
            out.updatedAt = now
            return out.normalised()
        }

        return flat.normalised()
    }
}

struct StyleDraft: Hashable {
    var backgroundColorHex: String
    var accentColorHex: String
    var primaryTextColorHex: String
    var secondaryTextColorHex: String

    var primaryFont: FontToken
    var secondaryFont: FontToken

    // Theme support
    var usesTheme: Bool
    var themeImageFileName: String
    var themeStrategy: ThemeStrategyToken
    var themeScale: Double
    var weatherScale: Double

    init(from spec: StyleSpec) {
        let s = spec.normalised()
        self.backgroundColorHex = s.backgroundColorHex
        self.accentColorHex = s.accentColorHex
        self.primaryTextColorHex = s.primaryTextColorHex
        self.secondaryTextColorHex = s.secondaryTextColorHex
        self.primaryFont = s.primaryFont
        self.secondaryFont = s.secondaryFont

        self.usesTheme = s.usesTheme
        self.themeImageFileName = s.themeImageFileName
        self.themeStrategy = s.themeStrategy
        self.themeScale = s.themeScale
        self.weatherScale = s.weatherScale
    }

    func toStyleSpec() -> StyleSpec {
        StyleSpec(
            backgroundColorHex: backgroundColorHex,
            accentColorHex: accentColorHex,
            primaryTextColorHex: primaryTextColorHex,
            secondaryTextColorHex: secondaryTextColorHex,
            primaryFont: primaryFont,
            secondaryFont: secondaryFont,
            usesTheme: usesTheme,
            themeImageFileName: themeImageFileName,
            themeStrategy: themeStrategy,
            themeScale: themeScale,
            weatherScale: weatherScale
        ).normalised()
    }
}

struct FamilyDraft: Hashable {
    // Text
    var primaryText: String
    var secondaryText: String

    // Symbol
    var symbolName: String
    var symbolPlacement: SymbolPlacementToken
    var symbolSize: Double
    var symbolWeight: SymbolWeightToken
    var symbolRenderingMode: SymbolRenderingModeToken
    var symbolTint: WidgetColorToken

    // Image
    var imageFileName: String
    var imageContentMode: ImageContentModeToken
    var imageHeight: Double
    var imageCornerRadius: Double
    var imageSmartPhoto: WidgetWeaverSmartPhotoSpec?

    // Layout
    var template: LayoutTemplateToken
    var showsAccentBar: Bool
    var axis: LayoutAxisToken
    var alignment: LayoutAlignmentToken
    var spacing: Double
    var primaryLineLimitSmall: Int
    var primaryLineLimit: Int
    var secondaryLineLimit: Int

    init(from spec: WidgetSpec) {
        let s = spec.normalised()

        self.primaryText = s.primaryText
        self.secondaryText = s.secondaryText ?? ""

        if let sym = s.symbol {
            self.symbolName = sym.name
            self.symbolPlacement = sym.placement
            self.symbolSize = sym.size
            self.symbolWeight = sym.weight
            self.symbolRenderingMode = sym.renderingMode
            self.symbolTint = sym.tint
        } else {
            self.symbolName = ""
            self.symbolPlacement = .leading
            self.symbolSize = 42
            self.symbolWeight = .semibold
            self.symbolRenderingMode = .monochrome
            self.symbolTint = .white
        }

        if let img = s.image {
            self.imageFileName = img.fileName
            self.imageContentMode = img.contentMode
            self.imageHeight = img.height
            self.imageCornerRadius = img.cornerRadius
            self.imageSmartPhoto = img.smartPhoto
        } else {
            self.imageFileName = ""
            self.imageContentMode = .fill
            self.imageHeight = 120
            self.imageCornerRadius = 16
            self.imageSmartPhoto = nil
        }

        self.template = s.layout.template
        self.showsAccentBar = s.layout.showsAccentBar
        self.axis = s.layout.axis
        self.alignment = s.layout.alignment
        self.spacing = s.layout.spacing
        self.primaryLineLimitSmall = s.layout.primaryLineLimitSmall
        self.primaryLineLimit = s.layout.primaryLineLimit
        self.secondaryLineLimit = s.layout.secondaryLineLimit
    }

    func toFlatSpec(id: UUID, name: String, style: StyleSpec, updatedAt: Date) -> WidgetSpec {
        let trimmedPrimary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondary = secondaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        let symName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol: SymbolSpec? = symName.isEmpty ? nil : SymbolSpec(
            name: symName,
            placement: symbolPlacement,
            size: symbolSize,
            weight: symbolWeight,
            renderingMode: symbolRenderingMode,
            tint: symbolTint
        )

        let imgName = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius,
            smartPhoto: imageSmartPhoto
        )

        let layout = LayoutSpec(
            template: template,
            showsAccentBar: showsAccentBar,
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            primaryLineLimitSmall: primaryLineLimitSmall,
            primaryLineLimit: primaryLineLimit,
            secondaryLineLimit: secondaryLineLimit
        )

        return WidgetSpec(
            id: id,
            name: name,
            primaryText: trimmedPrimary.isEmpty ? "Widget Weaver" : trimmedPrimary,
            secondaryText: trimmedSecondary.isEmpty ? nil : trimmedSecondary,
            symbol: symbol,
            image: image,
            style: style,
            layout: layout,
            matchedSet: nil,
            updatedAt: updatedAt
        ).normalised()
    }

    func toVariantSpec(for family: WidgetFamily) -> WidgetSpecVariant? {
        let s = WidgetSpec.defaultSpec().resolved(for: family)

        let trimmedPrimary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondary = secondaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        let symName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol: SymbolSpec? = symName.isEmpty ? nil : SymbolSpec(
            name: symName,
            placement: symbolPlacement,
            size: symbolSize,
            weight: symbolWeight,
            renderingMode: symbolRenderingMode,
            tint: symbolTint
        )

        let imgName = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius,
            smartPhoto: imageSmartPhoto
        )

        let layout = LayoutSpec(
            template: template,
            showsAccentBar: showsAccentBar,
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            primaryLineLimitSmall: primaryLineLimitSmall,
            primaryLineLimit: primaryLineLimit,
            secondaryLineLimit: secondaryLineLimit
        )

        let candidate = WidgetSpecVariant(
            primaryText: trimmedPrimary.isEmpty ? s.primaryText : trimmedPrimary,
            secondaryText: trimmedSecondary.isEmpty ? nil : trimmedSecondary,
            symbol: symbol,
            image: image,
            layout: layout
        ).normalised()

        let base = s.normalised()
        if candidate.primaryText == base.primaryText,
           candidate.secondaryText == base.secondaryText,
           candidate.symbol == base.symbol,
           candidate.image == base.image,
           candidate.layout == base.layout
        {
            return nil
        }

        return candidate
    }

    mutating func apply(flatSpec spec: WidgetSpec) {
        let s = spec.normalised()

        primaryText = s.primaryText
        secondaryText = s.secondaryText ?? ""

        if let sym = s.symbol {
            symbolName = sym.name
            symbolPlacement = sym.placement
            symbolSize = sym.size
            symbolWeight = sym.weight
            symbolRenderingMode = sym.renderingMode
            symbolTint = sym.tint
        } else {
            symbolName = ""
        }

        if let img = s.image {
            imageFileName = img.fileName
            imageContentMode = img.contentMode
            imageHeight = img.height
            imageCornerRadius = img.cornerRadius
            imageSmartPhoto = img.smartPhoto
        } else {
            imageFileName = ""
            imageSmartPhoto = nil
        }

        template = s.layout.template
        showsAccentBar = s.layout.showsAccentBar
        axis = s.layout.axis
        alignment = s.layout.alignment
        spacing = s.layout.spacing
        primaryLineLimitSmall = s.layout.primaryLineLimitSmall
        primaryLineLimit = s.layout.primaryLineLimit
        secondaryLineLimit = s.layout.secondaryLineLimit
    }
}


// MARK: - Actions (Interactive Widget Buttons)

struct ActionDraft: Hashable, Identifiable {
    var id: UUID
    var title: String
    var message: String
    var urlString: String
}
