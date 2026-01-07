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

    var cardinalityLabel: String {
        switch self {
        case .none: return "none"
        case .single: return "single"
        case .multi: return "multi"
        }
    }
}

/// The editor "focus" target (what the user is currently editing).
enum EditorFocusTarget: String, CaseIterable, Hashable, Sendable {
    case widget
    case smartPhotoRoot
    case smartPhotoContainerSuite
    case smartPhotoAlbum
    case smartPhotoPreviewStrip
    case smartPhotoCropEditor

    var isSmartPhotoRelated: Bool {
        switch self {
        case .smartPhotoRoot, .smartPhotoContainerSuite, .smartPhotoAlbum, .smartPhotoPreviewStrip, .smartPhotoCropEditor:
            return true
        default:
            return false
        }
    }

    var debugLabel: String { rawValue }
}

/// A compact snapshot of focus + selection state.
struct EditorFocusSnapshot: Hashable, Sendable {
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    static let widgetDefault = EditorFocusSnapshot(selection: .none, focus: .widget)
}
