//
//  ContentView+Model.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import WidgetKit

extension ContentView {

    // MARK: - Derived helpers

    var defaultName: String? {
        guard let defaultSpecID else { return nil }
        return savedSpecs.first(where: { $0.id == defaultSpecID })?.name ?? store.loadDefault().name
    }

    func specDisplayName(_ spec: WidgetSpec) -> String {
        if spec.id == defaultSpecID {
            return "\(spec.name) (Default)"
        }
        return spec.name
    }

    var hasUnsavedChanges: Bool {
        guard let saved = store.load(id: selectedSpecID) else { return false }
        let draft = draftSpec(id: selectedSpecID)
        return comparableSpec(draft) != comparableSpec(saved)
    }

    private func comparableSpec(_ spec: WidgetSpec) -> WidgetSpec {
        var s = spec.normalised()
        s.updatedAt = Date(timeIntervalSince1970: 0)
        return s
    }

    // MARK: - Model glue

    func bootstrap() {
        refreshSavedSpecs(preservingSelection: false)
        loadSelected()
    }

    func refreshSavedSpecs(preservingSelection: Bool = true) {
        let specs = store
            .loadAll()
            .sorted { $0.updatedAt > $1.updatedAt }

        savedSpecs = specs
        defaultSpecID = store.defaultSpecID()

        if preservingSelection, specs.contains(where: { $0.id == selectedSpecID }) {
            return
        }

        let fallback = store.loadDefault()
        selectedSpecID = defaultSpecID ?? fallback.id
    }

    func applySpec(_ spec: WidgetSpec) {
        let n = spec.normalised()

        designName = n.name
        styleDraft = StyleDraft(from: n.style)
        actionBarDraft = ActionBarDraft(from: n.actionBar)
        remindersDraft = (n.remindersConfig ?? .default).normalised()
        lastSavedAt = n.updatedAt

        if n.matchedSet != nil {
            matchedSetEnabled = true

            let smallFlat = n.resolved(for: .systemSmall)
            let mediumFlat = n.resolved(for: .systemMedium)
            let largeFlat = n.resolved(for: .systemLarge)

            matchedDrafts = MatchedDrafts(
                small: FamilyDraft(from: smallFlat),
                medium: FamilyDraft(from: mediumFlat),
                large: FamilyDraft(from: largeFlat)
            )

            baseDraft = matchedDrafts.medium
        } else {
            matchedSetEnabled = false

            baseDraft = FamilyDraft(from: n)
            matchedDrafts = MatchedDrafts(small: baseDraft, medium: baseDraft, large: baseDraft)
        }

        applyPhotoTemplateDefaultsIfNeeded(spec: n)

        if matchedSetEnabled {
            // Matched sets can place the clock template in only one family.
            // Ensure the editor opens on a clock-bearing family so focus routing
            // (D1) can immediately enter `.clock` focus.
            let clockFamily: WidgetFamily? = {
                if matchedDrafts.small.template == .clockIcon { return .systemSmall }
                if matchedDrafts.medium.template == .clockIcon { return .systemMedium }
                if matchedDrafts.large.template == .clockIcon { return .systemLarge }
                return nil
            }()

            if let clockFamily {
                let currentFamilyUsesClock: Bool = {
                    switch previewFamily {
                    case .systemSmall: return matchedDrafts.small.template == .clockIcon
                    case .systemMedium: return matchedDrafts.medium.template == .clockIcon
                    case .systemLarge: return matchedDrafts.large.template == .clockIcon
                    default: return false
                    }
                }()

                if !currentFamilyUsesClock {
                    previewFamily = clockFamily
                }
            }
        }

        // Route focus when loading a design so the tool suite is correctly gated.
        //
        // Clock templates have a specialised, element-less editing surface and should
        // enter `.clock` focus immediately to avoid surfacing unrelated tools.
        if currentFamilyDraft().template == .clockIcon {
            editorFocusSnapshot = .clockFocus()
        } else {
            editorFocusSnapshot = .widgetDefault
        }
    }



    private func applyPhotoTemplateDefaultsIfNeeded(spec: WidgetSpec) {
        let trimmedName = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)

        let isFramedPhotoTemplate = spec.layout.template == .poster
            && spec.layout.posterOverlayMode == .none
            && trimmedName == "Photo (Framed)"

        guard isFramedPhotoTemplate else { return }

        func apply(to draft: inout FamilyDraft) {
            guard draft.template == .poster else { return }

            let hasImage = !draft.imageFileName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty

            guard !hasImage else { return }

            // Default to a framed/matte look by using the existing Image Content Mode control.
            // The poster renderer treats `.fit` as the framed/matte variant.
            draft.imageContentMode = .fit
        }

