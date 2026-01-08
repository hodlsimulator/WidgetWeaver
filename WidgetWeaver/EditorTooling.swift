//
//  EditorTooling.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

// MARK: - Context model

struct EditorToolContext: Hashable, Sendable {
    var template: LayoutTemplateToken
    var isProUnlocked: Bool
    var matchedSetEnabled: Bool

    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    var photoLibraryAccess: EditorPhotoLibraryAccess

    /// Whether the draft has a symbol configured.
    ///
    /// This is not currently a capability, but it is part of the central context model so
    /// future tools can avoid re-deriving it.
    var hasSymbolConfigured: Bool

    /// Whether the draft has any image configured (regardless of whether Smart Photo has been prepared).
    var hasImageConfigured: Bool

    /// Whether the draft has a prepared Smart Photo configured and reachable from the current image spec.
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

// MARK: - Capability vocabulary

struct EditorCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let canEditLayout = EditorCapabilities(rawValue: 1 << 0)
    static let canEditTextContent = EditorCapabilities(rawValue: 1 << 1)
    static let canEditSymbol = EditorCapabilities(rawValue: 1 << 2)
    static let canEditImage = EditorCapabilities(rawValue: 1 << 3)
    static let canEditSmartPhoto = EditorCapabilities(rawValue: 1 << 4)
    static let canEditStyle = EditorCapabilities(rawValue: 1 << 5)
    static let canEditTypography = EditorCapabilities(rawValue: 1 << 6)
    static let canEditActions = EditorCapabilities(rawValue: 1 << 7)
    static let canEditMatchedSet = EditorCapabilities(rawValue: 1 << 8)
    static let canEditVariables = EditorCapabilities(rawValue: 1 << 9)
    static let canShare = EditorCapabilities(rawValue: 1 << 10)
    static let canUseAI = EditorCapabilities(rawValue: 1 << 11)
    static let canPurchasePro = EditorCapabilities(rawValue: 1 << 12)

    static let canEditAlbumShuffle = EditorCapabilities(rawValue: 1 << 13)

    // Permissions + availability
    static let canAccessPhotoLibrary = EditorCapabilities(rawValue: 1 << 14)
    static let hasImageConfigured = EditorCapabilities(rawValue: 1 << 15)
    static let hasSmartPhotoConfigured = EditorCapabilities(rawValue: 1 << 16)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

// MARK: - Tool definition

enum EditorToolID: String, CaseIterable, Hashable, Sendable {
    // Workflow / top-of-editor.
    case status
    case designs
    case widgets

    // Core editing.
    case layout
    case text
    case symbol
    case image

    // Smart Photos / Albums.
    case smartPhoto
    case smartPhotoCrop
    case smartRules
    case albumShuffle

    // Styling.
    case style
    case typography

    // Automation.
    case actions

    // Power features.
    case matchedSet
    case variables
    case sharing
    case ai
    case pro
}

struct EditorToolDefinition: Hashable, Sendable {
    var id: EditorToolID
    var order: Int

    var requiredCapabilities: EditorCapabilities
    var eligibility: EditorToolEligibility

    init(
        id: EditorToolID,
        order: Int,
        requiredCapabilities: EditorCapabilities = [],
        eligibility: EditorToolEligibility = .init()
    ) {
        self.id = id
        self.order = order
        self.requiredCapabilities = requiredCapabilities
        self.eligibility = eligibility
    }

    func isEligible(
        context: EditorToolContext,
        capabilities: EditorCapabilities,
        multiSelectionPolicy: EditorMultiSelectionPolicy
    ) -> Bool {
        guard requiredCapabilities.isSubset(of: capabilities) else { return false }

        let selectionDescriptor = EditorSelectionDescriptor.describe(
            selection: context.selection,
            focus: context.focus
        )

        let eligibilityResult = EditorToolEligibilityEvaluator.isEligible(
            eligibility: eligibility,
            selection: context.selection,
            selectionDescriptor: selectionDescriptor,
            focus: context.focus,
            multiSelectionPolicy: multiSelectionPolicy
        )
        guard eligibilityResult else { return false }

        return true
    }
}

// MARK: - Registry

enum EditorToolRegistry {
    static let multiSelectionPolicy: EditorMultiSelectionPolicy = .intersection

