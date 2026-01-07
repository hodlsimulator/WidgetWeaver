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

    /// Photo library access state (authorisation + availability).
    ///
    /// This is passed into context evaluation so capability derivation stays pure and testable.
    var photoLibraryAccess: EditorPhotoLibraryAccess

    var hasSymbolConfigured: Bool
    var hasImageConfigured: Bool
    var hasSmartPhotoConfigured: Bool

    init(
        template: LayoutTemplateToken,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        selection: EditorSelectionKind,
        focus: EditorFocusTarget,
        photoLibraryAccess: EditorPhotoLibraryAccess,
        hasSymbolConfigured: Bool,
        hasImageConfigured: Bool,
        hasSmartPhotoConfigured: Bool
    ) {
        self.template = template
        self.isProUnlocked = isProUnlocked
        self.matchedSetEnabled = matchedSetEnabled
        self.selection = selection
        self.focus = focus
        self.photoLibraryAccess = photoLibraryAccess
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

    /// Read/write access to the user’s Photo Library (authorised or limited).
    ///
    /// This is treated as a capability so tools can declare it as a requirement.
    static let canAccessPhotoLibrary = EditorCapabilities(rawValue: 1 << 9)

    /// Data availability flags.
    ///
    /// These keep non-actionable tools from surfacing when their prerequisites are missing.
    static let hasImageConfigured = EditorCapabilities(rawValue: 1 << 10)
    static let hasSmartPhotoConfigured = EditorCapabilities(rawValue: 1 << 11)
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
    case smartPhoto
    case smartPhotoCrop
    case smartRules
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

    /// Eligibility constraints beyond capabilities (selection/focus/selection count).
    ///
    /// This keeps complex UI conditions out of SwiftUI code and centralises them in one place.
    var eligibility: EditorToolEligibility

    init(
        id: EditorToolID,
        order: Int,
        requiredCapabilities: EditorCapabilities = [],
        eligibility: EditorToolEligibility = .unconstrained
    ) {
        self.id = id
        self.order = order
        self.requiredCapabilities = requiredCapabilities
        self.eligibility = eligibility
    }

    func isEligible(
        context: EditorToolContext,
        capabilities: EditorCapabilities,
        multiSelectionPolicy: EditorToolMultiSelectionPolicy
    ) -> Bool {
        guard capabilities.isSuperset(of: requiredCapabilities) else { return false }
        return eligibility.isEligible(context: context, multiSelectionPolicy: multiSelectionPolicy)
    }
}

enum EditorToolRegistry {
    /// Global multi-selection behaviour.
    ///
    /// Policy choice:
    /// - `.intersection`: only tools that explicitly declare they are multi-selection-safe will be shown
    ///   when selection cardinality is `.multi`.
    static let multiSelectionPolicy: EditorToolMultiSelectionPolicy = .intersection