        if matchedSetEnabled {
            var small = matchedDrafts.small
            var medium = matchedDrafts.medium
            var large = matchedDrafts.large

            apply(to: &small)
            apply(to: &medium)
            apply(to: &large)

            matchedDrafts = MatchedDrafts(small: small, medium: medium, large: large)
            baseDraft = matchedDrafts.medium
        } else {
            var draft = baseDraft
            apply(to: &draft)
            baseDraft = draft
            matchedDrafts = MatchedDrafts(small: draft, medium: draft, large: draft)
        }
    }

    func draftSpec(id: UUID) -> WidgetSpec {
        let trimmedName = designName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "WidgetWeaver" : trimmedName

        let style = styleDraft.toStyleSpec()
        let updatedAt = lastSavedAt ?? Date()

        let usesRemindersTemplate: Bool = {
            if matchedSetEnabled {
                return matchedDrafts.small.template == .reminders
                || matchedDrafts.medium.template == .reminders
                || matchedDrafts.large.template == .reminders
            }
            return baseDraft.template == .reminders
        }()

        let usesClockTemplate: Bool = {
            if matchedSetEnabled {
                return matchedDrafts.small.template == .clockIcon
                || matchedDrafts.medium.template == .clockIcon
                || matchedDrafts.large.template == .clockIcon
            }
            return baseDraft.template == .clockIcon
        }()

        func clockThemeRawForSpec() -> String {
            if matchedSetEnabled {
                let current = currentFamilyDraft()
                if current.template == .clockIcon {
                    return current.clockThemeRaw
                }

                if matchedDrafts.medium.template == .clockIcon { return matchedDrafts.medium.clockThemeRaw }
                if matchedDrafts.small.template == .clockIcon { return matchedDrafts.small.clockThemeRaw }
                if matchedDrafts.large.template == .clockIcon { return matchedDrafts.large.clockThemeRaw }

                return WidgetWeaverClockDesignConfig.defaultTheme
            }
            return baseDraft.clockThemeRaw
        }

        func clockFaceRawForSpec() -> String {
            if matchedSetEnabled {
                let current = currentFamilyDraft()
                if current.template == .clockIcon {
                    return WidgetWeaverClockFaceToken.canonical(from: current.clockFaceRaw).rawValue
                }

                if matchedDrafts.medium.template == .clockIcon {
                    return WidgetWeaverClockFaceToken.canonical(from: matchedDrafts.medium.clockFaceRaw).rawValue
                }
                if matchedDrafts.small.template == .clockIcon {
                    return WidgetWeaverClockFaceToken.canonical(from: matchedDrafts.small.clockFaceRaw).rawValue
                }
                if matchedDrafts.large.template == .clockIcon {
                    return WidgetWeaverClockFaceToken.canonical(from: matchedDrafts.large.clockFaceRaw).rawValue
                }

                return WidgetWeaverClockDesignConfig.defaultFace
            }
            return WidgetWeaverClockFaceToken.canonical(from: baseDraft.clockFaceRaw).rawValue
        }

        func overridePrimaryTextForSpecialTemplates(_ spec: inout WidgetSpec, source: FamilyDraft) {
            let trimmedPrimary = source.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)

            switch spec.layout.template {
            case .weather, .nextUpCalendar, .reminders, .clockIcon:
                spec.primaryText = trimmedPrimary
            default:
                break
            }
        }

        func overridePrimaryTextForSpecialTemplates(_ variant: inout WidgetSpecVariant, source: FamilyDraft) {
            let trimmedPrimary = source.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)

            switch variant.layout.template {
            case .weather, .nextUpCalendar, .reminders, .clockIcon:
                variant.primaryText = trimmedPrimary
            default:
                break
            }
        }

        if matchedSetEnabled {
            let base = matchedDrafts.medium

            var baseSpec = base.toFlatSpec(
                id: id,
                name: finalName,
                style: style,
                updatedAt: updatedAt
            )
            overridePrimaryTextForSpecialTemplates(&baseSpec, source: base)

            var smallVariant = matchedDrafts.small.toVariantSpec()
            var largeVariant = matchedDrafts.large.toVariantSpec()

            overridePrimaryTextForSpecialTemplates(&smallVariant, source: matchedDrafts.small)
            overridePrimaryTextForSpecialTemplates(&largeVariant, source: matchedDrafts.large)

            let matched = WidgetSpecMatchedSet(
                small: smallVariant,
                medium: nil,
                large: largeVariant
            )

            var out = baseSpec
            out.actionBar = actionBarDraft.toActionBarSpec()
            out.matchedSet = matched
            out.remindersConfig = usesRemindersTemplate ? remindersDraft.normalised() : nil
            out.clockConfig = usesClockTemplate ? WidgetWeaverClockDesignConfig(theme: clockThemeRawForSpec(), face: clockFaceRawForSpec()) : nil
            return out.normalised()

        } else {
            var out = baseDraft.toFlatSpec(
                id: id,
                name: finalName,
                style: style,
                updatedAt: updatedAt
            )
            overridePrimaryTextForSpecialTemplates(&out, source: baseDraft)

            out.actionBar = actionBarDraft.toActionBarSpec()
            out.remindersConfig = usesRemindersTemplate ? remindersDraft.normalised() : nil
            out.clockConfig = usesClockTemplate ? WidgetWeaverClockDesignConfig(theme: clockThemeRawForSpec(), face: clockFaceRawForSpec()) : nil
            return out.normalised()
        }
    }
}
