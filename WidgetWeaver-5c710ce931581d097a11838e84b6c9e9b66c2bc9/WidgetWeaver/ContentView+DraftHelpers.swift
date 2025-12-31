//
//  ContentView+DraftHelpers.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

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

    func setCurrentFamilyDraft(_ newValue: FamilyDraft) {
        if matchedSetEnabled {
            matchedDrafts[editingFamily] = newValue
        } else {
            baseDraft = newValue
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
