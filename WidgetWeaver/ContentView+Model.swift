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

        func overridePrimaryTextForSpecialTemplates(_ spec: inout WidgetSpec, source: FamilyDraft) {
            let trimmedPrimary = source.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)

            switch spec.layout.template {
            case .weather, .nextUpCalendar, .reminders:
                spec.primaryText = trimmedPrimary
            default:
                break
            }
        }

        func overridePrimaryTextForSpecialTemplates(_ variant: inout WidgetSpecVariant, source: FamilyDraft) {
            let trimmedPrimary = source.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)

            switch variant.layout.template {
            case .weather, .nextUpCalendar, .reminders:
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
            return out.normalised()
        }
    }
}
