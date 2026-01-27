//
//  SmartPhotoMemoriesEngine.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import Foundation
import Photos
import UIKit

enum SmartPhotoMemoriesMode: String, CaseIterable, Hashable, Sendable, Identifiable {
    case onThisDay
    case onThisWeek

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .onThisDay:
            return "On this day"
        case .onThisWeek:
            return "On this week"
        }
    }

    /// String prefix stored in `SmartPhotoShuffleManifest.sourceID`.
    ///
    /// No schema changes: mode is encoded via a stable prefix.
    var sourceIDPrefix: String {
        "memories:\(rawValue)"
    }

    func sourceID(now: Date, calendar: Calendar) -> String {
        let suffix = sourceIDSuffix(now: now, calendar: calendar)
        if suffix.isEmpty { return sourceIDPrefix }
        return "\(sourceIDPrefix):\(suffix)"
    }

    private func sourceIDSuffix(now: Date, calendar: Calendar) -> String {
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)

        func two(_ v: Int) -> String {
            let clamped = max(0, min(v, 99))
            return String(format: "%02d", clamped)
        }

        switch self {
        case .onThisDay:
            return "\(two(month))-\(two(day))"
        case .onThisWeek:
            return "weekOf-\(two(month))-\(two(day))"
        }
    }
}

enum SmartPhotoMemoriesEngine {

    enum MemoriesError: LocalizedError {
        case disabled
        case photoAccessDenied
        case noCandidates
        case manifestSaveFailed(String)
        case manifestLoadFailed

        var errorDescription: String? {
            switch self {
            case .disabled:
                return "Memories is disabled."
            case .photoAccessDenied:
                return "Photos access is off."
            case .noCandidates:
                return "No photos found for this date window."
            case .manifestSaveFailed(let detail):
                return "Failed to save Memories manifest: \(detail)"
            case .manifestLoadFailed:
                return "Memories manifest not found."
            }
        }
    }

    struct BuildResult: Sendable {
        var manifestFileName: String
        var candidateCount: Int
        var selectedCount: Int
        var preparedNow: Int
        var failedNow: Int
    }

    /// Builds a Smart Photo shuffle manifest for Memories (On this day / On this week) and
    /// prepares an initial batch so the widget can render immediately.
    ///
    /// This is engine-only and should be called from a gated UI surface.
    @MainActor
    static func buildManifestAndPrepareInitialBatch(
        mode: SmartPhotoMemoriesMode,
        now: Date = Date(),
        calendar: Calendar = .current,
        maxYearsBack: Int = 20,
        perYearLimit: Int = 40,
        maxEntries: Int = 200,
        initialPrepBatchSize: Int = 6,
        defaultRotationMinutes: Int? = nil
    ) async throws -> BuildResult {
        guard FeatureFlags.smartPhotoMemoriesEnabled else {
            throw MemoriesError.disabled
        }

        let ok = await SmartPhotoAlbumShuffleControlsEngine.ensurePhotoAccess()
        EditorToolRegistry.capabilitiesDidChange(reason: .photoLibraryAccessChanged)
        guard ok else {
            throw MemoriesError.photoAccessDenied
        }

        let rules = SmartPhotoShuffleRulesStore.load()

        let (candidateCount, selectedIDs) = await Task.detached(priority: .utility) {
            return buildCandidateIDs(
                mode: mode,
                now: now,
                calendar: calendar,
                rules: rules,
                maxYearsBack: maxYearsBack,
                perYearLimit: perYearLimit,
                maxEntries: maxEntries
            )
        }.value

        guard !selectedIDs.isEmpty else {
            throw MemoriesError.noCandidates
        }

        let manifestFileName = SmartPhotoShuffleManifestStore.createManifestFileName(prefix: "smart-memories", ext: "json")

        let rotationMinutes: Int = {
            if let defaultRotationMinutes {
                return defaultRotationMinutes
            }

            switch mode {
            case .onThisDay:
                return 1440
            case .onThisWeek:
                return 1440
            }
        }()

        let nextChange: Date? = {
            guard rotationMinutes > 0 else { return nil }
            return now.addingTimeInterval(TimeInterval(rotationMinutes) * 60.0)
        }()

        let manifest = SmartPhotoShuffleManifest(
            version: 4,
            sourceID: mode.sourceID(now: now, calendar: calendar),
            entries: selectedIDs.map { SmartPhotoShuffleManifest.Entry(id: $0) },
            currentIndex: 0,
            rotationIntervalMinutes: rotationMinutes,
            nextChangeDate: nextChange
        )

        do {
            try SmartPhotoShuffleManifestStore.save(manifest, fileName: manifestFileName)
        } catch {
            throw MemoriesError.manifestSaveFailed(error.localizedDescription)
        }

        let targets = SmartPhotoRenderTargets.forCurrentDevice()

        let prep = await prepareNextBatch(
            manifestFileName: manifestFileName,
            renderTargets: targets,
            batchSize: initialPrepBatchSize
        )

        return BuildResult(
            manifestFileName: manifestFileName,
            candidateCount: candidateCount,
            selectedCount: selectedIDs.count,
            preparedNow: prep.preparedNow,
            failedNow: prep.failedNow
        )
    }