    /// The tool manifest. This is the sole source of truth for what tools exist and their ordering.
    static let tools: [EditorToolDefinition] = [
        EditorToolDefinition(id: .status, order: 0, eligibility: .multiSafe()),
        EditorToolDefinition(id: .designs, order: 10, eligibility: .multiSafe()),
        EditorToolDefinition(id: .widgets, order: 20, eligibility: .multiSafe()),

        EditorToolDefinition(id: .layout, order: 30, requiredCapabilities: [.canEditLayout], eligibility: .multiSafe()),
        EditorToolDefinition(id: .text, order: 40, requiredCapabilities: [.canEditTextContent]),
        EditorToolDefinition(id: .symbol, order: 50, requiredCapabilities: [.canEditSymbol]),

        // Media / Smart Photos
        EditorToolDefinition(
            id: .image,
            order: 60,
            requiredCapabilities: [.canEditImage],
            eligibility: EditorToolEligibility(
                focus: .smartPhotoPhotoItemSuite,
                selection: .any,
                supportsMultiSelection: false
            )
        ),
        EditorToolDefinition(
            id: .smartPhoto,
            order: 62,
            requiredCapabilities: [.canEditSmartPhoto],
            eligibility: EditorToolEligibility(
                focus: .smartPhotoContainerSuite,
                selection: .any,
                supportsMultiSelection: false
            )
        ),
        EditorToolDefinition(
            id: .smartPhotoCrop,
            order: 63,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured],
            eligibility: EditorToolEligibility(
                focus: .smartPhotoContainerSuite,
                selection: .any,
                supportsMultiSelection: false
            )
        ),
        EditorToolDefinition(
            id: .smartRules,
            order: 64,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured],
            eligibility: EditorToolEligibility(
                focus: .smartPhotoContainerSuite,
                selection: .any,
                supportsMultiSelection: false
            )
        ),
        EditorToolDefinition(
            id: .albumShuffle,
            order: 65,
            requiredCapabilities: [.canEditAlbumShuffle, .hasSmartPhotoConfigured, .canAccessPhotoLibrary],
            eligibility: EditorToolEligibility(
                focus: .smartPhotoContainerSuite,
                selection: .any,
                supportsMultiSelection: false
            )
        ),

        EditorToolDefinition(id: .style, order: 70, requiredCapabilities: [.canEditStyle], eligibility: .multiSafe()),
        EditorToolDefinition(id: .typography, order: 80, requiredCapabilities: [.canEditTypography], eligibility: .multiSafe()),
        EditorToolDefinition(id: .actions, order: 90, requiredCapabilities: [.canEditActions], eligibility: .multiSafe()),

        EditorToolDefinition(id: .matchedSet, order: 100, eligibility: .multiSafe()),
        EditorToolDefinition(id: .variables, order: 110, eligibility: .multiSafe()),
        EditorToolDefinition(id: .sharing, order: 120, eligibility: .multiSafe()),
        EditorToolDefinition(id: .ai, order: 130, eligibility: .multiSafe()),
        EditorToolDefinition(id: .pro, order: 140, eligibility: .multiSafe()),
    ]

    /// Derives capabilities from the current editing context.
    ///
    /// This should be cheap (no image work). Permission/data availability is passed in via `EditorToolContext`.
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

        if context.photoLibraryAccess.allowsReadWrite {
            c.insert(.canAccessPhotoLibrary)
        }

        if context.hasImageConfigured {
            c.insert(.hasImageConfigured)
        }

        if context.hasSmartPhotoConfigured {
            c.insert(.hasSmartPhotoConfigured)
        }

        return c
    }

    /// Returns the ordered tool identifiers that should be visible for the given context.
    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let caps = capabilities(for: context)

        let eligible = tools
            .filter { $0.isEligible(context: context, capabilities: caps, multiSelectionPolicy: multiSelectionPolicy) }
            .sorted { $0.order < $1.order }
            .map { $0.id }

        let focusGroup = editorToolFocusGroup(for: context.focus)
        let gated = editorToolIDsApplyingFocusGate(eligible: eligible, focusGroup: focusGroup)

        if focusGroup == .smartPhotos {
            return prioritiseToolsForSmartPhotos(gated, focus: context.focus)
        }

        return gated
    }

    private static func prioritiseToolsForSmartPhotos(_ toolIDs: [EditorToolID], focus: EditorFocusTarget) -> [EditorToolID] {
        var out: [EditorToolID] = []

        // If the user is actively editing Smart Rules, keep that tool first.
        if case .smartRuleEditor = focus, toolIDs.contains(.smartRules) {
            out.append(.smartRules)
        }

        // 1) Album tools first.
        if toolIDs.contains(.albumShuffle), !out.contains(.albumShuffle) {
            out.append(.albumShuffle)
        }

        // 2) Smart Photo framing tools next.
        if toolIDs.contains(.smartPhotoCrop), !out.contains(.smartPhotoCrop) {
            out.append(.smartPhotoCrop)
        }

        // 3) Smart Rules / album criteria tools.
        if toolIDs.contains(.smartRules), !out.contains(.smartRules) {
            out.append(.smartRules)
        }

        // 4) Smart Photo creation/regeneration tools.
        if toolIDs.contains(.smartPhoto), !out.contains(.smartPhoto) {
            out.append(.smartPhoto)
        }

        // 5) Related image controls.
        if toolIDs.contains(.image), !out.contains(.image) {
            out.append(.image)
        }

        // 5) Remaining tools (keep relative order), with Style last.
        out.append(contentsOf: toolIDs.filter { !out.contains($0) && $0 != .style })

        if toolIDs.contains(.style), !out.contains(.style) {
            out.append(.style)
        }

        return out
    }
}
