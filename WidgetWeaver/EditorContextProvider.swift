//
//  EditorContextProvider.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import Foundation

/// Small abstraction over how `EditorToolContext` is derived from editor state.
///
/// This keeps SwiftUI surfaces from re-deriving context logic independently and
/// enables deterministic testing of context derivation.
protocol EditorContextProviding {
    func makeContext(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        focusSnapshot: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext
}

/// Default provider used by the editor UI.
struct EditorDefaultContextProvider: EditorContextProviding {
    init() {}

    func makeContext(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        focusSnapshot: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext {
        let normalisedFocus = EditorFocusSnapshotNormaliser.normalise(focusSnapshot)

        let context = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            focus: normalisedFocus,
            photoLibraryAccess: photoLibraryAccess
        )

#if DEBUG
        EditorContextProviderDiagnostics.maybeLogUnknownSelectionComposition(
            context: context,
            focusSnapshot: normalisedFocus
        )
#endif

        return context
    }
}

/// Normalises focus snapshots so selection signals become consistent and explicit for stable editor states.
///
/// Goals:
/// - ensure `selection` matches `selectionCount` when a count is known
/// - ensure `.none` selections are treated as `.single` when a non-widget focus target exists
/// - reduce `.unknown` selection composition for single selection states where the focus implies it
enum EditorFocusSnapshotNormaliser {
    static func normalise(_ snapshot: EditorFocusSnapshot) -> EditorFocusSnapshot {
        var s = snapshot

        // Clamp explicit counts.
        if let count = s.selectionCount {
            s.selectionCount = max(0, count)
        }

        // Derive missing count hints for stable states.
        if s.selectionCount == nil {
            switch s.selection {
            case .none:
                s.selectionCount = (s.focus == .widget) ? 0 : 1
            case .single:
                s.selectionCount = 1
            case .multi:
                // Multi-selection exists, count is unknown.
                s.selectionCount = nil
            }
        }

        // Ensure selection kind and count agree when the count is known.
        if let count = s.selectionCount {
            if count <= 0 {
                s.selection = .none
            } else if count == 1 {
                s.selection = .single
            } else {
                s.selection = .multi
            }
        } else {
            // Focus is treated as a stronger signal than an empty selection.
            if s.selection == .none, s.focus != .widget {
                s.selection = .single
            }
        }

        // Resolve composition for single / empty selections where focus implies a category.
        if s.selectionComposition == .unknown {
            if let count = s.selectionCount {
                if count <= 0 {
                    s.selectionComposition = .none
                } else if count == 1, let category = s.focus.impliedSelectionCategory {
                    s.selectionComposition = .known([category])
                }
            } else if s.selection == .single, let category = s.focus.impliedSelectionCategory {
                s.selectionComposition = .known([category])
            }
        }

        return s
    }
}

#if DEBUG
enum EditorContextProviderDiagnostics {
    static func maybeLogUnknownSelectionComposition(
        context: EditorToolContext,
        focusSnapshot: EditorFocusSnapshot
    ) {
        guard FeatureFlags.contextAwareEditorToolSuiteEnabled else { return }
        guard context.selection != .none else { return }
        guard context.selectionComposition == .unknown else { return }

        // Multi-selection in widget focus commonly lacks a typed selection model.
        if context.selection == .multi, context.focus == .widget {
            return
        }

        print(
            """
            ⚠️ [EditorContextProvider] selectionComposition is .unknown for a stable non-empty selection.
            selection=\(context.selection.rawValue) count=\(context.selectionCount.map(String.init) ?? "nil")
            focus=\(context.focus.debugLabel)
            focusSnapshot.selection=\(focusSnapshot.selection.rawValue) focusSnapshot.count=\(focusSnapshot.selectionCount.map(String.init) ?? "nil")
            """
        )
    }
}
#endif
