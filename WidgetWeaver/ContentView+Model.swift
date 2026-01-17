//
//  ContentView+Model.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import WidgetKit

extension ContentView {
    func loadSelected() {
        let spec = store.load(id: selectedSpecID) ?? WidgetSpec.defaultSpec
        applySpec(spec)
    }

    func applySpec(_ spec: WidgetSpec) {
        let n = spec.normalised()

        selectedSpecID = n.id
        designName = n.name
        styleDraft = StyleDraft(from: n.style)
        actionBarDraft = ActionBarDraft(from: n.actionBar)
        remindersDraft = (n.remindersConfig ?? .default).normalised()

        let familyDraft = FamilyDraft(from: n)

        matchedSetEnabled = n.matchedSet != nil
        if matchedSetEnabled, let set = n.matchedSet {
            let s = FamilyDraft(from: n.resolved(for: .systemSmall))
            let m = FamilyDraft(from: n.resolved(for: .systemMedium))
            let l = FamilyDraft(from: n.resolved(for: .systemLarge))

            matchedDrafts = MatchedDrafts(
                small: s,
                medium: m,
                large: l
            )
            baseDraft = m

            previewFamily = set.lastEditedFamily ?? .systemSmall

        } else {
            baseDraft = familyDraft
            matchedDrafts = MatchedDrafts(
                small: familyDraft,
                medium: familyDraft,
                large: familyDraft
            )
            previewFamily = .systemSmall
        }
    }

    func draftSpec(id: UUID) -> WidgetSpec {
        let usesRemindersTemplate: Bool = {
            if matchedSetEnabled {
                return matchedDrafts.small.template == .reminders
                || matchedDrafts.medium.template == .reminders
                || matchedDrafts.large.template == .reminders
            }
            return baseDraft.template == .reminders
        }()

        func applyAllowEmptyPrimaryTextForSpecialTemplates(_ spec: inout WidgetSpec, source: FamilyDraft) {
            switch spec.layout.template {
            case .nextUpCalendar, .reminders:
                spec.primaryText = source.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                break
            }
        }

        func applyAllowEmptyPrimaryTextForSpecialTemplates(_ variant: inout WidgetSpecVariant, source: FamilyDraft) {
            switch variant.layout.template {
            case .nextUpCalendar, .reminders:
                variant.primaryText = source.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
            default:
                break
            }
        }

        let actionBar = actionBarDraft.toActionBarSpec()

        if matchedSetEnabled {
            let base = matchedDrafts.medium
            var baseSpec = base.toFlatSpec(id: id)
            applyAllowEmptyPrimaryTextForSpecialTemplates(&baseSpec, source: base)

            var smallVariant = matchedDrafts.small.toVariantSpec()
            var largeVariant = matchedDrafts.large.toVariantSpec()

            applyAllowEmptyPrimaryTextForSpecialTemplates(&smallVariant, source: matchedDrafts.small)
            applyAllowEmptyPrimaryTextForSpecialTemplates(&largeVariant, source: matchedDrafts.large)

            var out = baseSpec
            out.matchedSet = WidgetSpecMatchedSet(
                small: smallVariant,
                large: largeVariant,
                lastEditedFamily: previewFamily
            )

            out.actionBar = actionBar
            out.remindersConfig = usesRemindersTemplate ? remindersDraft.normalised() : nil

            return out.normalised()

        } else {
            var out = baseDraft.toFlatSpec(id: id)
            applyAllowEmptyPrimaryTextForSpecialTemplates(&out, source: baseDraft)

            out.actionBar = actionBar
            out.remindersConfig = usesRemindersTemplate ? remindersDraft.normalised() : nil

            return out.normalised()
        }
    }
}
