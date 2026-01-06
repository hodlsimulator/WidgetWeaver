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
struct EditorFocusSnapshot: Hashable, Sendable {
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    static let widgetDefault = EditorFocusSnapshot(selection: .none, focus: .widget)
}
