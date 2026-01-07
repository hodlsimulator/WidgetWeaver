//
//  EditorSelectionDescriptor.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation

// MARK: - Selection modelling helpers

/// Whether the current selection is homogeneous (all of one type) vs mixed.
enum EditorSelectionHomogeneity: String, CaseIterable, Hashable, Sendable {
    case homogeneous
    case mixed
}

/// Rough classification of whether the selection refers to an album container, an item in an album, or not album-related.
enum EditorAlbumSelectionSpecificity: String, CaseIterable, Hashable, Sendable {
    case nonAlbum
    case albumContainer
    case albumItem
}

/// A richer description of selection state.
///
/// This exists to make selection modelling explicit (including mixed selection) without requiring
/// scattered conditional UI logic.
struct EditorSelectionDescriptor: Hashable, Sendable {
    /// Cardinality of the current selection.
    ///
    /// Note: this may be upgraded from `.none` to `.single` when a concrete focus target exists.
    var kind: EditorSelectionKind

    /// A deterministic minimum count for the current selection.
    ///
    /// For example: `.none` => 0ï¿½ 0, `.single` => 1, `.multi` => 2.
    var minCount: Int

    /// Whether selection is homogeneous (all same type) or mixed.
    var isHomogeneous: Bool

    /// How album-specific the selection is (if applicable).
    var albumSpecificity: EditorAlbumSelectionSpecificity

    static func describe(selection: EditorSelectionKind, focus: EditorFocusTarget) -> EditorSelectionDescriptor {
        // 1) Determine cardinality.
        //
        // - If focus is a concrete, item-like target and selection is `.none`,
        //   treat it as a single-target selection. Focus is considered the stronger signal.
        // - Otherwise, use selection as-is.
        let derivedKind: EditorSelectionKind = {
            switch selection {
            case .none:
                switch focus {
                case .element, .background, .smartPhotoTarget:
                    return .single
                default:
                    return .none
                }
            case .single, .multi:
                return selection
            }
        }()

        let minCount: Int = {
            switch derivedKind {
            case .none: return 0
            case .single: return 1
            case .multi: return 2
            }
        }()

        // 2) Homogeneity + album specificity.
        //
        // The real app can refine this based on concrete selection models.
        // For now, model focus-driven cases:
        let isHomogeneous: Bool = true

        let albumSpecificity: EditorAlbumSelectionSpecificity = {
            switch focus {
            case .albumShuffle:
                return .albumContainer
            case .smartPhotoContainerSuite:
                return .albumContainer
            case .smartPhotoTarget:
                // Smart Photo target may refer to an album item or non-album photo, but keep conservative.
                return .nonAlbum
            default:
                return .nonAlbum
            }
        }()

        return EditorSelectionDescriptor(
            kind: derivedKind,
            minCount: minCount,
            isHomogeneous: isHomogeneous,
            albumSpecificity: albumSpecificity
        )
    }
}

extension EditorSelectionDescriptor {
    var cardinalityLabel: String { kind.cardinalityLabel }

    var homogeneityLabel: String {
        isHomogeneous ? "homogeneous" : "mixed"
    }

    var albumSpecificityLabel: String {
        switch albumSpecificity {
        case .nonAlbum: return "nonAlbum"
        case .albumContainer: return "albumContainer"
        case .albumItem: return "albumItem"
        }
    }
}
