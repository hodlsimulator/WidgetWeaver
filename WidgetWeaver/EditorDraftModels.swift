//
//  EditorDraftModels.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import WidgetKit

// MARK: - StyleDraft

struct StyleDraft: Hashable {
    var background: BackgroundToken
    var accent: AccentToken

    var primaryTextStyle: TextStyleToken
    var secondaryTextStyle: TextStyleToken
    var tertiaryTextStyle: TextStyleToken

    var primaryFont: FontToken
    var secondaryFont: FontToken
    var tertiaryFont: FontToken

    var primarySize: Double
    var secondarySize: Double
    var tertiarySize: Double

    var primaryWeight: FontWeightToken
    var secondaryWeight: FontWeightToken
    var tertiaryWeight: FontWeightToken

    var primaryTextColour: TextColourToken
    var secondaryTextColour: TextColourToken
    var tertiaryTextColour: TextColourToken

    var shadowStyle: ShadowStyleToken
    var shadowOpacity: Double
    var shadowRadius: Double
    var shadowX: Double
    var shadowY: Double

    var usesTheme: Bool
    var themeImageFileName: String
    var themeScale: Double
    var themeStrategy: ThemeStrategyToken
    var themeControlsAccent: Bool
    var themeControlsText: Bool
    var themeControlsBackground: Bool

    var weatherScale: Double
    var weatherBlur: Double

    static var defaultDraft: StyleDraft {
        StyleDraft(from: WidgetSpec.defaultSpec().style)
    }

    init(from s: StyleSpec) {
        background = s.background
        accent = s.accent

        primaryTextStyle = s.primaryTextStyle
        secondaryTextStyle = s.secondaryTextStyle
        tertiaryTextStyle = s.tertiaryTextStyle

        primaryFont = s.primaryFont
        secondaryFont = s.secondaryFont
        tertiaryFont = s.tertiaryFont

        primarySize = s.primarySize
        secondarySize = s.secondarySize
        tertiarySize = s.tertiarySize

        primaryWeight = s.primaryWeight
        secondaryWeight = s.secondaryWeight
        tertiaryWeight = s.tertiaryWeight

        primaryTextColour = s.primaryTextColour
        secondaryTextColour = s.secondaryTextColour
        tertiaryTextColour = s.tertiaryTextColour

        shadowStyle = s.shadowStyle
        shadowOpacity = s.shadowOpacity
        shadowRadius = s.shadowRadius
        shadowX = s.shadowX
        shadowY = s.shadowY

        usesTheme = s.usesTheme
        themeImageFileName = s.themeImageFileName
        themeScale = s.themeScale
        themeStrategy = s.themeStrategy
        themeControlsAccent = s.themeControlsAccent
        themeControlsText = s.themeControlsText
        themeControlsBackground = s.themeControlsBackground

        weatherScale = s.weatherScale
        weatherBlur = s.weatherBlur
    }

    func toSpec() -> StyleSpec {
        StyleSpec(
            background: background,
            accent: accent,
            primaryTextStyle: primaryTextStyle,
            secondaryTextStyle: secondaryTextStyle,
            tertiaryTextStyle: tertiaryTextStyle,
            primaryFont: primaryFont,
            secondaryFont: secondaryFont,
            tertiaryFont: tertiaryFont,
            primarySize: primarySize,
            secondarySize: secondarySize,
            tertiarySize: tertiarySize,
            primaryWeight: primaryWeight,
            secondaryWeight: secondaryWeight,
            tertiaryWeight: tertiaryWeight,
            primaryTextColour: primaryTextColour,
            secondaryTextColour: secondaryTextColour,
            tertiaryTextColour: tertiaryTextColour,
            shadowStyle: shadowStyle,
            shadowOpacity: shadowOpacity,
            shadowRadius: shadowRadius,
            shadowX: shadowX,
            shadowY: shadowY,
            usesTheme: usesTheme,
            themeImageFileName: themeImageFileName,
            themeScale: themeScale,
            themeStrategy: themeStrategy,
            themeControlsAccent: themeControlsAccent,
            themeControlsText: themeControlsText,
            themeControlsBackground: themeControlsBackground,
            weatherScale: weatherScale,
            weatherBlur: weatherBlur
        ).normalised()
    }

    mutating func apply(spec s: StyleSpec) {
        background = s.background
        accent = s.accent

        primaryTextStyle = s.primaryTextStyle
        secondaryTextStyle = s.secondaryTextStyle
        tertiaryTextStyle = s.tertiaryTextStyle

        primaryFont = s.primaryFont
        secondaryFont = s.secondaryFont
        tertiaryFont = s.tertiaryFont

        primarySize = s.primarySize
        secondarySize = s.secondarySize
        tertiarySize = s.tertiarySize

        primaryWeight = s.primaryWeight
        secondaryWeight = s.secondaryWeight
        tertiaryWeight = s.tertiaryWeight

        primaryTextColour = s.primaryTextColour
        secondaryTextColour = s.secondaryTextColour
        tertiaryTextColour = s.tertiaryTextColour

        shadowStyle = s.shadowStyle
        shadowOpacity = s.shadowOpacity
        shadowRadius = s.shadowRadius
        shadowX = s.shadowX
        shadowY = s.shadowY

        usesTheme = s.usesTheme
        themeImageFileName = s.themeImageFileName
        themeScale = s.themeScale
        themeStrategy = s.themeStrategy
        themeControlsAccent = s.themeControlsAccent
        themeControlsText = s.themeControlsText
        themeControlsBackground = s.themeControlsBackground

        weatherScale = s.weatherScale
        weatherBlur = s.weatherBlur
    }
}

