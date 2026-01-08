//
//  EditorSelectionDescriptor.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation

enum EditorSelectionCategory: String, Hashable, Sendable {
    case nonAlbum
    case albumContainer
    case albumPhotoItem
}

enum EditorSelectionHomogeneity: Hashable, Sendable {
    case homogeneous
    case mixed
}

enum EditorSelectionAlbumSpecificity: Hashable, Sendable {
    case nonAlbum
    case albumContainer
    case albumPhotoItem
    case mixed
}

enum EditorSelectionComposition: Hashable, Sendable {
    case unknown
    case known(Set<EditorSelectionCategory>)

    static var none: EditorSelectionComposition { .known([]) }
}

extension EditorSelectionComposition {
    var debugLabel: String {
        switch self {
        case .unknown:
            return "unknown"
        case .known(let categories):
            if categories.isEmpty {
                return "none"
            }

            let stable = categories
                .map(\.rawValue)
                .sorted()
                .joined(separator: ",")

            return "known(\(stable))"
        }
    }
}

struct EditorSelectionDescriptor: Hashable, Sendable {
    var kind: EditorSelectionKind
    var count: Int
    var homogeneity: EditorSelectionHomogeneity
    var albumSpecificity: EditorSelectionAlbumSpecificity

    static func describe(
        selection: EditorSelectionKind,
        focus: EditorFocusTarget,
        selectionCount: Int? = nil,
        composition: EditorSelectionComposition = .unknown
    ) -> EditorSelectionDescriptor {
        let impliedCategory: EditorSelectionCategory? = {
            switch focus {
            case .widget:
                return nil
            case .clock:
                return .nonAlbum
            case .element:
                return .nonAlbum
            case .albumContainer:
                return .albumContainer
            case .albumPhoto:
                return .albumPhotoItem
            case .smartRuleEditor:
                return .albumContainer
            }
        }()

        let derivedCount: Int = {
            if let explicit = selectionCount {
                return max(0, explicit)
            }

            switch selection {
            case .none:
                // If selection is none but a non-widget focus is present, treat as single.
                if focus != .widget {
                    return 1
                }
                return 0

            case .single:
                return 1

            case .multi:
                // Default heuristic for multi-selection when no count is provided.
                return 2
            }
        }()

        let derivedKind: EditorSelectionKind = {
            switch derivedCount {
            case ...0:
                return .none
            case 1:
                return .single
            default:
                return .multi
            }
        }()

        let derivedComposition: Set<EditorSelectionCategory>? = {
            switch composition {
            case .known(let categories):
                return categories
            case .unknown:
                // Conservative inference for single selection or no selection.
                if derivedKind == .none {
                    return []
                }
                if derivedKind == .single, let implied = impliedCategory {
                    return [implied]
                }
                // Multi-selection composition cannot be inferred reliably here.
                return nil
            }
        }()

        let homogeneity: EditorSelectionHomogeneity = {
            guard let categories = derivedComposition else { return .mixed }
            return categories.count <= 1 ? .homogeneous : .mixed
        }()

        let albumSpecificity: EditorSelectionAlbumSpecificity = {
            guard let categories = derivedComposition else { return .mixed }
            if categories.count != 1 {
                return .mixed
            }
            switch categories.first {
            case .nonAlbum:
                return .nonAlbum
            case .albumContainer:
                return .albumContainer
            case .albumPhotoItem:
                return .albumPhotoItem
            case .none:
                return .mixed
            }
        }()

        return EditorSelectionDescriptor(
            kind: derivedKind,
            count: derivedCount,
            homogeneity: homogeneity,
            albumSpecificity: albumSpecificity
        )
    }
}
