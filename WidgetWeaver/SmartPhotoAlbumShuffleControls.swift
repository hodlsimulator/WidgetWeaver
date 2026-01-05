//
//  SmartPhotoAlbumShuffleControls.swift
//  WidgetWeaver
//
//  Created by . . on 1/5/26.
//

import SwiftUI
import Photos
import Vision
import ImageIO
import WidgetKit

/// App-only progressive processing for Smart Photo album shuffle.
///
/// The widget never decodes or analyses album photos.
/// It only reads the shuffle manifest and decodes **one** pre-rendered image per entry.
struct SmartPhotoAlbumShuffleControls: View {
    @Binding var smartPhoto: SmartPhotoSpec?
    @Binding var importInProgress: Bool
    @Binding var saveStatusMessage: String

    private let batchSize: Int = 10

    @State private var showAlbumPicker: Bool = false
    @State private var albumPickerState: AlbumPickerState = .idle
    @State private var albums: [SmartPhotoAlbumOption] = []
    @State private var progress: SmartPhotoShuffleProgressSummary?

    @State private var rankingPreview: [SmartPhotoRankingRow] = []

    private var manifestFileName: String {
        (smartPhoto?.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shuffleEnabled: Bool {
        !manifestFileName.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack(spacing: 10) {
                Label("Album shuffle (MVP)", systemImage: "photo.stack")
                Spacer(minLength: 0)
                Text(shuffleEnabled ? "On" : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            statusText

            controls

            if shuffleEnabled {
                rankingDebug
            }
        }
        .sheet(isPresented: $showAlbumPicker) {
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
                        Button("Cancel") { showAlbumPicker = false }
                    }
                }
            }
            .task {
                await loadAlbumsIfNeeded()
            }
        }
        .task(id: manifestFileName) {
            await refreshProgressAndRanking()
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if smartPhoto == nil {
            Text("Album shuffle requires Smart Photo.\nPick a photo, then tap “Make Smart Photo (per-size renders)” first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if shuffleEnabled {
            if let progress {
                Text("Prepared \(progress.prepared)/\(progress.total) • failed \(progress.failed) • currentIndex \(progress.currentIndex)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Loading shuffle status…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Pick a Photos album. While the app is open, it will progressively pre-render the next \(batchSize) images for widgets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        ControlGroup {
            Button {
                showAlbumPicker = true
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
                    Label("Disable shuffle", systemImage: "xmark.circle")
                }
                .disabled(importInProgress)
            }
        }
        .controlSize(.small)
    }

    private var rankingDebug: some View {
        DisclosureGroup {
            if rankingPreview.isEmpty {
                Text("No prepared photos yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rankingPreview) { row in
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

    private func refreshProgressAndRanking() async {
        let mf = manifestFileName
        guard !mf.isEmpty else {
            await MainActor.run {
                progress = nil
                rankingPreview = []
            }
            return
        }

        let newProgress = await SmartPhotoAlbumShuffleEngine.loadProgressSummary(manifestFileName: mf)
        let newRanking = await SmartPhotoAlbumShuffleEngine.loadRankingPreview(manifestFileName: mf, maxRows: 6)

        await MainActor.run {
            progress = newProgress
            rankingPreview = newRanking
        }
    }

    // MARK: - Album picker

    private func loadAlbumsIfNeeded() async {
        if case .ready = albumPickerState, !albums.isEmpty { return }

        albumPickerState = .loading
        albums = []

        let ok = await SmartPhotoAlbumShuffleEngine.ensurePhotoAccess()
        guard ok else {
            albumPickerState = .failed("Photo library access is off.\nEnable access in Settings to use album shuffle.")
            return
        }

        let result = await Task.detached(priority: .userInitiated) {
            SmartPhotoAlbumShuffleEngine.fetchAlbumOptions()
        }.value

        await MainActor.run {
            self.albums = result
            if self.albums.isEmpty {
                self.albumPickerState = .failed("No albums found.")
            } else {
                self.albumPickerState = .ready
            }
        }
    }

    // MARK: - Configure

    private func configureShuffle(album: SmartPhotoAlbumOption) async {
        guard var sp = smartPhoto else {
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

        saveStatusMessage = "Building album list…"

        let manifestFile = SmartPhotoShuffleManifestStore.createManifestFileName(prefix: "smart-shuffle", ext: "json")

        let assetIDs = await Task.detached(priority: .userInitiated) {
            SmartPhotoAlbumShuffleEngine.fetchImageAssetIdentifiers(albumID: album.id)
        }.value

        if assetIDs.isEmpty {
            saveStatusMessage = "No usable images found in \(album.title).\nScreenshots and very low-res images are ignored."
            return
        }

        let manifest = SmartPhotoShuffleManifest(
            version: 2,
            sourceID: album.id,
            entries: assetIDs.map { SmartPhotoShuffleManifest.Entry(id: $0) },
            currentIndex: 0,
            rotationIntervalMinutes: 60
        )

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: manifestFile)
        } catch {
            saveStatusMessage = "Failed to save shuffle manifest: \(error.localizedDescription)"
            return
        }

        sp.shuffleManifestFileName = manifestFile
        smartPhoto = sp.normalised()

        showAlbumPicker = false
        albumPickerState = .idle

        saveStatusMessage = "Album shuffle configured for “\(album.title)” (\(assetIDs.count) photos).\nSave to update widgets.\nPreparing next \(batchSize)…"

        await prepareNextBatch(alreadyBusy: true)
    }

    private func disableShuffle() {
        guard var sp = smartPhoto else { return }
        sp.shuffleManifestFileName = nil
        smartPhoto = sp.normalised()

        progress = nil
        rankingPreview = []
        saveStatusMessage = "Album shuffle disabled (draft only).\nSave to update widgets."
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

        let total = manifest.entries.count
        guard total > 0 else {
            saveStatusMessage = "No photos in the shuffle manifest."
            return
        }

        var nextIndex: Int?
        for step in 1...total {
            let candidate = (manifest.currentIndex + step) % total
            if manifest.entries[candidate].isPrepared {
                nextIndex = candidate
                break
            }
        }

        guard let next = nextIndex else {
            saveStatusMessage = "No prepared photos yet.\nTap “Prepare next \(batchSize)” first."
            return
        }

        manifest.currentIndex = next

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
        } catch {
            saveStatusMessage = "Failed to update shuffle index: \(error.localizedDescription)"
            return
        }

        await MainActor.run {
            WidgetWeaverWidgetRefresh.forceKick()
        }

        await refreshProgressAndRanking()
        saveStatusMessage = "Advanced to next prepared photo (index \(next))."
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
                    throw SmartPhotoShufflePrepError.missingVariants
                }

                let scored = await Task.detached(priority: .utility) {
                    SmartPhotoQualityScorer.score(entryID: entry.id, smartPhoto: sp)
                }.value

                entry.smallFile = small
                entry.mediumFile = medium
                entry.largeFile = large
                entry.preparedAt = Date()
                entry.score = scored.score
                entry.flags = SmartPhotoQualityScorer.mergeFlags(existing: entry.flags, adding: scored.flags)
                entry.flags.removeAll(where: { $0 == "failed" })

                manifest.entries[idx] = entry

                SmartPhotoAlbumShuffleEngine.resortPreparedEntriesByScoreKeepingCurrentStable(&manifest)

                try SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)

                preparedNow += 1
            } catch {
                entry.flags = SmartPhotoQualityScorer.mergeFlags(existing: entry.flags, adding: ["failed"])
                manifest.entries[idx] = entry
                try? SmartPhotoShuffleManifestStore.save(manifest, fileName: mf)
                failedNow += 1
            }
        }

        await MainActor.run {
            WidgetWeaverWidgetRefresh.forceKick()
        }

        await refreshProgressAndRanking()

        if preparedNow == 0, failedNow == 0 {
            saveStatusMessage = "No more photos to prepare right now."
        } else if failedNow == 0 {
            saveStatusMessage = "Prepared \(preparedNow) photos for shuffle.\nIf this is your first time enabling shuffle, tap Save once."
        } else {
            saveStatusMessage = "Prepared \(preparedNow) photos (\(failedNow) failed).\nIf this is your first time enabling shuffle, tap Save once."
        }
    }
}

// MARK: - UI models

private struct SmartPhotoRankingRow: Identifiable, Hashable, Sendable {
    var id: String
    var isCurrent: Bool
    var score: Double
    var flags: [String]

