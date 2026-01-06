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
    var imageSmartPhoto: SmartPhotoSpec?
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
            self.imageSmartPhoto = img.smartPhoto
            self.imageContentMode = img.contentMode
            self.imageHeight = img.height
            self.imageCornerRadius = img.cornerRadius
        } else {
            self.imageFileName = ""
            self.imageSmartPhoto = nil
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
            imageSmartPhoto = img.smartPhoto
            imageContentMode = img.contentMode
            imageHeight = img.height
            imageCornerRadius = img.cornerRadius
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
                        label: "−",
                        systemImage: "minus",
                        destination: .stepsVariableAdjust,
                        adjust: .init(key: "count", delta: -1, clampMin: nil, clampMax: nil)
                    ),
                    WidgetActionDraft(
                        label: "+",
                        systemImage: "plus",
                        destination: .stepsVariableAdjust,
                        adjust: .init(key: "count", delta: 1, clampMin: nil, clampMax: nil)
                    ),
                ]

            case .habitStreak:
                return [
                    WidgetActionDraft(
                        label: "Done",
                        systemImage: "checkmark",
                        destination: .stepsVariableAdjust,
                        adjust: .init(key: "streak", delta: 1, clampMin: 0, clampMax: nil)
                    ),
                    WidgetActionDraft(
                        label: "Undo",
                        systemImage: "arrow.uturn.left",
                        destination: .stepsVariableAdjust,
                        adjust: .init(key: "streak", delta: -1, clampMin: 0, clampMax: nil)
                    ),
                ]

            case .donePlusOne:
                return [
                    WidgetActionDraft(
                        label: "Done",
                        systemImage: "checkmark.circle.fill",
                        destination: .stepsVariableAdjust,
                        adjust: .init(key: "done", delta: 1, clampMin: 0, clampMax: nil)
                    ),
                ]

            case .hydration:
                return [
                    WidgetActionDraft(
                        label: "+250ml",
                        systemImage: "drop.fill",
                        destination: .stepsVariableAdjust,
                        adjust: .init(key: "waterMl", delta: 250, clampMin: 0, clampMax: nil)
                    ),
                    WidgetActionDraft(
                        label: "+500ml",
                        systemImage: "drop.fill",
                        destination: .stepsVariableAdjust,
                        adjust: .init(key: "waterMl", delta: 500, clampMin: 0, clampMax: nil)
                    ),
                ]

            case .pomodoro:
                return [
                    WidgetActionDraft(
                        label: "Start",
                        systemImage: "play.fill",
                        destination: .stepsVariableAdjust,
                        adjust: .init(key: "pomo", delta: 1, clampMin: 0, clampMax: nil)
                    ),
                    WidgetActionDraft(
                        label: "Stop",
                        systemImage: "stop.fill",
                        destination: .stepsVariableAdjust,
                        adjust: .init(key: "pomo", delta: -1, clampMin: 0, clampMax: nil)
                    ),
                ]
            }
        }()

        return out.enumerated().map { idx, d in
            var v = d
            v.order = idx
            return v
        }
    }
}

enum WidgetActionDestinationDraft: Hashable, CaseIterable, Identifiable {
    case openURL
    case stepsVariableAdjust

    var id: String {
        switch self {
        case .openURL: return "openURL"
        case .stepsVariableAdjust: return "stepsVariableAdjust"
        }
    }

    var label: String {
        switch self {
        case .openURL: return "Open URL"
        case .stepsVariableAdjust: return "Adjust Variable"
        }
    }
}

struct StepsVariableAdjustDraft: Hashable {
    var key: String
    var delta: Int
    var clampMin: Int?
    var clampMax: Int?

    init(key: String, delta: Int, clampMin: Int?, clampMax: Int?) {
        self.key = key
        self.delta = delta
        self.clampMin = clampMin
        self.clampMax = clampMax
    }

    init(from spec: StepsVariableAdjustSpec?) {
        guard let s = spec?.normalisedOrNil() else {
            self = StepsVariableAdjustDraft(key: "", delta: 1, clampMin: 0, clampMax: nil)
            return
        }
        self.key = s.key
        self.delta = s.delta
        self.clampMin = s.clampMin
        self.clampMax = s.clampMax
    }

    func toSpecOrNil() -> StepsVariableAdjustSpec? {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return nil }
        return StepsVariableAdjustSpec(key: k, delta: delta, clampMin: clampMin, clampMax: clampMax).normalisedOrNil()
    }
}

struct WidgetActionDraft: Hashable, Identifiable {
    var id: UUID

    var label: String
    var systemImage: String?

    var destination: WidgetActionDestinationDraft
    var openURLString: String
    var adjust: StepsVariableAdjustDraft

    var order: Int

    init(
        id: UUID = UUID(),
        label: String,
        systemImage: String?,
        destination: WidgetActionDestinationDraft,
        openURLString: String = "",
        adjust: StepsVariableAdjustDraft = StepsVariableAdjustDraft(key: "", delta: 1, clampMin: 0, clampMax: nil),
        order: Int = 0
    ) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
        self.destination = destination
        self.openURLString = openURLString
        self.adjust = adjust
        self.order = order
    }

    init(from spec: WidgetActionSpec) {
        self.id = spec.id
        self.label = spec.label
        self.systemImage = spec.systemImage
        self.order = spec.order

        switch spec.destination {
        case .openURL(let u):
            self.destination = .openURL
            self.openURLString = u
            self.adjust = StepsVariableAdjustDraft(key: "", delta: 1, clampMin: 0, clampMax: nil)

        case .stepsVariableAdjust(let a):
            self.destination = .stepsVariableAdjust
            self.openURLString = ""
            self.adjust = StepsVariableAdjustDraft(from: a)
        }
    }

    func toActionSpecOrNil() -> WidgetActionSpec? {
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else { return nil }

        let dest: WidgetActionDestinationSpec? = {
            switch destination {
            case .openURL:
                let u = openURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                return u.isEmpty ? nil : .openURL(u)

            case .stepsVariableAdjust:
                guard let a = adjust.toSpecOrNil() else { return nil }
                return .stepsVariableAdjust(a)
            }
        }()

        guard let d = dest else { return nil }

        let img = systemImage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sys = (img?.isEmpty ?? true) ? nil : img

        return WidgetActionSpec(
            id: id,
            label: trimmedLabel,
            systemImage: sys,
            destination: d,
            order: order
        ).normalised()
    }
}

enum VariableKeyValidator {
    static func validate(_ key: String) -> VariableKeyValidationResult {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
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
