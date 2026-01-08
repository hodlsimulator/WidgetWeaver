//
//  EditorContextEvaluator.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

/// Pure logic helpers used to derive context/capabilities from editor state.
///
/// This file deliberately avoids SwiftUI and any I/O to keep evaluation cheap and testable.
enum EditorContextEvaluator {
    static func selectionKind(selectionCount: Int) -> EditorSelectionKind {
        if selectionCount <= 0 { return .none }
        if selectionCount == 1 { return .single }
        return .multi
    }

    static func evaluate(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        focus: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext {
        let selectionCountHint: Int? = {
            if let explicit = focus.selectionCount {
                return explicit
            }

            switch focus.selection {
            case .none:
                return focus.focus == .widget ? 0 : 1
            case .single:
                return 1
            case .multi:
                return nil
            }
        }()

        let selectionCompositionHint: EditorSelectionComposition = {
            if focus.selectionComposition != .unknown {
                return focus.selectionComposition
            }

            switch selectionCountHint {
            case .some(0):
                return .none
            case .some(1):
                // Coarse typing for single selection when focus provides enough information.
                if let category = focus.focus.impliedSelectionCategory {
                    return .known([category])
                }
                return .unknown
            default:
                return .unknown
            }
        }()

        let symbolConfigured = !draft.symbolName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        let imageConfigured = !draft.imageFileName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty

        let smartPhotoConfigured = (draft.imageSmartPhoto != nil)

        return EditorToolContext(
            template: draft.template,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            selection: focus.selection,
            focus: focus.focus,
            selectionCount: selectionCountHint,
            selectionComposition: selectionCompositionHint,
            photoLibraryAccess: photoLibraryAccess,
            hasSymbolConfigured: symbolConfigured,
            hasImageConfigured: imageConfigured,
            hasSmartPhotoConfigured: smartPhotoConfigured
        )
    }
}