    var scoreText: String {
        let s = Int(score.rounded())
        return "\(s)"
    }

    var flagsText: String {
        if flags.isEmpty { return "—" }
        return flags.joined(separator: ", ")
    }
}

// MARK: - Models

private struct SmartPhotoAlbumOption: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var count: Int
}

private struct SmartPhotoShuffleProgressSummary: Hashable, Sendable {
    var total: Int
    var prepared: Int
    var failed: Int
    var currentIndex: Int
}

private enum SmartPhotoShufflePrepError: Error {
    case missingSmartPhoto
    case missingVariants
    case noAsset
    case noData
}

private enum AlbumPickerState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

// MARK: - Photos + manifest helpers

private enum SmartPhotoAlbumShuffleEngine {
    @MainActor
    static func ensurePhotoAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let updated = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return updated == .authorized || updated == .limited
        default:
            return false
        }
    }

    static func fetchAlbumOptions() -> [SmartPhotoAlbumOption] {
        let imageOptions: PHFetchOptions = {
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            return o
        }()

        func countImages(in collection: PHAssetCollection) -> Int {
            PHAsset.fetchAssets(in: collection, options: imageOptions).count
        }

        var out: [SmartPhotoAlbumOption] = []
        var seen = Set<String>()

        func appendCollection(_ collection: PHAssetCollection, overrideTitle: String? = nil) {
            let id = collection.localIdentifier
            guard !seen.contains(id) else { return }
            seen.insert(id)

            let title = (overrideTitle ?? collection.localizedTitle ?? "Album")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let count = countImages(in: collection)
            guard count > 0 else { return }

            out.append(SmartPhotoAlbumOption(id: id, title: title.isEmpty ? "Album" : title, count: count))
        }

        if let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil).firstObject {
            appendCollection(c, overrideTitle: "All Photos")
        }
        if let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumFavorites, options: nil).firstObject {
            appendCollection(c, overrideTitle: "Favourites")
        }
        if let c = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumRecentlyAdded, options: nil).firstObject {
            appendCollection(c, overrideTitle: "Recently Added")
        }

        var user: [SmartPhotoAlbumOption] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { collection, _, _ in
                let id = collection.localIdentifier
                if seen.contains(id) { return }

                let title = (collection.localizedTitle ?? "Album").trimmingCharacters(in: .whitespacesAndNewlines)
                let count = countImages(in: collection)
                guard count > 0 else { return }

                user.append(SmartPhotoAlbumOption(id: id, title: title.isEmpty ? "Album" : title, count: count))
            }

        user.sort { $0.title.lowercased() < $1.title.lowercased() }
        out.append(contentsOf: user)
        return out
    }

    static func fetchImageAssetIdentifiers(albumID: String) -> [String] {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
        guard let collection = collections.firstObject else { return [] }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let assets = PHAsset.fetchAssets(in: collection, options: options)

        var ids: [String] = []
        ids.reserveCapacity(assets.count)

        assets.enumerateObjects { asset, _, _ in
            if asset.mediaSubtypes.contains(.photoScreenshot) {
                return
            }

            let minDim = min(asset.pixelWidth, asset.pixelHeight)
            if minDim < 800 {
                return
            }

            ids.append(asset.localIdentifier)
        }

        return ids
    }

    static func requestImageData(localIdentifier: String) async throws -> Data {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil)
        guard let asset = assets.firstObject else {
            throw SmartPhotoShufflePrepError.noAsset
        }

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.version = .current
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { cont in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, info in
                if let error = info?[PHImageErrorKey] as? Error {
                    cont.resume(throwing: error)
                    return
                }
                guard let data else {
                    cont.resume(throwing: SmartPhotoShufflePrepError.noData)
                    return
                }
                cont.resume(returning: data)
            }
        }
    }

    static func loadProgressSummary(manifestFileName: String) async -> SmartPhotoShuffleProgressSummary? {
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mf.isEmpty else { return nil }

        return await Task.detached(priority: .utility) {
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return nil }
            let total = manifest.entries.count
            let prepared = manifest.entries.filter { $0.isPrepared }.count
            let failed = manifest.entries.filter { $0.flags.contains("failed") && !$0.isPrepared }.count
            return SmartPhotoShuffleProgressSummary(
                total: total,
                prepared: prepared,
                failed: failed,
                currentIndex: manifest.currentIndex
            )
        }.value
    }

    static func loadRankingPreview(manifestFileName: String, maxRows: Int) async -> [SmartPhotoRankingRow] {
        let mf = manifestFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mf.isEmpty else { return [] }

        return await Task.detached(priority: .utility) {
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return [] }

            let currentID: String? = {
                guard manifest.entries.indices.contains(manifest.currentIndex) else { return nil }
                return manifest.entries[manifest.currentIndex].id
            }()

            let prepared = manifest.entries.filter { $0.isPrepared }
            let sorted = prepared.sorted { a, b in
                let sa = a.scoreValue
                let sb = b.scoreValue
                if sa != sb { return sa > sb }
                let da = a.preparedAt ?? .distantPast
                let db = b.preparedAt ?? .distantPast
                if da != db { return da > db }
                return a.id < b.id
            }

            let rows = sorted.prefix(max(1, maxRows)).map { entry in
                SmartPhotoRankingRow(
                    id: entry.id,
                    isCurrent: (entry.id == currentID),
                    score: entry.scoreValue,
                    flags: SmartPhotoQualityScorer.displayFlags(entry.flags)
                )
            }

            return Array(rows)
        }.value
    }

    static func resortPreparedEntriesByScoreKeepingCurrentStable(_ manifest: inout SmartPhotoShuffleManifest) {
        let currentID: String? = {
            guard manifest.entries.indices.contains(manifest.currentIndex) else { return nil }
            return manifest.entries[manifest.currentIndex].id
        }()

        let indexed = manifest.entries.enumerated().map { (idx: $0.offset, entry: $0.element) }

        let prepared = indexed.filter { $0.entry.isPrepared }
        let unprepared = indexed.filter { !$0.entry.isPrepared }

        let preparedSorted = prepared.sorted { a, b in
            let sa = a.entry.scoreValue
            let sb = b.entry.scoreValue
            if sa != sb { return sa > sb }

            let da = a.entry.preparedAt ?? .distantPast
            let db = b.entry.preparedAt ?? .distantPast
            if da != db { return da > db }

            return a.idx < b.idx
        }

        manifest.entries = preparedSorted.map { $0.entry } + unprepared.map { $0.entry }

        if let currentID, let newIndex = manifest.entries.firstIndex(where: { $0.id == currentID }) {
            manifest.currentIndex = newIndex
        } else {
            manifest.currentIndex = max(0, min(manifest.currentIndex, manifest.entries.count - 1))
        }
    }
}

