//
//  EditorDraftModels.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import WidgetKit

// MARK: - Draft models

enum EditingFamily: String, CaseIterable {
    case small
    case medium
    case large

    init?(widgetFamily: WidgetFamily) {
        switch widgetFamily {
        case .systemSmall: self = .small
        case .systemMedium: self = .medium
        case .systemLarge: self = .large
        default: return nil
        }
    }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
}

struct MatchedDrafts: Hashable {
    var small: FamilyDraft
    var medium: FamilyDraft
    var large: FamilyDraft

    subscript(_ family: EditingFamily) -> FamilyDraft {
        get {
            switch family {
            case .small: return small
            case .medium: return medium
            case .large: return large
            }
        }
        set {
            switch family {
            case .small: small = newValue
            case .medium: medium = newValue
            case .large: large = newValue
            }
        }
    }
}

struct StyleDraft: Hashable {
    var padding: Double
    var cornerRadius: Double
    var weatherScale: Double
    var background: BackgroundToken
    var accent: AccentToken
    var nameTextStyle: TextStyleToken
    var primaryTextStyle: TextStyleToken
    var secondaryTextStyle: TextStyleToken

    static var defaultDraft: StyleDraft { StyleDraft(from: .defaultStyle) }

    init(from style: StyleSpec) {
        self.padding = style.padding
        self.cornerRadius = style.cornerRadius
        self.weatherScale = style.weatherScale
        self.background = style.background
        self.accent = style.accent
        self.nameTextStyle = style.nameTextStyle
        self.primaryTextStyle = style.primaryTextStyle
        self.secondaryTextStyle = style.secondaryTextStyle
    }

    func toStyleSpec() -> StyleSpec {
        StyleSpec(
            padding: padding,
            cornerRadius: cornerRadius,
            background: background,
            accent: accent,
            nameTextStyle: nameTextStyle,
            primaryTextStyle: primaryTextStyle,
            secondaryTextStyle: secondaryTextStyle,
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
    var symbolTint: SymbolTintToken

    // Image
    var imageFileName: String
    var imageContentMode: ImageContentModeToken
    var imageHeight: Double
    var imageCornerRadius: Double

    // Layout
    var template: LayoutTemplateToken
    var showsAccentBar: Bool
    var axis: LayoutAxisToken
    var alignment: LayoutAlignmentToken
    var spacing: Double
    var primaryLineLimitSmall: Int
    var primaryLineLimit: Int
    var secondaryLineLimit: Int

    static var defaultDraft: FamilyDraft { FamilyDraft(from: WidgetSpec.defaultSpec()) }

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
            self.symbolPlacement = .beforeName
            self.symbolSize = 18
            self.symbolWeight = .regular
            self.symbolRenderingMode = .monochrome
            self.symbolTint = .accent
        }

        if let img = s.image {
            self.imageFileName = img.fileName
            self.imageContentMode = img.contentMode
            self.imageHeight = img.height
            self.imageCornerRadius = img.cornerRadius
        } else {
            self.imageFileName = ""
            self.imageContentMode = .fill
            self.imageHeight = 120
            self.imageCornerRadius = 16
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
            size: symbolSize,
            weight: symbolWeight,
            renderingMode: symbolRenderingMode,
            tint: symbolTint,
            placement: symbolPlacement
        )

        let imgName = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius
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
        ).normalised()

