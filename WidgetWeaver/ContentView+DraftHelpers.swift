//
//  ContentView+DraftHelpers.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import SwiftUI
import WidgetKit

extension ContentView {

    // MARK: - Family selection

    var editingFamily: EditingFamily {
        EditingFamily(widgetFamily: previewFamily) ?? .small
    }

    var selectedFamily: EditingFamily {
        editingFamily
    }

    var editingFamilyLabel: String {
        editingFamily.label
    }

    // MARK: - Draft access

    func currentFamilyDraft() -> FamilyDraft {
        matchedSetEnabled ? matchedDrafts.forFamily(editingFamily) : baseDraft
    }

    func setCurrentFamilyDraft(_ draft: FamilyDraft) {
        if matchedSetEnabled {
            matchedDrafts = matchedDrafts.set(draft, forFamily: editingFamily)
        } else {
            baseDraft = draft
            matchedDrafts = MatchedDrafts(
                small: draft,
                medium: draft,
                large: draft,
                accessoryRectangular: draft,
                accessoryInline: draft
            )
        }
    }

    func setFamilyDraft(_ draft: FamilyDraft, for family: EditingFamily) {
        if matchedSetEnabled {
            matchedDrafts = matchedDrafts.set(draft, forFamily: family)
        } else {
            baseDraft = draft
            matchedDrafts = MatchedDrafts(
                small: draft,
                medium: draft,
                large: draft,
                accessoryRectangular: draft,
                accessoryInline: draft
            )
        }
    }

    func copyCurrentSizeToAllSizes() {
        let draft = currentFamilyDraft()
        matchedDrafts = MatchedDrafts(
            small: draft,
            medium: draft,
            large: draft,
            accessoryRectangular: draft,
            accessoryInline: draft
        )
        matchedSetEnabled = true
    }

    // MARK: - Presets

    func applyStepsStarterPreset(copyToAllSizes: Bool) {
        var draft = currentFamilyDraft()

        draft.template = .classic

        if draft.textPrimary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.textPrimary = "Steps"
        }
        if draft.statusText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.statusText = "Today"
        }

        setCurrentFamilyDraft(draft)

        if copyToAllSizes {
            copyCurrentSizeToAllSizes()
        }
    }

    // MARK: - Matched set toggle

    var matchedSetBinding: Binding<Bool> {
        Binding(
            get: { matchedSetEnabled },
            set: { newValue in
                guard newValue != matchedSetEnabled else { return }

                if newValue {
                    matchedDrafts = MatchedDrafts(
                        small: baseDraft,
                        medium: baseDraft,
                        large: baseDraft,
                        accessoryRectangular: baseDraft,
                        accessoryInline: baseDraft
                    )
                    matchedSetEnabled = true
                } else {
                    baseDraft = matchedDrafts.medium
                    matchedSetEnabled = false
                }
            }
        )
    }

    // MARK: - KeyPath bindings into the current draft

    func binding<Value>(_ keyPath: WritableKeyPath<FamilyDraft, Value>) -> Binding<Value> {
        Binding(
            get: { currentFamilyDraft()[keyPath: keyPath] },
            set: { newValue in
                var draft = currentFamilyDraft()
                draft[keyPath: keyPath] = newValue
                setCurrentFamilyDraft(draft)
            }
        )
    }

    // MARK: - Editor tooling integration

    var editorToolContext: EditorToolContext {
        let draft = currentFamilyDraft()

        let hasSymbolConfigured = !draft.symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasImageConfigured = !draft.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSmartPhotoConfigured = (draft.imageSmartPhoto != nil)

        return EditorToolContext(
            template: draft.template,
            isProUnlocked: proManager.isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            selection: editorFocusSnapshot.selection,
            focus: editorFocusSnapshot.focus,
            photoLibraryAccess: EditorPhotoLibraryAccess.current(),
            hasSymbolConfigured: hasSymbolConfigured,
            hasImageConfigured: hasImageConfigured,
            hasSmartPhotoConfigured: hasSmartPhotoConfigured,
            albumSubtype: editorFocusSnapshot.focus.albumSubtype
        )
    }

    var editorVisibleToolIDs: [EditorToolID] {
        let selectionDescriptor = EditorSelectionDescriptor.describe(
            selection: editorToolContext.selection,
            focus: editorToolContext.focus
        )
        return EditorToolRegistry.visibleToolIDs(
            context: editorToolContext,
            selectionDescriptor: selectionDescriptor
        )
    }
}
