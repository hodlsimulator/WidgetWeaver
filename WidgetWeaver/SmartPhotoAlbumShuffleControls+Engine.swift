//
//  SmartPhotoAlbumShuffleControls+Engine.swift
//  WidgetWeaver
//
//  Created by . . on 1/5/26.
//

import Foundation
import Photos
// MARK: - Smart Rules (Album Shuffle)

enum SmartPhotoShuffleSortOrder: String, CaseIterable, Hashable, Sendable, Identifiable {
    case newestFirst
    case oldestFirst
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        case .random: return "Random"
        }
    }
}

struct SmartPhotoShuffleRules: Hashable, Sendable {
    var includeScreenshots: Bool
    var minimumPixelDimension: Int
    var sortOrder: SmartPhotoShuffleSortOrder

    static let `default` = SmartPhotoShuffleRules(
        includeScreenshots: false,
        minimumPixelDimension: 800,
        sortOrder: .newestFirst
    )

    func normalised() -> SmartPhotoShuffleRules {
        var out = self
        out.minimumPixelDimension = max(200, min(4000, out.minimumPixelDimension))
        return out
    }
}

enum SmartPhotoShuffleRulesStore {
    enum Keys {
        static let includeScreenshots = "widgetweaver.smartphoto.shuffleRules.includeScreenshots"
        static let minimumPixelDimension = "widgetweaver.smartphoto.shuffleRules.minimumPixelDimension"
        static let sortOrder = "widgetweaver.smartphoto.shuffleRules.sortOrder"
    }

    static func load(defaults: UserDefaults = AppGroup.userDefaults) -> SmartPhotoShuffleRules {
        let includeScreenshots = defaults.object(forKey: Keys.includeScreenshots) as? Bool ?? SmartPhotoShuffleRules.default.includeScreenshots

        let storedMinDim = defaults.integer(forKey: Keys.minimumPixelDimension)
        let minDim = (storedMinDim > 0) ? storedMinDim : SmartPhotoShuffleRules.default.minimumPixelDimension

        let rawOrder = defaults.string(forKey: Keys.sortOrder) ?? SmartPhotoShuffleRules.default.sortOrder.rawValue
        let sortOrder = SmartPhotoShuffleSortOrder(rawValue: rawOrder) ?? SmartPhotoShuffleRules.default.sortOrder

        return SmartPhotoShuffleRules(
            includeScreenshots: includeScreenshots,
            minimumPixelDimension: minDim,
            sortOrder: sortOrder
        ).normalised()
    }

    static func save(_ rules: SmartPhotoShuffleRules, defaults: UserDefaults = AppGroup.userDefaults) {
        let n = rules.normalised()
        defaults.set(n.includeScreenshots, forKey: Keys.includeScreenshots)
        defaults.set(n.minimumPixelDimension, forKey: Keys.minimumPixelDimension)
        defaults.set(n.sortOrder.rawValue, forKey: Keys.sortOrder)
    }
}

enum SmartPhotoAlbumShuffleControlsEngine {
    enum PrepError: Error {
        case photoAccessDenied
        case noUsableImages
    }

