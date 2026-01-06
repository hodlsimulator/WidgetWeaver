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
        let hasImage = !d.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSmartPhoto = d.imageSmartPhoto != nil

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
                Text("Choose a photo in Image first to enable Smart Photo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    func smartRulesSection(focus: Binding<EditorFocusSnapshot>) -> some View {
        let d = currentFamilyDraft()
        let hasImage = !d.imageFileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasSmartPhoto = d.imageSmartPhoto != nil

        let rules = SmartPhotoShuffleRulesStore.load()

        let sortLabel = rules.sortOrder.displayName
        let screenshotsLabel = rules.includeScreenshots ? "Included" : "Excluded"
        let minDimLabel = "\(rules.minimumPixelDimension) px"

        return Section {
            if !hasImage {
                Text("Choose a photo in Image first.\nThen make Smart Photo renders in Smart Photo to enable Smart Rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !hasSmartPhoto {
                Text("Smart Rules require Smart Photo.\nIn Smart Photo, tap ‘Make Smart Photo (per-size renders)’ first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("These rules affect which items are included when building an Album Shuffle list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("• Sort: \(sortLabel)\n• Minimum size: \(minDimLabel)\n• Screenshots: \(screenshotsLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    SmartPhotoShuffleRulesEditorView(
                        smartPhoto: binding(\.imageSmartPhoto),
                        importInProgress: $importInProgress,
                        saveStatusMessage: $saveStatusMessage,
                        focusSnapshot: focus
                    )
                } label: {
                    Label("Edit Smart Rules", systemImage: "slider.horizontal.3")
                }
            }
        } header: {
            sectionHeader("Smart Rules")
        }
    }
}

// MARK: - Smart Rules editor

private struct SmartPhotoShuffleRulesEditorView: View {
    @Binding var smartPhoto: SmartPhotoSpec?
    @Binding var importInProgress: Bool
    @Binding var saveStatusMessage: String
    @Binding var focusSnapshot: EditorFocusSnapshot

    @Environment(\.dismiss) private var dismiss

    @State private var rules: SmartPhotoShuffleRules
    @State private var initialRules: SmartPhotoShuffleRules
    @State private var previousFocusSnapshot: EditorFocusSnapshot?
    @State private var focusAlbumID: String = "smart-photo-rules"

    init(
        smartPhoto: Binding<SmartPhotoSpec?>,
        importInProgress: Binding<Bool>,
        saveStatusMessage: Binding<String>,
        focusSnapshot: Binding<EditorFocusSnapshot>
    ) {
        self._smartPhoto = smartPhoto
        self._importInProgress = importInProgress
        self._saveStatusMessage = saveStatusMessage
        self._focusSnapshot = focusSnapshot

        let loaded = SmartPhotoShuffleRulesStore.load()
        self._rules = State(initialValue: loaded)
        self._initialRules = State(initialValue: loaded)
    }

    var body: some View {
        Form {
            Section {
                Picker("Sort", selection: $rules.sortOrder) {
                    ForEach(SmartPhotoShuffleSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }

                Stepper(value: $rules.minimumPixelDimension, in: 200 ... 4000, step: 100) {
                    Text("Minimum size: \(rules.minimumPixelDimension) px")
                }

                Toggle("Include screenshots", isOn: $rules.includeScreenshots)
            } header: {
                Text("Rules")
            } footer: {
                Text("Changes are saved immediately and apply the next time an Album Shuffle list is built.")
            }

            Section {
                Button {
                    rules = SmartPhotoShuffleRules.default
                } label: {
                    Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                }
                .disabled(importInProgress)
            }

            Section {
                Button {
                    Task { await rebuildCurrentShuffleManifestFromRules() }
                } label: {
                    Label("Rebuild current Album Shuffle list", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(importInProgress || currentManifestFileName().isEmpty)

                if currentManifestFileName().isEmpty {
                    Text("No Album Shuffle manifest yet.\nIn Album Shuffle, choose an album first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Rebuild overwrites the manifest and resets progress to 0 prepared items.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Apply")
            }
        }
        .navigationTitle("Smart Rules")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            focusAlbumID = currentAlbumIDForFocus()
            pushFocusIfNeeded()
        }
        .onDisappear {
            SmartPhotoShuffleRulesStore.save(rules)

            if rules.normalised() != initialRules.normalised() {
                saveStatusMessage = "Smart Rules updated."
                initialRules = rules
            }

            restoreFocusIfNeeded()
        }
        .onChange(of: rules) { newValue in
            SmartPhotoShuffleRulesStore.save(newValue)
        }
    }

    private func currentManifestFileName() -> String {
        (smartPhoto?.shuffleManifestFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func currentAlbumIDForFocus() -> String {
        let mf = currentManifestFileName()
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            return "smart-photo-rules"
        }
        let source = manifest.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? "smart-photo-rules" : source
    }

    private func pushFocusIfNeeded() {
        if previousFocusSnapshot == nil {
            previousFocusSnapshot = focusSnapshot
        }

        focusSnapshot = EditorFocusSnapshot(selection: .none, focus: .smartRuleEditor(albumID: focusAlbumID))
    }

    private func restoreFocusIfNeeded() {
        guard let previous = previousFocusSnapshot else { return }

        if case .smartRuleEditor(let albumID) = focusSnapshot.focus, albumID == focusAlbumID {
            focusSnapshot = previous
        }

        previousFocusSnapshot = nil
    }

    private func scheduledNextChangeDate(from now: Date, minutes: Int) -> Date {
        let safeMinutes = max(1, minutes)
        let raw = now.addingTimeInterval(TimeInterval(safeMinutes) * 60.0)
        let cal = Calendar.current
        return cal.date(bySetting: .second, value: 0, of: raw) ?? raw
    }

    private func rebuildCurrentShuffleManifestFromRules() async {
        let mf = currentManifestFileName()
        guard !mf.isEmpty else {
            saveStatusMessage = "No Album Shuffle manifest yet."
            return
        }

        importInProgress = true
        defer { importInProgress = false }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            saveStatusMessage = "Shuffle manifest not found."
            return
        }

        let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        guard ok else {
            saveStatusMessage = "Photo access not granted."
            return
        }

        let assetIDs = SmartPhotoAlbumShuffleControlsEngine.fetchImageAssetIdentifiers(albumID: manifest.sourceID)
        guard !assetIDs.isEmpty else {
            saveStatusMessage = "No usable images found with current Smart Rules."
            return
        }

        manifest.entries = assetIDs.map { SmartPhotoShuffleManifest.Entry(id: $0) }
        manifest.currentIndex = 0

        let minutes = manifest.rotationIntervalMinutes
        if minutes > 0 {
            manifest.nextChangeDate = scheduledNextChangeDate(from: Date(), minutes: minutes)
        } else {
            manifest.nextChangeDate = nil
        }

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
            WidgetWeaverWidgetRefresh.forceKick()
            saveStatusMessage = "Rebuilt shuffle list (\(assetIDs.count) items)."
        } catch {
            saveStatusMessage = "Failed to save shuffle manifest."
        }

        dismiss()
    }
}