        return WidgetSpec(
            id: id,
            name: name,
            primaryText: template == .weather ? trimmedPrimary : (trimmedPrimary.isEmpty ? "Hello" : trimmedPrimary),
            secondaryText: trimmedSecondary.isEmpty ? nil : trimmedSecondary,
            updatedAt: updatedAt,
            symbol: symbol,
            image: image,
            layout: layout,
            style: style,
            matchedSet: nil
        ).normalised()
    }

    func toVariantSpec() -> WidgetSpecVariant {
        let trimmedPrimary = primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecondary = secondaryText.trimmingCharacters(in: .whitespacesAndNewlines)

        let symName = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        let symbol: SymbolSpec? = symName.isEmpty ? nil : SymbolSpec(
            name: symName,
            size: symbolSize,
            weight: symbolWeight,
            renderingMode: symbolRenderingMode,
            tint: symbolTint,
            placement: symbolPlacement
        )

        let imgName = imageFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius
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
        ).normalised()

        return WidgetSpecVariant(
            primaryText: layout.template == .weather ? trimmedPrimary : (trimmedPrimary.isEmpty ? "Hello" : trimmedPrimary),
            secondaryText: trimmedSecondary.isEmpty ? nil : trimmedSecondary,
            symbol: symbol,
            image: image,
            layout: layout
        ).normalised()
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
        } else {
            imageFileName = ""
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

struct ActionBarDraft: Hashable {
    var isEnabled: Bool
    var style: WidgetActionButtonStyleToken
    var actions: [WidgetActionDraft]

    static var defaultDraft: ActionBarDraft {
        ActionBarDraft(isEnabled: false, style: .prominent, actions: [])
    }

    init(isEnabled: Bool, style: WidgetActionButtonStyleToken, actions: [WidgetActionDraft]) {
        self.isEnabled = isEnabled
        self.style = style
        self.actions = actions
    }

    init(from spec: WidgetActionBarSpec?) {
        guard let bar = spec?.normalisedOrNil() else {
            self = .defaultDraft
            return
        }
        self.isEnabled = true
        self.style = bar.style
        self.actions = bar.actions.map { WidgetActionDraft(from: $0) }
    }

    func toActionBarSpec() -> WidgetActionBarSpec? {
        guard isEnabled else { return nil }
        let specs = actions.compactMap { $0.toActionSpecOrNil() }
        return WidgetActionBarSpec(actions: specs, style: style).normalisedOrNil()
    }
}

struct WidgetActionDraft: Hashable, Identifiable {
    var id: UUID
    var title: String
    var systemImage: String
    var kind: WidgetActionKindToken
    var variableKey: String
    var incrementAmount: Int
    var nowFormat: WidgetNowFormatToken

    init(
        id: UUID = UUID(),
        title: String = "",
        systemImage: String = "",
        kind: WidgetActionKindToken = .incrementVariable,
        variableKey: String = "",
        incrementAmount: Int = 1,
        nowFormat: WidgetNowFormatToken = .iso8601
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
        self.variableKey = variableKey
        self.incrementAmount = incrementAmount
        self.nowFormat = nowFormat
    }

    init(from spec: WidgetActionSpec) {
        self.id = spec.id
        self.title = spec.title
        self.systemImage = spec.systemImage ?? ""
        self.kind = spec.kind
        self.variableKey = spec.variableKey
        self.incrementAmount = spec.incrementAmount
        self.nowFormat = spec.nowFormat
    }

    static func defaultIncrement() -> WidgetActionDraft {
        WidgetActionDraft(
            title: "+1",
            systemImage: "plus.circle.fill",
            kind: .incrementVariable,
            variableKey: "counter",
            incrementAmount: 1,
            nowFormat: .iso8601
        )
    }

    static func defaultDone() -> WidgetActionDraft {
        WidgetActionDraft(
            title: "Done",
            systemImage: "checkmark.circle.fill",
            kind: .setVariableToNow,
            variableKey: "last_done",
            incrementAmount: 1,
            nowFormat: .iso8601
        )
    }

    func toActionSpecOrNil() -> WidgetActionSpec? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSymbol = systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = variableKey.trimmingCharacters(in: .whitespacesAndNewlines)

        return WidgetActionSpec(
            id: id,
            title: trimmedTitle.isEmpty ? (kind == .incrementVariable ? "+1" : "Done") : trimmedTitle,
            systemImage: trimmedSymbol.isEmpty ? nil : trimmedSymbol,
            kind: kind,
            variableKey: trimmedKey,
            incrementAmount: incrementAmount,
            nowFormat: nowFormat
        ).normalisedOrNil()
    }
}
