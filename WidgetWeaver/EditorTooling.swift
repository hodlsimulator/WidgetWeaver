//
//  EditorTooling.swift
//  WidgetWeaver
//
//  Created by . . on 1/4/26.
//

import Foundation

enum EditorToolID: String, CaseIterable, Hashable, Sendable {
    // Layout
    case layout
    case padding
    case background
    case border

    // Text
    case text
    case typography

    // Symbols
    case symbols

    // Media
    case image
    case smartPhoto
    case smartPhotoCrop
    case smartRules
    case albumShuffle

    // Style
    case style

    // Actions
    case actions
}

struct EditorToolDefinition: Hashable, Sendable {
    let id: EditorToolID
    let order: Int
    let requiredCapabilities: Set<EditorCapability>

    init(
        id: EditorToolID,
        order: Int,
        requiredCapabilities: Set<EditorCapability>
    ) {
        self.id = id
        self.order = order
        self.requiredCapabilities = requiredCapabilities
    }
}

enum EditorToolRegistry {
    static let tools: [EditorToolDefinition] = [
        // Layout
        EditorToolDefinition(id: .layout, order: 10, requiredCapabilities: [.canEditLayout]),
        EditorToolDefinition(id: .padding, order: 12, requiredCapabilities: [.canEditLayout]),
        EditorToolDefinition(id: .background, order: 14, requiredCapabilities: [.canEditLayout]),
        EditorToolDefinition(id: .border, order: 16, requiredCapabilities: [.canEditLayout]),

        // Text
        EditorToolDefinition(id: .text, order: 30, requiredCapabilities: [.canEditText]),
        EditorToolDefinition(id: .typography, order: 32, requiredCapabilities: [.canEditTypography]),

        // Symbols
        EditorToolDefinition(id: .symbols, order: 40, requiredCapabilities: [.canEditSymbol]),

        // Media
        EditorToolDefinition(id: .image, order: 60, requiredCapabilities: [.canEditImage]),
        EditorToolDefinition(id: .smartPhoto, order: 62, requiredCapabilities: [.canEditSmartPhoto]),
        EditorToolDefinition(id: .smartPhotoCrop, order: 63, requiredCapabilities: [.canEditSmartPhoto]),
        EditorToolDefinition(id: .smartRules, order: 64, requiredCapabilities: [.canEditSmartPhoto]),
        EditorToolDefinition(id: .albumShuffle, order: 65, requiredCapabilities: [.canEditAlbumShuffle]),

        // Style
        EditorToolDefinition(id: .style, order: 70, requiredCapabilities: [.canEditStyle]),

        // Actions
        EditorToolDefinition(id: .actions, order: 80, requiredCapabilities: [.canEditActions]),
    ]

    static func visibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let eligible = eligibleTools(for: context)
        let gated = EditorToolFocusGating.editorToolIDsApplyingFocusGate(
            eligibleToolIDs: eligible,
            focusGroup: context.focusGroup
        )
        return prioritiseToolsForFocusGroup(toolIDs: gated, focusGroup: context.focusGroup)
    }

    static func eligibleTools(for context: EditorToolContext) -> [EditorToolID] {
        let eligible = tools
            .filter { def in
                def.requiredCapabilities.isSubset(of: context.capabilities)
            }
            .sorted { $0.order < $1.order }
            .map(\.id)

        return eligible
    }

    static func prioritiseToolsForFocusGroup(toolIDs: [EditorToolID], focusGroup: EditorToolFocusGroup) -> [EditorToolID] {
        switch focusGroup {
        case .smartPhotos:
            return prioritiseToolsForSmartPhotos(toolIDs: toolIDs)
        default:
            return toolIDs
        }
    }

    private static func prioritiseToolsForSmartPhotos(toolIDs: [EditorToolID]) -> [EditorToolID] {
        var out: [EditorToolID] = []
        out.reserveCapacity(toolIDs.count)

        // 1) Album Shuffle first (it is the "container" for Smart Photo inputs)
        if toolIDs.contains(.albumShuffle) {
            out.append(.albumShuffle)
        }

        // 2) Smart Photo framing tools next.
        if toolIDs.contains(.smartPhotoCrop) {
            out.append(.smartPhotoCrop)
        }

        // 3) Smart Rules / album criteria tools.
        if toolIDs.contains(.smartRules) {
            out.append(.smartRules)
        }

        // 4) Smart Photo creation/regeneration tools.
        if toolIDs.contains(.smartPhoto) {
            out.append(.smartPhoto)
        }

        // 5) Related image controls.
        if toolIDs.contains(.image) {
            out.append(.image)
        }

        // 6) Remaining tools (keep relative order), with Style last.
        let already = Set(out)
        for id in toolIDs where !already.contains(id) && id != .style {
            out.append(id)
        }
        if toolIDs.contains(.style) {
            out.append(.style)
        }

        return out
    }
}

enum EditorCapability: String, Hashable, Sendable {
    // Layout
    case canEditLayout

    // Text
    case canEditText
    case canEditTypography

    // Symbols
    case canEditSymbol

    // Media
    case canEditImage
    case canEditSmartPhoto
    case canEditAlbumShuffle

    // Style
    case canEditStyle

    // Actions
    case canEditActions
}

struct EditorToolContext: Hashable, Sendable {
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget
    var focusGroup: EditorToolFocusGroup
    var capabilities: Set<EditorCapability>
}

extension EditorCapability {
    static func derived(for template: WidgetTemplate) -> Set<EditorCapability> {
        switch template {
        case .classic:
            return [
                .canEditLayout,
                .canEditText,
                .canEditTypography,
                .canEditSymbol,
                .canEditStyle,
                .canEditActions,
            ]
        case .poster:
            return [
                .canEditLayout,
                .canEditText,
                .canEditTypography,
                .canEditImage,
                .canEditSmartPhoto,
                .canEditAlbumShuffle,
                .canEditStyle,
                .canEditActions,
            ]
        case .lockScreen:
            return [
                .canEditLayout,
                .canEditText,
                .canEditTypography,
                .canEditSymbol,
                .canEditStyle,
                .canEditActions,
            ]
        case .clock:
            return [
                .canEditLayout,
                .canEditText,
                .canEditTypography,
                .canEditSymbol,
                .canEditStyle,
                .canEditActions,
            ]
        }
    }
}
