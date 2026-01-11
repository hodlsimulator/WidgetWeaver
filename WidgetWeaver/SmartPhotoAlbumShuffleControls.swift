//
//  SmartPhotoAlbumShuffleControls.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation
import SwiftUI
import WidgetKit

/// App-only progressive processing for Smart Photo album shuffle.
///
/// Rules:
/// - App does all heavy work (Photos fetch, rendering, scoring).
/// - Widget reads manifest + loads exactly one pre-rendered file.
struct SmartPhotoAlbumShuffleControls: View {
    @Binding var smartPhoto: SmartPhotoSpec?
    @Binding var importInProgress: Bool
    @Binding var saveStatusMessage: String

    var focus: Binding<EditorFocusSnapshot>? = nil

    var albumPickerPresented: Binding<Bool>? = nil

    private let batchSize: Int = 10
    private let rotationOptionsMinutes: [Int] = [0, 15, 30, 60, 180, 360, 720, 1440]

    @State private var internalAlbumPickerPresented: Bool = false
    @State private var previousFocusSnapshot: EditorFocusSnapshot?
    @State private var albumPickerState: AlbumPickerState = .idle
    @State private var albums: [AlbumOption] = []

    @State private var progress: ProgressSummary?
    @State private var rankingRows: [RankingRow] = []
    @State private var rankingAlbumID: String? = nil

    @State private var rotationIntervalMinutes: Int = 60
    @State private var nextChangeDate: Date?

    private enum AlbumPickerState: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    struct AlbumOption: Identifiable, Hashable {
        let id: String
        let title: String
        let count: Int
    }

    struct ProgressSummary: Hashable {
        let total: Int
        let prepared: Int
        let failed: Int
        let currentIndex: Int
        let currentIsPrepared: Bool
    }

    struct RankingRow: Identifiable, Hashable {
        var id: String { localIdentifier }
        let localIdentifier: String
        let preparedAt: Date?
        let score: Double?
        let flags: [String]
    }

    private enum PrepError: Error {
        case missingSmartPhoto
        case missingVariants
    }

    private var albumPickerPresentedBinding: Binding<Bool> {
        if let albumPickerPresented {
            return albumPickerPresented
        }
        return $internalAlbumPickerPresented
    }

    private var isShuffleEnabled: Bool {
        !manifestFileName.isEmpty
    }