    // MARK: - Candidate fetch

    private struct Candidate: Hashable, Sendable {
        var id: String
        var createdAt: Date
        var year: Int
        var isFavourite: Bool
    }

    // MARK: - Anti-repeat

    private static func antiRepeatWindowSeconds(for mode: SmartPhotoMemoriesMode) -> TimeInterval {
        switch mode {
        case .onThisDay:
            // Tight window to drop near-duplicates (bursts) while keeping variety.
            return 60.0 * 30.0

        case .onThisWeek:
            // Wider window to avoid long runs of the same event within a single week window.
            return 60.0 * 60.0 * 3.0
        }
    }

    private static func thinCandidatesForAntiRepeat(
        _ candidates: [Candidate],
        mode: SmartPhotoMemoriesMode,
        perYearLimit: Int
    ) -> [Candidate] {
        let safeLimit = max(1, min(perYearLimit, 250))
        guard candidates.count > 0 else { return [] }

        // Keep behaviour stable for sparse years.
        let minKeep: Int = {
            switch mode {
            case .onThisDay:
                return min(6, safeLimit)
            case .onThisWeek:
                return min(10, safeLimit)
            }
        }()

        guard candidates.count > minKeep else {
            return Array(candidates.prefix(safeLimit))
        }

        let window = antiRepeatWindowSeconds(for: mode)
        guard window > 0 else {
            return Array(candidates.prefix(safeLimit))
        }

        var kept: [Candidate] = []
        kept.reserveCapacity(min(candidates.count, safeLimit))

        var lastKept: Date? = nil

        for candidate in candidates {
            if kept.count >= safeLimit {
                break
            }

            if kept.isEmpty {
                kept.append(candidate)
                lastKept = candidate.createdAt
                continue
            }

            if candidate.isFavourite {
                kept.append(candidate)
                lastKept = candidate.createdAt
                continue
            }

            if let lastKept {
                let delta = abs(lastKept.timeIntervalSince(candidate.createdAt))
                if delta < window {
                    continue
                }
            }

            kept.append(candidate)
            lastKept = candidate.createdAt
        }

        // If filtering made the year too sparse, fall back to the original list.
        if kept.count < minKeep {
            return Array(candidates.prefix(safeLimit))
        }

        return kept
    }

    private static func buildCandidateIDs(
        mode: SmartPhotoMemoriesMode,
        now: Date,
        calendar: Calendar,
        rules: SmartPhotoShuffleRules,
        maxYearsBack: Int,
        perYearLimit: Int,
        maxEntries: Int
    ) -> (candidateCount: Int, selectedIDs: [String]) {
        let clampedYearsBack = max(1, min(maxYearsBack, 50))
        let clampedPerYear = max(1, min(perYearLimit, 250))
        let clampedMaxEntries = max(1, min(maxEntries, 2000))

        let currentYear = calendar.component(.year, from: now)
        let earliestYear = earliestAssetYear(calendar: calendar) ?? (currentYear - clampedYearsBack)
        let startYear = max(earliestYear, currentYear - clampedYearsBack)

        if startYear > currentYear {
            return (0, [])
        }

        var perYearCandidates: [Int: [Candidate]] = [:]

        for year in stride(from: currentYear, through: startYear, by: -1) {
            guard let window = dateWindow(mode: mode, year: year, now: now, calendar: calendar) else {
                continue
            }

            let fetched = fetchCandidates(
                window: window,
                year: year,
                mode: mode,
                rules: rules,
                perYearLimit: clampedPerYear,
                calendar: calendar
            )

            if !fetched.isEmpty {
                perYearCandidates[year] = fetched
            }
        }

        let allCount = perYearCandidates.values.reduce(0) { $0 + $1.count }
        if allCount == 0 {
            return (0, [])
        }

        // Interleave across years to keep variety predictable.
        let yearsDesc = perYearCandidates.keys.sorted(by: >)
        var indices: [Int: Int] = [:]
        var out: [String] = []
        out.reserveCapacity(min(allCount, clampedMaxEntries))

        while out.count < clampedMaxEntries {
            var didAppend = false

            for year in yearsDesc {
                guard let arr = perYearCandidates[year] else { continue }
                let idx = indices[year, default: 0]
                guard idx < arr.count else { continue }

                let candidate = arr[idx]
                indices[year] = idx + 1

                let id = candidate.id.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else { continue }

                out.append(id)
                didAppend = true

                if out.count >= clampedMaxEntries {
                    break
                }
            }

            if !didAppend {
                break
            }
        }

        // De-duplication is cheap insurance. Local identifiers are expected to be unique,
        // but interleaving logic can be extended later.
        var seen = Set<String>()
        let deduped = out.filter { seen.insert($0).inserted }

        return (allCount, deduped)
    }

