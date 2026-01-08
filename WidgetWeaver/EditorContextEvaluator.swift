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
        let selectionCountHint: Int? = {
            if let explicit = focus.selectionCount {
                return max(0, explicit)
            }

            switch focus.selection {
            case .none:
                if focus.focus != .widget {
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
            if focus.selection == .none, focus.focus != .widget {
                return .single
            }

            return focus.selection
        }()

        let selectionCompositionHint: EditorSelectionComposition = {
            if focus.selectionComposition != .unknown {
                return focus.selectionComposition
            }

            switch resolvedSelection {
            case .none:
                return .none
            case .single:
                if let implied = impliedCategory(from: focus.focus) {
                    return .known([implied])
                }
                return .unknown
            case .multi:
                return .unknown
            }
        }()

#if DEBUG
        if resolvedSelection == .multi,
           selectionCountHint != nil,
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
            focus: focus.focus,
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