    private var manifestFileName: String {
        smartPhoto?.shuffleManifestFileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var progressLabel: String {
        guard let p = progress else { return "—" }
        let preparedLabel = "\(p.prepared)/\(p.total)"
        if p.failed > 0 {
            return "\(preparedLabel) prepared • \(p.failed) failed"
        }
        return "\(preparedLabel) prepared"
    }

    private var rotationPickerSelection: Binding<Int> {
        Binding(
            get: { rotationIntervalMinutes },
            set: { minutes in
                Task { await setRotationInterval(minutes: minutes) }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Album Shuffle", isOn: Binding(
                    get: { isShuffleEnabled },
                    set: { enabled in
                        if enabled {
                            albumPickerPresentedBinding.wrappedValue = true
                        } else {
                            disableShuffle()
                        }
                    }
                ))
                .disabled(importInProgress)
            } footer: {
                Text("Album Shuffle cycles through photos from an album.\nThe widget uses prepared renders for performance.")
            }

            if isShuffleEnabled {
                Section {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(progressLabel)
                            .foregroundStyle(.secondary)
                    }

                    if let nextChangeDate {
                        HStack {
                            Text("Next change")
                            Spacer()
                            Text(nextChangeDate.formatted(date: .omitted, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Rotation", selection: rotationPickerSelection) {
                        ForEach(rotationOptionsMinutes, id: \.self) { minutes in
                            Text(rotationLabel(minutes: minutes)).tag(minutes)
                        }
                    }
                    .disabled(importInProgress)

                    Button {
                        Task { await advanceToNextPrepared() }
                    } label: {
                        Label("Advance to next prepared", systemImage: "forward.end")
                    }
                    .disabled(importInProgress)

                    Button {
                        Task { await prepareNextBatch(alreadyBusy: false) }
                    } label: {
                        Label("Prepare next \(batchSize)", systemImage: "sparkles")
                    }
                    .disabled(importInProgress)

                    Menu {
                        Button {
                            WidgetWeaverWidgetRefresh.forceKick()
                            saveStatusMessage = "Forced widget refresh kick."
                        } label: {
                            Label("Force widget refresh kick", systemImage: "arrow.clockwise")
                        }

                        Button {
                            Task { await refreshFromManifest() }
                        } label: {
                            Label("Refresh from manifest", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } label: {
                        Label("Advanced", systemImage: "gear")
                    }
                    .disabled(importInProgress)
                } header: {
                    Text("Progress")
                }

                Section {
                    rankingDebugMenu
                } header: {
                    Text("Ranking")
                } footer: {
                    Text("Prepared photos are sorted by score.\nHigher scores are more likely to appear.")
                }
            }
        }
        .navigationTitle("Album Shuffle")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: albumPickerPresentedBinding) {
            NavigationStack {
                albumPickerView
                    .navigationTitle("Choose Album")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                albumPickerPresentedBinding.wrappedValue = false
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .onAppear { handleAlbumPickerPresentationChange(isPresented: true) }
            .onDisappear { handleAlbumPickerPresentationChange(isPresented: false) }
            .task {
                await loadAlbumsIfNeeded()
            }
        }
        .task {
            await refreshFromManifest()
        }
    }

    private var albumPickerView: some View {
        Group {
            switch albumPickerState {
            case .idle, .loading:
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .failed(let message):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .ready:
                List(albums) { album in
                    Button {
                        Task { await configureShuffle(album: album) }
                    } label: {
                        HStack {
                            Text(album.title)
                            Spacer()
                            Text("\(album.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(importInProgress)
                }
            }
        }
    }

    private var rankingDebugMenu: some View {
        Menu {
            if rankingRows.isEmpty {
                Text("No ranking rows yet.")
            } else {
                ForEach(Array(rankingRows.enumerated()), id: \.offset) { idx, row in
                    Button {
                        UIPasteboard.general.string = row.localIdentifier
                        saveStatusMessage = "Copied asset id."
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Score: \(row.score.map { String(format: "%.3f", $0) } ?? "—")")
                                .font(.caption)
                            Text(row.localIdentifier)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("AlbumShuffle.RankingRow.\(idx)")
                }
            }
        } label: {
            Text("Ranking debug")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Album picker

    private func handleAlbumPickerPresentationChange(isPresented: Bool) {
        guard let focus else { return }

        let pickerTarget: EditorFocusTarget = .albumContainer(
            id: "smartPhotoAlbumPicker",
            subtype: .smart
        )

        if isPresented {
            if previousFocusSnapshot == nil {
                previousFocusSnapshot = focus.wrappedValue
            }

            focus.wrappedValue = .smartAlbumContainer(id: "smartPhotoAlbumPicker")
        } else {
            guard let previous = previousFocusSnapshot else { return }
            defer { previousFocusSnapshot = nil }

            if focus.wrappedValue.focus == pickerTarget {
                focus.wrappedValue = previous
            }
        }
    }

    private func loadAlbumsIfNeeded() async {
        if case .ready = albumPickerState, !albums.isEmpty { return }

        albumPickerState = .loading
        albums = []

        let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
        guard ok else {
            albumPickerState = .failed("Photo library access is off.\nEnable access in Settings to use album shuffle.")
            return
        }

        let result = SmartPhotoAlbumShuffleControlsEngine.fetchAlbumOptions()

        await MainActor.run {
            self.albums = result
            self.albumPickerState = result.isEmpty ? .failed("No albums found.") : .ready
        }
    }

    // MARK: - Configure

    private func configureShuffle(album: AlbumOption) async {
        guard var sp = smartPhoto else {
            saveStatusMessage = "Make Smart Photo first."
            return
        }

        importInProgress = true
        defer { importInProgress = false }

        let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
        guard ok else {
            saveStatusMessage = "Photo library access is off."
            return
        }

        saveStatusMessage = "Building album list…"

        let manifestFile = SmartPhotoShuffleManifestStore.createManifestFileName(prefix: "smart-shuffle", ext: "json")

        let assetIDs = SmartPhotoAlbumShuffleControlsEngine.fetchImageAssetIdentifiers(albumID: album.id)

        if assetIDs.isEmpty {
            saveStatusMessage = "No usable images found in \(album.title).\nScreenshots and very low-res images are ignored."
            return
        }

        let defaultRotationMinutes: Int = 60
        let next = scheduledNextChangeDate(from: Date(), minutes: defaultRotationMinutes)

        let manifest = SmartPhotoShuffleManifest(
            version: 3,
            sourceID: album.id,
            entries: assetIDs.map { SmartPhotoShuffleManifest.Entry(id: $0) },
            currentIndex: 0,
            rotationIntervalMinutes: defaultRotationMinutes,
            nextChangeDate: next
        )

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: manifestFile)
        } catch {
            saveStatusMessage = "Failed to save shuffle manifest: \(error.localizedDescription)"
            return
        }

        sp.shuffleManifestFileName = manifestFile
        smartPhoto = sp

        albumPickerPresentedBinding.wrappedValue = false
        albumPickerState = .idle

        WidgetWeaverWidgetRefresh.forceKick()

        saveStatusMessage = "Album shuffle configured for “\(album.title)” (\(assetIDs.count) photos).\nPreparing next \(batchSize)…"

        await refreshFromManifest()
        await prepareNextBatch(alreadyBusy: true)
    }

    private func disableShuffle() {
        guard var sp = smartPhoto else { return }
        sp.shuffleManifestFileName = nil
        smartPhoto = sp

        progress = nil
        rankingRows = []
        nextChangeDate = nil
        rotationIntervalMinutes = 60

        saveStatusMessage = "Album shuffle disabled (draft only).\nSave to update widgets."
    }

    // MARK: - Rotation

    private func setRotationInterval(minutes: Int) async {
        let mf = manifestFileName
        guard !mf.isEmpty else { return }

        importInProgress = true
        defer { importInProgress = false }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            saveStatusMessage = "Shuffle manifest not found."
            return
        }

        let now = Date()
        _ = manifest.catchUpRotation(now: now)

        manifest.rotationIntervalMinutes = minutes
        if minutes > 0 {
            manifest.nextChangeDate = scheduledNextChangeDate(from: now, minutes: minutes)
        } else {
            manifest.nextChangeDate = nil
        }

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
        } catch {
            saveStatusMessage = "Failed to update rotation: \(error.localizedDescription)"
            return
        }

        WidgetWeaverWidgetRefresh.forceKick()
        await refreshFromManifest()

        if minutes <= 0 {
            saveStatusMessage = "Rotation turned off (manual only).\nSave to update widgets."
        } else if let next = manifest.nextChangeDateFrom(now: Date()) ?? manifest.nextChangeDate {
            saveStatusMessage = "Rotation set to \(rotationLabel(minutes: minutes)). Next change at \(next.formatted(date: .omitted, time: .shortened)).\nSave to update widgets."
        } else {
            saveStatusMessage = "Rotation updated.\nSave to update widgets."
        }
    }

    private func rotationLabel(minutes: Int) -> String {
        if minutes <= 0 { return "Off" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes % 60 == 0 {
            let hours = minutes / 60
            if hours == 24 { return "1d" }
            if hours > 24, hours % 24 == 0 { return "\(hours / 24)d" }
            return "\(hours)h"
        }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }

    private func scheduledNextChangeDate(from now: Date, minutes: Int) -> Date {
        let safeMinutes = max(1, minutes)
        let raw = now.addingTimeInterval(TimeInterval(safeMinutes) * 60.0)
        let cal = Calendar.current
        return cal.date(bySetting: .second, value: 0, of: raw) ?? raw
    }

    // MARK: - Manual advance

    private func advanceToNextPrepared() async {
        let mf = manifestFileName
        guard !mf.isEmpty else { return }

        importInProgress = true
        defer { importInProgress = false }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            saveStatusMessage = "Shuffle manifest not found."
            return
        }

        let total = manifest.entries.count
        guard total > 0 else {
            saveStatusMessage = "No photos in the shuffle manifest."
            return
        }

        let start = max(0, min(manifest.currentIndex, total - 1))

        var nextIndex: Int?
        for step in 1...total {
            let idx = (start + step) % total
            if manifest.entries[idx].isPrepared {
                nextIndex = idx
                break
            }
        }

        guard let nextIndex else {
            saveStatusMessage = "No prepared photos yet.\nTap “Prepare next \(batchSize)” first."
            return
        }

        manifest.currentIndex = nextIndex

        if manifest.rotationIntervalMinutes > 0 {
            manifest.nextChangeDate = scheduledNextChangeDate(from: Date(), minutes: manifest.rotationIntervalMinutes)
        }

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
        } catch {
            saveStatusMessage = "Failed to update shuffle index: \(error.localizedDescription)"
            return
        }

        WidgetWeaverWidgetRefresh.forceKick()
        await refreshFromManifest()
        saveStatusMessage = "Advanced to next prepared photo (index \(nextIndex)).\nSave to update widgets."
    }

    // MARK: - Progressive prep

    private func prepareNextBatch(alreadyBusy: Bool) async {
        let mf = manifestFileName
        guard !mf.isEmpty else { return }

        if !alreadyBusy {
            importInProgress = true
        }
        defer {
            if !alreadyBusy { importInProgress = false }
        }

        let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
        guard ok else {
            saveStatusMessage = "Photo library access is off."
            return
        }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            saveStatusMessage = "Shuffle manifest not found."
            return
        }

        let now = Date()
        if manifest.catchUpRotation(now: now) {
            try? SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
        }

        let targets = SmartPhotoRenderTargets.forCurrentDevice()

        var preparedNow = 0
        var failedNow = 0

        for idx in manifest.entries.indices {
            if preparedNow >= batchSize { break }

            var entry = manifest.entries[idx]
            if entry.isPrepared { continue }
            if entry.flags.contains("failed") { continue }

            do {
                let data = try await SmartPhotoAlbumShuffleControlsEngine.requestImageData(localIdentifier: entry.id)

                let imageSpec = try autoreleasepool {
                    try SmartPhotoPipeline.prepare(from: data, renderTargets: targets)
                }

                guard let sp = imageSpec.smartPhoto else {
                    throw PrepError.missingSmartPhoto
                }

                let small = sp.small?.renderFileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let medium = sp.medium?.renderFileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let large = sp.large?.renderFileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if small.isEmpty || medium.isEmpty || large.isEmpty {
                    throw PrepError.missingVariants
                }

                let scoreResult = try autoreleasepool {
                    try SmartPhotoQualityScorer.score(localIdentifier: entry.id, imageData: data, preparedSmartPhoto: sp)
                }

                entry.smallFile = small
                entry.mediumFile = medium
                entry.largeFile = large
                entry.preparedAt = Date()
                entry.score = scoreResult.score
                entry.flags = mergeFlags(existing: entry.flags, adding: scoreResult.flags)
                entry.flags.removeAll(where: { $0 == "failed" })

                manifest.entries[idx] = entry
                try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)

                preparedNow += 1
            } catch {
                entry.flags = mergeFlags(existing: entry.flags, adding: ["failed"])
                manifest.entries[idx] = entry
                try? SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
                failedNow += 1
            }
        }

        // Batch I: order prepared entries by score (keep current stable).
        SmartPhotoAlbumShuffleControlsEngine.resortPreparedEntriesByScoreKeepingCurrentStable(&manifest)
        try? SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)

        WidgetWeaverWidgetRefresh.forceKick()
        await refreshFromManifest()

        if preparedNow == 0, failedNow == 0 {
            saveStatusMessage = "No more photos to prepare right now.\nSave to update widgets."
        } else if failedNow == 0 {
            saveStatusMessage = "Prepared \(preparedNow) photos for shuffle.\nSave to update widgets."
        } else {
            saveStatusMessage = "Prepared \(preparedNow) photos (\(failedNow) failed).\nSave to update widgets."
        }
    }

    private func mergeFlags(existing: [String], adding: [String]) -> [String] {
        var set = Set(existing)
        for f in adding {
            let t = f.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { set.insert(t) }
        }
        return Array(set).sorted()
    }

    // MARK: - Manifest refresh

    private func refreshFromManifest() async {
        let mf = manifestFileName
        guard !mf.isEmpty else {
            await MainActor.run {
                progress = nil
                rankingRows = []
                rankingAlbumID = nil
                nextChangeDate = nil
                rotationIntervalMinutes = 60
            }
            return
        }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            await MainActor.run {
                progress = nil
                rankingRows = []
                rankingAlbumID = nil
                nextChangeDate = nil
                rotationIntervalMinutes = 60
            }
            return
        }

        let now = Date()
        if manifest.catchUpRotation(now: now) {
            try? SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
        }

        let total = manifest.entries.count
        let prepared = manifest.entries.filter { $0.isPrepared }.count
        let failed = manifest.entries.filter { $0.flags.contains("failed") }.count

        let currentIndex = max(0, min(manifest.currentIndex, max(0, total - 1)))
        let currentIsPrepared: Bool = {
            guard manifest.entries.indices.contains(currentIndex) else { return false }
            return manifest.entries[currentIndex].isPrepared
        }()

        let next: Date? = {
            if manifest.rotationIntervalMinutes <= 0 { return nil }
            return manifest.nextChangeDateFrom(now: now) ?? manifest.nextChangeDate
        }()

        let rows: [RankingRow] = manifest.entries.map { entry in
            RankingRow(
                localIdentifier: entry.id,
                preparedAt: entry.preparedAt,
                score: entry.score,
                flags: entry.flags
            )
        }

        await MainActor.run {
            progress = ProgressSummary(
                total: total,
                prepared: prepared,
                failed: failed,
                currentIndex: currentIndex,
                currentIsPrepared: currentIsPrepared
            )

            rankingRows = rows
            rankingAlbumID = manifest.sourceID

            rotationIntervalMinutes = manifest.rotationIntervalMinutes
            nextChangeDate = next
        }
    }
}
