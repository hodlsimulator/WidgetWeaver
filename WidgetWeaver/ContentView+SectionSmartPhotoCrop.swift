//
//  ContentView+SectionSmartPhotoCrop.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI
import WidgetKit

extension ContentView {
    var smartPhotoCropSection: some View {
        Section {
            if let smart = currentFamilyDraft().imageSmartPhoto {
                let shuffleEnabled = !(smart.shuffleManifestFileName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty

                if shuffleEnabled {
                    SmartPhotoShuffleFramingEditorView(
                        smart: smart,
                        manifestFileName: manifestFile,
                        focus: $editorFocusSnapshot,
                        isBusy: importInProgress,
                        selectedFamily: editingFamily,
                        onSelectFamily: { family in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                editingFamily = family
                            }
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
                            withAnimation(.easeInOut(duration: 0.15)) {
                                editingFamily = family
                            }
                        }
                    )

                    if let variant = smart.variant(for: editingFamily) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Current crop for \(editingFamily.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            cropRectRow(variant.cropRect)

                            NavigationLink {
                                SmartPhotoCropEditorView(
                                    family: editingFamily,
                                    masterFileName: SmartPhotoSpec.sanitisedFileName(currentFamilyDraft().imageFileName),
                                    targetPixels: SmartPhotoRenderTargets.forCurrentDevice().targetPixels(for: editingFamily),
                                    initialCropRect: variant.cropRect,
                                    focus: $editorFocusSnapshot,
                                    onApply: { rect in
                                        await applyManualSmartCrop(
                                            family: editingFamily,
                                            cropRect: rect
                                        )
                                    }
                                )
                            } label: {
                                Label("Fix framing (\(editingFamily.label))", systemImage: "crop")
                            }
                            .disabled(importInProgress)

                            Text("Tip: Only the Medium render is referenced by older widgets. Save to sync manual crops to your widget.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Smart Photo renders are missing. Rebuild Smart Photo first.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Make Smart Photo first to enable manual framing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Smart Photo Framing")
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

        let onApplyCrop: (_ entryID: String, _ family: EditingFamily, _ rect: NormalisedRect) async -> Void
        let onResetToAuto: (_ entryID: String, _ family: EditingFamily) async -> Void
        let onMakeCurrent: (_ entryID: String) async -> Void

    @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
    private var smartPhotoShuffleUpdateToken: Int = 0

    @AppStorage("preview.liveEnabled")
    private var liveEnabled: Bool = true

    @State private var selectedShuffleEntryID: String = ""
    @State private var isFollowingCurrentEntry: Bool = true

    private var shuffleManifestFileName: String {
        (smart.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let _ = smartPhotoShuffleUpdateToken

        Group {
            if shuffleManifestFileName.isEmpty {
                Text("Album Shuffle is enabled but no manifest file is configured.\nDisable and re-enable Album Shuffle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let manifest = SmartPhotoShuffleManifestStore.load(fileName: shuffleManifestFileName) {
                let prepared = preparedEntries(manifest)

                if prepared.isEmpty {
                    Text("Preparing album shuffle…\nKeep the app open until at least one photo is prepared.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if manifest.rotationIntervalMinutes > 0 {
                    let interval: TimeInterval = liveEnabled ? 5 : 60
                    let start = WidgetWeaverRenderClock.alignedTimelineStartDate(interval: interval)

                    TimelineView(.periodic(from: start, by: interval)) { ctx in
                        WidgetWeaverRenderClock.withNow(ctx.date) {
                            shuffleBody(manifest: manifest, prepared: prepared, manifestFile: shuffleManifestFileName)
                        }
                    }
                } else {
                    shuffleBody(manifest: manifest, prepared: prepared, manifestFile: shuffleManifestFileName)
                }
            } else {
                Text("Album Shuffle manifest could not be loaded.\nTry re-enabling Album Shuffle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            setDefaultSelectionIfNeeded()
        }
        .onChange(of: smartPhotoShuffleUpdateToken) { _, _ in
            setDefaultSelectionIfNeeded()
        }
    }

    @ViewBuilder
    private func shuffleBody(
        manifest: SmartPhotoShuffleManifest,
        prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)],
        manifestFile: String
    ) -> some View {
        let current = resolveCurrentEntry(manifest: manifest, prepared: prepared)
        let selected = resolveDisplayedEntry(current: current, prepared: prepared)

        let selectedPosition = (selected.index + 1)

        let currentPosition: Int = {
            if let current { return current.index + 1 }
            return selectedPosition
        }()

        let canNavigate = prepared.count > 1

        VStack(alignment: .leading, spacing: 10) {
            header(
                selectedPosition: selectedPosition,
                preparedCount: prepared.count,
                currentPosition: currentPosition,
                isFollowing: isFollowingCurrentEntry,
                canNavigate: canNavigate,
                onToggleFollow: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isFollowingCurrentEntry.toggle()
                        if isFollowingCurrentEntry {
                            selectedShuffleEntryID = current?.entry.id ?? selected.entry.id
                        }
                    }
                },
                onPrev: {
                    if isFollowingCurrentEntry {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isFollowingCurrentEntry = false
                        }
                    }
                    selectPrev(prepared: prepared)
                },
                onNext: {
                    if isFollowingCurrentEntry {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isFollowingCurrentEntry = false
                        }
                    }
                    selectNext(prepared: prepared)
                },
                onMakeCurrent: {
                    Task { await onMakeCurrent(selected.entry.id) }
                },
                canMakeCurrent: (selected.entry.id != (current?.entry.id ?? ""))
            )

            SmartPhotoPreviewStripView(
                smart: smart,
                selectedFamily: selectedFamily,
                onSelectFamily: onSelectFamily,
                fixedShuffleEntry: selected.entry
            )

            sizeControls(entry: selected.entry, manifestFile: manifestFile)
        }
    }

    private func header(
        selectedPosition: Int,
        preparedCount: Int,
        currentPosition: Int,
        isFollowing: Bool,
        canNavigate: Bool,
        onToggleFollow: @escaping () -> Void,
        onPrev: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onMakeCurrent: @escaping () -> Void,
        canMakeCurrent: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Selected photo \(selectedPosition) of \(preparedCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button(isFollowing ? "Edit" : "Follow") {
                    onToggleFollow()
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(!canNavigate)
            }

            HStack(spacing: 10) {
                Button {
                    onPrev()
                } label: {
                    Label("Prev", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(!canNavigate)

                Button {
                    onNext()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(!canNavigate)

                Spacer(minLength: 0)

                if !isFollowing {
                    Text("Current widget photo: \(currentPosition) of \(preparedCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if canMakeCurrent {
                        Button("Make current") {
                            onMakeCurrent()
                        }
                        .font(.caption)
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private func sizeControls(entry: SmartPhotoShuffleManifest.Entry, manifestFile: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Manual framing is per photo and per widget size.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            let canEdit = !(entry.sourceFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            VStack(spacing: 8) {
                sizeRow(family: .small, entry: entry, manifestFile: manifestFile, canEdit: canEdit)
                sizeRow(family: .medium, entry: entry, manifestFile: manifestFile, canEdit: canEdit)
                sizeRow(family: .large, entry: entry, manifestFile: manifestFile, canEdit: canEdit)
            }

            if !canEdit {
                Text("This shuffled photo has no saved source image.\nRebuild the Album Shuffle set to enable manual framing.")
                    .font(.caption2)
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
        let sourceFile = (entry.sourceFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let targets = SmartPhotoRenderTargets.forCurrentDevice()
        let targetPixels: PixelSize = {
            switch family {
            case .small: return targets.small
            case .medium: return targets.medium
            case .large: return targets.large
            }
        }()

        let autoRect: NormalisedRect? = {
            switch family {
            case .small: return entry.smallAutoCropRect
            case .medium: return entry.mediumAutoCropRect
            case .large: return entry.largeAutoCropRect
            }
        }()

        let manualRect: NormalisedRect? = {
            switch family {
            case .small: return entry.smallManualCropRect
            case .medium: return entry.mediumManualCropRect
            case .large: return entry.largeManualCropRect
            }
        }()

        let manualFile: String? = {
            switch family {
            case .small: return entry.smallManualFile
            case .medium: return entry.mediumManualFile
            case .large: return entry.largeManualFile
            }
        }()

        let hasManual = !(manualFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let initialRect = (manualRect ?? autoRect ?? NormalisedRect(x: 0, y: 0, width: 1, height: 1)).normalised()

        HStack(spacing: 12) {
            NavigationLink {
                SmartPhotoCropEditorView(
                    family: family,
                    masterFileName: sourceFile,
                    targetPixels: targetPixels,
                    initialCropRect: initialRect,
                    focus: focus,
                    onApply: { rect in
                        await onApplyCrop(entry.id, family, rect)
                    }
                )
            } label: {
                Label("Fix framing (\(family.label))", systemImage: "crop")
            }
            .disabled(isBusy || !canEdit)

            Spacer(minLength: 0)

            if hasManual {
                Text("Manual")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: Capsule())

                Button("Reset") {
                    Task { await onResetToAuto(entry.id, family) }
                }
                .font(.caption)
                .buttonStyle(.borderless)
                .disabled(isBusy)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func preparedEntries(_ manifest: SmartPhotoShuffleManifest) -> [(index: Int, entry: SmartPhotoShuffleManifest.Entry)] {
        manifest.entries
            .enumerated()
            .filter { $0.element.isPrepared }
            .map { (index: $0.offset, entry: $0.element) }
    }

    private func resolveCurrentEntry(
        manifest: SmartPhotoShuffleManifest,
        prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)]
    ) -> (index: Int, entry: SmartPhotoShuffleManifest.Entry)? {
        guard let current = manifest.entryForRender() else { return nil }

        if let direct = prepared.first(where: { $0.entry.id == current.id }) { return direct }

        let preparedIndices = Set(prepared.map(\.index))
        if preparedIndices.contains(manifest.currentIndex),
           let byIndex = prepared.first(where: { $0.index == manifest.currentIndex })
        {
            return byIndex
        }

        return prepared.first
    }

    private func resolveDisplayedEntry(
        current: (index: Int, entry: SmartPhotoShuffleManifest.Entry)?,
        prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)]
    ) -> (index: Int, entry: SmartPhotoShuffleManifest.Entry) {
        if isFollowingCurrentEntry {
            if let current { return current }
            return prepared.first!
        }

        let id = selectedShuffleEntryID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty, let match = prepared.first(where: { $0.entry.id == id }) {
            return match
        }

        if let current { return current }
        return prepared.first!
    }

    private func setDefaultSelectionIfNeeded() {
        guard isFollowingCurrentEntry else { return }
        guard shuffleManifestFileName.isEmpty == false else { return }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: shuffleManifestFileName) else { return }
        guard let current = manifest.entryForRender() else { return }

        if selectedShuffleEntryID.isEmpty {
            selectedShuffleEntryID = current.id
            return
        }

        if selectedShuffleEntryID != current.id {
            selectedShuffleEntryID = current.id
        }
    }

    private func selectPrev(prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)]) {
        guard !prepared.isEmpty else { return }

        let currentID = selectedShuffleEntryID.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentIdx = prepared.firstIndex(where: { $0.entry.id == currentID }) ?? 0

        let prev = (currentIdx - 1 + prepared.count) % prepared.count
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedShuffleEntryID = prepared[prev].entry.id
        }
    }

    private func selectNext(prepared: [(index: Int, entry: SmartPhotoShuffleManifest.Entry)]) {
        guard !prepared.isEmpty else { return }

        let currentID = selectedShuffleEntryID.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentIdx = prepared.firstIndex(where: { $0.entry.id == currentID }) ?? 0

        let next = (currentIdx + 1) % prepared.count
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedShuffleEntryID = prepared[next].entry.id
        }
    }
}

private extension SmartPhotoRenderTargets {
    func targetPixels(for family: EditingFamily) -> PixelSize {
        switch family {
        case .small: return small
        case .medium: return medium
        case .large: return large
        }
    }
}
