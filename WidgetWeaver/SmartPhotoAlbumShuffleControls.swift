//
//  SmartPhotoAlbumShuffleControls.swift
//  WidgetWeaver
//
//  Created by . . on 1/5/26.
//

import Foundation
import Photos
import SwiftUI
import Vision

/// Batch H/I/J container view (app-only):
/// - Album selection
/// - Progressive prep (N per session)
/// - Quality ranking + debug reasons
/// - Rotation schedule controls (Batch J)
///
/// The widget never decodes or analyses album photos.
struct SmartPhotoAlbumShuffleControls: View {
    @Binding var smartPhoto: ImageSpec?
    @Binding var draftName: String

    private let batchSize: Int = 10

    private let rotationOptionsMinutes: [Int] = [0, 15, 30, 60, 180, 360, 720, 1440]

    @State private var importInProgress: Bool = false
    @State private var saveStatusMessage: String = ""

    @State private var progress: SmartPhotoShuffleProgressSummary?
    @State private var rankingPreview: [SmartPhotoRankingRow] = []

    @State private var rotationIntervalMinutes: Int = 60
    @State private var rotationNextChangeDate: Date?

    private var manifestFileName: String {
        smartPhoto?.smartPhoto?.shuffleManifestFileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var shuffleEnabled: Bool {
        !manifestFileName.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Album Shuffle (Smart Photos)")
                .font(.headline)

            Text("The app prepares per-family renders and a tiny manifest. The widget only loads one pre-rendered file.")
                .font(.caption)
                .foregroundStyle(.secondary)

            statusText

            if shuffleEnabled {
                rotationControls
            }

            controls

            if shuffleEnabled {
                rankingDebug
            }

            if !saveStatusMessage.isEmpty {
                Text(saveStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .task(id: manifestFileName) {
            await refreshProgressAndRanking()
        }
    }

    private var statusText: some View {
        Group {
            if !shuffleEnabled {
                Text("Not configured. Choose an album to start.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let progress {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Album ID: \(progress.sourceID)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Text("Prepared: \(progress.preparedCount) / \(progress.totalCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if progress.failedCount > 0 {
                        Text("Failed: \(progress.failedCount) (skipped)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let current = progress.currentPreparedSummary {
                        Text("Current: \(current)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Current: (none prepared yet)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Loading…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label("Rotate", systemImage: "clock")
                Spacer(minLength: 0)

                Menu {
                    ForEach(rotationOptionsMinutes, id: \.self) { minutes in
                        Button {
                            Task { await setRotationInterval(minutes: minutes) }
                        } label: {
                            if minutes == rotationIntervalMinutes {
                                Text("✓ " + rotationLabel(minutes: minutes))
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
            .font(.caption)
            .foregroundStyle(.secondary)

            if rotationIntervalMinutes > 0, let next = rotationNextChangeDate {
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    Task { await pickAlbum() }
                } label: {
                    Label("Choose album", systemImage: "photo.on.rectangle")
                }

                Spacer()

                if shuffleEnabled {
                    Button {
                        Task { await prepareNextBatch(alreadyBusy: importInProgress) }
                    } label: {
                        Label("Prepare next \(batchSize)", systemImage: "bolt.fill")
                    }

                    Button {
                        Task { await advanceToNextPrepared() }
                    } label: {
                        Label("Next photo", systemImage: "arrow.right.circle")
                    }

                    Button(role: .destructive) {
                        disableShuffle()
                    } label: {
                        Label("Disable", systemImage: "xmark.circle")
                    }
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private var rankingDebug: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ranking (debug)")
                .font(.subheadline)

            if rankingPreview.isEmpty {
                Text("No prepared photos yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(rankingPreview) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("#\(row.rank)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(row.scoreText)
                                .font(.caption)
                                .monospacedDigit()

                            if !row.flagsText.isEmpty {
                                Text(row.flagsText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !row.reasonText.isEmpty {
                            Text(row.reasonText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.top, 8)
    }

    private func refreshProgressAndRanking() async {
        let mf = manifestFileName
        guard !mf.isEmpty else {
            await MainActor.run {
                progress = nil
                rankingPreview = []
                rotationNextChangeDate = nil
            }
            return
        }

        let rotation = await Task.detached(priority: .utility) { () -> (minutes: Int, next: Date?, didCatchUp: Bool)? in
            guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return nil }

            let now = Date()
            let didCatchUp = manifest.catchUpRotation(now: now)
            if didCatchUp {
                try? SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
            }

            let next = manifest.nextChangeDateFrom(now: now) ?? manifest.nextChangeDate
            return (manifest.rotationIntervalMinutes, next, didCatchUp)
        }.value

        let newProgress = await SmartPhotoAlbumShuffleEngine.loadProgressSummary(manifestFileName: mf)
        let newRanking = await SmartPhotoAlbumShuffleEngine.loadRankingPreview(manifestFileName: mf, maxRows: 6)

        await MainActor.run {
            progress = newProgress
            rankingPreview = newRanking
            if let rotation {
                rotationIntervalMinutes = rotation.minutes
                rotationNextChangeDate = rotation.next
                if rotation.didCatchUp {
                    WidgetWeaverWidgetRefresh.forceKick()
                }
            } else {
                rotationNextChangeDate = nil
            }
        }
    }

    // MARK: - Configure

    private func configureShuffle(album: SmartPhotoAlbumOption) async {
        guard var imageSpec = smartPhoto else {
            saveStatusMessage = "Make Smart Photo first."
            return
        }

        guard var sp = imageSpec.smartPhoto else {
            saveStatusMessage = "Make Smart Photo first."
            return
        }

        importInProgress = true
        defer { importInProgress = false }

        let ok = await SmartPhotoAlbumShuffleEngine.ensurePhotoAccess()
        guard ok else {
            saveStatusMessage = "Photo library access is off."
            return
        }

        let assetIDs = await SmartPhotoAlbumShuffleEngine.fetchImageAssetIdentifiers(albumLocalIdentifier: album.localIdentifier, maxCount: 5_000)

        if assetIDs.isEmpty {
            saveStatusMessage = "No usable photos found.\n(Filtered screenshots + low-res or invalid items.)"
            return
        }

        let manifestFile = SmartPhotoShuffleManifestStore.createManifestFileName()

        let defaultRotationMinutes: Int = 60
        let nextChange = scheduledNextChangeDate(from: Date(), minutes: defaultRotationMinutes)

        let manifest = SmartPhotoShuffleManifest(
            version: 3,
            sourceID: album.id,
            entries: assetIDs.map { SmartPhotoShuffleManifest.Entry(id: $0) },
            currentIndex: 0,
            rotationIntervalMinutes: defaultRotationMinutes,
            nextChangeDate: nextChange
        )

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: manifestFile)
        } catch {
            saveStatusMessage = "Failed to save shuffle manifest: \(error.localizedDescription)"
            return
        }

        sp.shuffleManifestFileName = manifestFile
        imageSpec.smartPhoto = sp
        smartPhoto = imageSpec

        saveStatusMessage = "Album chosen.\nTap “Prepare next \(batchSize)” while the app is active.\nSave to update widgets."

        await refreshProgressAndRanking()
    }

    private func disableShuffle() {
        guard var imageSpec = smartPhoto else { return }
        guard var sp = imageSpec.smartPhoto else { return }

        sp.shuffleManifestFileName = nil
        imageSpec.smartPhoto = sp
        smartPhoto = imageSpec

        saveStatusMessage = "Shuffle disabled.\nSave to update widgets."
    }

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

        await MainActor.run {
            WidgetWeaverWidgetRefresh.forceKick()
        }

        await refreshProgressAndRanking()

        if minutes <= 0 {
            saveStatusMessage = "Rotation turned off (manual only).\nSave to update widgets."
        } else if let next = manifest.nextChangeDate {
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
            if hours > 24, hours % 24 == 0 {
                return "\(hours / 24)d"
            }
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

    private func advanceToNextPrepared() async {
        let mf = manifestFileName
        guard !mf.isEmpty else { return }

        importInProgress = true
        defer { importInProgress = false }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            saveStatusMessage = "Shuffle manifest not found."
            return
        }

        guard !manifest.entries.isEmpty else {
            saveStatusMessage = "Manifest is empty."
            return
        }

        let total = manifest.entries.count
        let start = max(0, min(manifest.currentIndex, total - 1))

        var nextIndex: Int? = nil
        if total > 1 {
            for step in 1..<total {
                let idx = (start + step) % total
                if manifest.entries[idx].isPrepared {
                    nextIndex = idx
                    break
                }
            }
        }

        if nextIndex == nil {
            if manifest.entries[start].isPrepared {
                nextIndex = start
            }
        }

        guard let next = nextIndex else {
            saveStatusMessage = "No prepared photo yet.\nTap “Prepare next \(batchSize)” first."
            return
        }

        manifest.currentIndex = next

        if manifest.rotationIntervalMinutes > 0 {
            manifest.nextChangeDate = scheduledNextChangeDate(from: Date(), minutes: manifest.rotationIntervalMinutes)
        } else {
            manifest.nextChangeDate = nil
        }

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
        } catch {
            saveStatusMessage = "Failed to update manifest: \(error.localizedDescription)"
            return
        }

        WidgetWeaverWidgetRefresh.forceKick()
        saveStatusMessage = "Advanced to next prepared photo.\nSave to update widgets."

        await refreshProgressAndRanking()
    }

    // MARK: - Album picker

    private func pickAlbum() async {
        let ok = await SmartPhotoAlbumShuffleEngine.ensurePhotoAccess()
        guard ok else {
            saveStatusMessage = "Photo library access is off."
            return
        }

        do {
            let album = try await SmartPhotoAlbumShuffleEngine.pickAlbum()
            await configureShuffle(album: album)
        } catch {
            saveStatusMessage = "Album pick failed: \(error.localizedDescription)"
        }
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

        let ok = await SmartPhotoAlbumShuffleEngine.ensurePhotoAccess()
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

        let targets = await MainActor.run { SmartPhotoRenderTargets.forCurrentDevice() }

        var preparedNow = 0
        var failedNow = 0

        for idx in manifest.entries.indices {
            if preparedNow >= batchSize { break }

            var entry = manifest.entries[idx]
            if entry.isPrepared { continue }
            if entry.flags.contains("failed") { continue }

            do {
                let data = try await SmartPhotoAlbumShuffleEngine.requestImageData(localIdentifier: entry.id)

                let imageSpec = try await Task.detached(priority: .userInitiated) {
                    try autoreleasepool {
                        try SmartPhotoPipeline.prepare(from: data, renderTargets: targets)
                    }
                }.value

                guard let sp = imageSpec.smartPhoto else {
                    throw SmartPhotoShufflePrepError.missingSmartPhoto
                }

                let small = sp.small?.renderFileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let medium = sp.medium?.renderFileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let large = sp.large?.renderFileName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if small.isEmpty || medium.isEmpty || large.isEmpty {
                    throw SmartPhotoShufflePrepError.missingRenderFiles
                }

                entry.smallFile = small
                entry.mediumFile = medium
                entry.largeFile = large
                entry.preparedAt = Date()

                let scoreResult = try await Task.detached(priority: .utility) {
                    try autoreleasepool {
                        try SmartPhotoQualityScorer.score(localIdentifier: entry.id, imageData: data, preparedSmartPhoto: sp)
                    }
                }.value
                entry.score = scoreResult.score
                entry.flags = scoreResult.flags

                manifest.entries[idx] = entry
                preparedNow += 1

                do {
                    try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
                } catch {
                    saveStatusMessage = "Failed saving manifest: \(error.localizedDescription)"
                    return
                }

                await MainActor.run {
                    progress = SmartPhotoShuffleProgressSummary(from: manifest)
                    rankingPreview = SmartPhotoRankingRow.buildPreview(from: manifest, maxRows: 6)
                }
            } catch {
                failedNow += 1
                entry.flags.append("failed")
                manifest.entries[idx] = entry

                do {
                    try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
                } catch {
                    saveStatusMessage = "Failed saving manifest: \(error.localizedDescription)"
                    return
                }

                await MainActor.run {
                    progress = SmartPhotoShuffleProgressSummary(from: manifest)
                    rankingPreview = SmartPhotoRankingRow.buildPreview(from: manifest, maxRows: 6)
                }
            }
        }

        do {
            manifest.entries = SmartPhotoAlbumShuffleEngine.sortEntriesByScoreKeepingPreparedFirst(manifest.entries)

            if let currentID = progress?.currentEntryID,
               let newIndex = manifest.entries.firstIndex(where: { $0.id == currentID })
            {
                manifest.currentIndex = newIndex
            }

            try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
        } catch {
            saveStatusMessage = "Failed finalising manifest: \(error.localizedDescription)"
            return
        }

        WidgetWeaverWidgetRefresh.forceKick()

        if preparedNow == 0, failedNow == 0 {
            saveStatusMessage = "Nothing to prepare (already done).\nSave to update widgets."
        } else {
            saveStatusMessage = "Prepared \(preparedNow). Failed \(failedNow).\nSave to update widgets."
        }

        await refreshProgressAndRanking()
    }
}

// MARK: - Models used by the controls view

struct SmartPhotoAlbumOption: Identifiable, Hashable, Sendable {
    var id: String
    var localIdentifier: String
    var title: String
}

struct SmartPhotoShuffleProgressSummary: Hashable, Sendable {
    var sourceID: String
    var totalCount: Int
    var preparedCount: Int
    var failedCount: Int
    var currentIndex: Int
    var currentEntryID: String?

    var currentPreparedSummary: String? {
        guard let currentEntryID else { return nil }
        return currentEntryID
    }

    init(from manifest: SmartPhotoShuffleManifest) {
        sourceID = manifest.sourceID
        totalCount = manifest.entries.count
        preparedCount = manifest.entries.filter { $0.isPrepared }.count
        failedCount = manifest.entries.filter { $0.flags.contains("failed") }.count
        currentIndex = manifest.currentIndex
        if manifest.entries.indices.contains(manifest.currentIndex) {
            currentEntryID = manifest.entries[manifest.currentIndex].id
        } else {
            currentEntryID = nil
        }
    }
}

struct SmartPhotoRankingRow: Identifiable, Hashable, Sendable {
    var id: String { entryID }

    var rank: Int
    var entryID: String
    var score: Double
    var flags: [String]
    var reasonText: String

    var scoreText: String {
        String(format: "%.1f", score)
    }

    var flagsText: String {
        flags.joined(separator: ", ")
    }

    static func buildPreview(from manifest: SmartPhotoShuffleManifest, maxRows: Int) -> [SmartPhotoRankingRow] {
        let prepared = manifest.entries.enumerated().compactMap { (idx, entry) -> (idx: Int, entry: SmartPhotoShuffleManifest.Entry)? in
            guard entry.isPrepared else { return nil }
            return (idx, entry)
        }

        let sorted = prepared.sorted { a, b in
            if a.entry.scoreValue != b.entry.scoreValue { return a.entry.scoreValue > b.entry.scoreValue }
            return a.idx < b.idx
        }

        let top = sorted.prefix(maxRows)
        return top.enumerated().map { (i, pair) in
            SmartPhotoRankingRow(
                rank: i + 1,
                entryID: pair.entry.id,
                score: pair.entry.scoreValue,
                flags: pair.entry.flags,
                reasonText: SmartPhotoAlbumShuffleEngine.reasonText(from: pair.entry.flags)
            )
        }
    }
}

// MARK: - Engine helpers (Batch H/I)

enum SmartPhotoShufflePrepError: Error {
    case missingSmartPhoto
    case missingRenderFiles
}

enum SmartPhotoAlbumShuffleEngine {
    static func ensurePhotoAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited {
            return true
        }

        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                continuation.resume(returning: (newStatus == .authorized || newStatus == .limited))
            }
        }
    }

    static func pickAlbum() async throws -> SmartPhotoAlbumOption {
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        guard collections.count > 0 else {
            throw NSError(domain: "SmartPhotoAlbumShuffle", code: 1, userInfo: [NSLocalizedDescriptionKey: "No albums found"])
        }

        var options: [SmartPhotoAlbumOption] = []
        options.reserveCapacity(collections.count)

        collections.enumerateObjects { collection, _, _ in
            let title = collection.localizedTitle ?? "Album"
            options.append(
                SmartPhotoAlbumOption(
                    id: collection.localIdentifier,
                    localIdentifier: collection.localIdentifier,
                    title: title
                )
            )
        }

        let sorted = options.sorted { a, b in
            if a.title != b.title { return a.title < b.title }
            return a.id < b.id
        }

        if let first = sorted.first {
            return first
        }

        throw NSError(domain: "SmartPhotoAlbumShuffle", code: 2, userInfo: [NSLocalizedDescriptionKey: "No album selected"])
    }

    static func fetchImageAssetIdentifiers(albumLocalIdentifier: String, maxCount: Int) async -> [String] {
        let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumLocalIdentifier], options: nil).firstObject
        guard let album else { return [] }

        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(in: album, options: options)
        guard assets.count > 0 else { return [] }

        var ids: [String] = []
        ids.reserveCapacity(min(maxCount, assets.count))

        var count = 0
        assets.enumerateObjects { asset, _, stop in
            if count >= maxCount {
                stop.pointee = true
                return
            }

            if asset.mediaType != .image { return }
            if asset.pixelWidth < 512 || asset.pixelHeight < 512 { return }

            if #available(iOS 9.0, *) {
                if asset.mediaSubtypes.contains(.photoScreenshot) {
                    return
                }
            }

            ids.append(asset.localIdentifier)
            count += 1
        }

        return ids
    }

    static func requestImageData(localIdentifier: String) async throws -> Data {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            throw NSError(domain: "SmartPhotoAlbumShuffle", code: 10, userInfo: [NSLocalizedDescriptionKey: "Asset not found"])
        }

        let opts = PHImageRequestOptions()
        opts.deliveryMode = .highQualityFormat
        opts.isNetworkAccessAllowed = true
        opts.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, info in
                if let info,
                   let cancelled = info[PHImageCancelledKey] as? Bool,
                   cancelled
                {
                    continuation.resume(throwing: NSError(domain: "SmartPhotoAlbumShuffle", code: 11, userInfo: [NSLocalizedDescriptionKey: "Cancelled"]))
                    return
                }

                if let info,
                   let error = info[PHImageErrorKey] as? NSError
                {
                    continuation.resume(throwing: error)
                    return
                }

                guard let data else {
                    continuation.resume(throwing: NSError(domain: "SmartPhotoAlbumShuffle", code: 12, userInfo: [NSLocalizedDescriptionKey: "No image data"]))
                    return
                }

                continuation.resume(returning: data)
            }
        }
    }

    static func loadProgressSummary(manifestFileName: String) async -> SmartPhotoShuffleProgressSummary? {
        await Task.detached(priority: .utility) {
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFileName) else { return nil }
            return SmartPhotoShuffleProgressSummary(from: manifest)
        }.value
    }

    static func loadRankingPreview(manifestFileName: String, maxRows: Int) async -> [SmartPhotoRankingRow] {
        await Task.detached(priority: .utility) {
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: manifestFileName) else { return [] }
            return SmartPhotoRankingRow.buildPreview(from: manifest, maxRows: maxRows)
        }.value
    }

    static func sortEntriesByScoreKeepingPreparedFirst(_ entries: [SmartPhotoShuffleManifest.Entry]) -> [SmartPhotoShuffleManifest.Entry] {
        let prepared = entries.filter { $0.isPrepared }.sorted { a, b in
            if a.scoreValue != b.scoreValue { return a.scoreValue > b.scoreValue }
            return a.id < b.id
        }

        let unprepared = entries.filter { !$0.isPrepared }
        return prepared + unprepared
    }

    static func reasonText(from flags: [String]) -> String {
        if flags.isEmpty { return "" }
        return flags.joined(separator: " • ")
    }
}
