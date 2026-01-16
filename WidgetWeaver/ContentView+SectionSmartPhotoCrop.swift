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
    let selectedFamily: EditingFamily
    let focus: Binding<EditorFocusSnapshot>
    let isBusy: Bool
    let onSelectFamily: (EditingFamily) -> Void
    let onApplyCrop: (String, EditingFamily, NormalisedRect) async -> Void
    let onResetToAuto: (String, EditingFamily) async -> Void
    let onMakeCurrent: (String) async -> Void

    @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
    private var smartPhotoShuffleUpdateToken: Int = 0

    @State private var selectedShuffleEntryID: String?

    var body: some View {
        let _ = smartPhotoShuffleUpdateToken

        let trimmedManifestFile = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)

        return Group {
            if trimmedManifestFile.isEmpty {
                Text("Shuffle manifest file name is missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    shuffleBody(manifestFile: trimmedManifestFile)
                }
                .task {
                    setDefaultSelectionIfNeeded()
                }
                .onChange(of: smartPhotoShuffleUpdateToken) { _, _ in
                    setDefaultSelectionIfNeeded()
                }
            }
        }
    }

    private func shuffleBody(manifestFile: String) -> some View {
        Group {
            if let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFile) {
                let prepared = preparedEntries(manifest)

                if prepared.isEmpty {
                    Text("No prepared photos yet.\nUse “Prepare next batch” in Album Shuffle.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let resolved = resolveSelectedEntry(prepared: prepared, manifest: manifest)
                    let selectedEntry = resolved?.entry ?? prepared[0].entry
                    let selectedPosition = prepared.firstIndex(where: { $0.entry.id == selectedEntry.id }) ?? 0

                    selectedHeader(
                        selectedPosition: selectedPosition,
                        preparedCount: prepared.count,
                        canNavigate: prepared.count > 1,
                        onPrev: { selectPrevious(prepared: prepared) },
                        onNext: { selectNext(prepared: prepared) }
                    )

                    SmartPhotoPreviewStripView(
                        smart: smart,
                        selectedFamily: selectedFamily,
                        onSelectFamily: onSelectFamily,
                        fixedShuffleEntry: selectedEntry
                    )

                    sizeControls(entry: selectedEntry, manifestFile: manifestFile)

                    Button {
                        Task { await onMakeCurrent(selectedEntry.id) }
                    } label: {
                        Label("Make this the current widget photo", systemImage: "pin")
                    }
                    .disabled(isBusy)

                    if manifest.rotationIntervalMinutes > 0,
                       let next = manifest.nextChangeDateFrom(now: Date()) {
                        Text("Home Screen updates at shuffle boundaries. Next change: \(next.formatted(date: .abbreviated, time: .shortened)).")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Rotation is off. Use Prev/Next in Album Shuffle to change the widget photo.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Shuffle manifest not found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func selectedHeader(
        selectedPosition: Int,
        preparedCount: Int,
        canNavigate: Bool,
        onPrev: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Selected photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Photo \(min(preparedCount, selectedPosition + 1)) of \(preparedCount)")
                    .font(.subheadline)
                    .bold()
            }

            Spacer()

            Button(action: onPrev) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(isBusy || !canNavigate)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(isBusy || !canNavigate)
        }
    }

    private func sizeControls(entry: SmartPhotoShuffleManifest.Entry, manifestFile: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(EditingFamily.allCases, id: \.rawValue) { family in
                let hasManual = entryHasManual(for: family, entry: entry)
                let canEdit = entryHasSource(entry: entry)

                HStack(alignment: .center, spacing: 12) {
                    NavigationLink {
                        SmartPhotoCropEditorView(
                            family: family,
                            masterFileName: (entry.sourceFileName ?? "")
                                .trimmingCharacters(in: .whitespacesAndNewlines),
                            targetPixels: targetPixels(for: family),
                            initialCropRect: initialCropRect(for: family, entry: entry),
                            focus: focus,
                            onApply: { rect in
                                await onApplyCrop(entry.id, family, rect)
                            }
                        )
                    } label: {
                        Label("Fix framing (\(family.label))", systemImage: "crop")
                    }
                    .disabled(isBusy || !canEdit)

                    Spacer()

                    if hasManual {
                        Button {
                            Task { await onResetToAuto(entry.id, family) }
                        } label: {
                            Text("Reset to Auto")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isBusy)
                    }
                }

                if !canEdit {
                    Text("Source image for this shuffled photo is missing.\nRe-prepare this album shuffle set to enable manual framing.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func preparedEntries(_ manifest: SmartPhotoShuffleManifest) -> [(index: Int, entry: SmartPhotoShuffleManifest.Entry)] {
        manifest.entries.enumerated().compactMap { pair in
            let (idx, entry) = pair
            guard entry.isPrepared else { return nil }
            return (idx, entry)
        }
    }

    private func resolveSelectedEntry(
        prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)],
        manifest: SmartPhotoShuffleManifest
    ) -> (index: Int, entry: SmartPhotoShuffleManifest.Entry)? {
        if let selectedID = selectedShuffleEntryID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedID.isEmpty,
           let found = prepared.first(where: { $0.entry.id == selectedID }) {
            return found
        }

        if let current = manifest.entryForRender(),
           let found = prepared.first(where: { $0.entry.id == current.id }) {
            return found
        }

        return prepared.first
    }

    private func setDefaultSelectionIfNeeded() {
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mf.isEmpty else { return }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return }

        let prepared = preparedEntries(manifest)
        guard !prepared.isEmpty else { return }

        if let selectedID = selectedShuffleEntryID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedID.isEmpty,
           prepared.contains(where: { $0.entry.id == selectedID }) {
            return
        }

        if let current = manifest.entryForRender() {
            selectedShuffleEntryID = current.id
        } else {
            selectedShuffleEntryID = prepared.first?.entry.id
        }
    }

    private func selectPrevious(prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)]) {
        guard !prepared.isEmpty else { return }

        let currentID = selectedShuffleEntryID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let pos = prepared.firstIndex(where: { $0.entry.id == currentID }) ?? 0
        let nextPos = (pos - 1 + prepared.count) % prepared.count
        selectedShuffleEntryID = prepared[nextPos].entry.id
    }

    private func selectNext(prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)]) {
        guard !prepared.isEmpty else { return }

        let currentID = selectedShuffleEntryID?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let pos = prepared.firstIndex(where: { $0.entry.id == currentID }) ?? 0
        let nextPos = (pos + 1) % prepared.count
        selectedShuffleEntryID = prepared[nextPos].entry.id
    }

    private func entryHasSource(entry: SmartPhotoShuffleManifest.Entry) -> Bool {
        entry.hasSourceImageFile
    }

    private func entryHasManual(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> Bool {
        switch family {
        case .small:
            return !(entry.smallManualFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .medium:
            return !(entry.mediumManualFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .large:
            return !(entry.largeManualFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func targetPixels(for family: EditingFamily) -> PixelSize {
        let targets = SmartPhotoRenderTargets.forCurrentDevice()
        switch family {
        case .small: return targets.small
        case .medium: return targets.medium
        case .large: return targets.large
        }
    }

    private func initialCropRect(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> NormalisedRect {
        let fallback = NormalisedRect(x: 0, y: 0, width: 1, height: 1)

        switch family {
        case .small:
            return (entry.smallManualCropRect ?? entry.smallAutoCropRect ?? fallback).normalised()
        case .medium:
            return (entry.mediumManualCropRect ?? entry.mediumAutoCropRect ?? fallback).normalised()
        case .large:
            return (entry.largeManualCropRect ?? entry.largeAutoCropRect ?? fallback).normalised()
        }
    }
}