    static func ensurePhotoAccess() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .authorized || status == .limited { return true }

        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return newStatus == .authorized || newStatus == .limited
    }

    static func ensurePhotoAccessOrThrow() async throws {
        let ok = await ensurePhotoAccess()
        if !ok { throw PrepError.photoAccessDenied }
    }

    static func requestImageData(assetID: String, targetMaxDimension: CGFloat = 2048) async -> Data? {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return nil }

        return await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.isNetworkAccessAllowed = true
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .exact

            let targetSize = CGSize(width: targetMaxDimension, height: targetMaxDimension)
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: opts) { data, _, _, info in
                if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    static func prepareSmartPhotoRendersFromManifest(fileName: String, budget: Int, saveStatusMessage: @escaping (String) -> Void) async throws -> Int {
        try await ensurePhotoAccessOrThrow()

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: fileName) else {
            saveStatusMessage("Shuffle manifest not found.")
            return 0
        }

        if manifest.entries.isEmpty {
            saveStatusMessage("Shuffle manifest has no entries.")
            return 0
        }

        var preparedCount = 0

        let indicesToPrepare: [Int] = {
            // Prepare starting from currentIndex, wrapping around.
            let n = manifest.entries.count
            guard n > 0 else { return [] }
            var out: [Int] = []
            out.reserveCapacity(min(budget, n))
            var i = manifest.currentIndex
            while out.count < min(budget, n) {
                out.append(i)
                i = (i + 1) % n
            }
            return out
        }()

        for idx in indicesToPrepare {
            if preparedCount >= budget { break }

            var entry = manifest.entries[idx]

            // Skip already-prepared entries.
            if let preparedFile = entry.preparedFileName,
               !preparedFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               AppGroupImageStore.exists(fileName: preparedFile) {
                continue
            }

            saveStatusMessage("Preparing \(preparedCount + 1)/\(budget)…")

            guard let data = await requestImageData(assetID: entry.id) else {
                entry.flags.append("noData")
                manifest.entries[idx] = entry
                continue
            }

            guard let uiImage = UIImage(data: data) else {
                entry.flags.append("decodeFail")
                manifest.entries[idx] = entry
                continue
            }

            // Score raw image quality.
            let scoreResult = SmartPhotoQualityScorer.score(uiImage: uiImage)
            entry.score = scoreResult.score
            entry.flags.append(contentsOf: scoreResult.flags)

            // Save prepared file.
            let preparedFileName = "shuffle_prepared_\(UUID().uuidString).jpg"
            if let jpg = uiImage.jpegData(compressionQuality: 0.92) {
                AppGroupImageStore.save(data: jpg, fileName: preparedFileName)
                entry.preparedFileName = preparedFileName
                entry.preparedAt = Date()
                preparedCount += 1
            } else {
                entry.flags.append("jpegFail")
            }

            manifest.entries[idx] = entry
        }

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: fileName)
        } catch {
            saveStatusMessage("Failed to save shuffle manifest.")
        }

        saveStatusMessage("Prepared \(preparedCount) image(s).")
        return preparedCount
    }

    static func fetchImageAssetIdentifiers(albumID: String) -> [String] {
        let collections = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil)
        guard let collection = collections.firstObject else { return [] }

        let rules = SmartPhotoShuffleRulesStore.load()

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        switch rules.sortOrder {
        case .newestFirst:
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        case .oldestFirst:
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        case .random:
            options.sortDescriptors = nil
        }

        let assets = PHAsset.fetchAssets(in: collection, options: options)

        var ids: [String] = []
        ids.reserveCapacity(assets.count)

        let minAllowed = rules.minimumPixelDimension

        assets.enumerateObjects { asset, _, _ in
            if !rules.includeScreenshots, asset.mediaSubtypes.contains(.photoScreenshot) {
                return
            }

            let minDim = min(asset.pixelWidth, asset.pixelHeight)
            if minDim < minAllowed {
                return
            }

            ids.append(asset.localIdentifier)
        }

        if rules.sortOrder == .random {
            ids.shuffle()
        }

        return ids
    }

    static func scoreAndSortManifestEntries(_ entries: [SmartPhotoShuffleManifest.Entry]) -> [SmartPhotoShuffleManifest.Entry] {
        // Higher score first; unscored entries last.
        entries.sorted { a, b in
            let as = a.score ?? -Double.infinity
            let bs = b.score ?? -Double.infinity
            if as == bs {
                // Stable fallback: prefer preparedAt newer.
                let ad = a.preparedAt ?? .distantPast
                let bd = b.preparedAt ?? .distantPast
                return ad > bd
            }
            return as > bs
        }
    }
}
