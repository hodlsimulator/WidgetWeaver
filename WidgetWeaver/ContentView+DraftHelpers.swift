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

    // MARK: - Draft access

    func currentFamilyDraft() -> FamilyDraft {
        if matchedSetEnabled {
            return matchedDrafts.forFamily(editingFamily)
        } else {
            return baseDraft
        }
    }

    func setCurrentFamilyDraft(_ draft: FamilyDraft) {
        if matchedSetEnabled {
            matchedDrafts.set(draft, forFamily: editingFamily)
        } else {
            baseDraft = draft
        }
    }

    func setFamilyDraft(_ family: WidgetFamily, _ draft: FamilyDraft) {
        if matchedSetEnabled {
            matchedDrafts.set(draft, forFamily: EditingFamily(family))
        } else {
            baseDraft = draft
        }
    }

    func setFamilyDraft(_ pair: (WidgetFamily, FamilyDraft)) {
        setFamilyDraft(pair.0, pair.1)
    }

    // MARK: - Bindings

    func binding<T>(_ keyPath: WritableKeyPath<FamilyDraft, T>) -> Binding<T> {
        Binding(
            get: { currentFamilyDraft()[keyPath: keyPath] },
            set: { newValue in
                var d = currentFamilyDraft()
                d[keyPath: keyPath] = newValue
                setCurrentFamilyDraft(d)
            }
        )
    }

    // MARK: - Matched set helpers

    var matchedSetBinding: Binding<Bool> {
        Binding(
            get: { matchedSetEnabled },
            set: { newValue in
                if newValue == matchedSetEnabled { return }

                if newValue {
                    let seed = baseDraft
                    matchedDrafts = MatchedDrafts(small: seed, medium: seed, large: seed)
                    matchedSetGeneratedAt = Date()
                    matchedSetEnabled = true
                } else {
                    baseDraft = matchedDrafts.medium
                    matchedSetEnabled = false
                    selectedFamily = .systemMedium
                }
            }
        )
    }

    func copyCurrentSizeToAllSizes() {
        guard matchedSetEnabled else { return }
        let source = currentFamilyDraft()
        matchedDrafts = MatchedDrafts(small: source, medium: source, large: source)
        matchedSetGeneratedAt = Date()
    }

    // MARK: - Labels / presets

    var editingFamilyLabel: String {
        switch editingFamily {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    func applyStepsStarterPreset() {
        var d = currentFamilyDraft()
        d.template = .standard
        d.primaryText = "__steps"
        if d.secondaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            d.secondaryText = "Today"
        }
        setCurrentFamilyDraft(d)
    }

    // MARK: - Tool context

    var editorToolContext: EditorToolContext {
        let draft = currentFamilyDraft()
        let focus = editorFocusSnapshot.focus
        let selection = editorFocusSnapshot.selection

        let hasSymbolConfigured = draft.symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let hasSmartPhotoConfigured = (draft.imageSmartPhoto != nil)
        let hasImageConfigured = hasSmartPhotoConfigured || draft.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        let photoAccess = EditorPhotoLibraryAccess.current()

        return EditorToolContext(
            template: draft.template,
            isProUnlocked: isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            selection: selection,
            focus: focus,
            hasSymbolConfigured: hasSymbolConfigured,
            hasImageConfigured: hasImageConfigured,
            hasSmartPhotoConfigured: hasSmartPhotoConfigured,
            photoLibraryAccess: photoAccess,
            albumSubtype: focus.albumSubtype
        )
    }

    var editorVisibleToolIDs: [EditorToolID] {
        EditorToolRegistry.visibleTools(for: editorToolContext)
    }
}
