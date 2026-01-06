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
    var editingFamily: EditingFamily {
        EditingFamily(widgetFamily: previewFamily) ?? .small
    }

    var editingFamilyLabel: String {
        editingFamily.label
    }

    func currentFamilyDraft() -> FamilyDraft {
        matchedSetEnabled ? matchedDrafts[editingFamily] : baseDraft
    }

    /// Single source of truth for the editor’s current tool context.
    ///
    /// The context is derived from draft state + entitlements. Views should not attempt
    /// to re-derive these conditions independently.
    var editorToolContext: EditorToolContext {
        let d = currentFamilyDraft()

        let symbolConfigured = !d.symbolName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let imageConfigured = !d.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let smartPhotoConfigured = d.imageSmartPhoto != nil

        return EditorToolContext(
            template: d.template,
            isProUnlocked: proManager.isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            hasSymbolConfigured: symbolConfigured,
            hasImageConfigured: imageConfigured,
            hasSmartPhotoConfigured: smartPhotoConfigured
        )
    }

    /// Ordered tool identifiers that should be visible for the current context.
    var editorVisibleToolIDs: [EditorToolID] {
        EditorToolRegistry.visibleTools(for: editorToolContext)
    }

    func setCurrentFamilyDraft(_ newValue: FamilyDraft) {
        var v = newValue

        // If the image has been cleared, also clear any Smart Photo metadata.
        // This keeps the draft state tidy and avoids holding onto file references
        // that are no longer reachable from the spec.
        if v.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            v.imageSmartPhoto = nil
        }

        if matchedSetEnabled {
            matchedDrafts[editingFamily] = v
        } else {
            baseDraft = v
        }
    }

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

    var matchedSetBinding: Binding<Bool> {
        Binding(
            get: { matchedSetEnabled },
            set: { setMatchedSetEnabled($0) }
        )
    }

    func setMatchedSetEnabled(_ enabled: Bool) {
        guard enabled != matchedSetEnabled else { return }

        if enabled && !proManager.isProUnlocked {
            saveStatusMessage = "Matched sets require WidgetWeaver Pro."
            activeSheet = .pro
            return
        }

        if enabled {
            matchedDrafts = MatchedDrafts(small: baseDraft, medium: baseDraft, large: baseDraft)
            matchedSetEnabled = true
        } else {
            baseDraft = matchedDrafts.medium
            matchedSetEnabled = false
        }
    }

    func copyCurrentSizeToAllSizes() {
        guard matchedSetEnabled else { return }
        let d = matchedDrafts[editingFamily]
        matchedDrafts = MatchedDrafts(small: d, medium: d, large: d)
        saveStatusMessage = "Copied \(editingFamilyLabel) settings to Small/Medium/Large (draft only)."
    }
    
    func applyStepsStarterPreset(copyToAllSizes: Bool) {
        var d = currentFamilyDraft()

        d.primaryText = "{{__steps_today|--|number:0}}"
        d.secondaryText = "Goal {{__steps_goal_today|--|number:0}} • {{__steps_today_fraction|0|percent:0}}"

        d.template = .hero
        d.showsAccentBar = true

        d.symbolName = "figure.walk"
        d.symbolPlacement = .beforeName
        d.symbolSize = 18
        d.symbolWeight = .semibold
        d.symbolRenderingMode = .hierarchical
        d.symbolTint = .accent

        setCurrentFamilyDraft(d)

        if matchedSetEnabled && copyToAllSizes {
            matchedDrafts = MatchedDrafts(small: d, medium: d, large: d)
        }

        styleDraft.accent = .green
        styleDraft.background = .radialGlow

        saveStatusMessage = (matchedSetEnabled && copyToAllSizes)
            ? "Applied Steps preset to Small/Medium/Large (draft only)."
            : "Applied Steps preset (draft only)."
    }
}
