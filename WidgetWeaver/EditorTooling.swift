//
//  EditorTooling.swift
//  WidgetWeaver
//
//  Created by . . on 1/5/26.
//

import Foundation

/// Current editor context used to determine tool availability.
struct EditorToolContext: Hashable, Sendable {
    var template: LayoutTemplateToken
    var isProUnlocked: Bool
    var matchedSetEnabled: Bool
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    var hasSymbolConfigured: Bool
    var hasImageConfigured: Bool
    var hasSmartPhotoConfigured: Bool

    var photoLibraryAccess: EditorPhotoLibraryAccess
    var albumSubtype: EditorAlbumSubtype?
}

enum EditorToolID: String, CaseIterable, Hashable, Sendable {
    case status
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
    case designs
    case typography
    case actions
    case matchedSet
    case variables
    case sharing
    case ai
    case pro
}

struct EditorToolCapabilities: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let canEditLayout       = EditorToolCapabilities(rawValue: 1 << 0)
    static let canEditTextContent  = EditorToolCapabilities(rawValue: 1 << 1)
    static let canEditSymbol       = EditorToolCapabilities(rawValue: 1 << 2)
    static let canEditImage        = EditorToolCapabilities(rawValue: 1 << 3)
    static let canEditSmartPhoto   = EditorToolCapabilities(rawValue: 1 << 4)
    static let canEditStyle        = EditorToolCapabilities(rawValue: 1 << 5)
    static let canEditTypography   = EditorToolCapabilities(rawValue: 1 << 6)
    static let canEditActions      = EditorToolCapabilities(rawValue: 1 << 7)
}

enum EditorToolRegistry {

    private static let toolOrder: [EditorToolID] = [
        .status,
        .widgets,
        .layout,
        .designs,
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

    private static let eligibilityByToolID: [EditorToolID: EditorToolEligibility] = [
        .status: .init(),
        .widgets: .init(),
        .layout: .init(),
        .designs: .init(),
        .text: .init(),
        .symbol: .init(selectionDescriptor: .allowsNonAlbumOnly),
        .image: .init(),
        .smartPhoto: .init(),
        .smartPhotoCrop: .init(focus: .smartPhotoTarget),
        .smartRules: .init(focus: .smartRules),
        .albumShuffle: .init(focus: .albumShuffle),
        .style: .init(),
        .typography: .init(),
        .actions: .init(),
        .matchedSet: .init(),
        .variables: .init(),
        .sharing: .init(),
        .ai: .init(),
        .pro: .init()
    ]

    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let selectionDescriptor = EditorSelectionDescriptor.describe(selection: context.selection, focus: context.focus)

        var eligible = toolOrder.filter { toolID in
            let eligibility = eligibilityByToolID[toolID] ?? .init()
            return EditorToolEligibilityEvaluator.isEligible(
                eligibility: eligibility,
                selection: context.selection,
                selectionDescriptor: selectionDescriptor,
                focus: context.focus
            )
        }

        if context.hasSmartPhotoConfigured == false {
            eligible.removeAll(where: { $0 == .smartPhotoCrop || $0 == .smartRules || $0 == .albumShuffle })
        }

        let focusGroup = EditorToolFocusGroup.from(focus: context.focus)
        let gated = editorToolIDsApplyingFocusGate(eligible: eligible, focusGroup: focusGroup)

        return prioritised(toolIDs: gated, focusGroup: focusGroup)
    }

    static func capabilities(for context: EditorToolContext) -> EditorToolCapabilities {
        let toolIDs = visibleTools(for: context)

        var caps: EditorToolCapabilities = []

        if toolIDs.contains(.layout) { caps.insert(.canEditLayout) }
        if toolIDs.contains(.text) { caps.insert(.canEditTextContent) }
        if toolIDs.contains(.symbol) { caps.insert(.canEditSymbol) }
        if toolIDs.contains(.image) { caps.insert(.canEditImage) }
        if toolIDs.contains(where: { [.smartPhoto, .smartPhotoCrop, .smartRules, .albumShuffle].contains($0) }) {
            caps.insert(.canEditSmartPhoto)
        }
        if toolIDs.contains(.style) { caps.insert(.canEditStyle) }
        if toolIDs.contains(.typography) { caps.insert(.canEditTypography) }
        if toolIDs.contains(.actions) { caps.insert(.canEditActions) }

        return caps
    }

    private static func prioritised(toolIDs: [EditorToolID], focusGroup: EditorToolFocusGroup) -> [EditorToolID] {
        guard focusGroup == .smartPhotos else { return toolIDs }

        let preferred: [EditorToolID] = [
            .smartPhoto,
            .smartPhotoCrop,
            .smartRules,
            .albumShuffle,
            .image,
            .style
        ]

        return toolIDs.sorted { a, b in
            let ia = preferred.firstIndex(of: a) ?? Int.max
            let ib = preferred.firstIndex(of: b) ?? Int.max
            if ia != ib { return ia < ib }
            return a.rawValue < b.rawValue
        }
    }
}
