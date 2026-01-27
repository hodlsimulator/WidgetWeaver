//
//  SmartPhotoAlbumShuffleControls+Logic.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import Foundation
import SwiftUI
import WidgetKit

extension SmartPhotoAlbumShuffleControls {
    // MARK: - Focus snapshot handling

    func handleAlbumPickerPresentationChange(isPresented _: Bool) {
        // Focus handling disabled here because focus targets differ between builds.
    }

    // MARK: - Albums load

    func loadAlbumsIfNeeded() async {
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

    func configureShuffle(album: AlbumOption) async {
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

        if FeatureFlags.smartPhotoMemoriesEnabled {
            selectedSourceKey = SmartPhotoShuffleSourceKey.album
            sourceSelectionHydrationManifestFileName = manifestFile
        }

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

    func configureMemories(mode: SmartPhotoMemoriesMode) async {
        guard FeatureFlags.smartPhotoMemoriesEnabled else {
            saveStatusMessage = "Memories is disabled."
            return
        }

        guard var sp = smartPhoto else {
            saveStatusMessage = "Make Smart Photo first."
            return
        }

        importInProgress = true
        defer { importInProgress = false }

        saveStatusMessage = "Building \(mode.displayName)…"

        do {
            let result = try await SmartPhotoMemoriesEngine.buildManifestAndPrepareInitialBatch(mode: mode)

            sp.shuffleManifestFileName = result.manifestFileName
            smartPhoto = sp

            WidgetSpecStore.shared.setSmartPhotoShuffleManifestFileName(specID: specID, manifestFileName: result.manifestFileName)
            WidgetWeaverWidgetRefresh.forceKick()

            let failureSuffix = result.failedNow > 0 ? " (\(result.failedNow) failed)" : ""
            saveStatusMessage = "Shuffle configured for \(mode.displayName) (\(result.selectedCount) photos).\nPrepared \(result.preparedNow) now\(failureSuffix)."

            selectedSourceKey = mode.rawValue
            sourceSelectionHydrationManifestFileName = result.manifestFileName

            await refreshFromManifest()
        } catch let error as SmartPhotoMemoriesEngine.MemoriesError {
            switch error {
            case .disabled:
                saveStatusMessage = "Memories is disabled."

            case .photoAccessDenied:
                saveStatusMessage = "Photo library access is off.\nEnable Photos access in Settings."

            case .noCandidates:
                if mode == .onThisDay {
                    saveStatusMessage = "No usable photos found for \(mode.displayName).\nTry “On this week”, or choose an album."
                } else {
                    saveStatusMessage = "No usable photos found for \(mode.displayName).\nTry choosing an album."
                }

            case .manifestSaveFailed(let detail):
                saveStatusMessage = "Failed to save Memories manifest: \(detail)"

            case .manifestLoadFailed:
                saveStatusMessage = "Memories manifest not found."
            }
        } catch {
            saveStatusMessage = "Memories failed: \(error.localizedDescription)"
        }
    }

    func disableShuffle() {
        guard var sp = smartPhoto else { return }
        sp.shuffleManifestFileName = nil
        smartPhoto = sp

        // Persist immediately so the widget extension stays in sync with the editor.
        WidgetSpecStore.shared.setSmartPhotoShuffleManifestFileName(specID: specID, manifestFileName: nil)

        progress = nil
        nextChangeDate = nil
        rotationIntervalMinutes = 60

        if FeatureFlags.smartPhotoMemoriesEnabled {
            sourceSelectionHydrationManifestFileName = ""
            saveStatusMessage = "Shuffle disabled."
        } else {
            saveStatusMessage = "Album shuffle disabled."
        }
    }

    // MARK: - Rotation

    func setRotationInterval(minutes: Int) async {
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

    func rotationLabel(minutes: Int) -> String {
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

    func scheduledNextChangeDate(from now: Date, minutes: Int) -> Date? {
        guard minutes > 0 else { return nil }
        return now.addingTimeInterval(TimeInterval(minutes) * 60.0)
    }

    func advanceToNextPrepared() async {
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

    func prepareNextBatch(alreadyBusy _: Bool) async {
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

        let outcomeTask = Task.detached(priority: .utility) { () async -> BatchOutcome? in
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
        }

        let outcome: BatchOutcome? = await outcomeTask.value

        // Ignore results if the user switched manifests mid-batch.
        guard manifestFileName == mf else { return }

        guard let outcome else {
            saveStatusMessage = "Shuffle manifest not found."
            await refreshFromManifest()
            return
        }

        if outcome.didUpdate {
            await MainActor.run {
                WidgetWeaverWidgetRefresh.kickIfNeeded(minIntervalSeconds: 20)
            }
        }

        await refreshFromManifest()

        if outcome.preparedNow == 0, outcome.failedNow == 0 {
            saveStatusMessage = "No more photos to prepare right now."
        } else if outcome.failedNow == 0 {
            saveStatusMessage = "Prepared \(outcome.preparedNow) photos for shuffle."
        } else {
            saveStatusMessage = "Prepared \(outcome.preparedNow) photos (\(outcome.failedNow) failed)."
        }
    }

    func autoPrepareWhilePossible() async {
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

    func refreshFromManifest() async {
        let mf = manifestFileName
        guard !mf.isEmpty else {
            await MainActor.run {
                progress = nil
                nextChangeDate = nil
                rotationIntervalMinutes = 60
                configuredSourceKey = SmartPhotoShuffleSourceKey.album

                if FeatureFlags.smartPhotoMemoriesEnabled {
                    sourceSelectionHydrationManifestFileName = ""
                }
            }
            return
        }

        guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
            await MainActor.run {
                progress = nil
                nextChangeDate = nil
                rotationIntervalMinutes = 60
                configuredSourceKey = SmartPhotoShuffleSourceKey.album

                if FeatureFlags.smartPhotoMemoriesEnabled {
                    sourceSelectionHydrationManifestFileName = ""
                }
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

        let inferredMemoriesMode: SmartPhotoMemoriesMode? = {
            guard FeatureFlags.smartPhotoMemoriesEnabled else { return nil }

            let sourceID = manifest.sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            if sourceID.hasPrefix(SmartPhotoMemoriesMode.onThisDay.sourceIDPrefix) {
                return .onThisDay
            }
            if sourceID.hasPrefix(SmartPhotoMemoriesMode.onThisWeek.sourceIDPrefix) {
                return .onThisWeek
            }

            return nil
        }()

        let configuredKey: String = inferredMemoriesMode?.rawValue ?? SmartPhotoShuffleSourceKey.album

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

            configuredSourceKey = configuredKey

            if FeatureFlags.smartPhotoMemoriesEnabled {
                if sourceSelectionHydrationManifestFileName != mf {
                    selectedSourceKey = configuredKey
                    sourceSelectionHydrationManifestFileName = mf
                }
            }
        }
    }

    struct ProgressSummary: Hashable {
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
