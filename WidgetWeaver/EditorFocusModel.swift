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

extension EditorSelectionKind {
    var cardinalityLabel: String {
        switch self {
        case .none: return "none"
        case .single: return "single"
        case .multi: return "multi"
        }
    }
}

enum EditorFocusTarget: String, CaseIterable, Hashable, Sendable {
    case widget
    case element
    case background
    case smartPhotoTarget
    case smartPhotoContainerSuite
    case smartRules
    case albumShuffle
    case importReview
}

/// The permission state relevant to editor features that need Photos access.
enum EditorPhotoLibraryAccess: String, CaseIterable, Hashable, Sendable {
    case unknown
    case denied
    case authorised
}

extension EditorPhotoLibraryAccess {
    var allowsReading: Bool {
        switch self {
        case .authorised:
            return true
        case .unknown, .denied:
            return false
        }
    }
}

/// A compact snapshot of focus + selection state.
struct EditorFocusSnapshot: Hashable, Sendable {
    var selection: EditorSelectionKind
    var focus: EditorFocusTarget

    static let widgetDefault = EditorFocusSnapshot(selection: .none, focus: .widget)
}

extension EditorFocusTarget {
    var debugLabel: String {
        rawValue
    }
}
