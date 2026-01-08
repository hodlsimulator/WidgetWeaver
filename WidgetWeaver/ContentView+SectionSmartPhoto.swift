//
//  ContentView+SectionSmartPhoto.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI

extension ContentView {
    func smartPhotoSection(focus _: Binding<EditorFocusSnapshot>) -> some View {
        let d = currentFamilyDraft()

        let hasImage = editorToolContext.hasImageConfigured
        let hasSmartPhoto = editorToolContext.hasSmartPhotoConfigured
        let photoAccess = editorToolContext.photoLibraryAccess

        let legacyFamilies: [EditingFamily] = {
            guard matchedSetEnabled else { return [] }

            var out: [EditingFamily] = []

            let small = matchedDrafts.small
            let medium = matchedDrafts.medium
            let large = matchedDrafts.large

            if !small.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, small.imageSmartPhoto == nil {
                out.append(.small)
            }
            if !medium.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, medium.imageSmartPhoto == nil {
                out.append(.medium)
            }
            if !large.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, large.imageSmartPhoto == nil {
                out.append(.large)
            }

            return out
        }()

        let legacyFamiliesLabel = legacyFamilies.map { $0.label }.joined(separator: ", ")

        return Section {
            if !hasImage {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.imageRequiredForSmartPhoto(),
                    isBusy: false
                )
            } else if hasSmartPhoto, let smart = d.imageSmartPhoto {
                Button {
                    Task { await regenerateSmartPhotoRenders() }
                } label: {
                    Label("Regenerate smart renders", systemImage: "arrow.clockwise")
                }
                .disabled(importInProgress)

                Text("Smart Photo: v\(smart.algorithmVersion) • prepared \(smart.preparedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await regenerateSmartPhotoRenders() }
                } label: {
                    Label("Make Smart Photo (per-size renders)", systemImage: "sparkles")
                }
                .disabled(importInProgress)

                Text("Generates per-size crops for Small/Medium/Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("After Smart Photo is created, Smart Photo Framing, Smart Rules, and Album Shuffle will appear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hasSmartPhoto,
               let unavailable = EditorUnavailableState.photosAccessRequiredForAlbumShuffle(photoAccess: photoAccess) {
                EditorUnavailableStateView(
                    state: unavailable,
                    isBusy: importInProgress,
                    onPerformCTA: performEditorUnavailableCTA
                )
            }

            if matchedSetEnabled, !legacyFamilies.isEmpty {
                Button {
                    Task { await upgradeLegacyPhotosInCurrentDesign(maxUpgrades: 3) }
                } label: {
                    Label("Upgrade legacy photos to Smart Photo (\(legacyFamiliesLabel))", systemImage: "sparkles")
                }
                .disabled(importInProgress)

                Text("Upgrades up to 3 legacy image files per tap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Smart Photo")
        }
    }
}
