//
//  EditorContextProvider.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import Foundation

protocol EditorContextProviding {
    func makeContext(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        focusSnapshot: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext

    func visibleToolIDs(for context: EditorToolContext) -> [EditorToolID]
}

struct EditorDefaultContextProvider: EditorContextProviding {
    private let normaliser = EditorFocusSnapshotNormaliser()

    func makeContext(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        focusSnapshot: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext {
        let normalisedFocus = normaliser.normalise(snapshot: focusSnapshot)

        let context = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            focus: normalisedFocus,
            photoLibraryAccess: photoLibraryAccess
        )

        EditorContextProviderDiagnostics.maybeLogUnknownSelectionComposition(
            focusSnapshot: normalisedFocus,
            context: context
        )

        return context
    }

    func visibleToolIDs(for context: EditorToolContext) -> [EditorToolID] {
        if FeatureFlags.contextAwareEditorToolSuiteEnabled {
            return EditorToolRegistry.visibleTools(for: context)
        }

        return EditorToolRegistry.legacyVisibleTools(for: context)
    }
}

enum EditorContextProviderDiagnostics {
    static func maybeLogUnknownSelectionComposition(
        focusSnapshot: EditorFocusSnapshot,
        context: EditorToolContext
    ) {
#if DEBUG
        guard FeatureFlags.contextAwareEditorToolSuiteEnabled else { return }

        guard context.selection != .none else { return }
        guard context.selectionComposition == .unknown else { return }

        // Multi-selection in widget focus commonly lacks a typed selection model.
        // If an exact count is known, log so missing composition plumbing is visible.
        if context.selection == .multi, context.focus == .widget, context.selectionCount == nil {
            return
        }

        print(
            "⚠️ [EditorContextProvider] selectionComposition remained .unknown in stable selection: " +
            "selection=\(context.selection.debugLabel) " +
            "count=\(context.selectionCount?.description ?? "nil") " +
            "focus=\(context.focus.debugLabel) " +
            "snapshotComposition=\(focusSnapshot.selectionComposition.debugLabel)"
        )
#endif
    }
}
//
//  EditorContextProvider.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation

protocol EditorContextProviding {
    func makeContext(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        focusSnapshot: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext

    func visibleToolIDs(for context: EditorToolContext) -> [EditorToolID]
}

struct EditorDefaultContextProvider: EditorContextProviding {
    private let normaliser = EditorFocusSnapshotNormaliser()

    func makeContext(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        focusSnapshot: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext {
        let normalisedFocus = normaliser.normalise(snapshot: focusSnapshot)

        let context = EditorContextEvaluator.evaluate(
            draft: draft,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            focus: normalisedFocus,
            photoLibraryAccess: photoLibraryAccess
        )

        EditorContextProviderDiagnostics.maybeLogUnknownSelectionComposition(
            focusSnapshot: normalisedFocus,
            context: context
        )

        return context
    }

    func visibleToolIDs(for context: EditorToolContext) -> [EditorToolID] {
        if FeatureFlags.contextAwareEditorToolSuiteEnabled {
            return EditorToolRegistry.visibleTools(for: context)
        }

        return EditorToolRegistry.legacyVisibleTools(for: context)
    }
}

enum EditorContextProviderDiagnostics {
    static func maybeLogUnknownSelectionComposition(
        focusSnapshot: EditorFocusSnapshot,
        context: EditorToolContext
    ) {
#if DEBUG
        guard FeatureFlags.contextAwareEditorToolSuiteEnabled else { return }

        guard context.selection != .none else { return }
        guard context.selectionComposition == .unknown else { return }

        // Multi-selection in widget focus commonly lacks a typed selection model.
        // If an exact count is known, log so missing composition plumbing is visible.
        if context.selection == .multi, context.focus == .widget, context.selectionCount == nil {
            return
        }

        print(
            "⚠️ [EditorContextProvider] selectionComposition remained .unknown in stable selection: " +
            "selection=\(context.selection.debugLabel) " +
            "count=\(context.selectionCount?.description ?? "nil") " +
            "focus=\(context.focus.debugLabel) " +
            "snapshotComposition=\(focusSnapshot.selectionComposition.debugLabel)"
        )
#endif
    }
}
