//
//  ContentView+SectionSmartPhoto.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation
import SwiftUI

extension ContentView {
    func smartPhotoSection(focus _: Binding<EditorFocusSnapshot>) -> some View {
        let d = currentFamilyDraft()

        let hasImage = editorToolContext.hasImageConfigured
        let hasSmartPhoto = editorToolContext.hasSmartPhotoConfigured
        let photoAccess = editorToolContext.photoLibraryAccess
        let uxHardeningEnabled = FeatureFlags.smartPhotosUXHardeningEnabled

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

        func fileExistsInAppGroup(_ fileName: String?) -> Bool {
            let trimmed = (fileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            let url = AppGroup.imageFileURL(fileName: trimmed)
            return FileManager.default.fileExists(atPath: url.path)
        }

        func smartPhotoStatusHint(smart: SmartPhotoSpec) -> String? {
            guard uxHardeningEnabled else { return nil }

            let manifestFileName = (smart.shuffleManifestFileName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !manifestFileName.isEmpty {
                guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFileName) else {
                    return "Album Shuffle is enabled, but the shuffle manifest is missing.\nRe-select an album in Album Shuffle."
                }

                if manifest.entryForRender() == nil {
                    return "Album Shuffle is enabled, but no photos have been prepared yet.\nOpen Album Shuffle and tap “Prepare next batch”."
                }
            }

            let master = smart.masterFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            if master.isEmpty || !fileExistsInAppGroup(master) {
                return "Smart Photo master file is missing.\nTap “Regenerate smart renders”."
            }

            let checks: [(family: EditingFamily, fileName: String?)] = [
                (.small, smart.small?.renderFileName),
                (.medium, smart.medium?.renderFileName),
                (.large, smart.large?.renderFileName),
            ]

            let missing = checks.filter { pair in
                let t = (pair.fileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return true }
                return !fileExistsInAppGroup(t)
            }

            if !missing.isEmpty {
                let labels = missing.map { $0.family.label }.joined(separator: ", ")
                return "Some Smart Photo renders are missing (\(labels)).\nTap “Regenerate smart renders”."
            }

            return nil
        }

        func runSmartPhotoAction(_ work: @escaping @Sendable () async -> Void) {
            if !uxHardeningEnabled {
                Task { await work() }
                return
            }

            guard !importInProgress else { return }

            importInProgress = true

            Task {
                await work()
                await MainActor.run { importInProgress = false }
            }
        }

        return Section {
            if !hasImage {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.imageRequiredForSmartPhoto(),
                    isBusy: false
                )
            } else if hasSmartPhoto, let smart = d.imageSmartPhoto {
                Button {
                    runSmartPhotoAction {
                        await regenerateSmartPhotoRenders()
                    }
                } label: {
                    if uxHardeningEnabled {
                        Label {
                            HStack(spacing: 8) {
                                Text("Regenerate smart renders")
                                if importInProgress {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        } icon: {
                            Image(systemName: "arrow.clockwise")
                        }
                    } else {
                        Label("Regenerate smart renders", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(importInProgress)

                Text("Smart Photo: v\(smart.algorithmVersion) • prepared \(smart.preparedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let hint = smartPhotoStatusHint(smart: smart) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text(hint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    runSmartPhotoAction {
                        await regenerateSmartPhotoRenders()
                    }
                } label: {
                    if uxHardeningEnabled {
                        Label {
                            HStack(spacing: 8) {
                                Text("Make Smart Photo (per-size renders)")
                                if importInProgress {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                        } icon: {
                            Image(systemName: "sparkles")
                        }
                    } else {
                        Label("Make Smart Photo (per-size renders)", systemImage: "sparkles")
                    }
                }
                .disabled(importInProgress)

                Text("Generates per-size crops for Small/Medium/Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("After Smart Photo is created, Smart Photo Framing, Smart Rules, and Album Shuffle will appear.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if uxHardeningEnabled, importInProgress {
                let trimmed = saveStatusMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                Text(trimmed.isEmpty ? "Working…" : trimmed)
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
                    runSmartPhotoAction {
                        await upgradeLegacyPhotosInCurrentDesign(maxUpgrades: 3)
                    }
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