// MARK: - ActionBarDraft

struct ActionBarDraft: Hashable {
    var enabled: Bool
    var showsIcon: Bool
    var icon: ActionBarIconToken
    var label: String
    var labelSize: Double
    var labelWeight: FontWeightToken
    var labelColour: TextColourToken
    var tint: AccentToken
    var backgroundOpacity: Double
    var cornerRadius: Double
    var padding: Double

    static var defaultDraft: ActionBarDraft {
        ActionBarDraft(from: WidgetSpec.defaultSpec().actionBar)
    }

    init(from a: ActionBarSpec) {
        enabled = a.enabled
        showsIcon = a.showsIcon
        icon = a.icon
        label = a.label
        labelSize = a.labelSize
        labelWeight = a.labelWeight
        labelColour = a.labelColour
        tint = a.tint
        backgroundOpacity = a.backgroundOpacity
        cornerRadius = a.cornerRadius
        padding = a.padding
    }

    func toSpec() -> ActionBarSpec {
        ActionBarSpec(
            enabled: enabled,
            showsIcon: showsIcon,
            icon: icon,
            label: label,
            labelSize: labelSize,
            labelWeight: labelWeight,
            labelColour: labelColour,
            tint: tint,
            backgroundOpacity: backgroundOpacity,
            cornerRadius: cornerRadius,
            padding: padding
        ).normalised()
    }

    mutating func apply(spec a: ActionBarSpec) {
        enabled = a.enabled
        showsIcon = a.showsIcon
        icon = a.icon
        label = a.label
        labelSize = a.labelSize
        labelWeight = a.labelWeight
        labelColour = a.labelColour
        tint = a.tint
        backgroundOpacity = a.backgroundOpacity
        cornerRadius = a.cornerRadius
        padding = a.padding
    }
}

// MARK: - FamilyDraft

struct FamilyDraft: Hashable {
    // Layout
    var template: LayoutTemplateToken
    var axis: LayoutAxisToken
    var alignment: LayoutAlignmentToken
    var spacing: Double
    var padding: Double
    var showsAccentBar: Bool

    // Primary text
    var primaryText: String
    var primaryTextRole: TextRoleToken
    var primaryTextAlignment: TextAlignmentToken
    var primaryMaxLines: Int

    // Secondary text
    var secondaryText: String
    var secondaryTextRole: TextRoleToken
    var secondaryTextAlignment: TextAlignmentToken
    var secondaryMaxLines: Int

    // Tertiary text
    var tertiaryText: String
    var tertiaryTextRole: TextRoleToken
    var tertiaryTextAlignment: TextAlignmentToken
    var tertiaryMaxLines: Int

    // Symbol
    var symbol: String
    var symbolRenderingMode: SymbolRenderingModeToken
    var symbolTint: SymbolTintToken
    var symbolWeight: SymbolWeightToken
    var symbolScale: Double
    var symbolOpacity: Double
    var symbolPlacement: SymbolPlacementToken

    // Image
    var imageFileName: String
    var imageContentMode: ImageContentModeToken
    var imageHeight: Double
    var imageCornerRadius: Double

    // Smart Photo metadata (auto-crop + per-widget renders)
    var imageSmartPhoto: WidgetWeaverSmartPhotoSpec?

    static var defaultDraft: FamilyDraft {
        FamilyDraft(from: WidgetSpec.defaultSpec().base)
    }

    init(from s: WidgetSpecVariant) {
        template = s.layout.template
        axis = s.layout.axis
        alignment = s.layout.alignment
        spacing = s.layout.spacing
        padding = s.layout.padding
        showsAccentBar = s.layout.showsAccentBar

        primaryText = s.primaryText
        primaryTextRole = s.primaryTextRole
        primaryTextAlignment = s.primaryTextAlignment
        primaryMaxLines = s.primaryMaxLines

        secondaryText = s.secondaryText ?? ""
        secondaryTextRole = s.secondaryTextRole
        secondaryTextAlignment = s.secondaryTextAlignment
        secondaryMaxLines = s.secondaryMaxLines

        tertiaryText = s.tertiaryText ?? ""
        tertiaryTextRole = s.tertiaryTextRole
        tertiaryTextAlignment = s.tertiaryTextAlignment
        tertiaryMaxLines = s.tertiaryMaxLines

        symbol = s.symbol?.name ?? ""
        symbolRenderingMode = s.symbol?.renderingMode ?? .monochrome
        symbolTint = s.symbol?.tint ?? .accent
        symbolWeight = s.symbol?.weight ?? .regular
        symbolScale = s.symbol?.scale ?? 1.0
        symbolOpacity = s.symbol?.opacity ?? 1.0
        symbolPlacement = s.symbol?.placement ?? .above

        if let img = s.image {
            imageFileName = img.fileName
            imageContentMode = img.contentMode
            imageHeight = img.height
            imageCornerRadius = img.cornerRadius
            imageSmartPhoto = img.smartPhoto
        } else {
            imageFileName = ""
            imageContentMode = .fill
            imageHeight = 120
            imageCornerRadius = 16
            imageSmartPhoto = nil
        }
    }

