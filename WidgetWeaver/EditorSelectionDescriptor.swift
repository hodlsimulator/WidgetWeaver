//
//  EditorSelectionDescriptor.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation

enum EditorSelectionCardinality: String, Codable, Hashable {
    case none
    case single
    case multi
}

enum EditorSelectionHomogeneity: String, Codable, Hashable {
    case homogeneous
    case heterogeneous
}

enum EditorAlbumSelectionSpecificity: String, Codable, Hashable {
    case none
    case albumContainer
    case albumPhotoItem
    case mixed
}

struct EditorSelectionDescriptor: Codable, Hashable {

    let cardinality: EditorSelectionCardinality
    let homogeneity: EditorSelectionHomogeneity
    let albumSpecificity: EditorAlbumSelectionSpecificity

    static func describe(selection: EditorSelectionKind, focus: EditorFocusTarget) -> EditorSelectionDescriptor {

        let derivedKind: EditorSelectionCardinality = {
            switch selection {
            case .none:
                switch focus {
                case .widget:
                    return .none
                default:
                    return .single
                }
            case .single:
                return .single
            case .multi:
                return .multi
            }
        }()

        let derivedHomogeneity: EditorSelectionHomogeneity = .homogeneous

        let derivedSpecificity: EditorAlbumSelectionSpecificity = {
            switch focus {
            case .albumContainer(_, _):
                return .albumContainer
            case .albumPhoto(_, _, _):
                return .albumPhotoItem
            case .smartRuleEditor(_):
                return .albumContainer
            default:
                return .none
            }
        }()

        return EditorSelectionDescriptor(
            cardinality: derivedKind,
            homogeneity: derivedHomogeneity,
            albumSpecificity: derivedSpecificity
        )
    }
}

extension EditorSelectionDescriptor {
    var cardinalityLabel: String {
        switch cardinality {
        case .none: return "None"
        case .single: return "Single"
        case .multi: return "Multi"
        }
    }

    var albumSpecificityLabel: String {
        switch albumSpecificity {
        case .none: return "None"
        case .albumContainer: return "Album"
        case .albumPhotoItem: return "Photo"
        case .mixed: return "Mixed"
        }
    }
}
