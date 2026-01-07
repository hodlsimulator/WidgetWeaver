//
//  EditorSelectionDescriptor.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation

/// Whether the current selection is homogeneous (same kind of thing) or mixed.
enum EditorSelectionHomogeneity: String, CaseIterable, Hashable, Sendable {
    case homogeneous
    case mixed

    var label: String {
        switch self {
        case .homogeneous: return "homogeneous"
        case .mixed: return "mixed"
        }
    }
}

/// Whether the selection is related to albums/photos.
enum EditorAlbumSelectionSpecificity: String, CaseIterable, Hashable, Sendable {
    case none
    case albumContainer
    case albumPhotoItem
    case mixed

    var label: String {
        switch self {
        case .none: return "none"
        case .albumContainer: return "albumContainer"
        case .albumPhotoItem: return "albumPhotoItem"
        case .mixed: return "mixed"
        }
    }
}

/// Derived descriptor used for tool eligibility decisions.
struct EditorSelectionDescriptor: Hashable, Sendable {
    var kind: EditorSelectionKind
    var homogeneity: EditorSelectionHomogeneity
    var albumSpecificity: EditorAlbumSelectionSpecificity

    var cardinalityLabel: String { kind.cardinalityLabel }
    var homogeneityLabel: String { homogeneity.label }
    var albumSpecificityLabel: String { albumSpecificity.label }

    static func describe(selection: EditorSelectionKind, focus: EditorFocusTarget) -> EditorSelectionDescriptor {
        let derivedKind: EditorSelectionKind = {
            switch selection {
            case .none:
                switch focus {
                case .widget: return .none
                default: return .single
                }
            default:
                return selection
            }
        }()

        let homogeneity: EditorSelectionHomogeneity = (derivedKind == .multi) ? .mixed : .homogeneous

        let albumSpecificity: EditorAlbumSelectionSpecificity = {
            switch focus {
            case .albumContainer:
                return .albumContainer
            case .albumPhoto:
                return .albumPhotoItem
            default:
                return .none
            }
        }()

        return EditorSelectionDescriptor(kind: derivedKind, homogeneity: homogeneity, albumSpecificity: albumSpecificity)
    }
}
