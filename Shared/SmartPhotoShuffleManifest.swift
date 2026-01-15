//
//  SmartPhotoShuffleManifest.swift
//  WidgetWeaver
//
//  Created by . . on 1/5/26.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

/// A compact shuffle manifest stored in the App Group container.
/// The widget reads this manifest to choose which pre-rendered image file to display.
public struct SmartPhotoShuffleManifest: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable, Identifiable {
        public var id: String

        public var smallFile: String?
        public var mediumFile: String?
        public var largeFile: String?

        public var preparedAt: Date?
        public var flags: [String]

        /// Higher is better. Nil means not yet scored.
        public var score: Double?

        public init(
            id: String,
            smallFile: String? = nil,
            mediumFile: String? = nil,
            largeFile: String? = nil,
            preparedAt: Date? = nil,
            flags: [String] = [],
            score: Double? = nil
        ) {
            self.id = id
            self.smallFile = smallFile
            self.mediumFile = mediumFile
            self.largeFile = largeFile
            self.preparedAt = preparedAt
            self.flags = flags
            self.score = score
        }

        public var isPrepared: Bool {
            let s = (smallFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let m = (mediumFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let l = (largeFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !s.isEmpty && !m.isEmpty && !l.isEmpty
        }

        public var scoreValue: Double {
            score ?? 0
        }
    }

    public var version: Int
    public var sourceID: String

    public var entries: [Entry]

    /// The persisted base index. Rotation is anchored to this index + `nextChangeDate`.
    public var currentIndex: Int

    /// User-selected rotation interval in minutes. A value <= 0 disables rotation.
    public var rotationIntervalMinutes: Int

    /// The next scheduled rotation time for `currentIndex`.
    /// If nil, rotation is disabled (or not yet scheduled).
    public var nextChangeDate: Date?

    public init(
        version: Int = 1,
        sourceID: String,
        entries: [Entry] = [],
        currentIndex: Int = 0,
        rotationIntervalMinutes: Int = 60,
        nextChangeDate: Date? = nil
    ) {
        self.version = version
        self.sourceID = sourceID
        self.entries = entries
        self.currentIndex = currentIndex
        self.rotationIntervalMinutes = rotationIntervalMinutes
        self.nextChangeDate = nextChangeDate
    }

    /// Returns the best entry to render:
    /// - Uses time-based rotation if enabled (`rotationIntervalMinutes` + `nextChangeDate`).
    /// - Otherwise prefers `currentIndex` when it points at a prepared entry.
    /// - Falls back to the first prepared entry.
    ///
    /// Note:
    /// WidgetKit may render future timeline entries ahead-of-time. This uses
    /// `WidgetWeaverRenderClock.now` so the chosen entry matches the current timeline entry date.
    public func entryForRender() -> Entry? {
        let now = WidgetWeaverRenderClock.now

        let prepared = preparedEntriesInOrder()
        guard !prepared.isEmpty else { return nil }

        let baseIdx = max(0, min(currentIndex, entries.count - 1))

        var currentPreparedPos: Int = 0
        if entries.indices.contains(baseIdx),
           entries[baseIdx].isPrepared,
           let pos = prepared.firstIndex(where: { $0.index == baseIdx })
        {
            currentPreparedPos = pos
        }

        let steps = rotationStepsElapsed(now: now)
        let rotatedPos = (currentPreparedPos + steps) % prepared.count
        return prepared[rotatedPos].entry
    }

    /// Returns the next scheduled rotation date relative to `now`.
    /// If rotation is off or not scheduled, returns nil.
    public func nextChangeDateFrom(now: Date) -> Date? {
        guard let intervalSeconds = rotationIntervalSeconds(),
              let anchor = nextChangeDate
        else {
            return nil
        }

        if now < anchor { return anchor }

        let elapsed = now.timeIntervalSince(anchor)
        let steps = Int(floor(elapsed / intervalSeconds)) + 1
        return anchor.addingTimeInterval(TimeInterval(steps) * intervalSeconds)
    }

    /// Advances `currentIndex` and `nextChangeDate` to catch up with time-based rotation.
    ///
    /// This is safe for the app to call when opened (or when the user interacts with shuffle controls)
    /// so persisted state doesn't drift when WidgetKit is throttled.
    ///
    /// Returns true if the manifest was modified.
    public mutating func catchUpRotation(now: Date) -> Bool {
        let steps = rotationStepsElapsed(now: now)
        guard steps > 0 else { return false }

        let prepared = preparedEntriesInOrder()
        guard !prepared.isEmpty else {
            nextChangeDate = nextChangeDateFrom(now: now)
            return true
        }

        let baseIdx = max(0, min(currentIndex, entries.count - 1))

        var currentPreparedPos: Int = 0
        if entries.indices.contains(baseIdx),
           entries[baseIdx].isPrepared,
           let pos = prepared.firstIndex(where: { $0.index == baseIdx })
        {
            currentPreparedPos = pos
        }

        let rotatedPos = (currentPreparedPos + steps) % prepared.count
        currentIndex = prepared[rotatedPos].index
        nextChangeDate = nextChangeDateFrom(now: now)

        return true
    }

    // MARK: - Rotation helpers

    private func rotationIntervalSeconds() -> TimeInterval? {
        let minutes = rotationIntervalMinutes
        guard minutes > 0 else { return nil }
        return TimeInterval(minutes) * 60.0
    }

    private func rotationStepsElapsed(now: Date) -> Int {
        guard let intervalSeconds = rotationIntervalSeconds(),
              let anchor = nextChangeDate
        else {
            return 0
        }

        if now < anchor { return 0 }

        let elapsed = now.timeIntervalSince(anchor)
        let steps = Int(floor(elapsed / intervalSeconds)) + 1
        return max(0, steps)
    }

    private func preparedEntriesInOrder() -> [(index: Int, entry: Entry)] {
        entries.enumerated().compactMap { pair in
            let (idx, entry) = pair
            guard entry.isPrepared else { return nil }
            return (idx, entry)
        }
    }
}

#if canImport(WidgetKit)
public extension SmartPhotoShuffleManifest.Entry {
    func fileName(for family: WidgetFamily) -> String? {
        switch family {
        case .systemSmall:
            return smallFile
        case .systemMedium:
            return mediumFile
        case .systemLarge:
            return largeFile
        default:
            return mediumFile ?? smallFile ?? largeFile
        }
    }
}
#endif

/// Storage helpers for shuffle manifests.
///
/// This is intentionally tiny and file-based (no CoreData / no heavy caching).
public enum SmartPhotoShuffleManifestStore {
    private static let directoryName = "WidgetWeaverSmartPhoto"

    /// UserDefaults key used as a lightweight invalidation signal.
    ///
    /// The shuffle manifest itself is file-based, so SwiftUI views that render the current photo
    /// need a cheap way to know when the manifest changed (e.g. user tapped “Next photo”).
    ///
    /// Any code path that saves a manifest should bump this token.
    public static let updateTokenKey: String = "widgetweaver.smartPhotoShuffle.updateToken"

    private static func ensureDirectoryExists() {
        let url = AppGroup.containerURL.appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        } catch {
            // Intentionally ignored.
        }
    }

    private static func sanitisedFileName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = (trimmed as NSString).lastPathComponent
        return String(last.prefix(256))
    }

