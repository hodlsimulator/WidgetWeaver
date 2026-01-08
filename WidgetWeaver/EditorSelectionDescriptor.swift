//
//  EditorSelectionDescriptor.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation

enum EditorSelectionHomogeneity: String, CaseIterable, Hashable, Sendable {
    case homogeneous
    case mixed
}

/// Coarse selection specificity for album-related operations.
///
/// This is intentionally small: tools only need to distinguish between
/// operations that apply to:
/// - non-album content
/// - an album container (album-level operations)
/// - album photo items (per-photo operations)
/// - a mixed selection that crosses these boundaries
enum EditorAlbumSelectionSpecificity: String, CaseIterable, Hashable, Sendable {
    case nonAlbum
    case albumContainer
    case albumPhotoItem
    case mixed
}

/// Broad categories used to describe what is currently selected.
///
/// This intentionally ignores fine-grained element types (text vs image vs symbol).
/// The purpose is to keep album-related tools from surfacing in non-album contexts
/// and to model mixed selections explicitly.
enum EditorSelectionCategory: String, CaseIterable, Hashable, Sendable {
    case nonAlbum
    case albumContainer
    case albumPhotoItem
}

/// Composition of the current selection.
///
/// The selection model can explicitly supply this when the selection is known
/// (e.g. multi-selection in a list). When unknown, eligibility falls back to
/// conservative heuristics based on focus.
enum EditorSelectionComposition: Hashable, Sendable {
    /// No explicit composition information is available.
    case unknown

    /// Composition is known at least at the coarse category level.
    case known(Set<EditorSelectionCategory>)

    static var none: EditorSelectionComposition { .known([]) }
}

extension EditorFocusTarget {
    /// Coarse selection category implied by the focus target.
    ///
    /// This should only be used as a fallback when an explicit selection model
    /// is unavailable.
    var impliedSelectionCategory: EditorSelectionCategory? {
        switch self {
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
    }
}

struct EditorSelectionDescriptor: Hashable, Sendable {
    /// The selection kind, based on the resolved selection count.
    var kind: EditorSelectionKind

    /// Exact selection count when known.
    ///
    /// When no count is supplied for a multi-selection, this falls back to a
    /// conservative default of `2` to ensure “multi” logic is exercised.
    var count: Int

    var homogeneity: EditorSelectionHomogeneity
    var albumSpecificity: EditorAlbumSelectionSpecificity

    static func describe(
        selection: EditorSelectionKind,
        focus: EditorFocusTarget,
        selectionCount: Int? = nil,
        composition: EditorSelectionComposition = .unknown
    ) -> EditorSelectionDescriptor {
        // MARK: Resolve kind + count

        let resolvedCount: Int = {
            if let selectionCount {
                return max(0, selectionCount)
            }

            switch selection {
            case .none:
                return focus == .widget ? 0 : 1
            case .single:
                return 1
            case .multi:
                // Conservative default when no exact multi count is available.
                return 2
            }
        }()

        let resolvedKind: EditorSelectionKind = {
            if selectionCount != nil {
                switch resolvedCount {
                case 0:
                    return .none
                case 1:
                    return .single
                default:
                    return .multi
                }
            }

            // Focus is treated as a stronger signal than “none selection”.
            if selection == .none, focus != .widget {
                return .single
            }

            return selection
        }()

        // MARK: Resolve composition

        let resolvedComposition: EditorSelectionComposition = {
            if composition != .unknown {
                return composition
            }

            switch resolvedKind {
            case .none:
                return .none

            case .single:
                if let category = focus.impliedSelectionCategory {
                    return .known([category])
                }
                return .unknown

            case .multi:
                return .unknown
            }
        }()

        // MARK: Resolve homogeneity + album specificity

        let derivedHomogeneity: EditorSelectionHomogeneity
        let derivedAlbumSpecificity: EditorAlbumSelectionSpecificity

        switch resolvedComposition {
        case .known(let categories):
            if categories.count > 1 {
                derivedHomogeneity = .mixed
                derivedAlbumSpecificity = .mixed
            } else {
                derivedHomogeneity = .homogeneous

                if categories.contains(.albumContainer) {
                    derivedAlbumSpecificity = .albumContainer
                } else if categories.contains(.albumPhotoItem) {
                    derivedAlbumSpecificity = .albumPhotoItem
                } else {
                    // Empty or non-album-only selection composition.
                    derivedAlbumSpecificity = .nonAlbum
                }
            }

        case .unknown:
            // Conservative heuristics when composition is unknown.
            derivedHomogeneity = (resolvedKind == .multi && focus == .widget) ? .mixed : .homogeneous

            switch focus {
            case .albumContainer, .smartRuleEditor:
                derivedAlbumSpecificity = .albumContainer
            case .albumPhoto:
                derivedAlbumSpecificity = .albumPhotoItem
            case .widget:
                derivedAlbumSpecificity = (resolvedKind == .multi) ? .mixed : .nonAlbum
            case .element, .clock:
                derivedAlbumSpecificity = .nonAlbum
            }
        }

        return EditorSelectionDescriptor(
            kind: resolvedKind,
            count: resolvedCount,
            homogeneity: derivedHomogeneity,
            albumSpecificity: derivedAlbumSpecificity
        )
    }
}
