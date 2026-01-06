//
//  EditorDraftModels.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import WidgetKit

struct FamilyDraft: Hashable {
    var template: LayoutTemplateToken

    var showsAccentBar: Bool
    var axis: LayoutAxisToken
    var alignment: LayoutAlignmentToken
    var spacing: Double

    var primaryText: String
    var secondaryText: String

    var symbolName: String
    var symbolSize: Double
    var symbolWeight: SymbolWeightToken
    var symbolRenderingMode: SymbolRenderingModeToken

    var imageFileName: String
    var imageHeight: Double
    var imageCornerRadius: Double
    var imageScaling: ImageScalingToken
    var imageSmartPhoto: SmartPhotoSpec?
    var imageDebugShowsCropOverlay: Bool

    var actionBarDraft: ActionBarDraft

    init(
        template: LayoutTemplateToken = .classic,
        showsAccentBar: Bool = true,
        axis: LayoutAxisToken = .vertical,
        alignment: LayoutAlignmentToken = .center,
        spacing: Double = 10,
        primaryText: String = "Hello",
        secondaryText: String = "",
        symbolName: String = "sun.max.fill",
        symbolSize: Double = 44,
        symbolWeight: SymbolWeightToken = .regular,
        symbolRenderingMode: SymbolRenderingModeToken = .hierarchical,
        imageFileName: String = "",
        imageHeight: Double = 120,
        imageCornerRadius: Double = 14,
        imageScaling: ImageScalingToken = .fill,
        imageSmartPhoto: SmartPhotoSpec? = nil,
        imageDebugShowsCropOverlay: Bool = false,
        actionBarDraft: ActionBarDraft = .defaultDraft
    ) {
        self.template = template
        self.showsAccentBar = showsAccentBar
        self.axis = axis
        self.alignment = alignment
        self.spacing = spacing
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.symbolName = symbolName
        self.symbolSize = symbolSize
        self.symbolWeight = symbolWeight
        self.symbolRenderingMode = symbolRenderingMode
        self.imageFileName = imageFileName
        self.imageHeight = imageHeight
        self.imageCornerRadius = imageCornerRadius
        self.imageScaling = imageScaling
        self.imageSmartPhoto = imageSmartPhoto
        self.imageDebugShowsCropOverlay = imageDebugShowsCropOverlay
        self.actionBarDraft = actionBarDraft
    }

    static var defaultDraft: FamilyDraft {
        FamilyDraft()
    }

    static var defaultPoster: FamilyDraft {
        FamilyDraft(
            template: .poster,
            showsAccentBar: false,
            axis: .vertical,
            alignment: .leading,
            spacing: 8,
            primaryText: "Photo",
            secondaryText: "WidgetWeaver",
            symbolName: "",
            symbolSize: 44,
            symbolWeight: .regular,
            symbolRenderingMode: .hierarchical,
            imageFileName: "",
            imageHeight: 140,
            imageCornerRadius: 18,
            imageScaling: .fill,
            imageSmartPhoto: nil,
            imageDebugShowsCropOverlay: false,
            actionBarDraft: .defaultDraft
        )
    }
}

struct StyleDraft: Hashable {
    var accent: AccentColorToken
    var background: BackgroundColorToken
    var textColor: TextColorToken
    var backgroundOverlay: BackgroundOverlayToken
    var backgroundOverlayOpacity: Double
    var padding: Double
    var cornerRadius: Double

    var nameTextStyle: TextStyleToken
    var primaryTextStyle: TextStyleToken
    var secondaryTextStyle: TextStyleToken

    var weatherScale: Double

