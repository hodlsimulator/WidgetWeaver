//
//  EditorContextEvaluator.swift
//  WidgetWeaver
//
//  Created by . . on 1/8/26.
//

import Foundation

/// Central evaluation of current editor context.
///
/// This is intentionally “boring”: a single point where draft state + focus/selection
/// snapshots are normalised into an `EditorToolContext` for tooling decisions.
struct EditorContextEvaluator: Sendable {
    func evaluate(
        draft: FamilyDraft,
        isProUnlocked: Bool,
        matchedSetEnabled: Bool,
        originFocus: EditorFocusSnapshot,
        fallbackFocus: EditorFocusSnapshot,
        photoLibraryAccess: EditorPhotoLibraryAccess
    ) -> EditorToolContext {
        let resolvedSelection: EditorSelection = {
            if originFocus.selection != .none {
                return originFocus.selection
            }
            if fallbackFocus.selection != .none {
                return fallbackFocus.selection
            }
            return .none
        }()

        let explicitSelectionCount = originFocus.selectionCount
        let explicitComposition = originFocus.selectionComposition

        let selectionCountHint: Int? = {
            if let explicitSelectionCount {
                return explicitSelectionCount
            }

            if fallbackFocus.selectionCount != nil {
                return fallbackFocus.selectionCount
            }

            switch resolvedSelection {
            case .none:
                return nil
            case .single:
                return 1
            case .multi:
                return 2
            }
        }()

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
        let isRunningUnitTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        if !isRunningUnitTests,
           resolvedSelection == .multi,
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

    private func impliedCategory(from focus: EditorFocusTarget) -> EditorSelectionCategory? {
        switch focus {
        case .albumContainer:
            return .albumContainer
        case .albumPhoto:
            return .albumPhotoItem
        case .smartRuleEditor:
            return .albumContainer
        case .clock:
            return .nonAlbum
        case .element(let id) where id.hasPrefix("smartPhoto"):
            return .albumPhotoItem
        case .widget, .element:
            return nil
        }
    }
}
