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
    var backgroundOverlay: BackgroundToken
    var backgroundOverlayOpacity: Double
    var backgroundGlowEnabled: Bool
    var accent: AccentToken
    var nameTextStyle: TextStyleToken
    var primaryTextStyle: TextStyleToken
    var secondaryTextStyle: TextStyleToken

    var symbolSize: Double

    static var defaultDraft: StyleDraft { StyleDraft(from: .defaultStyle) }

    init(from style: StyleSpec) {
        self.padding = style.padding
        self.cornerRadius = style.cornerRadius
        self.weatherScale = style.weatherScale
        self.background = style.background
        self.backgroundOverlay = style.backgroundOverlay
        self.backgroundOverlayOpacity = style.backgroundOverlayOpacity
        self.backgroundGlowEnabled = style.backgroundGlowEnabled
        self.accent = style.accent
        self.nameTextStyle = style.nameTextStyle
        self.primaryTextStyle = style.primaryTextStyle
        self.secondaryTextStyle = style.secondaryTextStyle

        self.symbolSize = style.symbolSize
    }

    func toStyleSpec() -> StyleSpec {
        StyleSpec(
            padding: padding,
            cornerRadius: cornerRadius,
            background: background,
            backgroundOverlay: backgroundOverlay,
            backgroundOverlayOpacity: backgroundOverlayOpacity,
            backgroundGlowEnabled: backgroundGlowEnabled,
            accent: accent,
            nameTextStyle: nameTextStyle,
            primaryTextStyle: primaryTextStyle,
            secondaryTextStyle: secondaryTextStyle,
            symbolSize: symbolSize,
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
    var imageSmartPhoto: SmartPhotoSpec?
    var imageContentMode: ImageContentModeToken
    var imageHeight: Double
    var imageCornerRadius: Double

    var imageFilterToken: PhotoFilterToken
    var imageFilterIntensity: Double

    // Layout
    var template: LayoutTemplateToken
    var posterOverlayMode: PosterOverlayMode
    var showsAccentBar: Bool
    var axis: LayoutAxisToken
    var alignment: LayoutAlignmentToken
    var spacing: Double
    var primaryLineLimitSmall: Int
    var primaryLineLimit: Int
    var secondaryLineLimit: Int

    // Clock
    var clockThemeRaw: String
    var clockFaceRaw: String
    var clockIconDialColourTokenRaw: String?
    var clockIconSecondHandColourTokenRaw: String?

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
            self.imageSmartPhoto = img.smartPhoto
            self.imageContentMode = img.contentMode
            self.imageHeight = img.height
            self.imageCornerRadius = img.cornerRadius

            self.imageFilterToken = img.filter?.token ?? .none
            self.imageFilterIntensity = (img.filter?.intensity ?? 1.0).normalised().clamped(to: 0.0...1.0)
        } else {
            self.imageFileName = ""
            self.imageSmartPhoto = nil
            self.imageContentMode = .fill
            self.imageHeight = 120
            self.imageCornerRadius = 16

            self.imageFilterToken = .none
            self.imageFilterIntensity = 1.0
        }

        self.template = s.layout.template
        self.posterOverlayMode = s.layout.posterOverlayMode
        self.showsAccentBar = s.layout.showsAccentBar
        self.axis = s.layout.axis
        self.alignment = s.layout.alignment
        self.spacing = s.layout.spacing
        self.primaryLineLimitSmall = s.layout.primaryLineLimitSmall
        self.primaryLineLimit = s.layout.primaryLineLimit
        self.secondaryLineLimit = s.layout.secondaryLineLimit

        if s.layout.template == .clockIcon {
            self.clockThemeRaw = s.clockConfig?.theme ?? WidgetWeaverClockDesignConfig.defaultTheme
            self.clockFaceRaw = WidgetWeaverClockFaceToken.canonical(from: s.clockConfig?.face).rawValue
            self.clockIconDialColourTokenRaw = WidgetWeaverClockIconDialColourToken
                            .canonical(from: s.clockConfig?.iconDialColourToken)?
                            .rawValue
            self.clockIconSecondHandColourTokenRaw = WidgetWeaverClockSecondHandColourToken
                .canonical(from: s.clockConfig?.iconSecondHandColourToken)?
                .rawValue
        } else {
            self.clockThemeRaw = WidgetWeaverClockDesignConfig.defaultTheme
            self.clockFaceRaw = WidgetWeaverClockDesignConfig.defaultFace
            self.clockIconDialColourTokenRaw = nil
            self.clockIconSecondHandColourTokenRaw = nil
        }
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
        let filter = PhotoFilterSpec(token: imageFilterToken, intensity: imageFilterIntensity).normalisedOrNil()
        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius,
            filter: filter,
            smartPhoto: imageSmartPhoto
        )

        let layout = LayoutSpec(
            template: template,
            posterOverlayMode: posterOverlayMode,
            showsAccentBar: showsAccentBar,
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            primaryLineLimitSmall: primaryLineLimitSmall,
            primaryLineLimit: primaryLineLimit,
            secondaryLineLimit: secondaryLineLimit
        ).normalised()

        let allowsEmptyPrimaryText = layout.template == .weather
            || layout.template == .nextUpCalendar
            || layout.template == .reminders
            || layout.template == .clockIcon

        let finalPrimaryText = allowsEmptyPrimaryText
            ? trimmedPrimary
            : (trimmedPrimary.isEmpty ? "Hello" : trimmedPrimary)

        let clockConfig: WidgetWeaverClockDesignConfig? = layout.template == .clockIcon
                    ? WidgetWeaverClockDesignConfig(theme: clockThemeRaw, face: clockFaceRaw, iconDialColourToken: clockIconDialColourTokenRaw, iconSecondHandColourToken: clockIconSecondHandColourTokenRaw)
                    : nil

        return WidgetSpec(
            id: id,
            name: name,
            primaryText: finalPrimaryText,
            secondaryText: trimmedSecondary.isEmpty ? nil : trimmedSecondary,
            updatedAt: updatedAt,
            symbol: symbol,
            image: image,
            layout: layout,
            style: style,
            clockConfig: clockConfig,
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
        let filter = PhotoFilterSpec(token: imageFilterToken, intensity: imageFilterIntensity).normalisedOrNil()
        let image: ImageSpec? = imgName.isEmpty ? nil : ImageSpec(
            fileName: imgName,
            contentMode: imageContentMode,
            height: imageHeight,
            cornerRadius: imageCornerRadius,
            filter: filter,
            smartPhoto: imageSmartPhoto
        )

        let layout = LayoutSpec(
            template: template,
            posterOverlayMode: posterOverlayMode,
            showsAccentBar: showsAccentBar,
            axis: axis,
            alignment: alignment,
            spacing: spacing,
            primaryLineLimitSmall: primaryLineLimitSmall,
            primaryLineLimit: primaryLineLimit,
            secondaryLineLimit: secondaryLineLimit
        ).normalised()

        let allowsEmptyPrimaryText = layout.template == .weather
            || layout.template == .nextUpCalendar
            || layout.template == .reminders
            || layout.template == .clockIcon

        let finalPrimaryText = allowsEmptyPrimaryText
            ? trimmedPrimary
            : (trimmedPrimary.isEmpty ? "Hello" : trimmedPrimary)

        return WidgetSpecVariant(
            primaryText: finalPrimaryText,
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
            imageSmartPhoto = img.smartPhoto
            imageContentMode = img.contentMode
            imageHeight = img.height
            imageCornerRadius = img.cornerRadius

            imageFilterToken = img.filter?.token ?? .none
            imageFilterIntensity = (img.filter?.intensity ?? 1.0).normalised().clamped(to: 0.0...1.0)
        } else {
            imageFileName = ""
            imageSmartPhoto = nil
            imageFilterToken = .none
            imageFilterIntensity = 1.0
        }

        template = s.layout.template
        posterOverlayMode = s.layout.posterOverlayMode
        showsAccentBar = s.layout.showsAccentBar
        axis = s.layout.axis
        alignment = s.layout.alignment
        spacing = s.layout.spacing
        primaryLineLimitSmall = s.layout.primaryLineLimitSmall
        primaryLineLimit = s.layout.primaryLineLimit
        secondaryLineLimit = s.layout.secondaryLineLimit

        if s.layout.template == .clockIcon {
            clockThemeRaw = s.clockConfig?.theme ?? WidgetWeaverClockDesignConfig.defaultTheme
            clockFaceRaw = WidgetWeaverClockFaceToken.canonical(from: s.clockConfig?.face).rawValue
            clockIconDialColourTokenRaw = WidgetWeaverClockIconDialColourToken
                .canonical(from: s.clockConfig?.iconDialColourToken)?
                .rawValue
            clockIconSecondHandColourTokenRaw = WidgetWeaverClockSecondHandColourToken
                .canonical(from: s.clockConfig?.iconSecondHandColourToken)?
                .rawValue
        } else {
            clockThemeRaw = WidgetWeaverClockDesignConfig.defaultTheme
            clockFaceRaw = WidgetWeaverClockDesignConfig.defaultFace
            clockIconDialColourTokenRaw = nil
            clockIconSecondHandColourTokenRaw = nil
        }
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

    mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        actions.move(fromOffsets: fromOffsets, toOffset: toOffset)
    }

    mutating func moveUp(id: UUID) {
        guard let idx = actions.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        actions.swapAt(idx, idx - 1)
    }

    mutating func moveDown(id: UUID) {
        guard let idx = actions.firstIndex(where: { $0.id == id }), idx < actions.count - 1 else { return }
        actions.swapAt(idx, idx + 1)
    }

    mutating func replace(with preset: ActionBarPreset) {
        isEnabled = true
        actions = preset.buildActions()
    }
}