    func toVariantSpec() -> WidgetSpecVariant {
        let secondary: String? = secondaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : secondaryText
        let tertiary: String? = tertiaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : tertiaryText

        let symbolSpec: SymbolSpec? = {
            let trimmed = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return SymbolSpec(
                name: trimmed,
                renderingMode: symbolRenderingMode,
                tint: symbolTint,
                weight: symbolWeight,
                scale: symbolScale,
                opacity: symbolOpacity,
                placement: symbolPlacement
            ).normalised()
        }()

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
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            padding: padding,
            showsAccentBar: showsAccentBar
        ).normalised()

        return WidgetSpecVariant(
            layout: layout,
            primaryText: primaryText,
            primaryTextRole: primaryTextRole,
            primaryTextAlignment: primaryTextAlignment,
            primaryMaxLines: primaryMaxLines,
            secondaryText: secondary,
            secondaryTextRole: secondaryTextRole,
            secondaryTextAlignment: secondaryTextAlignment,
            secondaryMaxLines: secondaryMaxLines,
            tertiaryText: tertiary,
            tertiaryTextRole: tertiaryTextRole,
            tertiaryTextAlignment: tertiaryTextAlignment,
            tertiaryMaxLines: tertiaryMaxLines,
            symbol: symbolSpec,
            image: image
        ).normalised()
    }

    mutating func apply(flatSpec s: WidgetSpec) {
        let base = s.base

        template = base.layout.template
        axis = base.layout.axis
        alignment = base.layout.alignment
        spacing = base.layout.spacing
        padding = base.layout.padding
        showsAccentBar = base.layout.showsAccentBar

        primaryText = base.primaryText
        primaryTextRole = base.primaryTextRole
        primaryTextAlignment = base.primaryTextAlignment
        primaryMaxLines = base.primaryMaxLines

        secondaryText = base.secondaryText ?? ""
        secondaryTextRole = base.secondaryTextRole
        secondaryTextAlignment = base.secondaryTextAlignment
        secondaryMaxLines = base.secondaryMaxLines

        tertiaryText = base.tertiaryText ?? ""
        tertiaryTextRole = base.tertiaryTextRole
        tertiaryTextAlignment = base.tertiaryTextAlignment
        tertiaryMaxLines = base.tertiaryMaxLines

        symbol = base.symbol?.name ?? ""
        symbolRenderingMode = base.symbol?.renderingMode ?? .monochrome
        symbolTint = base.symbol?.tint ?? .accent
        symbolWeight = base.symbol?.weight ?? .regular
        symbolScale = base.symbol?.scale ?? 1.0
        symbolOpacity = base.symbol?.opacity ?? 1.0
        symbolPlacement = base.symbol?.placement ?? .above

        if let img = base.image {
            imageFileName = img.fileName
            imageContentMode = img.contentMode
            imageHeight = img.height
            imageCornerRadius = img.cornerRadius
            imageSmartPhoto = img.smartPhoto
        } else {
            imageFileName = ""
            imageSmartPhoto = nil
        }
    }
}

// MARK: - MatchedDrafts

struct MatchedDrafts: Hashable {
    var small: FamilyDraft
    var medium: FamilyDraft
    var large: FamilyDraft

    init(small: FamilyDraft, medium: FamilyDraft, large: FamilyDraft) {
        self.small = small
        self.medium = medium
        self.large = large
    }

    init(from s: MatchedSetSpec?) {
        if let s = s {
            small = FamilyDraft(from: s.small ?? WidgetSpecVariant.defaultVariantSpec())
            medium = FamilyDraft(from: s.medium ?? WidgetSpecVariant.defaultVariantSpec())
            large = FamilyDraft(from: s.large ?? WidgetSpecVariant.defaultVariantSpec())
        } else {
            small = .defaultDraft
            medium = .defaultDraft
            large = .defaultDraft
        }
    }

    func toSpecIfEnabled(enabled: Bool) -> MatchedSetSpec? {
        guard enabled else { return nil }
        return MatchedSetSpec(
            small: small.toVariantSpec(),
            medium: medium.toVariantSpec(),
            large: large.toVariantSpec()
        ).normalised()
    }

    mutating func apply(spec: MatchedSetSpec?) {
        if let s = spec {
            small = FamilyDraft(from: s.small ?? WidgetSpecVariant.defaultVariantSpec())
            medium = FamilyDraft(from: s.medium ?? WidgetSpecVariant.defaultVariantSpec())
            large = FamilyDraft(from: s.large ?? WidgetSpecVariant.defaultVariantSpec())
        } else {
            small = .defaultDraft
            medium = .defaultDraft
            large = .defaultDraft
        }
    }
}