    /// Canonical tool manifest.
    static let tools: [EditorToolDefinition] = [
        // Workflow.
        EditorToolDefinition(id: .status, order: 10, requiredCapabilities: [], eligibility: .multiSafe()),
        EditorToolDefinition(id: .designs, order: 20, requiredCapabilities: [], eligibility: .multiSafe()),
        EditorToolDefinition(id: .widgets, order: 30, requiredCapabilities: [], eligibility: .multiSafe()),

        // Core editing.
        EditorToolDefinition(
            id: .layout,
            order: 40,
            requiredCapabilities: [.canEditLayout],
            eligibility: .multiSafe(
                focus: .any,
                selection: .any,
                selectionDescriptor: .any
            )
        ),
        EditorToolDefinition(
            id: .text,
            order: 50,
            requiredCapabilities: [.canEditTextContent],
            eligibility: .singleTarget(
                focus: .any,
                selectionDescriptor: .any
            )
        ),
        EditorToolDefinition(
            id: .symbol,
            order: 60,
            requiredCapabilities: [.canEditSymbol],
            eligibility: .singleTarget(
                focus: .any,
                selectionDescriptor: .any
            )
        ),
        EditorToolDefinition(
            id: .image,
            order: 70,
            requiredCapabilities: [.canEditImage],
            eligibility: .singleTarget(
                focus: .smartPhotoPhotoItemSuite,
                selectionDescriptor: .any
            )
        ),

        // Smart Photos / Albums.
        EditorToolDefinition(
            id: .smartPhoto,
            order: 80,
            requiredCapabilities: [.canEditSmartPhoto],
            eligibility: .singleTarget(
                focus: .smartPhotoContainerSuite,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection
            )
        ),
        EditorToolDefinition(
            id: .smartPhotoCrop,
            order: 81,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured],
            eligibility: .singleTarget(
                focus: .smartPhotoPhotoItemSuite,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection
            )
        ),
        EditorToolDefinition(
            id: .smartRules,
            order: 82,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured],
            eligibility: .singleTarget(
                focus: .smartPhotoContainerSuite,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection
            )
        ),
        EditorToolDefinition(
            id: .albumShuffle,
            order: 83,
            requiredCapabilities: [.canEditAlbumShuffle, .hasSmartPhotoConfigured, .canAccessPhotoLibrary],
            eligibility: .singleTarget(
                focus: .smartPhotoContainerSuite,
                selectionDescriptor: .allowsAlbumContainerOrNonAlbumHomogeneousOrNone
            )
        ),

        // Styling.
        EditorToolDefinition(
            id: .style,
            order: 90,
            requiredCapabilities: [.canEditStyle],
            eligibility: .multiSafe(
                focus: .any,
                selection: .any,
                selectionDescriptor: .any
            )
        ),
        EditorToolDefinition(
            id: .typography,
            order: 100,
            requiredCapabilities: [.canEditTypography],
            eligibility: .singleTarget(
                focus: .any,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection
            )
        ),

        // Automation.
        EditorToolDefinition(
            id: .actions,
            order: 110,
            requiredCapabilities: [.canEditActions],
            eligibility: .singleTarget(
                focus: .any,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection
            )
        ),

        // Power features.
        EditorToolDefinition(
            id: .matchedSet,
            order: 120,
            requiredCapabilities: [.canEditMatchedSet],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .variables,
            order: 130,
            requiredCapabilities: [.canEditVariables],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .sharing,
            order: 140,
            requiredCapabilities: [.canShare],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .ai,
            order: 150,
            requiredCapabilities: [.canUseAI],
            eligibility: .multiSafe()
        ),
        EditorToolDefinition(
            id: .pro,
            order: 160,
            requiredCapabilities: [.canPurchasePro],
            eligibility: .multiSafe()
        ),
    ]

    static func capabilities(for context: EditorToolContext) -> EditorCapabilities {
        var c: EditorCapabilities = [
            .canEditLayout,
            .canEditTextContent,
            .canEditStyle,
            .canEditMatchedSet,
            .canEditVariables,
            .canShare,
            .canPurchasePro,
        ]

        if context.isProUnlocked {
            c.insert(.canUseAI)
        }

        if context.matchedSetEnabled {
            c.insert(.canEditMatchedSet)
        }

        // Template-specific editing capabilities.
        switch context.template {
        case .classic:
            c.insert(.canEditSymbol)
            c.insert(.canEditTypography)
            c.insert(.canEditActions)

        case .hero:
            c.insert(.canEditSymbol)
            c.insert(.canEditTypography)
            c.insert(.canEditActions)

        case .poster:
            c.insert(.canEditSymbol)
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

        let out: [EditorToolID] = {
            if focusGroup == .smartPhotos {
                return prioritiseToolsForSmartPhotos(gated, focus: context.focus)
            }
            return gated
        }()

#if DEBUG
        debugLogUnexpectedToolListIfNeeded(
            context: context,
            capabilities: caps,
            eligibleTools: eligible,
            gatedTools: gated,
            visibleTools: out,
            focusGroup: focusGroup
        )
#endif

        return out
    }

    /// Legacy / fallback tool surface.
    ///
    /// This intentionally ignores:
    /// - selection intersection policy
    /// - focus gating
    /// - availability gating (Smart Photo presence / Photos permission)
    ///
    /// It is useful as a safety hatch while context-aware tooling is being rolled out.
    static func legacyVisibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let caps = capabilities(for: context)

        // Availability + permissions are treated as “soft requirements” in legacy mode so the user
        // can still discover the section and see inline guidance / CTAs.
        let ignored: EditorCapabilities = [
            .canAccessPhotoLibrary,
            .hasImageConfigured,
            .hasSmartPhotoConfigured,
        ]

        return tools
            .sorted { $0.order < $1.order }
            .filter { tool in
                let required = tool.requiredCapabilities.subtracting(ignored)
                return required.isSubset(of: caps)
            }
            .map { $0.id }
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

        // 2) Smart Photo editing tools.
        if toolIDs.contains(.smartPhotoCrop), !out.contains(.smartPhotoCrop) {
            out.append(.smartPhotoCrop)
        }

        if toolIDs.contains(.smartPhoto), !out.contains(.smartPhoto) {
            out.append(.smartPhoto)
        }

        if toolIDs.contains(.image), !out.contains(.image) {
            out.append(.image)
        }

        // 3) Smart Rules, unless already pinned first.
        if toolIDs.contains(.smartRules), !out.contains(.smartRules) {
            out.append(.smartRules)
        }

        // 4) Keep Style last so it’s still reachable, but not dominant.
        if toolIDs.contains(.style), !out.contains(.style) {
            out.append(.style)
        }

        // Append any remaining tools not explicitly prioritised (defensive).
        for t in toolIDs where !out.contains(t) {
            out.append(t)
        }

        return out
    }
}

