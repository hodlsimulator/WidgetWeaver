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
                    isBusy: importInProgress,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else if !hasSmartPhoto {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.smartPhotoRequiredForSmartPhotoFraming(),
                    isBusy: importInProgress,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else if let smart = d.imageSmartPhoto {
                let manifestFileName = (smart.shuffleManifestFileName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !manifestFileName.isEmpty {
                    SmartPhotoShuffleFramingEditorView(
                        smart: smart,
                        manifestFileName: manifestFileName,
                        selectedFamily: editingFamily,
                        focus: focus,
                        isBusy: importInProgress,
                        onSelectFamily: { fam in
                            previewFamily = widgetFamily(for: fam)
                        },
                        onApplyCrop: { entryID, fam, cropRect in
                            await applyManualSmartCropForShuffleEntry(
                                manifestFileName: manifestFileName,
                                entryID: entryID,
                                family: fam,
                                cropRect: cropRect
                            )
                        },
                        onResetToAuto: { entryID, fam in
                            await resetManualSmartCropForShuffleEntry(
                                manifestFileName: manifestFileName,
                                entryID: entryID,
                                family: fam
                            )
                        },
                        onMakeCurrent: { entryID in
                            await makeShuffleEntryCurrent(
                                manifestFileName: manifestFileName,
                                entryID: entryID
                            )
                        }
                    )
                } else {
                    Text("Album Shuffle is off. Enable it in Album Shuffle to use per-photo framing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.smartPhotoRequiredForSmartPhotoFraming(),
                    isBusy: importInProgress,
                    onPerformCTA: performEditorUnavailableCTA
                )
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
    private enum SelectionMode: String, CaseIterable {
        case current
        case browse
    }

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

    @AppStorage("preview.liveEnabled")
    private var liveEnabled: Bool = true

    @State private var selectionMode: SelectionMode = .current
    @State private var selectedShuffleEntryID: String?

    var body: some View {
        let _ = smartPhotoShuffleUpdateToken
        let trimmedManifestFile = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)

        Group {
            if trimmedManifestFile.isEmpty {
                Text("Shuffle manifest file name is missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if shouldDriveLiveUpdates(manifestFile: trimmedManifestFile) {
                let interval: TimeInterval = liveEnabled ? 5.0 : 60.0
                let start = WidgetWeaverRenderClock.alignedTimelineStartDate(interval: interval)

                TimelineView(.periodic(from: start, by: interval)) { ctx in
                    WidgetWeaverRenderClock.withNow(ctx.date) {
                        VStack(alignment: .leading, spacing: 12) {
                            shuffleBody(manifestFile: trimmedManifestFile)
                        }
                    }
                }
                .task { setDefaultSelectionIfNeeded() }
                .onChange(of: smartPhotoShuffleUpdateToken) { _, _ in setDefaultSelectionIfNeeded() }
                .onChange(of: selectionMode) { _, newValue in
                    guard newValue == .browse else { return }
                    snapBrowseSelectionToCurrentIfPossible()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    shuffleBody(manifestFile: trimmedManifestFile)
                }
                .task { setDefaultSelectionIfNeeded() }
                .onChange(of: smartPhotoShuffleUpdateToken) { _, _ in setDefaultSelectionIfNeeded() }
                .onChange(of: selectionMode) { _, newValue in
                    guard newValue == .browse else { return }
                    snapBrowseSelectionToCurrentIfPossible()
                }
            }
        }
    }

    private func shouldDriveLiveUpdates(manifestFile: String) -> Bool {
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFile) else {
            // If the manifest is missing temporarily, keep the view responsive so it can recover without needing a scroll refresh.
            return true
        }
        return manifest.rotationIntervalMinutes > 0
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
                    let currentResolved = resolveCurrentEntry(prepared: prepared, manifest: manifest)
                    let currentEntry = currentResolved?.entry ?? prepared[0].entry
                    let currentPosition = prepared.firstIndex(where: { $0.entry.id == currentEntry.id }) ?? 0

                    let displayedEntry: SmartPhotoShuffleManifest.Entry = {
                        switch selectionMode {
                        case .current:
                            return currentEntry
                        case .browse:
                            return resolveBrowseSelectedEntry(prepared: prepared, fallback: currentEntry) ?? currentEntry
                        }
                    }()

                    let displayedPosition = prepared.firstIndex(where: { $0.entry.id == displayedEntry.id }) ?? 0

                    header(
                        manifest: manifest,
                        preparedCount: prepared.count,
                        displayedPosition: displayedPosition,
                        currentPosition: currentPosition,
                        canNavigate: prepared.count > 1,
                        onPrev: { selectPrevious(prepared: prepared) },
                        onNext: { selectNext(prepared: prepared) }
                    )

                    SmartPhotoPreviewStripView(
                        smart: smart,
                        selectedFamily: selectedFamily,
                        onSelectFamily: onSelectFamily,
                        fixedShuffleEntry: displayedEntry
                    )

                    sizeControls(entry: displayedEntry)

                    if selectionMode == .browse {
                        Button {
                            Task { await onMakeCurrent(displayedEntry.id) }
                        } label: {
                            Label("Make this the current widget photo", systemImage: "pin")
                        }
                        .disabled(isBusy)
                    }

                    footer(manifest: manifest)
                }
            } else {
                Text("Shuffle manifest not found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func header(
        manifest: SmartPhotoShuffleManifest,
        preparedCount: Int,
        displayedPosition: Int,
        currentPosition: Int,
        canNavigate: Bool,
        onPrev: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectionMode == .current ? "Current photo" : "Selected photo")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Photo \(min(preparedCount, displayedPosition + 1)) of \(preparedCount)")
                        .font(.subheadline)
                        .bold()
                }

                Spacer(minLength: 0)

                Picker("Photo selection", selection: $selectionMode) {
                    Text("Current").tag(SelectionMode.current)
                    Text("Browse").tag(SelectionMode.browse)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(maxWidth: 220)
            }

            if selectionMode == .browse {
                HStack(alignment: .center, spacing: 12) {
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

                    Spacer()

                    if currentPosition != displayedPosition {
                        Text("Current widget photo: \(min(preparedCount, currentPosition + 1)) of \(preparedCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Currently showing this photo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Following the shuffle schedule.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if manifest.rotationIntervalMinutes > 0,
               let next = manifest.nextChangeDateFrom(now: WidgetWeaverRenderClock.now)
            {
                Text("Next change: \(next.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Rotation is off (manual only).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func footer(manifest: SmartPhotoShuffleManifest) -> some View {
        Group {
            if manifest.rotationIntervalMinutes > 0,
               let next = manifest.nextChangeDateFrom(now: WidgetWeaverRenderClock.now)
            {
                Text("Home Screen updates at shuffle boundaries. Next change: \(next.formatted(date: .abbreviated, time: .shortened)).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Rotation is off. Use Prev/Next in Album Shuffle to change the widget photo.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sizeControls(entry: SmartPhotoShuffleManifest.Entry) -> some View {
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

    private func resolveCurrentEntry(
        prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)],
        manifest: SmartPhotoShuffleManifest
    ) -> (index: Int, entry: SmartPhotoShuffleManifest.Entry)? {
        if let current = manifest.entryForRender(),
           let found = prepared.first(where: { $0.entry.id == current.id })
        {
            return found
        }

        return prepared.first
    }

    private func resolveBrowseSelectedEntry(
        prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)],
        fallback: SmartPhotoShuffleManifest.Entry
    ) -> SmartPhotoShuffleManifest.Entry? {
        if let selectedID = selectedShuffleEntryID?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !selectedID.isEmpty,
           let found = prepared.first(where: { $0.entry.id == selectedID })?.entry
        {
            return found
        }

        return fallback
    }

    private func setDefaultSelectionIfNeeded() {
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mf.isEmpty else { return }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return }

        let prepared = preparedEntries(manifest)
        guard !prepared.isEmpty else { return }

        if selectionMode == .browse {
            if let selectedID = selectedShuffleEntryID?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !selectedID.isEmpty,
               prepared.contains(where: { $0.entry.id == selectedID })
            {
                return
            }

            if let current = manifest.entryForRender(),
               prepared.contains(where: { $0.entry.id == current.id })
            {
                selectedShuffleEntryID = current.id
            } else {
                selectedShuffleEntryID = prepared.first?.entry.id
            }
            return
        }

        if selectedShuffleEntryID == nil,
           let current = manifest.entryForRender()
        {
            selectedShuffleEntryID = current.id
        }
    }

    private func snapBrowseSelectionToCurrentIfPossible() {
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mf.isEmpty else { return }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return }

        if let current = manifest.entryForRender() {
            selectedShuffleEntryID = current.id
        } else {
            let prepared = preparedEntries(manifest)
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
