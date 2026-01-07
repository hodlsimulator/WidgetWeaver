//
//  EditorTooling.swift
//  WidgetWeaver
//
//  Created by . . on 1/5/26.
//

import Foundation

struct EditorToolContext: Equatable, Hashable {
    let template: LayoutTemplateToken
    let isProUnlocked: Bool
    let matchedSetEnabled: Bool

    let selection: EditorSelectionKind
    let focus: EditorFocusTarget

    let hasSymbolConfigured: Bool
    let hasImageConfigured: Bool
    let hasSmartPhotoConfigured: Bool

    let photoLibraryAccess: EditorPhotoLibraryAccess
    let albumSubtype: EditorAlbumSubtype?

    init(
        template: LayoutTemplateToken,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        selection: EditorSelectionKind,
        focus: EditorFocusTarget,
        photoLibraryAccess: EditorPhotoLibraryAccess,
        hasSymbolConfigured: Bool,
        hasImageConfigured: Bool,
        hasSmartPhotoConfigured: Bool,
        albumSubtype: EditorAlbumSubtype? = nil
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
        self.albumSubtype = albumSubtype
    }
}

enum EditorToolID: String, CaseIterable, Codable, Hashable {
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
}

struct EditorToolCapabilities: Equatable, Hashable {
    let canEditLayout: Bool
    let canEditTextContent: Bool
    let canEditSymbol: Bool
    let canEditImage: Bool
    let canEditSmartPhoto: Bool
    let canEditStyle: Bool
    let canEditTypography: Bool
    let canEditActions: Bool

    let canAccessPro: Bool
    let canAccessAI: Bool
}

enum EditorToolRegistry {

    static func visibleToolIDs(context: EditorToolContext, selectionDescriptor: EditorSelectionDescriptor) -> [EditorToolID] {

        let base: [EditorToolID] = [
            .status,
            .designs,
            .widgets,

            .layout,
            .text,
            .symbol,

            .image,
            .smartPhoto,
            .smartPhotoCrop,

            .smartRules,
            .albumShuffle,

            .style,
            .typography,
            .actions,

            .matchedSet,
            .variables,
            .sharing,

            .ai,
            .pro
        ]

        var eligible: [EditorToolID] = []
        eligible.reserveCapacity(base.count)

        for toolID in base {
            guard let eligibility = eligibilityByToolID[toolID] else {
                eligible.append(toolID)
                continue
            }

            if EditorToolEligibilityEvaluator.isEligible(
                toolID: toolID,
                rules: eligibility,
                context: context,
                selection: selectionDescriptor
            ) {
                eligible.append(toolID)
            }
        }

        let focusGroup = editorToolFocusGroup(for: context.focus)
        let eligibleAfterFocusGate = editorToolIDsApplyingFocusGate(eligible: eligible, focusGroup: focusGroup)

        return prioritised(eligibleAfterFocusGate, focusGroup: focusGroup)
    }

    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let selectionDescriptor = EditorSelectionDescriptor.describe(selection: context.selection, focus: context.focus)
        return visibleToolIDs(context: context, selectionDescriptor: selectionDescriptor)
    }

    static func capabilities(for context: EditorToolContext) -> EditorToolCapabilities {
        let toolIDs = Set(visibleTools(for: context))

        return EditorToolCapabilities(
            canEditLayout: toolIDs.contains(.layout),
            canEditTextContent: toolIDs.contains(.text),
            canEditSymbol: toolIDs.contains(.symbol),
            canEditImage: toolIDs.contains(.image),
            canEditSmartPhoto: toolIDs.contains(.smartPhoto),
            canEditStyle: toolIDs.contains(.style),
            canEditTypography: toolIDs.contains(.typography),
            canEditActions: toolIDs.contains(.actions),
            canAccessPro: toolIDs.contains(.pro),
            canAccessAI: toolIDs.contains(.ai)
        )
    }

    private static func prioritised(_ toolIDs: [EditorToolID], focusGroup: EditorToolFocusGroup) -> [EditorToolID] {
        switch focusGroup {
        case .smartPhotos:
            let first: [EditorToolID] = [.smartRules, .albumShuffle, .smartPhoto, .smartPhotoCrop, .image]
            return stableBucket(toolIDs, first: first)

        case .widget:
            let first: [EditorToolID] = [.status, .layout, .text, .style]
            return stableBucket(toolIDs, first: first)

        case .clock:
            let first: [EditorToolID] = [.status, .layout, .style]
            return stableBucket(toolIDs, first: first)

        default:
            return toolIDs
        }
    }

    private static func stableBucket(_ toolIDs: [EditorToolID], first: [EditorToolID]) -> [EditorToolID] {
        let firstSet = Set(first)
        let a = toolIDs.filter { firstSet.contains($0) }
        let b = toolIDs.filter { !firstSet.contains($0) }
        return a + b
    }

    private static let eligibilityByToolID: [EditorToolID: EditorToolEligibility] = [
        .status: .init(),
        .designs: .init(),
        .widgets: .init(),

        .layout: .init(
            selectionDescriptor: .allowsNonAlbumOnly
        ),

        .text: .init(
            selectionDescriptor: .allowsNonAlbumOnly
        ),

        .symbol: .init(
            selectionDescriptor: .allowsNonAlbumOnly
        ),

        .image: .init(
            selectionDescriptor: .allowsNonAlbumOnly
        ),

        .smartPhoto: .init(
            focus: .smartPhotoTarget
        ),

        .smartPhotoCrop: .init(
            focus: .smartPhotoTarget,
            requires: .requiresAny([
                .hasSmartPhotoConfigured,
                .hasImageConfigured
            ])
        ),

        .smartRules: .init(
            focus: .smartRules,
            selectionDescriptor: .allowsAlbumContainerOrNone
        ),

        .albumShuffle: .init(
            focus: .albumShuffle,
            selectionDescriptor: .allowsAlbumContainerOrNone
        ),

        .style: .init(),
        .typography: .init(),
        .actions: .init(),

        .matchedSet: .init(),
        .variables: .init(),
        .sharing: .init(),

        .ai: .init(
            requires: .requiresAny([.isProUnlocked])
        ),

        .pro: .init()
    ]
}
