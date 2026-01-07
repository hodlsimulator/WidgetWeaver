//
//  EditorSelectionDescriptor.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation

// MARK: - Selection descriptor

/// Whether the current selection is homogeneous (all targets are the same content kind) or mixed.
///
/// Mixed selection is represented explicitly so tool filtering stays deterministic even when the
/// editor cannot safely assume a single target type.
enum EditorSelectionHomogeneity: String, CaseIterable, Hashable, Sendable {
    case homogeneous
    case mixed
}

/// Album specificity for the current selection.
///
/// This provides a stable vocabulary for tools that must distinguish between:
/// - album container editing
/// - album photo-item editing
/// - non-album editing
/// - mixed/ambiguous selection
enum EditorAlbumSelectionSpecificity: String, CaseIterable, Hashable, Sendable {
    case nonAlbum
    case albumContainer
    case albumPhotoItem
    case mixed
}

/// A compact, deterministic description of the current selection derived from `selection` + `focus`.
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
    /// The editor does not currently store exact multi-selection counts, so `.multi` is treated as 2.
    var count: Int

    /// Whether the selection is mixed or homogeneous.
    var homogeneity: EditorSelectionHomogeneity

    /// Album specificity for the selection.
    var albumSpecificity: EditorAlbumSelectionSpecificity

    static func describe(selection: EditorSelectionKind, focus: EditorFocusTarget) -> EditorSelectionDescriptor {
        // 1) Determine cardinality.
        //
        // Policy:
        // - If a concrete focus target exists (element/album/clock/smartRuleEditor) and selection is `.none`,
        //   treat it as a single-target selection. Focus is considered the stronger signal.
        // - Otherwise, use selection as-is.
        let derivedKind: EditorSelectionKind = {
            switch selection {
            case .none:
                switch focus {
                case .widget:
                    return .none
                case .clock, .element, .albumContainer, .albumPhoto, .smartRuleEditor:
                    return .single
                }
            case .single:
                return .single
            case .multi:
                return .multi
            }
        }()

        let derivedCount: Int = {
            switch derivedKind {
            case .none:
                return 0
            case .single:
                return 1
            case .multi:
                // The editor does not yet store exact multi-selection counts.
                return 2
            }
        }()

        // 2) Determine homogeneity.
        //
        // Contract:
        // - When selection is `.multi` and focus is `.widget`, the selection is considered mixed/ambiguous.
        // - When selection is `.multi` and a concrete focus target exists, treat as homogeneous for now.
        //   This assumes future multi-selection UX will clear focus to `.widget` when the selection spans
        //   multiple content kinds.
        let derivedHomogeneity: EditorSelectionHomogeneity = {
            guard derivedKind == .multi else { return .homogeneous }
            if case .widget = focus { return .mixed }
            return .homogeneous
        }()

        // 3) Determine album specificity.
        let derivedAlbumSpecificity: EditorAlbumSelectionSpecificity = {
            if derivedHomogeneity == .mixed { return .mixed }

            switch focus {
            case .albumContainer:
                return .albumContainer
            case .albumPhoto:
                return .albumPhotoItem
            case .smartRuleEditor:
                // Rules are a container-level album edit.
                return .albumContainer
            case .widget, .clock, .element:
                return .nonAlbum
            }
        }()

        return EditorSelectionDescriptor(
            kind: derivedKind,
            count: derivedCount,
            homogeneity: derivedHomogeneity,
            albumSpecificity: derivedAlbumSpecificity
        )
    }
}