    public static func createManifestFileName(prefix: String = "smart-shuffle", ext: String = "json") -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePrefix = trimmedPrefix.isEmpty ? "smart-shuffle" : String(trimmedPrefix.prefix(32))
        let safeExt = ext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "json" : ext
        return "\(safePrefix)-\(UUID().uuidString).\(safeExt)"
    }

    public static func manifestURL(fileName: String) -> URL {
        ensureDirectoryExists()
        let safe = sanitisedFileName(fileName)
        let dir = AppGroup.containerURL.appendingPathComponent(directoryName, isDirectory: true)
        return dir.appendingPathComponent(safe)
    }

    public static func load(fileName: String) -> SmartPhotoShuffleManifest? {
        let safe = sanitisedFileName(fileName)
        guard !safe.isEmpty else { return nil }

        let url = manifestURL(fileName: safe)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SmartPhotoShuffleManifest.self, from: data)
    }

    public static func save(_ manifest: SmartPhotoShuffleManifest, fileName: String) throws {
        ensureDirectoryExists()
        let safe = sanitisedFileName(fileName)
        guard !safe.isEmpty else { return }

        let url = manifestURL(fileName: safe)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: url, options: [.atomic])

        bumpUpdateToken()
    }

    private static func bumpUpdateToken() {
        let defaults = AppGroup.userDefaults
        let current = defaults.integer(forKey: updateTokenKey)
        defaults.set(current &+ 1, forKey: updateTokenKey)
    }
}
