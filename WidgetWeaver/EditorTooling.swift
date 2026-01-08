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

    /// Exact selection count when known.
    ///
    /// Nil means the selection is known to be multi-select but an exact count
    /// is unavailable.
    var selectionCount: Int?

    /// Coarse selection composition when known.
    ///
    /// When `.unknown`, selection modelling falls back to conservative heuristics.
    var selectionComposition: EditorSelectionComposition

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
        selectionCount: Int? = nil,
        selectionComposition: EditorSelectionComposition = .unknown,
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
        self.selectionCount = selectionCount
        self.selectionComposition = selectionComposition
        self.photoLibraryAccess = photoLibraryAccess
        self.hasSymbolConfigured = hasSymbolConfigured
        self.hasImageConfigured = hasImageConfigured
        self.hasSmartPhotoConfigured = hasSmartPhotoConfigured
    }
}

// MARK: - Capability vocabulary

struct EditorCapability: Hashable, Sendable, RawRepresentable {
    var rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
}

typealias EditorCapabilities = Set<EditorCapability>

extension EditorCapability {
    // Template / tool availability.
    static let canEditLayout = EditorCapability(rawValue: "layout")
    static let canEditTextContent = EditorCapability(rawValue: "text")
    static let canEditSymbol = EditorCapability(rawValue: "symbol")
    static let canEditImage = EditorCapability(rawValue: "image")
    static let canEditSmartPhoto = EditorCapability(rawValue: "smartPhoto")
    static let canEditTypography = EditorCapability(rawValue: "typography")
    static let canEditStyle = EditorCapability(rawValue: "style")
    static let canEditActions = EditorCapability(rawValue: "actions")
    static let canEditMatchedSet = EditorCapability(rawValue: "matchedSet")

    // Editor-level features.
    static let canEditVariables = EditorCapability(rawValue: "variables")
    static let canShare = EditorCapability(rawValue: "share")
    static let canUseAI = EditorCapability(rawValue: "ai")
    static let canPurchasePro = EditorCapability(rawValue: "pro")

    // Albums.
    static let canEditAlbumShuffle = EditorCapability(rawValue: "albumShuffle")

    // Permissions and derived availability.
    static let canAccessPhotoLibrary = EditorCapability(rawValue: "photosAccess")
    static let hasImageConfigured = EditorCapability(rawValue: "hasImage")
    static let hasSmartPhotoConfigured = EditorCapability(rawValue: "hasSmartPhoto")
}

// MARK: - Tool IDs

enum EditorToolID: String, CaseIterable, Hashable, Identifiable, Sendable {
    case status
    case designs
    case widgets

    case layout
    case text
    case symbol
    case image
    case smartPhoto
    case smartPhotoCrop
    case albumShuffle
    case smartRules
    case typography
    case style

    case actions
    case matchedSet
    case variables
    case sharing
    case ai
    case pro

    var id: String { rawValue }
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
            focus: context.focus,
            selectionCount: context.selectionCount,
            composition: context.selectionComposition
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
            id: .albumShuffle,
            order: 82,
            requiredCapabilities: [.canEditAlbumShuffle, .hasSmartPhotoConfigured],
            eligibility: .singleTarget(
                focus: EditorToolFocusConstraint(
                    allowClock: false,
                    allowSmartRuleEditor: true,
                    allowAnyElement: false,
                    allowedElementIDPrefixes: ["smartPhoto"],
                    allowAnyAlbumContainer: false,
                    allowedAlbumContainerSubtypes: [.smart],
                    allowAnyAlbumPhotoItem: false,
                    allowedAlbumPhotoItemSubtypes: [.smart]
                ),
                selectionDescriptor: .allowsAlbumContainerOrNonAlbumHomogeneousOrNone
            )
        ),
        EditorToolDefinition(
            id: .smartRules,
            order: 83,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured],
            eligibility: .singleTarget(
                focus: .smartPhotoContainerSuite,
                selectionDescriptor: .allowsAlbumContainerOrNonAlbumHomogeneousOrNone
            )
        ),

        // Style group.
        EditorToolDefinition(
            id: .style,
            order: 90,
            requiredCapabilities: [.canEditStyle],
            eligibility: .multiSafe()
        ),

        // Typography group.
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
            c.insert(.canEditTypography)

        case .nextUpCalendar:
            c.insert(.canEditTypography)
        }

        // Permissions and derived availability.
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

    static func legacyVisibleTools(for context: EditorToolContext) -> [EditorToolID] {
        // Old behaviour: capabilities-only ordering (no eligibility/focus gating).
        let caps = capabilities(for: context)

        return tools
            .filter { $0.requiredCapabilities.isSubset(of: caps) }
            .sorted { $0.order < $1.order }
            .map(\.id)
    }

    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let caps = capabilities(for: context)

        let eligible = tools
            .filter { $0.isEligible(context: context, capabilities: caps, multiSelectionPolicy: multiSelectionPolicy) }
            .sorted { $0.order < $1.order }
            .map(\.id)

        // Apply focus gating as last-mile filter.
        let focusGroup = editorToolFocusGroup(for: context.focus)
        let focusGated = editorToolIDsApplyingFocusGate(
            eligible: eligible,
            focusGroup: focusGroup
        )

        // Prioritise Smart Rules when editing them.
        if case .smartRuleEditor = context.focus {
            if let idx = focusGated.firstIndex(of: EditorToolID.smartRules), idx != 0 {
                var moved = focusGated
                moved.remove(at: idx)
                moved.insert(EditorToolID.smartRules, at: 0)
                return moved
            }
        }

        return focusGated
    }
}

// MARK: - Debug / diagnostics

extension EditorToolContext {
    var debugSummary: String {
        """
        template=\(template.rawValue)
        pro=\(isProUnlocked)
        matchedSet=\(matchedSetEnabled)
        selection=\(selection.rawValue)
        focus=\(focus.debugLabel)
        photos=\(photoLibraryAccess.status.rawValue)
        hasSymbol=\(hasSymbolConfigured)
        hasImage=\(hasImageConfigured)
        hasSmartPhoto=\(hasSmartPhotoConfigured)
        """
    }
}

extension EditorFocusTarget {
    var debugLabel: String {
        switch self {
        case .widget:
            return "widget"
        case .clock:
            return "clock"
        case .smartRuleEditor(let albumID):
            return "smartRuleEditor(\(albumID))"
        case .element(let id):
            return "element(\(id))"
        case .albumContainer(let id, let subtype):
            return "albumContainer(\(id), \(subtype.rawValue))"
        case .albumPhoto(let albumID, let itemID, let subtype):
            return "albumPhoto(\(albumID), \(itemID), \(subtype.rawValue))"
        }
    }
}

extension EditorCapabilities {
    static let allKnown: [EditorCapability] = [
        .canEditLayout,
        .canEditTextContent,
        .canEditSymbol,
        .canEditImage,
        .canEditSmartPhoto,
        .canEditTypography,
        .canEditStyle,
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
}

extension EditorCapability {
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
