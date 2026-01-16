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

    let specID: UUID

    var focus: Binding<EditorFocusSnapshot>? = nil

    var albumPickerPresented: Binding<Bool>? = nil

    @Environment(\.scenePhase) private var scenePhase

    private let batchSize: Int = 10
    private let rotationOptionsMinutes: [Int] = [2, 15, 30, 60, 180, 360, 720, 1440] // Changed 0 to 2 for testing

    @State private var internalAlbumPickerPresented: Bool = false
    @State private var previousFocusSnapshot: EditorFocusSnapshot?
    @State private var albumPickerState: AlbumPickerState = .idle
    @State private var albums: [AlbumOption] = []

    @State private var progress: ProgressSummary?

    @State private var rotationIntervalMinutes: Int = 60
    @State private var nextChangeDate: Date?

    @State private var isPreparingBatch: Bool = false

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

            statusText

            actionRow
                .padding(.top, 2)

            rotationControls
                .padding(.top, 4)

            Divider()
        }
        .onAppear {
            handleAlbumPickerPresentationChange(isPresented: albumPickerPresentedBinding.wrappedValue)
        }
        .sheet(isPresented: albumPickerPresentedBinding) {
            NavigationStack {
                Group {
                    switch albumPickerState {
                    case .idle:
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Loading albums…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .loading:
                        VStack(spacing: 10) {
                            ProgressView()
                            Text("Requesting access…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .ready:
                        List {
                            ForEach($albums, id: \.id) { album in
                                Button {
                                    Task { await configureShuffle(album: album.wrappedValue) }
                                } label: {
                                    let a = album.wrappedValue

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(a.title)
                                            .font(.body)

                                        Text("\(a.count) photos")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .disabled(importInProgress)
                            }
                        }

                    case .failed(let message):
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 28))
                                .foregroundStyle(.orange)
                            Text(message)
                                .multilineTextAlignment(.center)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                }
                .navigationTitle("Choose album")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            albumPickerPresentedBinding.wrappedValue = false
                        }
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
            await autoPrepareWhilePossible()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if smartPhoto == nil {
            Text("Album shuffle requires Smart Photo.\nPick a photo and create Smart Photo renders first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !shuffleEnabled {
            Text("Choose an album to start. While the app is open, it will progressively pre-render the album (in batches of \(batchSize)).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let progress {
            HStack(spacing: 8) {
                if isPreparingBatch {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Prepared \(progress.prepared)/\(progress.total) • failed \(progress.failed) • currentIndex \(progress.currentIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                if isPreparingBatch {
                    ProgressView()
                        .controlSize(.small)
                }

                Text("Loading shuffle status…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                .disabled(importInProgress || isPreparingBatch)
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

    private struct ActionTileLabel: View {
        let title: String
        let systemImage: String

        var body: some View {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 20)

                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.vertical, 4)
        }
    }

    private var actionRow: some View {
        Group {
            if shuffleEnabled {
                ViewThatFits(in: .horizontal) {
                    actionGrid(columns: 4)
                    actionGrid(columns: 2)
                }
            } else {
                actionGrid(columns: 1)
            }
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func actionGrid(columns: Int) -> some View {
        let minTileWidth: CGFloat = 120
        let cols = Array(repeating: GridItem(.flexible(minimum: minTileWidth), spacing: 12), count: columns)

        LazyVGrid(columns: cols, spacing: 12) {
            Button {
                albumPickerPresentedBinding.wrappedValue = true
            } label: {
                ActionTileLabel(title: "Choose\nalbum…", systemImage: "rectangle.stack.badge.plus")
            }
            .disabled(importInProgress || smartPhoto == nil || isPreparingBatch)

            if shuffleEnabled {
                Button {
                    Task { await prepareNextBatch(alreadyBusy: false) }
                } label: {
                    ActionTileLabel(title: "Prepare\nnext \(batchSize)", systemImage: "gearshape.2")
                }
                .disabled(importInProgress || isPreparingBatch)

                Button {
                    Task { await advanceToNextPrepared() }
                } label: {
                    ActionTileLabel(title: "Next\nphoto", systemImage: "arrow.right.circle")
                }
                .disabled(importInProgress || isPreparingBatch)

                Button(role: .destructive) {
                    disableShuffle()
                } label: {
                    ActionTileLabel(title: "Disable", systemImage: "xmark.circle")
                }
                .disabled(importInProgress || isPreparingBatch)
            }
        }
    }

    // MARK: - Focus snapshot handling

    private func handleAlbumPickerPresentationChange(isPresented _: Bool) {
        // Focus handling disabled here because focus targets differ between builds.
    }

    // MARK: - Albums load

    private func loadAlbumsIfNeeded() async {
        if case .ready = albumPickerState { return }
        if case .loading = albumPickerState { return }
        if case .failed = albumPickerState { return }

        albumPickerState = .loading

        let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
        guard ok else {
            await MainActor.run {
                self.albumPickerState = .failed("Photo library access is off.\nEnable Photos access in Settings.")
            }
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

        let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
        guard ok else {
            importInProgress = false
            saveStatusMessage = "Photo library access is off."
            return
        }

        saveStatusMessage = "Building album list…"

        let manifestFile = SmartPhotoShuffleManifestStore.createManifestFileName(prefix: "smart-shuffle", ext: "json")

        let assetIDs = SmartPhotoAlbumShuffleControlsEngine.fetchImageAssetIdentifiers(albumID: album.id)

        if assetIDs.isEmpty {
            importInProgress = false
            saveStatusMessage = "No usable images found in \(album.title).\nScreenshots and very low-res images are ignored."
            return
        }

        let defaultRotationMinutes: Int = 60
        let next = scheduledNextChangeDate(from: Date(), minutes: defaultRotationMinutes)

        let manifest = SmartPhotoShuffleManifest(
            version: 4,
            sourceID: album.id,
            entries: assetIDs.map { SmartPhotoShuffleManifest.Entry(id: $0) },
            currentIndex: 0,
            rotationIntervalMinutes: defaultRotationMinutes,
            nextChangeDate: next
        )

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: manifestFile)
        } catch {
            importInProgress = false
            saveStatusMessage = "Failed to save shuffle manifest: \(error.localizedDescription)"
            return
        }

        sp.shuffleManifestFileName = manifestFile
        smartPhoto = sp

        // Persist immediately so the widget extension uses the same manifest as the editor.
        WidgetSpecStore.shared.setSmartPhotoShuffleManifestFileName(specID: specID, manifestFileName: manifestFile)

        albumPickerPresentedBinding.wrappedValue = false
        albumPickerState = .idle

        WidgetWeaverWidgetRefresh.forceKick()

        importInProgress = false

        saveStatusMessage = "Album shuffle configured for “\(album.title)” (\(assetIDs.count) photos).\nPreparing next \(batchSize)…"

        await refreshFromManifest()

        // Kick the initial batch without locking the rest of the editor UI.
        Task {
            await prepareNextBatch(alreadyBusy: true)
        }
    }

    private func disableShuffle() {
        guard var sp = smartPhoto else { return }
        sp.shuffleManifestFileName = nil
        smartPhoto = sp

        // Persist immediately so the widget extension stays in sync with the editor.
        WidgetSpecStore.shared.setSmartPhotoShuffleManifestFileName(specID: specID, manifestFileName: nil)

        progress = nil
        nextChangeDate = nil
        rotationIntervalMinutes = 60

        saveStatusMessage = "Album shuffle disabled."
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
            saveStatusMessage = "Rotation disabled (manual only)."
        } else {
            saveStatusMessage = "Rotation set to \(rotationLabel(minutes: minutes))."
        }
    }

    private func rotationLabel(minutes: Int) -> String {
        if minutes <= 0 { return "Off" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes == 60 { return "1h" }
        if minutes == 180 { return "3h" }
        if minutes == 360 { return "6h" }
        if minutes == 720 { return "12h" }
        if minutes == 1440 { return "1d" }
        let hours = minutes / 60
        return "\(hours)h"
    }

    private func scheduledNextChangeDate(from now: Date, minutes: Int) -> Date? {
        guard minutes > 0 else { return nil }
        return now.addingTimeInterval(TimeInterval(minutes) * 60.0)
    }

    private func advanceToNextPrepared() async {
        let mf = manifestFileName
        guard !mf.isEmpty else { return }

        importInProgress = true
        defer { importInProgress = false }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            saveStatusMessage = "Shuffle manifest not found."
            return
        }

        let now = Date()
        let didCatchUp = manifest.catchUpRotation(now: now)

        let total = manifest.entries.count
        if total == 0 {
            saveStatusMessage = "Manifest is empty."
            return
        }

        var nextIndex = manifest.currentIndex
        var found = false

        for step in 1...total {
            let candidate = (manifest.currentIndex + step) % total
            if manifest.entries.indices.contains(candidate),
               manifest.entries[candidate].isPrepared
            {
                nextIndex = candidate
                found = true
                break
            }
        }

        guard found else {
            saveStatusMessage = "No prepared photos yet.\nUse “Prepare next \(batchSize)”."
            await refreshFromManifest()
            return
        }

        manifest.currentIndex = nextIndex
        if manifest.rotationIntervalMinutes > 0 {
            manifest.nextChangeDate = scheduledNextChangeDate(from: now, minutes: manifest.rotationIntervalMinutes)
        }

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
        } catch {
            saveStatusMessage = "Failed to advance shuffle: \(error.localizedDescription)"
            return
        }

        WidgetWeaverWidgetRefresh.forceKick()
        await refreshFromManifest()

        if didCatchUp {
            saveStatusMessage = "Advanced to next photo (rotation caught up)."
        } else {
            saveStatusMessage = "Advanced to next photo."
        }
    }

    // MARK: - Progressive prep

    private func prepareNextBatch(alreadyBusy _: Bool) async {
        let mf = manifestFileName
        guard !mf.isEmpty else { return }

        let didStart = await MainActor.run { () -> Bool in
            if isPreparingBatch { return false }
            isPreparingBatch = true
            return true
        }
        guard didStart else { return }

        defer {
            Task { @MainActor in
                isPreparingBatch = false
            }
        }

        let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
        guard ok else {
            saveStatusMessage = "Photo library access is off."
            return
        }

        let targets = await MainActor.run {
            SmartPhotoRenderTargets.forCurrentDevice()
        }

        let bs = batchSize

        struct BatchOutcome: Sendable {
            var preparedNow: Int
            var failedNow: Int
            var didUpdate: Bool
        }

        let outcome: BatchOutcome? = await Task.detached(priority: .utility) { () async -> BatchOutcome? in
            guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return nil }

            let now = Date()
            var didUpdate = manifest.catchUpRotation(now: now)

            var preparedNow = 0
            var failedNow = 0

            for idx in manifest.entries.indices {
                if preparedNow >= bs { break }

                var entry = manifest.entries[idx]
                if entry.isPrepared { continue }
                if entry.flags.contains("failed") { continue }

                do {
                    let data = try await SmartPhotoAlbumShuffleControlsEngine.requestImageData(localIdentifier: entry.id)

                    let imageSpec: ImageSpec = try autoreleasepool {
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

                    let scoreResult: SmartPhotoQualityScorer.Result = try autoreleasepool {
                        try SmartPhotoQualityScorer.score(localIdentifier: entry.id, imageData: data, preparedSmartPhoto: sp)
                    }

                    entry.smallFile = small
                    entry.mediumFile = medium
                    entry.largeFile = large

                    // Persist the App Group source file so the app can later re-render
                    // manual per-photo crops without touching the Photos library.
                    entry.sourceFileName = sp.masterFileName

                    // Persist the auto crop rects so the crop editor can reopen using the
                    // saved auto framing.
                    entry.smallAutoCropRect = sp.small?.cropRect
                    entry.mediumAutoCropRect = sp.medium?.cropRect
                    entry.largeAutoCropRect = sp.large?.cropRect

                    entry.preparedAt = sp.preparedAt
                    entry.score = scoreResult.score
                    entry.flags = Array(Set(entry.flags).union(scoreResult.flags)).sorted()
                    entry.flags.removeAll(where: { $0 == "failed" })

                    manifest.entries[idx] = entry
                    preparedNow += 1
                    didUpdate = true
                } catch {
                    entry.flags = Array(Set(entry.flags).union(["failed"])).sorted()
                    manifest.entries[idx] = entry
                    failedNow += 1
                    didUpdate = true
                }
            }

            if didUpdate {
                SmartPhotoAlbumShuffleControlsEngine.resortPreparedEntriesByScoreKeepingCurrentStable(&manifest)
                try? SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
            }

            return BatchOutcome(preparedNow: preparedNow, failedNow: failedNow, didUpdate: didUpdate)
        }.value

        // Ignore results if the user switched manifests mid-batch.
        guard manifestFileName == mf else { return }

        guard let outcome else {
            saveStatusMessage = "Shuffle manifest not found."
            await refreshFromManifest()
            return
        }

        if outcome.didUpdate { await MainActor.run { WidgetWeaverWidgetRefresh.kickIfNeeded(minIntervalSeconds: 20) } }

        await refreshFromManifest()

        if outcome.preparedNow == 0, outcome.failedNow == 0 {
            saveStatusMessage = "No more photos to prepare right now."
        } else if outcome.failedNow == 0 {
            saveStatusMessage = "Prepared \(outcome.preparedNow) photos for shuffle."
        } else {
            saveStatusMessage = "Prepared \(outcome.preparedNow) photos (\(outcome.failedNow) failed)."
        }
    }

    private func autoPrepareWhilePossible() async {
        let mf = manifestFileName
        guard !mf.isEmpty else { return }

        // Give the UI a moment to settle before starting heavy work.
        try? await Task.sleep(nanoseconds: 250_000_000)

        while !Task.isCancelled {
            if manifestFileName != mf { return }

            if scenePhase != .active {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            if importInProgress || isPreparingBatch || albumPickerPresentedBinding.wrappedValue {
                try? await Task.sleep(nanoseconds: 500_000_000)
                continue
            }

            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return }

            let hasMoreToPrepare = manifest.entries.contains { entry in
                !entry.isPrepared && !entry.flags.contains("failed")
            }

            if !hasMoreToPrepare { return }

            await prepareNextBatch(alreadyBusy: true)

            // Small breather between batches to keep the app responsive.
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    private static func mergeFlags(existing: [String], adding: [String]) -> [String] {
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
                nextChangeDate = nil
                rotationIntervalMinutes = 60
            }
            return
        }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            await MainActor.run {
                progress = nil
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

        await MainActor.run {
            progress = ProgressSummary(
                total: total,
                prepared: prepared,
                failed: failed,
                currentIndex: currentIndex,
                currentIsPrepared: currentIsPrepared
            )

            rotationIntervalMinutes = manifest.rotationIntervalMinutes
            nextChangeDate = next
        }
    }

    private struct ProgressSummary: Hashable {
        let total: Int
        let prepared: Int
        let failed: Int
        let currentIndex: Int
        let currentIsPrepared: Bool
    }

    private enum PrepError: Error {
        case missingSmartPhoto
        case missingVariants
    }
}