// MARK: - Debug diagnostics

#if DEBUG
private func debugLogUnexpectedToolListIfNeeded(
    context: EditorToolContext,
    capabilities: EditorCapabilities,
    eligibleTools: [EditorToolID],
    gatedTools: [EditorToolID],
    visibleTools: [EditorToolID],
    focusGroup: EditorToolFocusGroup
) {
    // Log when the list becomes empty or suspiciously small, to catch modelling gaps.
    let suspiciouslySmallThreshold = 2

    if visibleTools.isEmpty || visibleTools.count <= suspiciouslySmallThreshold {
        let capsSorted = EditorCapabilities.allKnown
            .filter { capabilities.contains($0) }
            .map { $0.debugLabel }
            .joined(separator: ", ")

        let eligibleJoined = eligibleTools.map(\.rawValue).joined(separator: ", ")
        let gatedJoined = gatedTools.map(\.rawValue).joined(separator: ", ")
        let visibleJoined = visibleTools.map(\.rawValue).joined(separator: ", ")

        print(
            """
            [EditorTooling] Suspicious tool list
            - template: \(context.template.rawValue)
            - selection: \(context.selection.debugLabel)
            - focus: \(context.focus.debugLabel)
            - focusGroup: \(focusGroup.rawValue)
            - capabilities: [\(capsSorted)]
            - eligible: [\(eligibleJoined)]
            - gated: [\(gatedJoined)]
            - visible: [\(visibleJoined)]
            """
        )
    }
}
#endif

// MARK: - Capability debugging helpers

extension EditorCapabilities {
    static let allKnown: [EditorCapabilities] = [
        .canEditLayout,
        .canEditTextContent,
        .canEditSymbol,
        .canEditImage,
        .canEditSmartPhoto,
        .canEditStyle,
        .canEditTypography,
        .canEditActions,
        .canEditMatchedSet,
        .canEditVariables,
        .canShare,
        .canUseAI,
        .canPurchasePro,
        .canEditAlbumShuffle,
        .canAccessPhotoLibrary,
        .hasImageConfigured,
        .hasSmartPhotoConfigured,
    ]

    var debugLabel: String {
        switch self {
        case .canEditLayout: return "layout"
        case .canEditTextContent: return "text"
        case .canEditSymbol: return "symbol"
        case .canEditImage: return "image"
        case .canEditSmartPhoto: return "smartPhoto"
        case .canEditStyle: return "style"
        case .canEditTypography: return "typography"
        case .canEditActions: return "actions"
        case .canEditMatchedSet: return "matchedSet"
        case .canEditVariables: return "variables"
        case .canShare: return "share"
        case .canUseAI: return "ai"
        case .canPurchasePro: return "pro"
        case .canEditAlbumShuffle: return "albumShuffle"
        case .canAccessPhotoLibrary: return "photosAccess"
        case .hasImageConfigured: return "hasImage"
        case .hasSmartPhotoConfigured: return "hasSmartPhoto"
        default: return "unknown(\(rawValue))"
        }
    }
}

// MARK: - Ordering helpers

extension EditorSelectionKind {
    var debugLabel: String {
        rawValue
    }
}
