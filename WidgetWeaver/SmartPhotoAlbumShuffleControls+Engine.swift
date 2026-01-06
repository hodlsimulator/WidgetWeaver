//
//  SmartPhotoAlbumShuffleControls+Engine.swift
//  WidgetWeaver
//
//  Created by . . on 1/6/26.
//

import Foundation
import Photos

enum PrepError: Error {
    case missingSmartPhoto
    case missingVariants
}

enum AlbumPickerState: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
}

struct AlbumOption: Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var count: Int
}

struct ProgressSummary: Hashable, Sendable {
    var total: Int
    var prepared: Int
    var failed: Int
    var currentIndex: Int

    static func from(manifest: SmartPhotoShuffleManifest) -> ProgressSummary {
        let total = manifest.entries.count
        let prepared = manifest.entries.filter { $0.isPrepared }.count
        let failed = manifest.entries.filter { $0.flags.contains("failed") && !$0.isPrepared }.count
        let currentIndex = manifest.currentIndex
        return ProgressSummary(total: total, prepared: prepared, failed: failed, currentIndex: currentIndex)
    }
}

struct RankingRow: Identifiable, Hashable, Sendable {
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

    static func preview(from manifest: SmartPhotoShuffleManifest, maxRows: Int) -> [RankingRow] {
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

        return sorted.prefix(max(1, maxRows)).map { entry in
            RankingRow(
                id: entry.id,
                isCurrent: (entry.id == currentID),
                score: entry.scoreValue,
                flags: entry.flags.filter { $0 != "failed" }
            )
        }
    }
}

enum SmartPhotoAlbumShuffleControlsEngine {

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

    static func fetchAlbumOptions() -> [AlbumOption] {
        let imageOptions: PHFetchOptions = {
            let o = PHFetchOptions()
            o.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            return o
        }()

        func countImages(in collection: PHAssetCollection) -> Int {
            PHAsset.fetchAssets(in: collection, options: imageOptions).count
        }

        var out: [AlbumOption] = []
        var seen = Set<String>()

        func appendCollection(_ collection: PHAssetCollection, overrideTitle: String? = nil) {
            let id = collection.localIdentifier
            guard !seen.contains(id) else { return }
            seen.insert(id)

            let title = (overrideTitle ?? collection.localizedTitle ?? "Album")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let count = countImages(in: collection)
            guard count > 0 else { return }

            out.append(AlbumOption(id: id, title: title.isEmpty ? "Album" : title, count: count))
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

        var user: [AlbumOption] = []
        PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            .enumerateObjects { collection, _, _ in
                let id = collection.localIdentifier
                if seen.contains(id) { return }

                let title = (collection.localizedTitle ?? "Album").trimmingCharacters(in: .whitespacesAndNewlines)
                let count = countImages(in: collection)
                guard count > 0 else { return }

                user.append(AlbumOption(id: id, title: title.isEmpty ? "Album" : title, count: count))
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
            throw NSError(domain: "SmartPhotoShuffle", code: 1, userInfo: [NSLocalizedDescriptionKey: "Asset not found"])
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
                    cont.resume(throwing: NSError(domain: "SmartPhotoShuffle", code: 2, userInfo: [NSLocalizedDescriptionKey: "No image data"]))
                    return
                }
                cont.resume(returning: data)
            }
        }
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
            manifest.currentIndex = max(0, min(manifest.currentIndex, max(0, manifest.entries.count - 1)))
        }
    }
}
