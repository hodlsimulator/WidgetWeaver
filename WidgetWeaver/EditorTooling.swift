//
//  EditorTooling.swift
//  WidgetWeaver
//
//  Created by . . on 1/5/26.
//

import Foundation

enum EditorSelectionKind: Hashable, Sendable {
    case none
    case single
    case multi

    var cardinalityLabel: String {
        switch self {
        case .none: return "none"
        case .single: return "single"
        case .multi: return "multi"
        }
    }
}

struct EditorToolContext: Hashable, Sendable {
    var template: LayoutTemplateToken
    var isProUnlocked: Bool
    var matchedSetEnabled: Bool
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

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

enum EditorToolID: String, CaseIterable, Hashable, Sendable {
    // Workflow.
    case status
    case designs
    case widgets

    // Core edit.
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

    // Behaviour / actions.
    case actions

    // Matched set + globals.
    case matchedSet
    case variables

    // Sharing / growth.
    case sharing
    case ai
    case pro
}

/// Capability vocabulary.
/// Keep this additive and stable; tools declare requirements by capability.
struct EditorCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int

    init(rawValue: Int) { self.rawValue = rawValue }

    static let canEditLayout = EditorCapabilities(rawValue: 1 << 0)
    static let canEditTextContent = EditorCapabilities(rawValue: 1 << 1)
    static let canEditSymbol = EditorCapabilities(rawValue: 1 << 2)
    static let canEditImage = EditorCapabilities(rawValue: 1 << 3)
    static let canEditSmartPhoto = EditorCapabilities(rawValue: 1 << 4)
    static let canEditAlbumShuffle = EditorCapabilities(rawValue: 1 << 5)
    static let canEditStyle = EditorCapabilities(rawValue: 1 << 6)
    static let canEditTypography = EditorCapabilities(rawValue: 1 << 7)
    static let canEditActions = EditorCapabilities(rawValue: 1 << 8)
    static let canEditMatchedSet = EditorCapabilities(rawValue: 1 << 9)
    static let canEditVariables = EditorCapabilities(rawValue: 1 << 10)
    static let canShare = EditorCapabilities(rawValue: 1 << 11)
    static let canUseAI = EditorCapabilities(rawValue: 1 << 12)
    static let canPurchasePro = EditorCapabilities(rawValue: 1 << 13)

    // Permission/availability.
    static let canAccessPhotoLibrary = EditorCapabilities(rawValue: 1 << 14)
    static let hasSymbolConfigured = EditorCapabilities(rawValue: 1 << 15)
    static let hasImageConfigured = EditorCapabilities(rawValue: 1 << 16)
    static let hasSmartPhotoConfigured = EditorCapabilities(rawValue: 1 << 17)
}

struct EditorToolDefinition: Hashable, Sendable {
    var id: EditorToolID
    var order: Int
    var requiredCapabilities: EditorCapabilities
    var eligibility: EditorToolEligibility

    init(id: EditorToolID, order: Int, requiredCapabilities: EditorCapabilities, eligibility: EditorToolEligibility) {
        self.id = id
        self.order = order
        self.requiredCapabilities = requiredCapabilities
        self.eligibility = eligibility
    }
}

