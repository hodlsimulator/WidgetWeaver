//
//  ContentView+DraftHelpers.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI

extension ContentViewModel {
    var editorVisibleToolIDs: [EditorToolID] {
        editorVisibleToolIDs(
            selectionKind: currentToolSelectionKind(),
            focusTarget: currentEditorFocusTarget()
        )
    }

    func editorVisibleToolIDs(
        selectionKind: EditorSelectionKind,
        focusTarget: EditorFocusTarget
    ) -> [EditorToolID] {
        let photoLibraryAccess = EditorPhotoLibraryAccess.current()

        let editorToolContext = EditorContextEvaluator.evaluate(
            draft: currentDraft,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            focus: EditorFocusSnapshot(selection: selectionKind, focus: focusTarget),
            photoLibraryAccess: photoLibraryAccess
        )

        if FeatureFlags.editorContextAwareToolSuiteEnabled {
            // Context-aware suite (new).
            return EditorToolRegistry.visibleTools(for: editorToolContext).map(\.id)
        }

        // Legacy tool visibility rules (old).
        if focusTarget.isSmartPhotoRelated {
            return EditorToolRegistry.smartPhotoTools().map(\.id)
        }

        return EditorToolRegistry.defaultTools().map(\.id)
    }

    func editorToolIDsForTargetDraft(
        _ draft: FamilyDraft,
        selectionKind: EditorSelectionKind = .none,
        focusTarget: EditorFocusTarget = .widget
    ) -> [EditorToolID] {
        let photoLibraryAccess = EditorPhotoLibraryAccess.current()

        let editorToolContext = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            focus: EditorFocusSnapshot(selection: selectionKind, focus: focusTarget),
            photoLibraryAccess: photoLibraryAccess
        )

        return EditorToolRegistry.visibleTools(for: editorToolContext).map(\.id)
    }
}
