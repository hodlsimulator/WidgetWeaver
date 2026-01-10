//
//  ContentView+SectionSmartRules.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI

extension ContentView {
    func smartRulesSection(focus: Binding<EditorFocusSnapshot>) -> some View {
        let hasImage = editorToolContext.hasImageConfigured
        let hasSmartPhoto = editorToolContext.hasSmartPhotoConfigured

        return Section {
            if !hasImage {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.imageRequiredForSmartRules(),
                    isBusy: false
                )
            } else if !hasSmartPhoto {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.smartPhotoRequiredForSmartRules(),
                    isBusy: false
                )
            } else {
                SmartPhotoSmartRulesSummaryView()

                NavigationLink {
                    SmartPhotoSmartRulesEditorView(
                        smartPhoto: binding(\.imageSmartPhoto),
                        importInProgress: $importInProgress,
                        saveStatusMessage: $saveStatusMessage,
                        focus: focus
                    )
                } label: {
                    Label("Edit Smart Rules", systemImage: "slider.horizontal.3")
                }
                .disabled(importInProgress)

                Text("Rules apply when building the album list.\nUse Rebuild to re-filter the current album without losing prepared renders.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Smart Rules")
        }
    }
}

private struct SmartPhotoSmartRulesSummaryView: View {
    @AppStorage(SmartPhotoShuffleRulesStore.Keys.includeScreenshots, store: AppGroup.userDefaults)
    private var includeScreenshots: Bool = SmartPhotoShuffleRules.defaultRules.includeScreenshots

    @AppStorage(SmartPhotoShuffleRulesStore.Keys.minPixelDimension, store: AppGroup.userDefaults)
    private var minPixelDimension: Int = SmartPhotoShuffleRules.defaultRules.minimumPixelDimension

    @AppStorage(SmartPhotoShuffleRulesStore.Keys.sortOrder, store: AppGroup.userDefaults)
    private var sortOrderRaw: String = SmartPhotoShuffleRules.defaultRules.sortOrder.rawValue

    private var sortOrder: SmartPhotoShuffleSortOrder {
        SmartPhotoShuffleSortOrder(rawValue: sortOrderRaw) ?? SmartPhotoShuffleRules.defaultRules.sortOrder
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current rules")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Minimum size: \(minPixelDimension)px")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Screenshots: \(includeScreenshots ? "Included" : "Excluded")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Order: \(sortOrder.displayName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SmartPhotoSmartRulesEditorView: View {
    @Binding var smartPhoto: SmartPhotoSpec?
    @Binding var importInProgress: Bool
    @Binding var saveStatusMessage: String

    var focus: Binding<EditorFocusSnapshot>

    @AppStorage(SmartPhotoShuffleRulesStore.Keys.includeScreenshots, store: AppGroup.userDefaults)
    private var includeScreenshots: Bool = SmartPhotoShuffleRules.defaultRules.includeScreenshots

    @AppStorage(SmartPhotoShuffleRulesStore.Keys.minPixelDimension, store: AppGroup.userDefaults)
    private var minPixelDimension: Int = SmartPhotoShuffleRules.defaultRules.minimumPixelDimension

    @AppStorage(SmartPhotoShuffleRulesStore.Keys.sortOrder, store: AppGroup.userDefaults)
    private var sortOrderRaw: String = SmartPhotoShuffleRules.defaultRules.sortOrder.rawValue

    @State private var previousFocusSnapshot: EditorFocusSnapshot? = nil
    @State private var focusAlbumID: String = "smartRules"

    private var sortOrderBinding: Binding<SmartPhotoShuffleSortOrder> {
        Binding(
            get: {
                SmartPhotoShuffleSortOrder(rawValue: sortOrderRaw) ?? SmartPhotoShuffleRules.defaultRules.sortOrder
            },
            set: { newValue in
                sortOrderRaw = newValue.rawValue
            }
        )
    }

    private var manifestFileName: String {
        (smartPhoto?.shuffleManifestFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Include screenshots", isOn: $includeScreenshots)

                Stepper(
                    value: $minPixelDimension,
                    in: SmartPhotoShuffleRules.minimumPixelDimensionRange,
                    step: 50
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Minimum image size")
                        Text("\(minPixelDimension)px on the shortest edge")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Order", selection: sortOrderBinding) {
                    ForEach(SmartPhotoShuffleSortOrder.allCases) { order in
                        Text(order.displayName).tag(order)
                    }
                }
            } header: {
                Text("Rules")
            } footer: {
                Text("Rules are applied when building the Album Shuffle list.\nThey do not change the photo you selected in Image.")
            }

            Section {
                Button {
                    Task { await rebuildAlbumListPreservingPrepared() }
                } label: {
                    Label("Rebuild current album list", systemImage: "arrow.clockwise")
                }
                .disabled(importInProgress || manifestFileName.isEmpty)

                if manifestFileName.isEmpty {
                    Text("Album Shuffle is not configured yet.\nPick an album in Album Shuffle to create a list, then use Rebuild here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .onAppear { handlePresentationChange(isPresented: true) }
        .onDisappear { handlePresentationChange(isPresented: false) }
    }

    private func handlePresentationChange(isPresented: Bool) {
        if isPresented {
            if previousFocusSnapshot == nil {
                previousFocusSnapshot = focus.wrappedValue
            }

            if !manifestFileName.isEmpty,
               let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFileName)
            {
                focusAlbumID = manifest.sourceID
            } else {
                focusAlbumID = "smartRules"
            }

            focus.wrappedValue = .smartRuleEditor(albumID: focusAlbumID)
        } else {
            guard let previous = previousFocusSnapshot else { return }
            defer { previousFocusSnapshot = nil }

            if case .smartRuleEditor = focus.wrappedValue.focus {
                focus.wrappedValue = previous
            }
        }
    }

    @MainActor
    private func rebuildAlbumListPreservingPrepared() async {
        let mf = manifestFileName
        guard !mf.isEmpty else {
            saveStatusMessage = "Album Shuffle is not configured yet."
            return
        }

        importInProgress = true
        defer { importInProgress = false }

        let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
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