enum EditorToolRegistry {
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
                selectionDescriptor: .allowsHomogeneousOrNoneSelection
            )
        ),
        EditorToolDefinition(
            id: .symbol,
            order: 60,
            requiredCapabilities: [.canEditSymbol],
            eligibility: .singleTarget(
                focus: .any,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection
            )
        ),
        EditorToolDefinition(
            id: .image,
            order: 70,
            requiredCapabilities: [.canEditImage],
            eligibility: .singleTarget(
                focus: .smartPhotoPhotoItemSuite,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection
            )
        ),

        // Smart Photos / Albums.
        EditorToolDefinition(
            id: .smartPhoto,
            order: 80,
            requiredCapabilities: [.canEditSmartPhoto],
            eligibility: .init(
                focus: .smartPhotoContainerSuite,
                selection: .any,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection,
                supportsMultiSelection: true
            )
        ),
        EditorToolDefinition(
            id: .smartPhotoCrop,
            order: 81,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured],
            eligibility: .init(
                focus: .smartPhotoPhotoItemSuite,
                selection: .allowsNoneOrSingle,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection,
                supportsMultiSelection: false
            )
        ),
        EditorToolDefinition(
            id: .smartRules,
            order: 82,
            requiredCapabilities: [.canEditSmartPhoto, .hasSmartPhotoConfigured],
            eligibility: .init(
                focus: .smartPhotoContainerSuite,
                selection: .allowsNoneOrSingle,
                selectionDescriptor: .allowsHomogeneousOrNoneSelection,
                supportsMultiSelection: false
            )
        ),
        EditorToolDefinition(
            id: .albumShuffle,
            order: 83,
            requiredCapabilities: [.canEditAlbumShuffle, .hasSmartPhotoConfigured, .canAccessPhotoLibrary],
            eligibility: .init(
                focus: .smartPhotoContainerSuite,
                selection: .allowsNoneOrSingle,
                selectionDescriptor: .allowsAlbumContainerOrNone,
                supportsMultiSelection: false
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
            eligibility: .singleTarget(selectionDescriptor: .allowsHomogeneousOrNoneSelection)
        ),

        // Actions.
        EditorToolDefinition(
            id: .actions,
            order: 110,
            requiredCapabilities: [.canEditActions],
            eligibility: .singleTarget(selectionDescriptor: .allowsHomogeneousOrNoneSelection)
        ),

        // Matched set / globals.
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

        // Sharing / growth.
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
        var caps: EditorCapabilities = [
            .canEditLayout,
            .canEditTextContent,
            .canEditStyle,
            .canEditMatchedSet,
            .canEditVariables,
            .canShare,
            .canPurchasePro,
        ]

        if context.isProUnlocked {
            caps.insert(.canUseAI)
        }

        if context.matchedSetEnabled {
            caps.insert(.canEditMatchedSet)
        }

        if context.photoLibraryAccess.allowsReadWrite {
            caps.insert(.canAccessPhotoLibrary)
        }

        if context.hasSymbolConfigured {
            caps.insert(.hasSymbolConfigured)
        }

        if context.hasImageConfigured {
            caps.insert(.hasImageConfigured)
        }

        if context.hasSmartPhotoConfigured {
            caps.insert(.hasSmartPhotoConfigured)
        }

        switch context.template {
        case .classic:
            caps.insert(.canEditSymbol)
            caps.insert(.canEditTypography)
            caps.insert(.canEditActions)

        case .hero:
            caps.insert(.canEditSymbol)
            caps.insert(.canEditTypography)
            caps.insert(.canEditActions)

        case .poster:
            caps.insert(.canEditSymbol)
            caps.insert(.canEditImage)
            caps.insert(.canEditSmartPhoto)
            caps.insert(.canEditAlbumShuffle)
            caps.insert(.canEditTypography)

        case .weather:
            break

        case .nextUpCalendar:
            break
        }

        return caps
    }

    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let caps = capabilities(for: context)
        let descriptor = EditorSelectionDescriptor.describe(selection: context.selection, focus: context.focus)

        var eligible = tools
            .filter { def in
                caps.contains(def.requiredCapabilities)
            }
            .filter { def in
                EditorToolEligibilityEvaluator.isEligible(
                    tool: def.id,
                    eligibility: def.eligibility,
                    selection: context.selection,
                    focus: context.focus,
                    selectionDescriptor: descriptor
                )
            }
            .sorted { $0.order < $1.order }
            .map(\.id)

        let focusGroup = editorToolFocusGroup(for: context.focus)
        eligible = editorToolIDsApplyingFocusGate(
            eligibleToolIDs: eligible,
            focusGroup: focusGroup
        )

        if focusGroup == .smartPhotos {
            eligible = prioritiseToolsForSmartPhotos(
                eligibleToolIDs: eligible,
                focus: context.focus
            )
        }

        #if DEBUG
        logUnexpectedToolStatesIfNeeded(
            eligibleToolIDs: eligible,
            context: context,
            selectionDescriptor: descriptor
        )
        #endif

        return eligible
    }

    static func legacyVisibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let caps = capabilities(for: context)

        let eligible = tools
            .filter { def in
                caps.contains(def.requiredCapabilities)
            }
            .sorted { $0.order < $1.order }
            .map(\.id)

        return eligible
    }
}

#if DEBUG
private func logUnexpectedToolStatesIfNeeded(
    eligibleToolIDs: [EditorToolID],
    context: EditorToolContext,
    selectionDescriptor: EditorSelectionDescriptor
) {
    guard !eligibleToolIDs.isEmpty else {
        print(
            "[EditorToolRegistry] ⚠️ Visible tools empty | template=\(context.template) selection=\(context.selection.cardinalityLabel) focus=\(context.focus.debugLabel) " +
                "descriptor=(\(selectionDescriptor.cardinalityLabel), \(selectionDescriptor.homogeneityLabel), \(selectionDescriptor.albumSpecificityLabel))"
        )
        return
    }

    if eligibleToolIDs.count <= 3 {
        print(
            "[EditorToolRegistry] ⚠️ Visible tools suspiciously small (\(eligibleToolIDs.count)) | template=\(context.template) selection=\(context.selection.cardinalityLabel) focus=\(context.focus.debugLabel) " +
                "tools=\(eligibleToolIDs.map(\.rawValue).joined(separator: \",\")) " +
                "descriptor=(\(selectionDescriptor.cardinalityLabel), \(selectionDescriptor.homogeneityLabel), \(selectionDescriptor.albumSpecificityLabel))"
        )
    }
}
#endif
