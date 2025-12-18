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
        if spec.id == defaultSpecID { return "\(spec.name) (Default)" }
        return spec.name
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

        if matchedSetEnabled {
            let base = matchedDrafts.medium
            let baseSpec = base.toFlatSpec(
                id: id,
                name: finalName,
                style: style,
                updatedAt: lastSavedAt ?? Date()
            )

            let matched = WidgetSpecMatchedSet(
                small: matchedDrafts.small.toVariantSpec(),
                medium: nil,
                large: matchedDrafts.large.toVariantSpec()
            )

            var out = baseSpec
            out.matchedSet = matched
            return out.normalised()
        } else {
            let out = baseDraft.toFlatSpec(
                id: id,
                name: finalName,
                style: style,
                updatedAt: lastSavedAt ?? Date()
            )
            return out.normalised()
        }
    }
}
