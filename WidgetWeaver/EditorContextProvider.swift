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
#if DEBUG
        let (normalisedFocus, normalisationDiagnostics) = EditorFocusSnapshotNormaliser.normaliseWithDiagnostics(focusSnapshot)
#else
        let normalisedFocus = EditorFocusSnapshotNormaliser.normalise(focusSnapshot)
#endif

        let context = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            originFocus: focusSnapshot,
            fallbackFocus: normalisedFocus,
            photoLibraryAccess: photoLibraryAccess
        )

#if DEBUG
        EditorFocusSnapshotNormaliserDiagnostics.maybeLogOriginBackedInference(
            originSnapshot: focusSnapshot,
            normalisedSnapshot: normalisedFocus,
            diagnostics: normalisationDiagnostics
        )

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
    struct Diagnostics: Hashable, Sendable {
        var didClampSelectionCount: Bool
        var didInferSelectionCount: Bool
        var didAdjustSelectionKindToMatchCount: Bool
        var didInferSelectionComposition: Bool

        init(
            didClampSelectionCount: Bool = false,
            didInferSelectionCount: Bool = false,
            didAdjustSelectionKindToMatchCount: Bool = false,
            didInferSelectionComposition: Bool = false
        ) {
            self.didClampSelectionCount = didClampSelectionCount
            self.didInferSelectionCount = didInferSelectionCount
            self.didAdjustSelectionKindToMatchCount = didAdjustSelectionKindToMatchCount
            self.didInferSelectionComposition = didInferSelectionComposition
        }

        var didInferAnySelectionMetadata: Bool {
            didInferSelectionCount || didInferSelectionComposition
        }
    }

    static func normalise(_ snapshot: EditorFocusSnapshot) -> EditorFocusSnapshot {
        normaliseWithDiagnostics(snapshot).snapshot
    }

    static func normaliseWithDiagnostics(_ snapshot: EditorFocusSnapshot) -> (snapshot: EditorFocusSnapshot, diagnostics: Diagnostics) {
        let original = snapshot
        var s = snapshot
        var d = Diagnostics()

        // Clamp explicit counts.
        if let count = s.selectionCount {
            let clamped = max(0, count)
            if clamped != count {
                d.didClampSelectionCount = true
            }
            s.selectionCount = clamped
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

            if original.selectionCount == nil, s.selectionCount != nil {
                d.didInferSelectionCount = true
            }
        }

        // Ensure selection kind and count agree when the count is known.
        if let count = s.selectionCount {
            let before = s.selection

            if count <= 0 {
                s.selection = .none
            } else if count == 1 {
                s.selection = .single
            } else {
                s.selection = .multi
            }

            if before != s.selection {
                d.didAdjustSelectionKindToMatchCount = true
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

            if original.selectionComposition == .unknown, s.selectionComposition != .unknown {
                d.didInferSelectionComposition = true
            }
        }

        return (s, d)
    }
}

#if DEBUG
private enum EditorFocusSnapshotNormaliserDiagnostics {
    static func maybeLogOriginBackedInference(
        originSnapshot: EditorFocusSnapshot,
        normalisedSnapshot: EditorFocusSnapshot,
        diagnostics: EditorFocusSnapshotNormaliser.Diagnostics
    ) {
        guard FeatureFlags.contextAwareEditorToolSuiteEnabled else { return }
        guard diagnostics.didInferAnySelectionMetadata else { return }
        guard expectsOriginBackedSelectionMetadata(originSnapshot: originSnapshot) else { return }

        print(
            """
            ⚠️ [EditorFocusSnapshotNormaliser] inferred selection metadata for a focus that should be origin-backed.
            focus=\(originSnapshot.focus.debugLabel)
            inferredCount=\(diagnostics.didInferSelectionCount) inferredComposition=\(diagnostics.didInferSelectionComposition)
            origin.selection=\(originSnapshot.selection.rawValue) origin.count=\(originSnapshot.selectionCount.map(String.init) ?? "nil") origin.composition=\(debugLabel(for: originSnapshot.selectionComposition))
            normalised.selection=\(normalisedSnapshot.selection.rawValue) normalised.count=\(normalisedSnapshot.selectionCount.map(String.init) ?? "nil") normalised.composition=\(debugLabel(for: normalisedSnapshot.selectionComposition))
            """
        )
    }

    private static func expectsOriginBackedSelectionMetadata(originSnapshot: EditorFocusSnapshot) -> Bool {
        switch originSnapshot.focus {
        case .smartRuleEditor:
            return true
        case .albumContainer(_, let subtype) where subtype == .smart:
            return true
        case .albumPhoto(_, _, let subtype) where subtype == .smart:
            return true
        case .element(let id) where id.hasPrefix("smartPhoto"):
            return true
        case .clock:
            return true
        case .widget:
            // Multi-selection should be written from selection set origins with explicit count + composition.
            return originSnapshot.selection == .multi
        case .element, .albumContainer, .albumPhoto:
            return false
        }
    }

    private static func debugLabel(for composition: EditorSelectionComposition) -> String {
        switch composition {
        case .unknown:
            return "unknown"
        case .known(let categories):
            if categories.isEmpty { return "none" }
            let parts = categories.map(\.rawValue).sorted().joined(separator: ",")
            return "known(\(parts))"
        }
    }
}

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
