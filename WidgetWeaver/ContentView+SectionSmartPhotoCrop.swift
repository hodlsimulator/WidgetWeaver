//
//  ContentView+SectionSmartPhotoCrop.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI
import WidgetKit

extension ContentView {
    func smartPhotoCropSection(focus: Binding<EditorFocusSnapshot>) -> some View {
        let d = currentFamilyDraft()
        let hasImage = editorToolContext.hasImageConfigured
        let hasSmartPhoto = editorToolContext.hasSmartPhotoConfigured

        return Section {
            if !hasImage {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.imageRequiredForSmartPhotoFraming(),
                    isBusy: false
                )
            } else if !hasSmartPhoto {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.smartPhotoRequiredForSmartPhotoFraming(),
                    isBusy: false
                )
            } else if let smart = d.imageSmartPhoto {
                let manifestFile = (smart.shuffleManifestFileName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                let shuffleEnabled = !manifestFile.isEmpty

                if shuffleEnabled {
                    SmartPhotoShuffleFramingEditorView(
                        smart: smart,
                        manifestFileName: manifestFile,
                        selectedFamily: editingFamily,
                        focus: focus,
                        isBusy: importInProgress,
                        onSelectFamily: { family in
                            previewFamily = widgetFamily(for: family)
                        },
                        onApplyCrop: { entryID, family, rect in
                            await applyManualSmartCropForShuffleEntry(
                                manifestFileName: manifestFile,
                                entryID: entryID,
                                family: family,
                                cropRect: rect
                            )
                        },
                        onResetToAuto: { entryID, family in
                            await resetManualSmartCropForShuffleEntry(
                                manifestFileName: manifestFile,
                                entryID: entryID,
                                family: family
                            )
                        },
                        onMakeCurrent: { entryID in
                            await makeShuffleEntryCurrent(
                                manifestFileName: manifestFile,
                                entryID: entryID
                            )
                        }
                    )
                } else {
                    SmartPhotoPreviewStripView(
                        smart: smart,
                        selectedFamily: editingFamily,
                        onSelectFamily: { family in
                            previewFamily = widgetFamily(for: family)
                        }
                    )

                    let family = editingFamily
                    let familyLabel = editingFamilyLabel

                    let variant: SmartPhotoVariantSpec? = {
                        switch family {
                        case .small: return smart.small
                        case .medium: return smart.medium
                        case .large: return smart.large
                        }
                    }()

                    if let variant {
                        NavigationLink {
                            SmartPhotoCropEditorView(
                                family: family,
                                masterFileName: smart.masterFileName,
                                targetPixels: variant.pixelSize,
                                initialCropRect: variant.cropRect,
                                focus: focus,
                                onApply: { rect in
                                    await applyManualSmartCrop(family: family, cropRect: rect)
                                }
                            )
                        } label: {
                            Label("Fix framing (\(familyLabel))", systemImage: "crop")
                        }
                        .disabled(importInProgress)
                    } else {
                        Text("Smart render data missing for \(familyLabel).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            sectionHeader("Smart Photo Framing")
        }
    }

    private func widgetFamily(for family: EditingFamily) -> WidgetFamily {
        switch family {
        case .small: return .systemSmall
        case .medium: return .systemMedium
        case .large: return .systemLarge
        }
    }
}

private struct SmartPhotoShuffleFramingEditorView: View {
        let smart: SmartPhotoSpec
        let manifestFileName: String
        let focus: Binding<EditorFocusSnapshot>
        let isBusy: Bool

        let selectedFamily: EditingFamily
        let onSelectFamily: (EditingFamily) -> Void
        let onApplyCrop: (String, EditingFamily, NormalisedRect) async -> Void
        let onResetToAuto: (String, EditingFamily) async -> Void
        let onMakeCurrent: (String) async -> Void

        @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
        private var smartPhotoShuffleUpdateToken: Int = 0

        /// When true, the section follows the same time-based shuffle logic as the widget.
        /// When false, a specific photo is selected for per-photo manual framing.
        @State private var isFollowingCurrentEntry: Bool = true

        /// Editor-only state: which shuffle entry is selected when not following the current entry.
        @State private var selectedShuffleEntryID: String? = nil

        var body: some View {
            let _ = smartPhotoShuffleUpdateToken
            let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)

            return Group {
                if mf.isEmpty {
                    Text("Shuffle manifest missing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) {
                    let prepared = preparedEntries(manifest)

                    if prepared.isEmpty {
                        Text("Shuffle photos are still preparing…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if manifest.rotationIntervalMinutes > 0 {
                        // Match preview/widget update cadence to keep editor previews in sync.
                        let interval: TimeInterval = 5
                        let start = WidgetWeaverRenderClock.alignedTimelineStartDate(interval: interval)

                        TimelineView(.periodic(from: start, by: interval)) { ctx in
                            WidgetWeaverRenderClock.withNow(ctx.date) {
                                shuffleBody(manifest: manifest, prepared: prepared, manifestFile: mf)
                            }
                        }
                    } else {
                        shuffleBody(manifest: manifest, prepared: prepared, manifestFile: mf)
                    }
                } else {
                    Text("Shuffle manifest not found.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                setDefaultSelectionIfNeeded()
            }
            .onChange(of: smartPhotoShuffleUpdateToken) { _, _ in
                // If the manifest changes (new batch prepared, manual crop saved, shuffle regenerated),
                // keep the current manual selection valid.
                setDefaultSelectionIfNeeded()
            }
        }

        @ViewBuilder
        private func shuffleBody(
            manifest: SmartPhotoShuffleManifest,
            prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)],
            manifestFile: String
        ) -> some View {
            let current = resolveCurrentEntry(prepared: prepared, manifest: manifest)
            let selected = resolveDisplayedEntry(prepared: prepared, manifest: manifest, current: current)

            let selectedPosition = prepared.firstIndex(where: { $0.entry.id == selected.entry.id }) ?? 0
            let currentPosition: Int? = {
                guard let current else { return nil }
                return prepared.firstIndex(where: { $0.entry.id == current.entry.id })
            }()

            return VStack(alignment: .leading, spacing: 10) {
                header(
                    selectedPosition: selectedPosition,
                    preparedCount: prepared.count,
                    currentPosition: currentPosition,
                    currentEntryID: current?.entry.id,
                    selectedEntryID: selected.entry.id
                )

                SmartPhotoPreviewStripView(
                    smart: smart,
                    selectedFamily: selectedFamily,
                    fixedShuffleEntry: selected.entry,
                    onSelectFamily: onSelectFamily
                )

                if !isFollowingCurrentEntry, prepared.count > 1 {
                    Button {
                        Task { await onMakeCurrent(selected.entry.id) }
                    } label: {
                        Label("Make this the current widget photo", systemImage: "pin")
                    }
                    .disabled(isBusy)
                }

                sizeControls(entry: selected.entry, manifestFile: manifestFile)
            }
        }

        @ViewBuilder
        private func header(
            selectedPosition: Int,
            preparedCount: Int,
            currentPosition: Int?,
            currentEntryID: String?,
            selectedEntryID: String
        ) -> some View {
            let canNavigate = preparedCount > 1

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isFollowingCurrentEntry ? "Current photo" : "Selected photo")
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        Text("Photo \(selectedPosition + 1) of \(preparedCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isFollowingCurrentEntry {
                        Button {
                            // Lock to the current photo for per-photo editing.
                            isFollowingCurrentEntry = false
                            selectedShuffleEntryID = selectedEntryID
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                    } else if canNavigate {
                        HStack(spacing: 8) {
                            Button {
                                selectPrevious(prepared: preparedCount)
                            } label: {
                                Image(systemName: "chevron.left")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                selectNext(prepared: preparedCount)
                            } label: {
                                Image(systemName: "chevron.right")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }

                if isFollowingCurrentEntry {
                    Text("Follows the widget's current shuffle choice.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 10) {
                        Button {
                            isFollowingCurrentEntry = true
                        } label: {
                            Label("Follow shuffle", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)

                        if let currentEntryID,
                           currentEntryID != selectedEntryID,
                           currentPosition != nil
                        {
                            Button {
                                // Jump the manual selection to whatever the widget is showing now.
                                isFollowingCurrentEntry = false
                                selectedShuffleEntryID = currentEntryID
                            } label: {
                                Text("Jump to current")
                            }
                            .buttonStyle(.bordered)
                        }

                        Spacer()
                    }

                    if let currentPosition,
                       let currentEntryID,
                       currentEntryID != selectedEntryID
                    {
                        Text("Widget currently showing Photo \(currentPosition + 1) of \(preparedCount).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not following shuffle while editing a specific photo.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private func selectPrevious(prepared preparedCount: Int) {
            guard preparedCount > 1 else { return }

            let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return }

            let prepared = preparedEntries(manifest)
            guard prepared.count > 1 else { return }

            let currentID = (selectedShuffleEntryID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let currentPos = prepared.firstIndex(where: { $0.entry.id == currentID }) ?? 0
            let prev = (currentPos - 1 + prepared.count) % prepared.count

            isFollowingCurrentEntry = false
            selectedShuffleEntryID = prepared[prev].entry.id
        }

        private func selectNext(prepared preparedCount: Int) {
            guard preparedCount > 1 else { return }

            let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return }

            let prepared = preparedEntries(manifest)
            guard prepared.count > 1 else { return }

            let currentID = (selectedShuffleEntryID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let currentPos = prepared.firstIndex(where: { $0.entry.id == currentID }) ?? 0
            let next = (currentPos + 1) % prepared.count

            isFollowingCurrentEntry = false
            selectedShuffleEntryID = prepared[next].entry.id
        }

        private func preparedEntries(_ manifest: SmartPhotoShuffleManifest) -> [(index: Int, entry: SmartPhotoShuffleManifest.Entry)] {
            manifest.entries.enumerated().filter { $0.element.isPrepared }.map { (index: $0.offset, entry: $0.element) }
        }

        private func resolveCurrentEntry(
            prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)],
            manifest: SmartPhotoShuffleManifest
        ) -> (index: Int, entry: SmartPhotoShuffleManifest.Entry)? {
            guard let current = manifest.entryForRender() else { return nil }
            return prepared.first(where: { $0.entry.id == current.id })
        }

        private func resolveDisplayedEntry(
            prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)],
            manifest: SmartPhotoShuffleManifest,
            current: (index: Int, entry: SmartPhotoShuffleManifest.Entry)?
        ) -> (index: Int, entry: SmartPhotoShuffleManifest.Entry) {
            if isFollowingCurrentEntry, let current {
                return current
            }

            let cleanedSelected = (selectedShuffleEntryID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanedSelected.isEmpty,
               let hit = prepared.first(where: { $0.entry.id == cleanedSelected })
            {
                return hit
            }

            if let current {
                return current
            }

            return prepared[0]
        }

        private func setDefaultSelectionIfNeeded() {
            let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return }

            let prepared = preparedEntries(manifest)
            if prepared.isEmpty { return }

            let cleaned = (selectedShuffleEntryID ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty,
               prepared.contains(where: { $0.entry.id == cleaned })
            {
                return
            }

            // Default manual selection to the current shuffle choice (or the first prepared entry).
            if let current = manifest.entryForRender() {
                selectedShuffleEntryID = current.id
            } else {
                selectedShuffleEntryID = prepared[0].entry.id
            }
        }

        @ViewBuilder
        private func sizeControls(entry: SmartPhotoShuffleManifest.Entry, manifestFile: String) -> some View {
            let canEdit = (entry.sourceFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

            VStack(alignment: .leading, spacing: 10) {
                Text("Fix framing")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 12) {
                    sizeRow(family: .small, entry: entry, manifestFile: manifestFile, canEdit: canEdit)
                    sizeRow(family: .medium, entry: entry, manifestFile: manifestFile, canEdit: canEdit)
                    sizeRow(family: .large, entry: entry, manifestFile: manifestFile, canEdit: canEdit)
                }

                if !canEdit {
                    Text("Source image missing for this shuffled photo. Re-prepare the album shuffle set to enable manual framing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        @ViewBuilder
        private func sizeRow(
            family: EditingFamily,
            entry: SmartPhotoShuffleManifest.Entry,
            manifestFile: String,
            canEdit: Bool
        ) -> some View {
            let manualRect: NormalisedRect? = {
                switch family {
                case .small: return entry.smallManualCropRect
                case .medium: return entry.mediumManualCropRect
                case .large: return entry.largeManualCropRect
                }
            }()

            let hasManual = manualRect != nil

            HStack(spacing: 12) {
                NavigationLink {
                    SmartPhotoCropEditorView(
                        smart: smart,
                        selectedFamily: family,
                        focus: focus,
                        isBusy: isBusy,
                        fixedShuffleEntryID: entry.id,
                        initialCropRect: manualRect,
                        onApplyCrop: { rect in
                            await onApplyCrop(entry.id, family, rect)
                        }
                    )
                } label: {
                    Label("Fix framing (\(family.displayName))", systemImage: "crop")
                }
                .disabled(isBusy || !canEdit)

                Spacer()

                if hasManual {
                    Text("Manual")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.08), in: Capsule())

                    Button {
                        Task { await onResetToAuto(entry.id, family) }
                    } label: {
                        Text("Reset")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isBusy)
                }
            }
        }
    }
