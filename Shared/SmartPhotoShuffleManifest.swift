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

    public var currentIndex: Int
    public var rotationIntervalMinutes: Int

    public init(
        version: Int = 1,
        sourceID: String,
        entries: [Entry] = [],
        currentIndex: Int = 0,
        rotationIntervalMinutes: Int = 60
    ) {
        self.version = version
        self.sourceID = sourceID
        self.entries = entries
        self.currentIndex = currentIndex
        self.rotationIntervalMinutes = rotationIntervalMinutes
    }

    /// Returns the best entry to render:
    /// - Prefer `currentIndex` when it points at a prepared entry.
    /// - Otherwise, fall back to the first prepared entry.
    public func entryForRender() -> Entry? {
        guard !entries.isEmpty else { return nil }

        let idx = max(0, min(currentIndex, entries.count - 1))
        let preferred = entries[idx]
        if preferred.isPrepared { return preferred }

        return entries.first(where: { $0.isPrepared })
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
    }
}