enum VariableKeyValidationResult: Hashable {
    case ok
    case warning(String)
}

enum ActionBarPreset: String, CaseIterable, Identifiable {
    case counter
    case habitStreak
    case donePlusOne
    case hydration
    case pomodoro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .counter: return "Counter"
        case .habitStreak: return "Habit Streak"
        case .donePlusOne: return "Done +1"
        case .hydration: return "Hydration"
        case .pomodoro: return "Pomodoro"
        }
    }

    var description: String {
        switch self {
        case .counter:
            return "Count up/down (key: count)."
        case .habitStreak:
            return "Track a streak with Done/Undo (key: streak)."
        case .donePlusOne:
            return "Single Done button (key: done)."
        case .hydration:
            return "Quick adds for water intake (key: waterMl)."
        case .pomodoro:
            return "Start/Stop as a simple counter (key: pomo)."
        }
    }

    func buildActions() -> [WidgetActionDraft] {
        let out: [WidgetActionDraft] = {
            switch self {
            case .counter:
                return [
                    WidgetActionDraft(
                        title: "+1",
                        systemImage: "plus.circle.fill",
                        kind: .incrementVariable,
                        variableKey: "count",
                        incrementAmount: 1,
                        nowFormat: .iso8601
                    ),
                    WidgetActionDraft(
                        title: "-1",
                        systemImage: "minus.circle.fill",
                        kind: .incrementVariable,
                        variableKey: "count",
                        incrementAmount: -1,
                        nowFormat: .iso8601
                    )
                ]

            case .habitStreak:
                return [
                    WidgetActionDraft(
                        title: "Done +1",
                        systemImage: "checkmark.circle.fill",
                        kind: .incrementVariable,
                        variableKey: "streak",
                        incrementAmount: 1,
                        nowFormat: .iso8601
                    ),
                    WidgetActionDraft(
                        title: "Undo -1",
                        systemImage: "arrow.uturn.backward.circle.fill",
                        kind: .incrementVariable,
                        variableKey: "streak",
                        incrementAmount: -1,
                        nowFormat: .iso8601
                    )
                ]

            case .donePlusOne:
                return [
                    WidgetActionDraft(
                        title: "Done +1",
                        systemImage: "checkmark.circle.fill",
                        kind: .incrementVariable,
                        variableKey: "done",
                        incrementAmount: 1,
                        nowFormat: .iso8601
                    )
                ]

            case .hydration:
                return [
                    WidgetActionDraft(
                        title: "+25ml",
                        systemImage: "drop.circle.fill",
                        kind: .incrementVariable,
                        variableKey: "waterMl",
                        incrementAmount: 25,
                        nowFormat: .iso8601
                    ),
                    WidgetActionDraft(
                        title: "+50ml",
                        systemImage: "drop.circle",
                        kind: .incrementVariable,
                        variableKey: "waterMl",
                        incrementAmount: 50,
                        nowFormat: .iso8601
                    )
                ]

            case .pomodoro:
                return [
                    WidgetActionDraft(
                        title: "Start",
                        systemImage: "play.circle.fill",
                        kind: .incrementVariable,
                        variableKey: "pomo",
                        incrementAmount: 1,
                        nowFormat: .iso8601
                    ),
                    WidgetActionDraft(
                        title: "Stop",
                        systemImage: "stop.circle.fill",
                        kind: .incrementVariable,
                        variableKey: "pomo",
                        incrementAmount: -1,
                        nowFormat: .iso8601
                    )
                ]
            }
        }()

        return Array(out.prefix(WidgetActionBarSpec.maxActions))
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
        title: String,
        systemImage: String,
        kind: WidgetActionKindToken,
        variableKey: String,
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
        let s = spec.normalisedOrNil() ?? spec
        self.id = s.id
        self.title = s.title
        self.systemImage = s.systemImage ?? ""
        self.kind = s.kind
        self.variableKey = s.variableKey
        self.incrementAmount = s.incrementAmount
        self.nowFormat = s.nowFormat
    }

    func toActionSpecOrNil() -> WidgetActionSpec? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let img = systemImage.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = variableKey.trimmingCharacters(in: .whitespacesAndNewlines)

        let spec = WidgetActionSpec(
            id: id,
            title: t,
            systemImage: img.isEmpty ? nil : img,
            kind: kind,
            variableKey: key,
            incrementAmount: incrementAmount,
            nowFormat: nowFormat
        )

        return spec.normalisedOrNil()
    }

    func validateVariableKey() -> VariableKeyValidationResult {
        let key = variableKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !key.isEmpty else {
            return .warning("Key is required.")
        }

        if key.hasPrefix("__") {
            return .warning("Reserved key (starts with \"__\").")
        }

        if key.count > 32 {
            return .warning("Key is too long (max 32 characters).")
        }

        guard let first = key.unicodeScalars.first, Self.isASCIIAlpha(first) else {
            return .warning("Key must start with a letter.")
        }

        for s in key.unicodeScalars {
            if Self.isASCIIAlpha(s) { continue }
            if Self.isASCIIDigit(s) { continue }
            if s.value == 95 { continue }
            return .warning("Only letters, numbers, and _ are allowed.")
        }

        return .ok
    }

    private static func isASCIIAlpha(_ s: UnicodeScalar) -> Bool {
        (s.value >= 65 && s.value <= 90) || (s.value >= 97 && s.value <= 122)
    }

    private static func isASCIIDigit(_ s: UnicodeScalar) -> Bool {
        (s.value >= 48 && s.value <= 57)
    }
}
