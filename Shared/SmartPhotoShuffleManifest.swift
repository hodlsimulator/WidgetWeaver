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

        /// App Group file name for the persistent source image for this entry.
        ///
        /// Constraint:
        /// The widget extension cannot read the Photos library. To support manual re-rendering
        /// (per-photo overrides) from the app, every shuffle entry needs a stable source image
        /// stored in the App Group container.
        public var sourceFileName: String?

        public var smallFile: String?
        public var mediumFile: String?
        public var largeFile: String?

        /// Auto crop rects (normalised 0...1). These allow the crop editor to reopen using
        /// the same auto framing that produced the auto renders.
        public var smallAutoCropRect: NormalisedRect?
        public var mediumAutoCropRect: NormalisedRect?
        public var largeAutoCropRect: NormalisedRect?

        /// Optional manual per-size render file names.
        /// When present, these should be preferred over the auto render file names.
        public var smallManualFile: String?
        public var mediumManualFile: String?
        public var largeManualFile: String?

        /// Optional manual crop rects (normalised 0...1) used to reopen the crop editor.
        public var smallManualCropRect: NormalisedRect?
        public var mediumManualCropRect: NormalisedRect?
        public var largeManualCropRect: NormalisedRect?

        public var preparedAt: Date?
        public var flags: [String]

        /// Higher is better. Nil means not yet scored.
        public var score: Double?

        public init(
            id: String,
            sourceFileName: String? = nil,
            smallFile: String? = nil,
            mediumFile: String? = nil,
            largeFile: String? = nil,
            smallAutoCropRect: NormalisedRect? = nil,
            mediumAutoCropRect: NormalisedRect? = nil,
            largeAutoCropRect: NormalisedRect? = nil,
            smallManualFile: String? = nil,
            mediumManualFile: String? = nil,
            largeManualFile: String? = nil,
            smallManualCropRect: NormalisedRect? = nil,
            mediumManualCropRect: NormalisedRect? = nil,
            largeManualCropRect: NormalisedRect? = nil,
            preparedAt: Date? = nil,
            flags: [String] = [],
            score: Double? = nil
        ) {
            self.id = id
            self.sourceFileName = sourceFileName
            self.smallFile = smallFile
            self.mediumFile = mediumFile
            self.largeFile = largeFile
            self.smallAutoCropRect = smallAutoCropRect
            self.mediumAutoCropRect = mediumAutoCropRect
            self.largeAutoCropRect = largeAutoCropRect
            self.smallManualFile = smallManualFile
            self.mediumManualFile = mediumManualFile
            self.largeManualFile = largeManualFile
            self.smallManualCropRect = smallManualCropRect
            self.mediumManualCropRect = mediumManualCropRect
            self.largeManualCropRect = largeManualCropRect
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

        public var hasSourceImageFile: Bool {
            let t = (sourceFileName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty
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
        let manualCandidate: String?
        let autoCandidate: String?

        switch family {
        case .systemSmall:
            manualCandidate = smallManualFile
            autoCandidate = smallFile
        case .systemMedium:
            manualCandidate = mediumManualFile
            autoCandidate = mediumFile
        case .systemLarge:
            manualCandidate = largeManualFile
            autoCandidate = largeFile
        default:
            // Prefer medium as the general fallback (matches existing behaviour).
            manualCandidate = mediumManualFile ?? smallManualFile ?? largeManualFile
            autoCandidate = mediumFile ?? smallFile ?? largeFile
        }

        let manualTrimmed = (manualCandidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !manualTrimmed.isEmpty {
            let url = AppGroup.imageFileURL(fileName: manualTrimmed)
            if FileManager.default.fileExists(atPath: url.path) {
                return manualTrimmed
            }
        }

        let autoTrimmed = (autoCandidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return autoTrimmed.isEmpty ? nil : autoTrimmed
    }

    func isManual(for family: WidgetFamily) -> Bool {
        let manualCandidate: String?
        switch family {
        case .systemSmall:
            manualCandidate = smallManualFile
        case .systemMedium:
            manualCandidate = mediumManualFile
        case .systemLarge:
            manualCandidate = largeManualFile
        default:
            manualCandidate = nil
        }

        let manualTrimmed = (manualCandidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !manualTrimmed.isEmpty else { return false }
        return fileName(for: family) == manualTrimmed
    }
}
#endif

#if canImport(WidgetKit)
@MainActor
private final class SmartPhotoShuffleWidgetReloadDebouncer {
    static let shared = SmartPhotoShuffleWidgetReloadDebouncer()

    private var pendingWorkItem: DispatchWorkItem?

    private init() {}

    func scheduleReloadCoalesced() {
        if isRunningInWidgetKitExtension() { return }

        pendingWorkItem?.cancel()

        let work = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
        }

        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func isRunningInWidgetKitExtension() -> Bool {
        guard let ext = Bundle.main.object(forInfoDictionaryKey: "NSExtension") as? [String: Any] else {
            return false
        }
        let pointID = ext["NSExtensionPointIdentifier"] as? String
        return pointID == "com.apple.widgetkit-extension"
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

        #if canImport(WidgetKit)
        Task { @MainActor in
            SmartPhotoShuffleWidgetReloadDebouncer.shared.scheduleReloadCoalesced()
        }
        #endif
    }
}