    init(
        accent: AccentColorToken = .blue,
        background: BackgroundColorToken = .neutral,
        textColor: TextColorToken = .auto,
        backgroundOverlay: BackgroundOverlayToken = .none,
        backgroundOverlayOpacity: Double = 0.18,
        padding: Double = 16,
        cornerRadius: Double = 22,
        nameTextStyle: TextStyleToken = .caption,
        primaryTextStyle: TextStyleToken = .title3,
        secondaryTextStyle: TextStyleToken = .caption2,
        weatherScale: Double = 1.0
    ) {
        self.accent = accent
        self.background = background
        self.textColor = textColor
        self.backgroundOverlay = backgroundOverlay
        self.backgroundOverlayOpacity = backgroundOverlayOpacity
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.nameTextStyle = nameTextStyle
        self.primaryTextStyle = primaryTextStyle
        self.secondaryTextStyle = secondaryTextStyle
        self.weatherScale = weatherScale
    }

    static var defaultDraft: StyleDraft {
        StyleDraft()
    }
}

struct MatchedDrafts: Hashable {
    var small: FamilyDraft
    var medium: FamilyDraft
    var large: FamilyDraft

    init(small: FamilyDraft, medium: FamilyDraft, large: FamilyDraft) {
        self.small = small
        self.medium = medium
        self.large = large
    }

    subscript(_ editingFamily: EditingFamily) -> FamilyDraft {
        get {
            switch editingFamily {
            case .small: return small
            case .medium: return medium
            case .large: return large
            }
        }
        set {
            switch editingFamily {
            case .small: small = newValue
            case .medium: medium = newValue
            case .large: large = newValue
            }
        }
    }
}

enum EditingFamily: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    var widgetFamily: WidgetFamily {
        switch self {
        case .small: return .systemSmall
        case .medium: return .systemMedium
        case .large: return .systemLarge
        }
    }

    init?(widgetFamily: WidgetFamily) {
        switch widgetFamily {
        case .systemSmall: self = .small
        case .systemMedium: self = .medium
        case .systemLarge: self = .large
        default: return nil
        }
    }
}

struct ActionBarDraft: Hashable {
    var isEnabled: Bool
    var actions: [WidgetActionDraft]

    init(isEnabled: Bool = false, actions: [WidgetActionDraft] = []) {
        self.isEnabled = isEnabled
        self.actions = actions
    }

    static var defaultDraft: ActionBarDraft {
        ActionBarDraft(isEnabled: false, actions: [])
    }

    mutating func addNewAction() {
        guard actions.count < WidgetActionBarSpec.maxActions else { return }
        actions.append(WidgetActionDraft.defaultIncrement())
    }