// MARK: - Scoring (Batch I)

private enum SmartPhotoQualityScorer {
    struct Result: Sendable {
        var score: Double
        var flags: [String]
    }

    static func mergeFlags(existing: [String], adding: [String]) -> [String] {
        var set = Set(existing)
        for f in adding {
            let t = f.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { set.insert(t) }
        }
        return Array(set).sorted()
    }

    static func displayFlags(_ flags: [String]) -> [String] {
        let drop: Set<String> = ["failed"]
        let kept = flags.filter { !drop.contains($0) }
        return Array(Set(kept)).sorted()
    }

    static func score(entryID: String, smartPhoto: SmartPhotoSpec) -> Result {
        let analysis = analysisCGImage(masterFileName: smartPhoto.masterFileName, maxPixel: 480)

        var faceCount: Int = 0
        var faceConfSum: Double = 0
        var blackFrac: Double = 0
        var whiteFrac: Double = 0
        var sharpNorm: Double = 0

        if let analysis {
            let faces = detectFaces(analysis)
            faceCount = faces.count
            faceConfSum = faces.confidenceSum

            let metrics = exposureAndSharpness(analysis)
            blackFrac = metrics.blackFrac
            whiteFrac = metrics.whiteFrac
            sharpNorm = metrics.sharpNorm
        }

        let cropStats = cropHeuristics(smartPhoto)

        var flags: [String] = []
        flags.append("faces\(faceCount)")

        if faceCount == 0 {
            flags.append("noFaces")
        }

        if sharpNorm < 0.18 {
            flags.append("soft")
        } else {
            flags.append("sharp")
        }

        if blackFrac > 0.45 {
            flags.append("dark")
        } else if whiteFrac > 0.45 {
            flags.append("bright")
        } else {
            flags.append("okExposure")
        }

        if cropStats.minArea < 0.12 {
            flags.append("extremeZoom")
        } else if cropStats.minArea < 0.20 {
            flags.append("zoom")
        }

        if cropStats.touchesEdges {
            flags.append("tight")
        }

        var score: Double = 100

        score += Double(min(faceCount, 4)) * 18
        score += faceConfSum * 12

        score += sharpNorm * 25

        let extreme = min(1.0, (blackFrac + whiteFrac) * 1.25)
        score += (1.0 - extreme) * 15

        if blackFrac > 0.45 { score -= 25 }
        if whiteFrac > 0.45 { score -= 25 }

        if cropStats.minArea < 0.12 { score -= 35 }
        else if cropStats.minArea < 0.20 { score -= 18 }

        if cropStats.touchesEdges { score -= 10 }

        return Result(score: score, flags: flags)
    }

