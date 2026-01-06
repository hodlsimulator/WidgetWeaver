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

    @State private var rotationIntervalMinutes: Int = 60
    @State private var nextChangeDate: Date?

    private var manifestFileName: String {
        (smartPhoto?.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shuffleEnabled: Bool {
        !manifestFileName.isEmpty
    }


    private var albumPickerPresentedBinding: Binding<Bool> {
        albumPickerPresented ?? $internalAlbumPickerPresented
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(spacing: 10) {
                Label("Album shuffle (Smart Photos)", systemImage: "photo.stack")
                Spacer(minLength: 0)
                Text(shuffleEnabled ? "On" : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            statusText

            if shuffleEnabled {
                rotationControls
            }

            actionRow

            if shuffleEnabled {
                rankingDebug
            }
        }
        .sheet(isPresented: albumPickerPresentedBinding) {
            NavigationStack {
                Group {
                    switch albumPickerState {
                    case .idle, .loading:
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading albums…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .failed(let message):
                        VStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .ready:
                        List(albums) { album in
                            Button {
                                Task { await configureShuffle(album: album) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.title)
                                        .font(.headline)
                                    Text("\(album.count) photos")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(importInProgress)
                        }
                    }
                }
                .navigationTitle("Choose Album")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { albumPickerPresentedBinding.wrappedValue = false }
                    }
                }
            }
            .task {
                await loadAlbumsIfNeeded()
            }
        }
        .onChange(of: albumPickerPresentedBinding.wrappedValue) { _, newValue in
            handleAlbumPickerPresentationChange(isPresented: newValue)
        }
        .task(id: manifestFileName) {
            await refreshFromManifest()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if smartPhoto == nil {
            Text("Album shuffle requires Smart Photo.\nPick a photo and create Smart Photo renders first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !shuffleEnabled {
            Text("Choose an album to start. While the app is open, it will pre-render the next \(batchSize) photos.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let progress {
            Text("Prepared \(progress.prepared)/\(progress.total) • failed \(progress.failed) • currentIndex \(progress.currentIndex)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("Loading shuffle status…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Label("Rotate", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Menu {
                    ForEach(rotationOptionsMinutes, id: \.self) { minutes in
                        Button {
                            Task { await setRotationInterval(minutes: minutes) }
                        } label: {
                            if minutes == rotationIntervalMinutes {
                                Text("✓ \(rotationLabel(minutes: minutes))")
                            } else {
                                Text(rotationLabel(minutes: minutes))
                            }
                        }
                    }
                } label: {
                    Text(rotationLabel(minutes: rotationIntervalMinutes))
                        .font(.caption)
                }
                .disabled(importInProgress)
            }

            if rotationIntervalMinutes > 0, let nextChangeDate {
                Text("Next change: \(nextChangeDate.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Rotation is off (manual only).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button {
                albumPickerPresentedBinding.wrappedValue = true
            } label: {
                Label("Choose album…", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(importInProgress || smartPhoto == nil)

            if shuffleEnabled {
                Button {
                    Task { await prepareNextBatch(alreadyBusy: false) }
                } label: {
                    Label("Prepare next \(batchSize)", systemImage: "gearshape.2")
                }
                .disabled(importInProgress)

                Button {
                    Task { await advanceToNextPrepared() }
                } label: {
                    Label("Next photo", systemImage: "arrow.right.circle")
                }
                .disabled(importInProgress)

                Button(role: .destructive) {
                    disableShuffle()
                } label: {
                    Label("Disable", systemImage: "xmark.circle")
                }
                .disabled(importInProgress)
            }
        }
        .controlSize(.small)
        .buttonStyle(BorderlessButtonStyle())
    }

    private var rankingDebug: some View {
        DisclosureGroup {
            if rankingRows.isEmpty {
                Text("No prepared photos yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rankingRows) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.isCurrent ? "▶︎" : " ")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(row.scoreText)
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)

                            Text(row.flagsText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.top, 4)
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

            focus.wrappedValue = EditorFocusSnapshot(
                selection: .none,
                focus: pickerTarget
            )
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
                nextChangeDate = nil
                rotationIntervalMinutes = 60
            }
            return
        }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            await MainActor.run {
                progress = nil
                rankingRows = []
                nextChangeDate = nil
            }
            return
        }

        let now = Date()
        let didCatchUp = manifest.catchUpRotation(now: now)
        if didCatchUp {
            try? SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
            WidgetWeaverWidgetRefresh.forceKick()
        }

        let next = manifest.nextChangeDateFrom(now: now) ?? manifest.nextChangeDate

        let p = ProgressSummary.from(manifest: manifest)
        let rows = RankingRow.preview(from: manifest, maxRows: 6)

        await MainActor.run {
            progress = p
            rankingRows = rows
            rotationIntervalMinutes = manifest.rotationIntervalMinutes
            nextChangeDate = next
        }
    }
}
