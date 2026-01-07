//
//  EditorFocusModel.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

/// Coarse cardinality for the current editor selection.
///
/// The editor tracks cardinality separately from focus so the UI can express
/// interactions like multi-select while still having a focused target.
enum EditorSelectionKind: String, CaseIterable, Hashable, Sendable {
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

/// Broad categorisation for album-backed content.
enum EditorAlbumSubtype: String, CaseIterable, Hashable, Sendable {
    case smart
    case user

    var label: String {
        switch self {
        case .smart: return "smart"
        case .user: return "user"
        }
    }
}

/// Focus target for tool gating and editor UI state.
///
/// Keep this enum in sync with switches in ContentView (debug overlay etc).
enum EditorFocusTarget: Hashable, Sendable {
    case widget
    case clock
    case element(id: String)
    case albumContainer(id: String, subtype: EditorAlbumSubtype)
    case albumPhoto(albumID: String, itemID: String, subtype: EditorAlbumSubtype)
    case smartRuleEditor(albumID: String)
}

extension EditorFocusTarget {
    var albumSubtype: EditorAlbumSubtype? {
        switch self {
        case .albumContainer(_, let subtype): return subtype
        case .albumPhoto(_, _, let subtype): return subtype
        default: return nil
        }
    }

    var elementID: String? {
        switch self {
        case .element(let id): return id
        default: return nil
        }
    }

    var debugLabel: String {
        switch self {
        case .widget:
            return "widget"
        case .clock:
            return "clock"
        case .element(let id):
            return "element(\(id))"
        case .albumContainer(let id, let subtype):
            return "albumContainer(\(id), \(subtype.label))"
        case .albumPhoto(let albumID, let itemID, let subtype):
            return "albumPhoto(\(albumID), \(itemID), \(subtype.label))"
        case .smartRuleEditor(let albumID):
            return "smartRuleEditor(\(albumID))"
        }
    }
}

struct EditorFocusSnapshot: Hashable, Sendable {
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    static let widgetDefault = EditorFocusSnapshot(selection: .none, focus: .widget)
}
