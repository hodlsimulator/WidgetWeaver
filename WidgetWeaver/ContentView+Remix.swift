//
//  ContentView+Remix.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import SwiftUI
import WidgetKit

extension ContentView {

    private var remixVariantCount: Int { 12 }

    var remixToolbarButton: some View {
        Button {
            presentRemixSheet()
        } label: {
            Image(systemName: "wand.and.stars")
        }
        .accessibilityLabel("Remix")
    }

    func presentRemixSheet() {
        remixVariants = WidgetWeaverRemixEngine.generateVariants(from: remixBaseSpec(), count: remixVariantCount)
        activeSheet = .remix
    }

    func remixAgain() {
        remixVariants = WidgetWeaverRemixEngine.generateVariants(from: remixBaseSpec(), count: remixVariantCount)
    }

    func applyRemixVariant(_ variant: WidgetSpec) {
        // Text is identical by construction; applying the variant is safe.
        styleDraft = StyleDraft(from: variant.style)

        var d = currentFamilyDraft()
        d.apply(flatSpec: variant)
        setCurrentFamilyDraft(d)

        saveStatusMessage = "Applied remix (draft only)."
        activeSheet = nil
    }

    private func remixBaseSpec() -> WidgetSpec {
        let trimmedName = designName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "WidgetWeaver" : trimmedName

        let style = styleDraft.toStyleSpec()

        var spec = currentFamilyDraft().toFlatSpec(
            id: selectedSpecID,
            name: finalName,
            style: style,
            updatedAt: lastSavedAt ?? Date()
        ).normalised()

        spec.actionBar = actionBarDraft.toActionBarSpec()
        return spec
    }
}