    mutating func delete(id: UUID) {
        actions.removeAll { $0.id == id }
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

    var previewString: String {
        let key = variableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyPart = key.isEmpty ? "(No key)" : key

        switch kind {
        case .incrementVariable:
            let amt = incrementAmount
            let signed = amt >= 0 ? "+\(amt)" : "\(amt)"
            return "Increment \(signed) → \(keyPart)"
        case .setVariableToNow:
            let fmt: String = {
                switch nowFormat {
                case .iso8601: return "ISO"
                case .unixSeconds: return "Unix s"
                case .unixMilliseconds: return "Unix ms"
                case .dateOnly: return "Date"
                case .timeOnly: return "Time"
                }
            }()
            return "Set Now (\(fmt)) → \(keyPart)"
        }
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


// MARK: - Editor tool filtering (context-aware tool suite)

/// A compact, testable summary of what the editor is currently editing.
///
/// This is deliberately plain data (no SwiftUI state) so it can be derived from view state
/// and fed into tool eligibility filtering.
struct EditorToolContext: Hashable {
    var template: LayoutTemplateToken
    var isProUnlocked: Bool
    var matchedSetEnabled: Bool

    var hasSymbolConfigured: Bool
    var hasImageConfigured: Bool
    var hasSmartPhotoConfigured: Bool

    init(
        template: LayoutTemplateToken,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        hasSymbolConfigured: Bool,
        hasImageConfigured: Bool,
        hasSmartPhotoConfigured: Bool
    ) {
        self.template = template
        self.isProUnlocked = isProUnlocked
        self.matchedSetEnabled = matchedSetEnabled
        self.hasSymbolConfigured = hasSymbolConfigured
        self.hasImageConfigured = hasImageConfigured
        self.hasSmartPhotoConfigured = hasSmartPhotoConfigured
    }
}

/// A vocabulary for what the *current content* supports editing.
///
/// Tools declare requirements in terms of these capabilities.
struct EditorCapabilities: OptionSet, Hashable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    static let canEditLayout = EditorCapabilities(rawValue: 1 << 0)
    static let canEditTextContent = EditorCapabilities(rawValue: 1 << 1)
    static let canEditSymbol = EditorCapabilities(rawValue: 1 << 2)
    static let canEditImage = EditorCapabilities(rawValue: 1 << 3)
    static let canEditSmartPhoto = EditorCapabilities(rawValue: 1 << 4)
    static let canEditStyle = EditorCapabilities(rawValue: 1 << 5)
    static let canEditTypography = EditorCapabilities(rawValue: 1 << 6)
    static let canEditActions = EditorCapabilities(rawValue: 1 << 7)
}

/// Stable identifiers for the editor’s primary tool surface.
///
/// In the current app UI, each tool maps to a single `Form` section.
enum EditorToolID: String, CaseIterable, Hashable, Identifiable {
    case status
    case designs
    case widgets

    case layout
    case text
    case symbol
    case image
    case style
    case typography
    case actions

    case matchedSet
    case variables
    case sharing
    case ai
    case pro

    var id: String { rawValue }
}

struct EditorToolDefinition: Hashable {
    var id: EditorToolID
    var order: Int
    var requiredCapabilities: EditorCapabilities

    init(id: EditorToolID, order: Int, requiredCapabilities: EditorCapabilities = []) {
        self.id = id
        self.order = order
        self.requiredCapabilities = requiredCapabilities
    }

    func isEligible(capabilities: EditorCapabilities) -> Bool {
        capabilities.isSuperset(of: requiredCapabilities)
    }
}

enum EditorToolRegistry {
    static let tools: [EditorToolDefinition] = [
        EditorToolDefinition(id: .status, order: 0),
        EditorToolDefinition(id: .designs, order: 10),
        EditorToolDefinition(id: .widgets, order: 20),

        EditorToolDefinition(id: .layout, order: 30, requiredCapabilities: [.canEditLayout]),
        EditorToolDefinition(id: .text, order: 40, requiredCapabilities: [.canEditTextContent]),
        EditorToolDefinition(id: .symbol, order: 50, requiredCapabilities: [.canEditSymbol]),
        EditorToolDefinition(id: .image, order: 60, requiredCapabilities: [.canEditImage]),
        EditorToolDefinition(id: .style, order: 70, requiredCapabilities: [.canEditStyle]),
        EditorToolDefinition(id: .typography, order: 80, requiredCapabilities: [.canEditTypography]),
        EditorToolDefinition(id: .actions, order: 90, requiredCapabilities: [.canEditActions]),

        EditorToolDefinition(id: .matchedSet, order: 100),
        EditorToolDefinition(id: .variables, order: 110),
        EditorToolDefinition(id: .sharing, order: 120),
        EditorToolDefinition(id: .ai, order: 130),
        EditorToolDefinition(id: .pro, order: 140),
    ]

    static func capabilities(for context: EditorToolContext) -> EditorCapabilities {
        var c: EditorCapabilities = [.canEditLayout, .canEditStyle]

        // Text content is always editable at least for naming the design.
        c.insert(.canEditTextContent)

        switch context.template {
        case .classic, .hero:
            c.insert(.canEditSymbol)
            c.insert(.canEditTypography)
            c.insert(.canEditActions)

        case .poster:
            c.insert(.canEditImage)
            c.insert(.canEditTypography)
            c.insert(.canEditSmartPhoto)

        case .weather:
            // Weather does not use the generic text styles.
            // Symbol/image/actions are not part of the weather template.
            break

        case .nextUpCalendar:
            // Calendar template is data-driven; keep content tools minimal.
            break
        }

        return c
    }

    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let caps = capabilities(for: context)

        return tools
            .filter { $0.isEligible(capabilities: caps) }
            .sorted { $0.order < $1.order }
            .map { $0.id }
    }
}