    private static func cropHeuristics(_ smartPhoto: SmartPhotoSpec) -> (minArea: Double, touchesEdges: Bool) {
        let variants: [SmartPhotoVariantSpec] = [smartPhoto.small, smartPhoto.medium, smartPhoto.large].compactMap { $0 }

        var minArea: Double = 1.0
        var touches = false

        for v in variants {
            let r = v.cropRect.normalised()
            minArea = min(minArea, r.width * r.height)

            let left = r.x
            let top = r.y
            let right = r.x + r.width
            let bottom = r.y + r.height

            if left < 0.02 || top < 0.02 || right > 0.98 || bottom > 0.98 {
                touches = true
            }
        }

        return (minArea, touches)
    }

    private static func analysisCGImage(masterFileName: String, maxPixel: Int) -> CGImage? {
        let safe = SmartPhotoSpec.sanitisedFileName(masterFileName)
        guard !safe.isEmpty else { return nil }

        let url = AppGroup.imageFileURL(fileName: safe)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]

        guard let src = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else { return nil }

        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(64, maxPixel),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCache: false
        ]

        return CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOptions as CFDictionary)
    }

    private static func detectFaces(_ cgImage: CGImage) -> (count: Int, confidenceSum: Double) {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
            let faces = (request.results as? [VNFaceObservation]) ?? []
            let sum = faces.reduce(0.0) { $0 + Double($1.confidence) }
            return (faces.count, sum)
        } catch {
            return (0, 0)
        }
    }

    private static func exposureAndSharpness(_ cgImage: CGImage) -> (blackFrac: Double, whiteFrac: Double, sharpNorm: Double) {
        let w = max(1, cgImage.width)
        let h = max(1, cgImage.height)

        var pixels = [UInt8](repeating: 0, count: w * h)

        let ok: Bool = pixels.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return false }

            guard let ctx = CGContext(
                data: base,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }

            ctx.interpolationQuality = .low
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }

        guard ok else { return (0, 0, 0) }

        let step = max(1, min(w, h) / 220)

        var count = 0
        var black = 0
        var white = 0

        var mean = 0.0
        var m2 = 0.0

        for y in stride(from: 1, to: h - 1, by: step) {
            for x in stride(from: 1, to: w - 1, by: step) {
                let i = y * w + x
                let p = Int(pixels[i])

                if p <= 10 { black += 1 }
                if p >= 245 { white += 1 }

                let lap = Int(pixels[i - 1]) + Int(pixels[i + 1]) + Int(pixels[i - w]) + Int(pixels[i + w]) - (4 * p)
                let v = Double(lap)

                count += 1
                let delta = v - mean
                mean += delta / Double(count)
                let delta2 = v - mean
                m2 += delta * delta2
            }
        }

        guard count > 1 else { return (0, 0, 0) }

        let variance = max(0.0, m2 / Double(count - 1))
        let blackFrac = Double(black) / Double(count)
        let whiteFrac = Double(white) / Double(count)

        let sharpLog = log10(variance + 1.0)
        let sharpNorm = min(1.0, max(0.0, sharpLog / 4.0))

        return (blackFrac, whiteFrac, sharpNorm)
    }
}
