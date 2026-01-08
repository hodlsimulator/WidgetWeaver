//
//  EditorFocusModel.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

/// Cardinality of the current selection (if any).
enum EditorSelectionKind: String, CaseIterable, Hashable, Sendable {
    case none
    case single
    case multi
}

/// Album subtype for album editing focus.
enum EditorAlbumSubtype: String, CaseIterable, Hashable, Sendable {
    case manual
    case smart
}

/// The single active focus target for the editor.
///
/// This is intentionally plain data (no SwiftUI) so it can be stored in model state,
/// fed into context evaluation, and unit-tested.
enum EditorFocusTarget: Hashable, Sendable {
    /// Widget-level focus (nothing selected).
    case widget

    /// A generic element is selected (non-album).
    case element(id: String)

    /// Album container focus.
    case albumContainer(id: String, subtype: EditorAlbumSubtype)

    /// A photo item inside an album is selected.
    case albumPhoto(albumID: String, itemID: String, subtype: EditorAlbumSubtype)

    /// Smart rule editor is open (exclusive).
    case smartRuleEditor(albumID: String)

    /// Clock editor focus (separate from image/album tools).
    case clock
}

/// A compact snapshot of focus + selection state.
///
/// This acts as the editor's focus/selection source-of-truth. When a selection model
/// can supply exact counts or coarse composition, they can be stored here so eligibility
/// logic remains data-driven.
struct EditorFocusSnapshot: Hashable, Sendable {
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    /// Exact selection count when known.
    ///
    /// Nil indicates that a multi-selection exists but the exact count is not available.
    var selectionCount: Int?

    /// Explicit coarse selection composition when known.
    ///
    /// When `.unknown`, selection modelling falls back to conservative heuristics.
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

// MARK: - Convenience factories (UI test hooks / smoke coverage)

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

    static func widgetMultiSelection(
        count: Int,
        categories: Set<EditorSelectionCategory>
    ) -> EditorFocusSnapshot {
        let safeCount = max(2, count)
        return EditorFocusSnapshot(
            selection: .multi,
            focus: .widget,
            selectionCount: safeCount,
            selectionComposition: .known(categories)
        )
    }
}
