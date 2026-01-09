//
//  EditorContextEvaluator.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

enum EditorContextEvaluator {
    static func evaluate(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        focus: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext {
        evaluate(
            draft: draft,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            originFocus: focus,
            fallbackFocus: focus,
            photoLibraryAccess: photoLibraryAccess
        )
    }

    /// Derives editor tool context from focus snapshots.
    ///
    /// `originFocus` represents the selection origin's explicit data (when available).
    /// `fallbackFocus` is a defensive normalised snapshot used only when origin metadata
    /// is unavailable.
    static func evaluate(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        originFocus: EditorFocusSnapshot,
        fallbackFocus: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext {
        let explicitSelectionCount = originFocus.selectionCount.map { max(0, $0) }
        let fallbackSelectionCount = fallbackFocus.selectionCount.map { max(0, $0) }

        let selectionCountHint: Int? = {
            if let explicitSelectionCount {
                return explicitSelectionCount
            }

            if let fallbackSelectionCount {
                return fallbackSelectionCount
            }

            switch originFocus.selection {
            case .none:
                if originFocus.focus != .widget {
                    return 1
                }
                return 0
            case .single:
                return 1
            case .multi:
                return nil
            }
        }()

        let resolvedSelection: EditorSelectionKind = {
            if let count = selectionCountHint {
                return selectionKind(selectionCount: count)
            }

            // If selection says "none" but a non-widget focus exists, treat as single.
            if originFocus.selection == .none, originFocus.focus != .widget {
                return .single
            }

            return originFocus.selection
        }()

        let explicitComposition = originFocus.selectionComposition

        let selectionCompositionHint: EditorSelectionComposition = {
            if explicitComposition != .unknown {
                return explicitComposition
            }

            if fallbackFocus.selectionComposition != .unknown {
                return fallbackFocus.selectionComposition
            }

            switch resolvedSelection {
            case .none:
                return .none
            case .single:
                if let implied = impliedCategory(from: originFocus.focus) {
                    return .known([implied])
                }
                return .unknown
            case .multi:
                return .unknown
            }
        }()

#if DEBUG
        if resolvedSelection == .multi,
           explicitSelectionCount != nil,
           explicitComposition == .unknown,
           selectionCompositionHint == .unknown {
            print("⚠️ [EditorContextEvaluator] multi-selection has explicit count but unknown composition; supply composition at the selection origin if possible.")
        }
#endif

        let hasSymbolConfigured = !draft.symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImageConfigured = !draft.imageFileName.isEmpty
        let hasSmartPhotoConfigured = draft.imageSmartPhoto != nil

        return EditorToolContext(
            template: draft.template,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            selection: resolvedSelection,
            focus: originFocus.focus,
            selectionCount: selectionCountHint,
            selectionComposition: selectionCompositionHint,
            photoLibraryAccess: photoLibraryAccess,
            hasSymbolConfigured: hasSymbolConfigured,
            hasImageConfigured: hasImageConfigured,
            hasSmartPhotoConfigured: hasSmartPhotoConfigured
        )
    }

    static func selectionKind(selectionCount: Int) -> EditorSelectionKind {
        switch selectionCount {
        case ...0:
            return .none
        case 1:
            return .single
        default:
            return .multi
        }
    }

    static func impliedCategory(from focus: EditorFocusTarget) -> EditorSelectionCategory? {
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
    }
}
