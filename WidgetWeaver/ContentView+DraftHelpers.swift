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
        EditorDefaultContextProvider().makeContext(
            draft: currentFamilyDraft(),
            isProUnlocked: proManager.isProUnlocked,
            matchedSetEnabled: matchedSetEnabled,
            focusSnapshot: editorFocusSnapshot,
            photoLibraryAccess: EditorPhotoLibraryAccess.current()
        )
    }

    /// Ordered tool identifiers that should be visible for the current context.
    var editorVisibleToolIDs: [EditorToolID] {
        _ = editorToolCapabilitiesDidChangeTick

        var tools: [EditorToolID]
        if FeatureFlags.contextAwareEditorToolSuiteEnabled {
            tools = EditorToolRegistry.visibleTools(for: editorToolContext)
        } else {
            tools = EditorToolRegistry.legacyVisibleTools(for: editorToolContext)
        }

        // Poster is still themeable; the Style section hides non-applicable controls for this template.
        return tools
    }

    func setCurrentFamilyDraft(_ newValue: FamilyDraft) {
        var v = newValue

        // If the image has been cleared, also clear any Smart Photo metadata.
        // This keeps the draft state tidy and avoids holding onto file references
        // that are no longer reachable from the spec.
        if v.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            v.imageSmartPhoto = nil
            v.imageFilterToken = .none
            v.imageFilterIntensity = 1.0
        }

        if v.template == .clockIcon {
            let canonical = WidgetWeaverClockDesignConfig(
                theme: v.clockThemeRaw,
                face: v.clockFaceRaw,
                iconDialColourToken: v.clockIconDialColourTokenRaw,
                iconSecondHandColourToken: v.clockIconSecondHandColourTokenRaw
            )
            v.clockThemeRaw = canonical.theme
            v.clockFaceRaw = canonical.face
            v.clockIconDialColourTokenRaw = canonical.iconDialColourToken
            v.clockIconSecondHandColourTokenRaw = canonical.iconSecondHandColourToken
        }

        if matchedSetEnabled {
            matchedDrafts[editingFamily] = v

            if v.template == .clockIcon {
                propagateClockThemeToAllClockDrafts(rawTheme: v.clockThemeRaw)
                propagateClockFaceToAllClockDrafts(rawFace: v.clockFaceRaw)
                propagateClockIconDialColourTokenToAllClockDrafts(rawToken: v.clockIconDialColourTokenRaw)
                propagateClockIconSecondHandColourTokenToAllClockDrafts(rawToken: v.clockIconSecondHandColourTokenRaw)
            }
        } else {
            baseDraft = v

            if v.template == .clockIcon {
                let canonical = WidgetWeaverClockDesignConfig(
                    theme: v.clockThemeRaw,
                    face: v.clockFaceRaw,
                    iconDialColourToken: v.clockIconDialColourTokenRaw
                )
                baseDraft.clockThemeRaw = canonical.theme
                baseDraft.clockFaceRaw = canonical.face
                baseDraft.clockIconDialColourTokenRaw = canonical.iconDialColourToken
            }
        }
    }

    private func propagateClockThemeToAllClockDrafts(rawTheme: String) {
        let canonical = WidgetWeaverClockDesignConfig(theme: rawTheme).theme

        if matchedDrafts.small.template == .clockIcon {
            matchedDrafts.small.clockThemeRaw = canonical
        }
        if matchedDrafts.medium.template == .clockIcon {
            matchedDrafts.medium.clockThemeRaw = canonical
        }
        if matchedDrafts.large.template == .clockIcon {
            matchedDrafts.large.clockThemeRaw = canonical
        }
    }
    
    private func propagateClockIconDialColourTokenToAllClockDrafts(rawToken: String?) {
            let canonical = WidgetWeaverClockIconDialColourToken
                .canonical(from: rawToken)?
                .rawValue

            if matchedDrafts.small.template == .clockIcon {
                matchedDrafts.small.clockIconDialColourTokenRaw = canonical
            }
            if matchedDrafts.medium.template == .clockIcon {
                matchedDrafts.medium.clockIconDialColourTokenRaw = canonical
            }
            if matchedDrafts.large.template == .clockIcon {
                matchedDrafts.large.clockIconDialColourTokenRaw = canonical
            }
        }

    private func propagateClockFaceToAllClockDrafts(rawFace: String) {
        let canonical = WidgetWeaverClockFaceToken.canonical(from: rawFace).rawValue

        if matchedDrafts.small.template == .clockIcon {
            matchedDrafts.small.clockFaceRaw = canonical
        }
        if matchedDrafts.medium.template == .clockIcon {
            matchedDrafts.medium.clockFaceRaw = canonical
        }
        if matchedDrafts.large.template == .clockIcon {
            matchedDrafts.large.clockFaceRaw = canonical
        }
    }
    
    private func propagateClockIconSecondHandColourTokenToAllClockDrafts(rawToken: String?) {
        let canonical = WidgetWeaverClockSecondHandColourToken
            .canonical(from: rawToken)?
            .rawValue

        if matchedDrafts.small.template == .clockIcon {
            matchedDrafts.small.clockIconSecondHandColourTokenRaw = canonical
        }
        if matchedDrafts.medium.template == .clockIcon {
            matchedDrafts.medium.clockIconSecondHandColourTokenRaw = canonical
        }
        if matchedDrafts.large.template == .clockIcon {
            matchedDrafts.large.clockIconSecondHandColourTokenRaw = canonical
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
            if baseDraft.template == .clockIcon {
                let seed = seededNonClockDraft(from: baseDraft)
                matchedDrafts = MatchedDrafts(small: baseDraft, medium: seed, large: seed)
            } else {
                matchedDrafts = MatchedDrafts(small: baseDraft, medium: baseDraft, large: baseDraft)
            }
            matchedSetEnabled = true
        } else {
            let chosen = matchedDrafts[editingFamily]
            baseDraft = chosen.template == .clockIcon ? matchedDrafts.small : chosen
            matchedSetEnabled = false
        }
    }

    private func seededNonClockDraft(from base: FamilyDraft) -> FamilyDraft {
        var d = base

        if d.template == .clockIcon {
            d.template = .classic

            if d.primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                d.primaryText = "Hello"
            }
        }

        return d
    }

    func copyCurrentSizeToAllSizes() {
        guard matchedSetEnabled else { return }
        let d = matchedDrafts[editingFamily]

        if d.template == .clockIcon {
            saveStatusMessage = "Clock templates are Small-only.\nCopy to all sizes is unavailable."
            return
        }

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

        if matchedSetEnabled, copyToAllSizes {
            copyCurrentSizeToAllSizes()
        }

        saveStatusMessage = "Applied Steps starter preset."
    }
}
