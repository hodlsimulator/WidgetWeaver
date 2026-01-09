//
//  EditorSelectionSet.swift
//  WidgetWeaver
//
//  Created by . . on 1/9/26.
//

import Foundation

/// A typed representation of a user selection set.
///
/// The editor's single source of truth remains `EditorFocusSnapshot`, but selection
/// surfaces (lists, browsers, pickers) can use this model to derive origin-backed
/// focus snapshots with explicit `selectionCount` and `selectionComposition`.
enum EditorSelectionItem: Hashable, Sendable {
    case nonAlbumElement(id: String)
    case albumContainer(id: String, subtype: EditorAlbumSubtype)
    case albumPhotoItem(albumID: String, itemID: String, subtype: EditorAlbumSubtype)

    var impliedSelectionCategory: EditorSelectionCategory {
        switch self {
        case .nonAlbumElement:
            return .nonAlbum
        case .albumContainer:
            return .albumContainer
        case .albumPhotoItem:
            return .albumPhotoItem
        }
    }

    var impliedFocusTarget: EditorFocusTarget {
        switch self {
        case .nonAlbumElement(let id):
            return .element(id: id)
        case .albumContainer(let id, let subtype):
            return .albumContainer(id: id, subtype: subtype)
        case .albumPhotoItem(let albumID, let itemID, let subtype):
            return .albumPhoto(albumID: albumID, itemID: itemID, subtype: subtype)
        }
    }
}

struct EditorSelectionSet: Hashable, Sendable {
    var items: Set<EditorSelectionItem>

    init(items: Set<EditorSelectionItem> = []) {
        self.items = items
    }

    var selectionCount: Int {
        items.count
    }

    var selection: EditorSelectionKind {
        if selectionCount <= 0 { return .none }
        if selectionCount == 1 { return .single }
        return .multi
    }

    var selectionComposition: EditorSelectionComposition {
        let categories = Set(items.map(\.impliedSelectionCategory))
        if categories.isEmpty { return .none }
        return .known(categories)
    }

    /// Derives an origin-backed focus snapshot.
    ///
    /// - For empty selections, returns `.widgetDefault`.
    /// - For single selections, focuses the selected item.
    /// - For multi-selections, focuses `.widget` (the editor is in "selection set" mode).
    func toFocusSnapshot() -> EditorFocusSnapshot {
        switch selection {
        case .none:
            return .widgetDefault
        case .single:
            guard let item = items.first else {
                return .widgetDefault
            }
            return EditorFocusSnapshot(
                selection: .single,
                focus: item.impliedFocusTarget,
                selectionCount: 1,
                selectionComposition: selectionComposition
            )
        case .multi:
            return EditorFocusSnapshot(
                selection: .multi,
                focus: .widget,
                selectionCount: selectionCount,
                selectionComposition: selectionComposition
            )
        }
    }
}
