//
//  ContentView+SectionSmartRules.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI

extension ContentView {
    struct SmartRulesSection: View {
        @Binding var draft: FamilyDraft
        @Binding var focus: EditorFocusSnapshot

        @Binding var importInProgress: Bool
        @Binding var saveStatusMessage: String

        let autoThemeFromImage: Bool

        @State private var showRulesEditor: Bool = false

        var body: some View {
            Form {
                Section {
                    Text("Smart Rules are optional filters for Album Shuffle.\nThey can reduce low-quality photos, prioritise recent images, and ignore screenshots.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Auto theme from image", isOn: Binding(
                        get: { autoThemeFromImage },
                        set: { _ in }
                    ))
                    .disabled(true)
                } header: {
                    Text("Theme")
                } footer: {
                    Text("Theme auto-selection can be configured in the main editor.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showRulesEditor = true
                    } label: {
                        Label("Edit rules", systemImage: "slider.horizontal.3")
                    }
                    .disabled(importInProgress)

                    Button {
                        Task { await rebuildAlbumListPreservingPrepared() }
                    } label: {
                        Label("Rebuild album list (preserve prepared)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(importInProgress)
                } header: {
                    Text("Album Shuffle")
                } footer: {
                    Text("Rebuild keeps prepared renders for any photos still included by the rules.")
                }

                Section {
                    Button(role: .destructive) {
                        SmartPhotoShuffleRulesStore.resetToDefaults()
                    } label: {
                        Label("Reset to defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Smart Rules")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRulesEditor) {
                SmartPhotoShuffleRulesEditor()
            }
        }

        @MainActor
        private func rebuildAlbumListPreservingPrepared() async {
            let mf = draft.imageSmartPhoto?.shuffleManifestFileName ?? ""
            guard !mf.isEmpty else {
                saveStatusMessage = "Album Shuffle is not configured yet."
                return
            }

            importInProgress = true
            defer { importInProgress = false }

            let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
            EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
            guard ok else {
                saveStatusMessage = "Photo library access is off.\nEnable access in Settings to use Album Shuffle."
                return
            }

            guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
                saveStatusMessage = "Shuffle manifest not found."
                return
            }

            let oldCurrentID: String? = {
                guard manifest.entries.indices.contains(manifest.currentIndex) else { return nil }
                return manifest.entries[manifest.currentIndex].id
            }()

            let oldPreparedIDs = Set(manifest.entries.filter { $0.isPrepared }.map { $0.id })

            let assetIDs = SmartPhotoAlbumShuffleControlsEngine.fetchImageAssetIdentifiers(albumID: manifest.sourceID)

            if assetIDs.isEmpty {
                saveStatusMessage = "No usable images found with the current rules.\nTry lowering the minimum size or including screenshots."
                return
            }

            var oldByID: [String: SmartPhotoShuffleManifest.Entry] = [:]
            oldByID.reserveCapacity(manifest.entries.count)

            for entry in manifest.entries {
                if oldByID[entry.id] == nil {
                    oldByID[entry.id] = entry
                }
            }

            manifest.entries = assetIDs.map { id in
                oldByID[id] ?? SmartPhotoShuffleManifest.Entry(id: id)
            }

            if let oldCurrentID,
               let newIndex = manifest.entries.firstIndex(where: { $0.id == oldCurrentID })
            {
                manifest.currentIndex = newIndex
            } else {
                manifest.currentIndex = 0
            }

            if manifest.rotationIntervalMinutes > 0 {
                manifest.nextChangeDate = scheduledNextChangeDate(from: Date(), minutes: manifest.rotationIntervalMinutes)
            }

            do {
                try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
            } catch {
                saveStatusMessage = "Failed to save shuffle manifest: \(error.localizedDescription)"
                return
            }

            WidgetWeaverWidgetRefresh.forceKick()

            let preservedPrepared = manifest.entries.filter { $0.isPrepared && oldPreparedIDs.contains($0.id) }.count

            saveStatusMessage = "Rebuilt album list: \(assetIDs.count) photos.\nPreserved \(preservedPrepared) prepared renders.\nSave to update widgets."
        }

        private func scheduledNextChangeDate(from now: Date, minutes: Int) -> Date {
            let safeMinutes = max(1, minutes)
            let raw = now.addingTimeInterval(TimeInterval(safeMinutes) * 60.0)
            let cal = Calendar.current
            return cal.date(bySetting: .second, value: 0, of: raw) ?? raw
        }
    }

    func smartRulesSection(focus: Binding<EditorFocusSnapshot>) -> some View {
        SmartRulesSection(
            draft: binding(\.self),
            focus: focus.wrappedValueBinding(),
            importInProgress: $importInProgress,
            saveStatusMessage: $saveStatusMessage,
            autoThemeFromImage: autoThemeFromImage
        )
    }
}

private extension Binding where Value == EditorFocusSnapshot {
    func wrappedValueBinding() -> Binding<EditorFocusSnapshot> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }
}
