//
//  EditorFocusModel.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

enum EditorSelectionKind: Hashable, Sendable {
    case none
    case single
    case multi
}

enum EditorAlbumSubtype: Hashable, Sendable {
    case smart
    case manual
}

enum EditorFocusTarget: Hashable, Sendable {
    case widget

    /// A focused element within the widget. The `id` is intentionally an opaque identifier owned by the editor.
    case element(id: String)

    /// A focused album-like container (Smart Photo album shuffle, manual albums, etc).
    case albumContainer(id: String, subtype: EditorAlbumSubtype)

    /// A focused photo item within an album-like container.
    case albumPhoto(albumID: String, itemID: String, subtype: EditorAlbumSubtype)

    /// A nested editor for smart rules associated with an album container.
    case smartRuleEditor(albumID: String)

    /// Clock adjustment focus. Must not affect WidgetWeaverWidget/Clock ticking logic.
    case clock
}

struct EditorFocusSnapshot: Hashable, Sendable {
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    /// Optional selection count hint for more accurate eligibility/diagnostics.
    /// - If nil, selection count is inferred conservatively by the context evaluator.
    var selectionCount: Int?

    /// Optional selection composition hint for album-vs-non-album tool filtering.
    /// - If unknown, selection composition is inferred conservatively when possible.
    var selectionComposition: EditorSelectionComposition

    init(
        selection: EditorSelectionKind,
        focus: EditorFocusTarget,
        selectionCount: Int? = nil,
        selectionComposition: EditorSelectionComposition = .unknown
    ) {
        self.selection = selection
        self.focus = focus
        self.selectionCount = selectionCount
        self.selectionComposition = selectionComposition
    }

    static let widgetDefault = EditorFocusSnapshot(
        selection: .none,
        focus: .widget,
        selectionCount: 0,
        selectionComposition: .none
    )
}

// MARK: - Convenience factories

extension EditorFocusSnapshot {
    static func singleNonAlbumElement(id: String) -> EditorFocusSnapshot {
        EditorFocusSnapshot(
            selection: .single,
            focus: .element(id: id),
            selectionCount: 1,
            selectionComposition: .known([.nonAlbum])
        )
    }

    static func clockFocus() -> EditorFocusSnapshot {
        EditorFocusSnapshot(
            selection: .single,
            focus: .clock,
            selectionCount: 1,
            selectionComposition: .known([.nonAlbum])
        )
    }

    static func smartAlbumContainer(id: String) -> EditorFocusSnapshot {
        EditorFocusSnapshot(
            selection: .single,
            focus: .albumContainer(id: id, subtype: .smart),
            selectionCount: 1,
            selectionComposition: .known([.albumContainer])
        )
    }

    static func smartAlbumPhotoItem(albumID: String, itemID: String) -> EditorFocusSnapshot {
        EditorFocusSnapshot(
            selection: .single,
            focus: .albumPhoto(albumID: albumID, itemID: itemID, subtype: .smart),
            selectionCount: 1,
            selectionComposition: .known([.albumPhotoItem])
        )
    }

    static func smartRuleEditor(albumID: String) -> EditorFocusSnapshot {
        EditorFocusSnapshot(
            selection: .single,
            focus: .smartRuleEditor(albumID: albumID),
            selectionCount: 1,
            selectionComposition: .known([.albumContainer])
        )
    }

    static func widgetNonAlbumMultiSelection(count: Int) -> EditorFocusSnapshot {
        widgetMultiSelection(count: count, categories: [.nonAlbum])
    }

    static func widgetMixedMultiSelection(count: Int) -> EditorFocusSnapshot {
        widgetMultiSelection(count: count, categories: [.albumContainer, .nonAlbum])
    }

    static func widgetMultiSelection(count: Int, categories: Set<EditorSelectionCategory>) -> EditorFocusSnapshot {
        let safeCount = max(2, count)
        return EditorFocusSnapshot(
            selection: .multi,
            focus: .widget,
            selectionCount: safeCount,
            selectionComposition: .known(categories)
        )
    }
}
