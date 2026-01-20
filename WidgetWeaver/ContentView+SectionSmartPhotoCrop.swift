//
//  ContentView+SectionSmartPhotoCrop.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import SwiftUI
import WidgetKit
import UIKit

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
                        onApplyCrop: { entryID, fam, cropRect, straightenDegrees in
                            await applyManualSmartCropForShuffleEntryWithStraighten(
                                manifestFileName: manifestFileName,
                                entryID: entryID,
                                family: fam,
                                cropRect: cropRect,
                                straightenDegrees: straightenDegrees
                            )
                        },
                        onResetToAuto: { entryID, fam in
                            await resetManualSmartCropForShuffleEntryWithStraighten(
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
                    SmartPhotoSingleFramingEditorView(
                        smart: smart,
                        selectedFamily: editingFamily,
                        isBusy: importInProgress,
                        onSelectFamily: { fam in
                            previewFamily = widgetFamily(for: fam)
                        },
                        onApplyCrop: { fam, cropRect, straightenDegrees in
                            await applyManualSmartCropWithStraighten(
                                family: fam,
                                cropRect: cropRect,
                                straightenDegrees: straightenDegrees
                            )
                        }
                    )
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

private struct SmartPhotoSingleFramingEditorView: View {
    private struct CropRoute: Identifiable {
        var family: EditingFamily
        var masterFileName: String
        var targetPixels: PixelSize
        var initialCropRect: NormalisedRect
        var initialStraightenDegrees: Double

        var id: String { family.rawValue }
    }

    let smart: SmartPhotoSpec
    let selectedFamily: EditingFamily
    let isBusy: Bool

    let onSelectFamily: (EditingFamily) -> Void
    let onApplyCrop: (EditingFamily, NormalisedRect, Double) async -> Void

    @State private var activeCropRoute: CropRoute?
    @State private var showOtherSizes: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SmartPhotoPreviewStripView(
                smart: smart,
                selectedFamily: selectedFamily,
                onSelectFamily: onSelectFamily,
                fixedShuffleEntry: nil
            )

            sizeControls

            Text("Applies to this single photo. To revert to automatic framing for all sizes, use “Regenerate smart renders” in Smart Photo.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .fullScreenCover(item: $activeCropRoute) { route in
            NavigationStack {
                SmartPhotoCropEditorView(
                    family: route.family,
                    masterFileName: route.masterFileName,
                    targetPixels: route.targetPixels,
                    initialCropRect: route.initialCropRect,
                    initialStraightenDegrees: route.initialStraightenDegrees,
                    autoCropRect: nil,
                    focus: nil,
                    onResetToAuto: nil,
                    onApply: { rect, straightenDegrees in
                        await onApplyCrop(route.family, rect, straightenDegrees)
                    }
                )
                .id("cropSheet-single-\(route.family.rawValue)")
            }
        }
    }

    private var sizeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sizeRow(family: selectedFamily)

            DisclosureGroup(isExpanded: $showOtherSizes) {
                ForEach(EditingFamily.allCases.filter { $0 != selectedFamily }, id: \.rawValue) { family in
                    sizeRow(family: family)
                }
            } label: {
                Text("Other sizes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func variant(for family: EditingFamily) -> SmartPhotoVariantSpec? {
        switch family {
        case .small: return smart.small
        case .medium: return smart.medium
        case .large: return smart.large
        }
    }

    private func cropRoute(for family: EditingFamily) -> CropRoute? {
        guard let variant = variant(for: family) else { return nil }

        let master = smart.masterFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !master.isEmpty else { return nil }

        return CropRoute(
            family: family,
            masterFileName: master,
            targetPixels: variant.pixelSize.normalised(),
            initialCropRect: variant.cropRect.normalised(),
            initialStraightenDegrees: variant.straightenDegrees ?? 0
        )
    }

    @ViewBuilder
    private func sizeRow(family: EditingFamily) -> some View {
        let route = cropRoute(for: family)

        HStack(alignment: .center, spacing: 12) {
            Button {
                activeCropRoute = route
            } label: {
                Label("Fix framing (\(family.label))", systemImage: "crop")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .id("singleCropButton-\(family.rawValue)")
            .disabled(isBusy || route == nil)
        }
        .id("singleSizeRow-\(family.rawValue)")
    }
}


private struct SmartPhotoShuffleFramingEditorView: View {
    private enum SelectionMode: String, CaseIterable {
        case current
        case browse
    }

    private struct CropRoute: Identifiable {
        var entryID: String
        var family: EditingFamily
        var masterFileName: String
        var targetPixels: PixelSize
        var initialCropRect: NormalisedRect
        var initialStraightenDegrees: Double
        var autoCropRect: NormalisedRect?

        var id: String { "\(entryID)-\(family.rawValue)" }
    }

    let smart: SmartPhotoSpec
    let manifestFileName: String
    let selectedFamily: EditingFamily
    let focus: Binding<EditorFocusSnapshot>
    let isBusy: Bool

    let onSelectFamily: (EditingFamily) -> Void
    let onApplyCrop: (String, EditingFamily, NormalisedRect, Double) async -> Void
    let onResetToAuto: (String, EditingFamily) async -> Void
    let onMakeCurrent: (String) async -> Void

    @AppStorage(SmartPhotoShuffleManifestStore.updateTokenKey, store: AppGroup.userDefaults)
    private var smartPhotoShuffleUpdateToken: Int = 0

    @AppStorage("preview.liveEnabled")
    private var liveEnabled: Bool = true

    @State private var selectionMode: SelectionMode = .current
    @State private var selectedShuffleEntryID: String?

    @State private var activeCropRoute: CropRoute?

    @State private var showOtherSizes: Bool = false
    @State private var lastFocusDrivenEntryID: String?

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
                .task {
                    setDefaultSelectionIfNeeded()
                    applySelectionFromFocusIfNeeded()
                }
                .onChange(of: smartPhotoShuffleUpdateToken) { _, _ in
                    setDefaultSelectionIfNeeded()
                }
                .onChange(of: selectionMode) { _, newValue in
                    guard newValue == .browse else { return }
                    snapBrowseSelectionToCurrentIfPossible()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    shuffleBody(manifestFile: trimmedManifestFile)
                }
                .task {
                    setDefaultSelectionIfNeeded()
                    applySelectionFromFocusIfNeeded()
                }
                .onChange(of: smartPhotoShuffleUpdateToken) { _, _ in
                    setDefaultSelectionIfNeeded()
                }
                .onChange(of: selectionMode) { _, newValue in
                    guard newValue == .browse else { return }
                    snapBrowseSelectionToCurrentIfPossible()
                }
            }
        }
        .onChange(of: focus.wrappedValue.focus) { _, _ in
            applySelectionFromFocusIfNeeded()
        }
        .fullScreenCover(item: $activeCropRoute) { route in
            NavigationStack {
                SmartPhotoCropEditorView(
                    family: route.family,
                    masterFileName: route.masterFileName,
                    targetPixels: route.targetPixels,
                    initialCropRect: route.initialCropRect,
                    initialStraightenDegrees: route.initialStraightenDegrees,
                    autoCropRect: route.autoCropRect,
                    focus: nil,
                    onResetToAuto: {
                        await onResetToAuto(route.entryID, route.family)
                    },
                    onApply: { rect, straightenDegrees in
                        await onApplyCrop(route.entryID, route.family, rect, straightenDegrees)
                    }
                )
                .id("cropSheet-\(route.entryID)-\(route.family.rawValue)")
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
                let now = WidgetWeaverRenderClock.now
                let sameDay = Calendar.current.isDate(next, inSameDayAs: now)
                Text("Next change: \(next.formatted(date: sameDay ? .omitted : .abbreviated, time: .shortened))")
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
        let canEdit = entryHasSource(entry: entry)

        return VStack(alignment: .leading, spacing: 10) {
            sizeRow(family: selectedFamily, entry: entry, canEdit: canEdit)

            DisclosureGroup(isExpanded: $showOtherSizes) {
                ForEach(EditingFamily.allCases.filter { $0 != selectedFamily }, id: \.rawValue) { family in
                    sizeRow(family: family, entry: entry, canEdit: canEdit)
                }
            } label: {
                Text("Other sizes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !canEdit {
                Text("Source image for this shuffled photo is missing.\nRe-prepare this album shuffle set to enable manual framing.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cropRoute(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> CropRoute {
        CropRoute(
            entryID: entry.id,
            family: family,
            masterFileName: (entry.sourceFileName ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            targetPixels: targetPixels(for: family),
            initialCropRect: initialCropRect(for: family, entry: entry),
            initialStraightenDegrees: initialStraightenDegrees(for: family, entry: entry),
            autoCropRect: autoCropRect(for: family, entry: entry)
        )
    }

    @ViewBuilder
    private func sizeRow(
        family: EditingFamily,
        entry: SmartPhotoShuffleManifest.Entry,
        canEdit: Bool
    ) -> some View {
        let hasManual = entryHasManual(for: family, entry: entry)
        let route = cropRoute(for: family, entry: entry)

        HStack(alignment: .center, spacing: 12) {
            Button {
                activeCropRoute = route
            } label: {
                Label("Fix framing (\(family.label))", systemImage: "crop")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .id("cropButton-\(entry.id)-\(family.rawValue)")
            .disabled(isBusy || !canEdit)

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
        .id("sizeRow-\(entry.id)-\(family.rawValue)")
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

    private func applySelectionFromFocusIfNeeded() {
        guard case .albumPhoto(_, let itemID, let subtype) = focus.wrappedValue.focus else { return }
        guard subtype == .smart else { return }

        let trimmed = itemID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if lastFocusDrivenEntryID == trimmed {
            return
        }

        lastFocusDrivenEntryID = trimmed
        selectedShuffleEntryID = trimmed

        // Auto-switch into Browse when the selected focus does not match the current render entry.
        // This avoids flipping the segmented control when editing the already-current entry.
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mf.isEmpty,
           let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf),
           let current = manifest.entryForRender(),
           current.id == trimmed
        {
            return
        }

        selectionMode = .browse
    }

    private func snapBrowseSelectionToCurrentIfPossible() {
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mf.isEmpty else { return }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return }

        let prepared = preparedEntries(manifest)
        guard !prepared.isEmpty else { return }

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

    private func autoCropRect(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> NormalisedRect? {
        switch family {
        case .small:
            return entry.smallAutoCropRect?.normalised()
        case .medium:
            return entry.mediumAutoCropRect?.normalised()
        case .large:
            return entry.largeAutoCropRect?.normalised()
        }
    }


    private func initialStraightenDegrees(for family: EditingFamily, entry: SmartPhotoShuffleManifest.Entry) -> Double {
        let fallback: Double = 0

        switch family {
        case .small:
            return entry.smallManualStraightenDegrees ?? fallback
        case .medium:
            return entry.mediumManualStraightenDegrees ?? fallback
        case .large:
            return entry.largeManualStraightenDegrees ?? fallback
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


// MARK: - Manual framing: straightening + fine controls

extension ContentView {
    func applyManualSmartCropWithStraighten(
        family: EditingFamily,
        cropRect: NormalisedRect,
        straightenDegrees: Double
    ) async {
        let newCrop = cropRect.normalised()
        let straighten = SmartPhotoManualCropRenderer.normalisedStraightenDegrees(straightenDegrees)

        var d = currentFamilyDraft()
        guard var smart = d.imageSmartPhoto else {
            saveStatusMessage = "Smart Photo data missing."
            return
        }

        let existingVariant: SmartPhotoVariantSpec
        switch family {
        case .small:
            existingVariant = smart.small
        case .medium:
            existingVariant = smart.medium
        case .large:
            existingVariant = smart.large
        }

        let masterFileName = smart.masterFileName
        let targetPixels = existingVariant.pixelSize.normalised()

        guard let masterURL = AppGroup.containerURL?.appendingPathComponent(masterFileName) else {
            saveStatusMessage = "Smart master file missing.\nTry “Regenerate smart renders”."
            return
        }

        let masterData: Data
        do {
            masterData = try Data(contentsOf: masterURL)
        } catch {
            saveStatusMessage = "Smart master file missing.\nTry “Regenerate smart renders”."
            return
        }

        Task.detached(priority: .userInitiated) {
            do {
                guard let masterImage = UIImage(data: masterData) else {
                    throw SmartPhotoManualTransformError.masterDecodeFailed
                }

                let rendered = SmartPhotoManualCropRenderer.render(
                    master: masterImage,
                    cropRect: newCrop,
                    straightenDegrees: straighten ?? 0,
                    targetPixels: targetPixels
                )

                let jpeg = try SmartPhotoManualCropRenderer.encodeJPEG(
                    image: rendered,
                    quality: 0.92
                )

                let newRenderFileName = "smart_\(UUID().uuidString).jpg"
                guard let renderURL = AppGroup.containerURL?.appendingPathComponent(newRenderFileName) else {
                    throw SmartPhotoManualTransformError.renderWriteFailed
                }

                try jpeg.write(to: renderURL, options: .atomic)

                if let oldURL = AppGroup.containerURL?.appendingPathComponent(existingVariant.renderFileName) {
                    try? FileManager.default.removeItem(at: oldURL)
                }

                await MainActor.run {
                    var updated = existingVariant
                    updated.cropRect = newCrop
                    updated.renderFileName = newRenderFileName
                    updated.straightenDegrees = straighten

                    switch family {
                    case .small:
                        smart.small = updated
                    case .medium:
                        smart.medium = updated
                    case .large:
                        smart.large = updated
                    }

                    smart.preparedAt = Date()
                    smart = smart.normalised()

                    d.imageSmartPhoto = smart
                    if family == .medium {
                        d.imageFileName = newRenderFileName
                    }

                    setCurrentFamilyDraft(d)
                    saveStatusMessage = "Updated \(family.label) framing (draft only).\nSave to update widgets."
                }
            } catch {
                await MainActor.run {
                    saveStatusMessage = error.localizedDescription
                }
            }
        }
    }

    func applyManualSmartCropForShuffleEntryWithStraighten(
        manifestFileName: String,
        entryID: String,
        family: EditingFamily,
        cropRect: NormalisedRect,
        straightenDegrees: Double
    ) async {
        let newCrop = cropRect.normalised()
        let straighten = SmartPhotoManualCropRenderer.normalisedStraightenDegrees(straightenDegrees)

        let store = SmartPhotoShuffleManifestStore(manifestFileName: manifestFileName)

        guard var manifest = store.load() else {
            saveStatusMessage = "Shuffle manifest could not be loaded."
            return
        }

        guard var entry = manifest.entries.first(where: { $0.id == entryID }) else {
            saveStatusMessage = "Shuffle entry not found."
            return
        }

        guard entry.isPrepared else {
            saveStatusMessage = "This photo has not been prepared yet."
            return
        }

        guard let masterFileName = entry.sourceImageFileName else {
            saveStatusMessage = "Source image is missing for this shuffled photo.\nRe-prepare this album shuffle set to enable manual framing."
            return
        }

        guard let masterURL = AppGroup.containerURL?.appendingPathComponent(masterFileName) else {
            saveStatusMessage = "Source image file not found on disk.\nRe-prepare this album shuffle set to enable manual framing."
            return
        }

        let masterData: Data
        do {
            masterData = try Data(contentsOf: masterURL)
        } catch {
            saveStatusMessage = "Source image file not found on disk.\nRe-prepare this album shuffle set to enable manual framing."
            return
        }

        let oldManualFileName: String?
        let targetPixels: PixelSize

        switch family {
        case .small:
            oldManualFileName = entry.smallManualFileName
            targetPixels = entry.smallPixelSize
        case .medium:
            oldManualFileName = entry.mediumManualFileName
            targetPixels = entry.mediumPixelSize
        case .large:
            oldManualFileName = entry.largeManualFileName
            targetPixels = entry.largePixelSize
        }

        Task.detached(priority: .userInitiated) {
            do {
                guard let masterImage = UIImage(data: masterData) else {
                    throw SmartPhotoManualTransformError.masterDecodeFailed
                }

                let rendered = SmartPhotoManualCropRenderer.render(
                    master: masterImage,
                    cropRect: newCrop,
                    straightenDegrees: straighten ?? 0,
                    targetPixels: targetPixels.normalised()
                )

                let jpeg = try SmartPhotoManualCropRenderer.encodeJPEG(
                    image: rendered,
                    quality: 0.92
                )

                let newRenderFileName = "smartshuffle_\(UUID().uuidString).jpg"
                guard let renderURL = AppGroup.containerURL?.appendingPathComponent(newRenderFileName) else {
                    throw SmartPhotoManualTransformError.renderWriteFailed
                }

                try jpeg.write(to: renderURL, options: .atomic)

                if let old = oldManualFileName,
                   let oldURL = AppGroup.containerURL?.appendingPathComponent(old)
                {
                    try? FileManager.default.removeItem(at: oldURL)
                }

                await MainActor.run {
                    var updated = entry

                    switch family {
                    case .small:
                        updated.smallManualFileName = newRenderFileName
                        updated.smallManualCropRect = newCrop
                        updated.smallManualStraightenDegrees = straighten
                    case .medium:
                        updated.mediumManualFileName = newRenderFileName
                        updated.mediumManualCropRect = newCrop
                        updated.mediumManualStraightenDegrees = straighten
                    case .large:
                        updated.largeManualFileName = newRenderFileName
                        updated.largeManualCropRect = newCrop
                        updated.largeManualStraightenDegrees = straighten
                    }

                    if let idx = manifest.entries.firstIndex(where: { $0.id == entryID }) {
                        manifest.entries[idx] = updated
                    }

                    store.save(manifest)
                    saveStatusMessage = "Updated \(family.label) framing."
                }
            } catch {
                await MainActor.run {
                    saveStatusMessage = error.localizedDescription
                }
            }
        }
    }

    func resetManualSmartCropForShuffleEntryWithStraighten(
        manifestFileName: String,
        entryID: String,
        family: EditingFamily
    ) async {
        let store = SmartPhotoShuffleManifestStore(manifestFileName: manifestFileName)

        guard var manifest = store.load() else {
            saveStatusMessage = "Shuffle manifest could not be loaded."
            return
        }

        guard let idx = manifest.entries.firstIndex(where: { $0.id == entryID }) else {
            saveStatusMessage = "Shuffle entry not found."
            return
        }

        var entry = manifest.entries[idx]

        let oldManualFileName: String?
        switch family {
        case .small:
            oldManualFileName = entry.smallManualFileName
            entry.smallManualFileName = nil
            entry.smallManualCropRect = nil
            entry.smallManualStraightenDegrees = nil
        case .medium:
            oldManualFileName = entry.mediumManualFileName
            entry.mediumManualFileName = nil
            entry.mediumManualCropRect = nil
            entry.mediumManualStraightenDegrees = nil
        case .large:
            oldManualFileName = entry.largeManualFileName
            entry.largeManualFileName = nil
            entry.largeManualCropRect = nil
            entry.largeManualStraightenDegrees = nil
        }

        manifest.entries[idx] = entry
        store.save(manifest)

        if let old = oldManualFileName,
           let url = AppGroup.containerURL?.appendingPathComponent(old)
        {
            try? FileManager.default.removeItem(at: url)
        }

        saveStatusMessage = "Reset \(family.label) framing to auto."
    }
}

private enum SmartPhotoManualTransformError: LocalizedError {
    case masterDecodeFailed
    case renderWriteFailed
    case jpegEncodeFailed

    var errorDescription: String? {
        switch self {
        case .masterDecodeFailed:
            return "Could not decode the source image."
        case .renderWriteFailed:
            return "Could not write the rendered image."
        case .jpegEncodeFailed:
            return "Could not encode the rendered image."
        }
    }
}

private enum SmartPhotoManualCropRenderer {
    static func normalisedStraightenDegrees(_ degrees: Double) -> Double? {
        let clamped = degrees.clamped(to: -45...45)
        if abs(clamped) < 0.0001 { return nil }
        return clamped
    }

    static func render(
        master: UIImage,
        cropRect: NormalisedRect,
        straightenDegrees: Double,
        targetPixels: PixelSize
    ) -> UIImage {
        let base = master.ww_normalisedOrientation()
        guard let sourceCg = base.cgImage else { return base }

        let rotatedCg: CGImage
        if abs(straightenDegrees) < 0.0001 {
            rotatedCg = sourceCg
        } else {
            rotatedCg = rotateCGImageWithinBounds(sourceCg, degrees: straightenDegrees) ?? sourceCg
        }

        let w = rotatedCg.width
        let h = rotatedCg.height

        let cropPixels = CGRect(
            x: CGFloat(cropRect.x) * CGFloat(w),
            y: CGFloat(cropRect.y) * CGFloat(h),
            width: CGFloat(cropRect.width) * CGFloat(w),
            height: CGFloat(cropRect.height) * CGFloat(h)
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: w, height: h))

        let cropped = rotatedCg.cropping(to: cropPixels) ?? rotatedCg

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let targetSize = CGSize(width: targetPixels.width, height: targetPixels.height)
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)

        return renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))

            ctx.cgContext.draw(cropped, in: CGRect(origin: .zero, size: targetSize))
        }
    }

    static func encodeJPEG(image: UIImage, quality: CGFloat) throws -> Data {
        let q = max(0.1, min(0.95, quality))

        guard let data = image.jpegData(compressionQuality: q), !data.isEmpty else {
            throw SmartPhotoManualTransformError.jpegEncodeFailed
        }

        return data
    }

    private static func rotateCGImageWithinBounds(_ cgImage: CGImage, degrees: Double) -> CGImage? {
        let radians = CGFloat(degrees * Double.pi / 180.0)
        let w = cgImage.width
        let h = cgImage.height

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let img = renderer.image { ctx in
            ctx.cgContext.interpolationQuality = .high
            UIColor.black.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

            ctx.cgContext.translateBy(x: CGFloat(w) / 2.0, y: CGFloat(h) / 2.0)
            ctx.cgContext.rotate(by: radians)
            ctx.cgContext.translateBy(x: -CGFloat(w) / 2.0, y: -CGFloat(h) / 2.0)

            ctx.cgContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        }

        return img.cgImage
    }
}

private extension UIImage {
    func ww_normalisedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let sizePixels = CGSize(
            width: (size.width * scale).rounded(),
            height: (size.height * scale).rounded()
        )

        let renderer = UIGraphicsImageRenderer(size: sizePixels, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: sizePixels))
        }
    }
}
