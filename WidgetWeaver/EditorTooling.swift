//
//  EditorTooling.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

// MARK: - Context-aware editor tools

/// A compact, testable summary of what the editor is currently editing.
///
/// This is deliberately plain data (no SwiftUI state) so it can be derived from view state
/// and used to drive capability-based tool filtering.
struct EditorToolContext: Hashable {
    var template: LayoutTemplateToken
    var isProUnlocked: Bool
    var matchedSetEnabled: Bool

    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    var hasSymbolConfigured: Bool
    var hasImageConfigured: Bool
    var hasSmartPhotoConfigured: Bool

    init(
        template: LayoutTemplateToken,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        selection: EditorSelectionKind,
        focus: EditorFocusTarget,
        hasSymbolConfigured: Bool,
        hasImageConfigured: Bool,
        hasSmartPhotoConfigured: Bool
    ) {
        self.template = template
        self.isProUnlocked = isProUnlocked
        self.matchedSetEnabled = matchedSetEnabled
        self.selection = selection
        self.focus = focus
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
    static let canEditAlbumShuffle = EditorCapabilities(rawValue: 1 << 8)
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
    case albumShuffle
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
    /// The tool manifest. This is the sole source of truth for what tools exist and their ordering.
    static let tools: [EditorToolDefinition] = [
        EditorToolDefinition(id: .status, order: 0),
        EditorToolDefinition(id: .designs, order: 10),
        EditorToolDefinition(id: .widgets, order: 20),

        EditorToolDefinition(id: .layout, order: 30, requiredCapabilities: [.canEditLayout]),
        EditorToolDefinition(id: .text, order: 40, requiredCapabilities: [.canEditTextContent]),
        EditorToolDefinition(id: .symbol, order: 50, requiredCapabilities: [.canEditSymbol]),
        EditorToolDefinition(id: .image, order: 60, requiredCapabilities: [.canEditImage]),
        EditorToolDefinition(id: .albumShuffle, order: 65, requiredCapabilities: [.canEditAlbumShuffle]),
        EditorToolDefinition(id: .style, order: 70, requiredCapabilities: [.canEditStyle]),
        EditorToolDefinition(id: .typography, order: 80, requiredCapabilities: [.canEditTypography]),
        EditorToolDefinition(id: .actions, order: 90, requiredCapabilities: [.canEditActions]),

        EditorToolDefinition(id: .matchedSet, order: 100),
        EditorToolDefinition(id: .variables, order: 110),
        EditorToolDefinition(id: .sharing, order: 120),
        EditorToolDefinition(id: .ai, order: 130),
        EditorToolDefinition(id: .pro, order: 140),
    ]

    /// Derives capabilities from the current editing context.
    ///
    /// This should be cheap (no I/O, no image work) so it can run synchronously on every relevant state change.
    static func capabilities(for context: EditorToolContext) -> EditorCapabilities {
        var c: EditorCapabilities = [.canEditLayout, .canEditTextContent, .canEditStyle]

        switch context.template {
        case .classic, .hero:
            c.insert(.canEditSymbol)
            c.insert(.canEditTypography)
            c.insert(.canEditActions)

        case .poster:
            c.insert(.canEditImage)
            c.insert(.canEditSmartPhoto)
            c.insert(.canEditAlbumShuffle)
            c.insert(.canEditTypography)

        case .weather:
            // Weather is data-driven; symbol/image/actions/typography are not applied.
            break

        case .nextUpCalendar:
            // Calendar is data-driven; symbol/image/actions/typography are not applied.
            break
        }

        return c
    }

    /// Returns the ordered tool identifiers that should be visible for the given context.
    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let caps = capabilities(for: context)

        return tools
            .filter { $0.isEligible(capabilities: caps) }
            .sorted { $0.order < $1.order }
            .map { $0.id }
    }
}