    private static func earliestAssetYear(calendar: Calendar) -> Int? {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.fetchLimit = 1

        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard let asset = assets.firstObject else { return nil }
        guard let date = asset.creationDate else { return nil }
        return calendar.component(.year, from: date)
    }

    private static func dateWindow(
        mode: SmartPhotoMemoriesMode,
        year: Int,
        now: Date,
        calendar: Calendar
    ) -> DateInterval? {
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)

        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = calendar.timeZone
        comps.year = year
        comps.month = month
        comps.day = day

        guard let base = calendar.date(from: comps) else { return nil }

        switch mode {
        case .onThisDay:
            let start = calendar.startOfDay(for: base)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return DateInterval(start: start, end: end)

        case .onThisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: base) else { return nil }
            return interval
        }
    }

    private static func fetchCandidates(
        window: DateInterval,
        year: Int,
        mode: SmartPhotoMemoriesMode,
        rules: SmartPhotoShuffleRules,
        perYearLimit: Int,
        calendar: Calendar
    ) -> [Candidate] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        // `creationDate` can be nil for some assets; PhotoKit handles the predicate.
        options.predicate = NSPredicate(
            format: "creationDate >= %@ AND creationDate < %@",
            window.start as NSDate,
            window.end as NSDate
        )

        let assets = PHAsset.fetchAssets(with: .image, options: options)

        if assets.count == 0 {
            return []
        }

        var out: [Candidate] = []
        out.reserveCapacity(min(assets.count, perYearLimit))

        var added = 0

        assets.enumerateObjects { asset, _, stop in
            if added >= perYearLimit {
                stop.pointee = true
                return
            }

            if asset.isHidden {
                return
            }

            if !rules.includeScreenshots, asset.mediaSubtypes.contains(.photoScreenshot) {
                return
            }

            let minDim = min(asset.pixelWidth, asset.pixelHeight)
            if minDim < rules.minimumPixelDimension {
                return
            }

            guard let createdAt = asset.creationDate else {
                return
            }

            let id = asset.localIdentifier
            if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return
            }

            let candidate = Candidate(
                id: id,
                createdAt: createdAt,
                year: year,
                isFavourite: asset.isFavorite
            )

            out.append(candidate)
            added += 1
        }

        // Prefer favourites earlier within the year, then recency.
        out.sort { a, b in
            if a.isFavourite != b.isFavourite { return a.isFavourite && !b.isFavourite }
            if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
            return a.id < b.id
        }

        return thinCandidatesForAntiRepeat(out, mode: mode, perYearLimit: perYearLimit)
    }

    // MARK: - Initial prep

    private struct PrepOutcome: Sendable {
        var preparedNow: Int
        var failedNow: Int
    }

    private static func prepareNextBatch(
        manifestFileName: String,
        renderTargets: SmartPhotoRenderTargets,
        batchSize: Int
    ) async -> PrepOutcome {
        let mf = manifestFileName
        let bs = max(0, min(batchSize, 50))

        guard !mf.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return PrepOutcome(preparedNow: 0, failedNow: 0)
        }

        guard bs > 0 else {
            return PrepOutcome(preparedNow: 0, failedNow: 0)
        }

        return await Task.detached(priority: .utility) {
            guard var manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else {
                return PrepOutcome(preparedNow: 0, failedNow: 0)
            }

            var preparedNow = 0
            var failedNow = 0
            var didUpdate = false

            for idx in manifest.entries.indices {
                if preparedNow >= bs {
                    break
                }

                var entry = manifest.entries[idx]

                if entry.isPrepared {
                    continue
                }

                if entry.flags.contains("failed") {
                    continue
                }

                do {
                    let data = try await SmartPhotoAlbumShuffleControlsEngine.requestImageData(localIdentifier: entry.id)

                    let imageSpec: ImageSpec = try autoreleasepool {
                        try SmartPhotoPipeline.prepare(from: data, renderTargets: renderTargets)
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

                    entry.sourceFileName = sp.masterFileName

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

            return PrepOutcome(preparedNow: preparedNow, failedNow: failedNow)
        }.value
    }
}
