//
//  WidgetSpecStore.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

public struct WidgetWeaverImageCleanupResult: Hashable, Sendable {
    public var referencedCount: Int
    public var existingCount: Int
    public var deletedFileNames: [String]

    public var deletedCount: Int { deletedFileNames.count }

    public init(referencedCount: Int, existingCount: Int, deletedFileNames: [String]) {
        self.referencedCount = referencedCount
        self.existingCount = existingCount
        self.deletedFileNames = deletedFileNames
    }
}

public final class WidgetSpecStore: @unchecked Sendable {
    public static let shared = WidgetSpecStore()

    private let defaults: UserDefaults
    private let specsKey = "widgetweaver.specs.v1"
    private let defaultIDKey = "widgetweaver.specs.v1.default_id"
    private let legacySingleSpecKey = "widgetweaver.spec.v1.default"

    public init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
        migrateLegacySingleSpecIfNeeded()
        seedIfNeeded()
    }

    // MARK: - Compatibility (v0.9.x API)

    public func load() -> WidgetSpec { loadDefault() }

    public func save(_ spec: WidgetSpec) {
        save(spec, makeDefault: false)
    }

    public func clear() {
        defaults.removeObject(forKey: specsKey)
        defaults.removeObject(forKey: defaultIDKey)
        defaults.removeObject(forKey: legacySingleSpecKey)
        seedIfNeeded()
        flushAndNotifyWidgets()
    }

    // MARK: - Multi-spec API

    public func loadAll() -> [WidgetSpec] {
        loadAllInternal()
    }

    public func load(id: UUID) -> WidgetSpec? {
        loadAllInternal().first(where: { $0.id == id })?.normalised()
    }

    public func defaultSpecID() -> UUID? {
        guard let raw = defaults.string(forKey: defaultIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    public func setDefault(id: UUID) {
        setDefaultInternal(id: id)
        flushAndNotifyWidgets()
    }

    public func loadDefault() -> WidgetSpec {
        let specs = loadAllInternal()

        if let id = defaultSpecID(), let match = specs.first(where: { $0.id == id }) {
            return match.normalised()
        }
        if let first = specs.first {
            return first.normalised()
        }
        return WidgetSpec.defaultSpec().normalised()
    }

    public func save(_ spec: WidgetSpec, makeDefault: Bool) {
        var specs = loadAllInternal()
        let normalised = spec.normalised()

        if let idx = specs.firstIndex(where: { $0.id == normalised.id }) {
            specs[idx] = normalised
        } else {
            specs.append(normalised)
        }

        saveAllInternal(specs)

        if makeDefault || defaultSpecID() == nil {
            setDefaultInternal(id: normalised.id)
        }

        flushAndNotifyWidgets()
    }

    public func delete(id: UUID) {
        var specs = loadAllInternal()
        specs.removeAll { $0.id == id }

        if specs.isEmpty {
            let seeded = WidgetSpec.defaultSpec().normalised()
            saveAllInternal([seeded])
            setDefaultInternal(id: seeded.id)
            flushAndNotifyWidgets()
            return
        }

        saveAllInternal(specs)

        if defaultSpecID() == id {
            setDefaultInternal(id: specs[0].id)
        }

        flushAndNotifyWidgets()
    }

    public func reloadWidgets() {
        flushAndNotifyWidgets()
    }

    // MARK: - Image maintenance

    public func cleanupUnusedImages() -> WidgetWeaverImageCleanupResult {
        let specs = loadAllInternal()
        var referenced = Set(collectUniqueImageFileNames(in: specs))
        referenced.formUnion(collectUniqueImageFileNamesFromReferencedShuffleManifests(in: specs))
        let existing = AppGroup.listImageFileNames()

        var deleted: [String] = []
        deleted.reserveCapacity(max(0, existing.count - referenced.count))

        for fileName in existing {
            if referenced.contains(fileName) { continue }
            AppGroup.deleteImage(fileName: fileName)
            deleted.append(fileName)
        }

        if !deleted.isEmpty {
            flushAndNotifyWidgets()
        }

        return WidgetWeaverImageCleanupResult(
            referencedCount: referenced.count,
            existingCount: existing.count,
            deletedFileNames: deleted
        )
    }

    // MARK: - Sharing / Import / Export (Milestone 7 + 8)

    public func exportExchangeData(specs: [WidgetSpec], includeImages: Bool = true) throws -> Data {
        let file = exportExchangeFile(specs: specs, includeImages: includeImages)
        return try WidgetWeaverDesignExchangeCodec.encode(file)
    }

    public func exportAllExchangeData(includeImages: Bool = true) throws -> Data {
        let specs = loadAllInternal()
        return try exportExchangeData(specs: specs, includeImages: includeImages)
    }

    /// Imports specs from an exchange payload (also accepts raw `WidgetSpec` or `[WidgetSpec]` JSON for convenience).
    /// - Behaviour: imported specs are duplicated with new IDs and updated timestamps to avoid overwriting.
    /// - Images: embedded images are restored into the App Group container and fileName references are rewritten.
    ///
    /// Milestone 8: Free tier import respects the max designs limit.
    public func importDesigns(from data: Data, makeDefault: Bool = false) throws -> WidgetWeaverImportResult {
        let payload = try WidgetWeaverDesignExchangeCodec.decodeAny(data)
        return importExchangePayload(payload, makeDefault: makeDefault)
    }

    // MARK: - Internals (storage)

    private func loadAllInternal() -> [WidgetSpec] {
        guard let data = defaults.data(forKey: specsKey) else { return [] }
        do {
            let specs = try JSONDecoder().decode([WidgetSpec].self, from: data)
            return specs.map { $0.normalised() }
        } catch {
            return []
        }
    }

    private func saveAllInternal(_ specs: [WidgetSpec]) {
        do {
            let data = try JSONEncoder().encode(specs.map { $0.normalised() })
            defaults.set(data, forKey: specsKey)
        } catch {
            // Intentionally ignored.
        }
    }

    private func migrateLegacySingleSpecIfNeeded() {
        guard defaults.data(forKey: specsKey) == nil else { return }
        guard let legacyData = defaults.data(forKey: legacySingleSpecKey) else { return }
        defer { defaults.removeObject(forKey: legacySingleSpecKey) }

        do {
            let legacySpec = try JSONDecoder().decode(WidgetSpec.self, from: legacyData).normalised()
            saveAllInternal([legacySpec])
            setDefaultInternal(id: legacySpec.id)
        } catch {
            // Intentionally ignored.
        }
    }

    private func seedIfNeeded() {
        let specs = loadAllInternal()
        if specs.isEmpty {
            let seeded = WidgetSpec.defaultSpec().normalised()
            saveAllInternal([seeded])
            setDefaultInternal(id: seeded.id)
            return
        }
        if defaultSpecID() == nil, let first = specs.first {
            setDefaultInternal(id: first.id)
        }
    }

    private func setDefaultInternal(id: UUID) {
        defaults.set(id.uuidString, forKey: defaultIDKey)
    }

    private func flushAndNotifyWidgets() {
        defaults.synchronize()

        #if canImport(WidgetKit)
        let kind = WidgetWeaverWidgetKinds.main
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }
        #endif
    }

    // MARK: - Internals (import)

    private func importExchangePayload(_ payload: WidgetWeaverDesignExchangePayload, makeDefault: Bool) -> WidgetWeaverImportResult {
        var notes: [String] = []

        // Restore embedded images first.
        var imageFileNameMap: [String: String] = [:] // originalFileName -> newFileName
        if !payload.images.isEmpty {
            for embedded in payload.images {
                let original = embedded.originalFileName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !original.isEmpty else { continue }

                let ext = URL(fileURLWithPath: original).pathExtension
                let safeExt = ext.isEmpty ? "jpg" : ext
                let newFileName = AppGroup.createImageFileName(ext: safeExt)

                do {
                    try AppGroup.writeImageData(embedded.data, fileName: newFileName)
                    imageFileNameMap[original] = newFileName
                } catch {
                    notes.append("Failed to restore image: \(original)")
                }
            }
        }

        // Duplicate specs with new IDs (avoid overwrite).
        let now = Date()
        var imported: [WidgetSpec] = []
        imported.reserveCapacity(payload.specs.count)

        for raw in payload.specs {
            var s = raw.normalised()
            s.id = UUID()
            s.updatedAt = now
            s = s.rewritingImageFileNames(using: imageFileNameMap)
            imported.append(s)
        }

        if imported.isEmpty {
            return WidgetWeaverImportResult(importedCount: 0, importedIDs: [], notes: notes)
        }

        // Merge into store with Milestone 8 (free tier) enforcement.
        var existing = loadAllInternal()

        if !WidgetWeaverEntitlements.isProUnlocked {
            let max = WidgetWeaverEntitlements.maxFreeDesigns
            let available = max - existing.count

            if available <= 0 {
                notes.append("Free tier allows up to \(max) designs. Upgrade to Pro to import more.")
                return WidgetWeaverImportResult(importedCount: 0, importedIDs: [], notes: notes)
            }

            if imported.count > available {
                notes.append("Free tier limit: imported \(available) of \(imported.count) designs.\nUpgrade to Pro for unlimited designs.")
                imported = Array(imported.prefix(available))
            }
        }

        if imported.isEmpty {
            return WidgetWeaverImportResult(importedCount: 0, importedIDs: [], notes: notes)
        }

        existing.append(contentsOf: imported.map { $0.normalised() })
        saveAllInternal(existing)

        if makeDefault, let last = imported.last {
            setDefaultInternal(id: last.id)
        } else if defaultSpecID() == nil, let first = existing.first {
            setDefaultInternal(id: first.id)
        }

        flushAndNotifyWidgets()

        return WidgetWeaverImportResult(
            importedCount: imported.count,
            importedIDs: imported.map(\.id),
            notes: notes
        )
    }
}

// MARK: - Exchange payload + codec

public struct WidgetWeaverDesignExchangePayload: Codable, Hashable {
    public static let magicValue = "com.conornolan.widgetweaver.exchange"
    public static let currentFormatVersion = 1

    public var magic: String
    public var formatVersion: Int
    public var createdAt: Date
    public var specs: [WidgetSpec]
    public var images: [WidgetWeaverEmbeddedImage]

    public init(
        magic: String = WidgetWeaverDesignExchangePayload.magicValue,
        formatVersion: Int = WidgetWeaverDesignExchangePayload.currentFormatVersion,
        createdAt: Date = Date(),
        specs: [WidgetSpec],
        images: [WidgetWeaverEmbeddedImage] = []
    ) {
        self.magic = magic
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.specs = specs
        self.images = images
    }
}

public struct WidgetWeaverEmbeddedImage: Codable, Hashable {
    public var originalFileName: String
    public var data: Data

    public init(originalFileName: String, data: Data) {
        self.originalFileName = originalFileName
        self.data = data
    }
}

public struct WidgetWeaverImportResult: Hashable {
    public var importedCount: Int
    public var importedIDs: [UUID]
    public var notes: [String]

    public init(importedCount: Int, importedIDs: [UUID], notes: [String]) {
        self.importedCount = importedCount
        self.importedIDs = importedIDs
        self.notes = notes
    }
}

public enum WidgetWeaverDesignExchangeError: Error, LocalizedError {
    case emptyExport
    case invalidExchangeFile
    case unsupportedFormatVersion(Int)
    case noSpecsFound
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case .emptyExport: return "Nothing to export."
        case .invalidExchangeFile: return "This file does not look like a WidgetWeaver export."
        case .unsupportedFormatVersion(let v): return "Unsupported WidgetWeaver export format version: \(v)."
        case .noSpecsFound: return "No designs were found in the file."
        case .decodingFailed: return "Could not read this file."
        }
    }
}

public enum WidgetWeaverDesignExchangeCodec {
    public static func encode(_ payload: WidgetWeaverDesignExchangePayload) throws -> Data {
        guard !payload.specs.isEmpty else { throw WidgetWeaverDesignExchangeError.emptyExport }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    /// Decodes:
    /// - WidgetWeaver exchange payload (preferred)
    /// - Array of WidgetSpec
    /// - Single WidgetSpec
    public static func decodeAny(_ data: Data) throws -> WidgetWeaverDesignExchangePayload {
        if let payload = try? decodeExchange(data, iso8601: true) { return try validate(payload) }
        if let payload = try? decodeExchange(data, iso8601: false) { return try validate(payload) }

        if let specs = try? JSONDecoder().decode([WidgetSpec].self, from: data) {
            let normalised = specs.map { $0.normalised() }
            guard !normalised.isEmpty else { throw WidgetWeaverDesignExchangeError.noSpecsFound }
            return WidgetWeaverDesignExchangePayload(specs: normalised, images: [])
        }

        if let spec = try? JSONDecoder().decode(WidgetSpec.self, from: data) {
            return WidgetWeaverDesignExchangePayload(specs: [spec.normalised()], images: [])
        }

        throw WidgetWeaverDesignExchangeError.decodingFailed
    }

    private static func decodeExchange(_ data: Data, iso8601: Bool) throws -> WidgetWeaverDesignExchangePayload {
        let decoder = JSONDecoder()
        if iso8601 { decoder.dateDecodingStrategy = .iso8601 }
        return try decoder.decode(WidgetWeaverDesignExchangePayload.self, from: data)
    }

    private static func validate(_ payload: WidgetWeaverDesignExchangePayload) throws -> WidgetWeaverDesignExchangePayload {
        guard payload.magic == WidgetWeaverDesignExchangePayload.magicValue else {
            throw WidgetWeaverDesignExchangeError.invalidExchangeFile
        }
        if payload.formatVersion > WidgetWeaverDesignExchangePayload.currentFormatVersion {
            throw WidgetWeaverDesignExchangeError.unsupportedFormatVersion(payload.formatVersion)
        }
        guard !payload.specs.isEmpty else { throw WidgetWeaverDesignExchangeError.noSpecsFound }

        var out = payload
        out.specs = out.specs.map { $0.normalised() }
        return out
    }
}

// MARK: - Export builder

private extension WidgetSpecStore {
    func exportExchangeFile(specs: [WidgetSpec], includeImages: Bool) -> WidgetWeaverDesignExchangePayload {
        let normalisedSpecs = specs.map { $0.normalised() }
        var embeddedImages: [WidgetWeaverEmbeddedImage] = []

        if includeImages {
            let fileNames = collectUniqueImageFileNames(in: normalisedSpecs)
            embeddedImages = fileNames.compactMap { fileName in
                let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                guard let data = AppGroup.readImageData(fileName: trimmed) else { return nil }
                return WidgetWeaverEmbeddedImage(originalFileName: trimmed, data: data)
            }
        }

        return WidgetWeaverDesignExchangePayload(
            createdAt: Date(),
            specs: normalisedSpecs,
            images: embeddedImages
        )
    }

    func collectUniqueImageFileNames(in specs: [WidgetSpec]) -> [String] {
        var set = Set<String>()

        func insertImage(_ img: ImageSpec?) {
            guard let img else { return }
            for raw in img.allReferencedFileNames() {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                set.insert(trimmed)
            }
        }

        for spec in specs {
            insertImage(spec.image)

            if let matched = spec.matchedSet {
                if let v = matched.small { insertImage(v.image) }
                if let v = matched.medium { insertImage(v.image) }
                if let v = matched.large { insertImage(v.image) }
            }
        }

        return Array(set).sorted()
    }

    func collectUniqueImageFileNamesFromReferencedShuffleManifests(in specs: [WidgetSpec]) -> [String] {
        var manifestFileNames = Set<String>()

        func insertShuffleManifest(_ image: ImageSpec?) {
            guard let mf = image?.smartPhoto?.shuffleManifestFileName else { return }
            let trimmed = mf.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            manifestFileNames.insert(trimmed)
        }

        for spec in specs {
            insertShuffleManifest(spec.image)
            if let matched = spec.matchedSet {
                if let v = matched.small { insertShuffleManifest(v.image) }
                if let v = matched.medium { insertShuffleManifest(v.image) }
                if let v = matched.large { insertShuffleManifest(v.image) }
            }
        }

        var out = Set<String>()

        func insertImageName(_ raw: String?) {
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let last = (trimmed as NSString).lastPathComponent
            let safe = String(last.prefix(256))
            guard !safe.isEmpty else { return }
            out.insert(safe)
        }

        for mf in manifestFileNames {
            guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { continue }
            for entry in manifest.entries {
                insertImageName(entry.sourceFileName)

                insertImageName(entry.smallFile)
                insertImageName(entry.mediumFile)
                insertImageName(entry.largeFile)

                insertImageName(entry.smallManualFile)
                insertImageName(entry.mediumManualFile)
                insertImageName(entry.largeManualFile)
            }
        }

        return Array(out).sorted()
    }
}

// MARK: - Image fileName rewriting (base + matched variants)

private extension WidgetSpec {
    func rewritingImageFileNames(using map: [String: String]) -> WidgetSpec {
        guard !map.isEmpty else { return self }

        var out = self

        if let base = out.image {
            out.image = base.rewritingFileNames(using: map)
        }

        if var matched = out.matchedSet {
            if var v = matched.small { v = v.rewritingImageFileNames(using: map); matched.small = v }
            if var v = matched.medium { v = v.rewritingImageFileNames(using: map); matched.medium = v }
            if var v = matched.large { v = v.rewritingImageFileNames(using: map); matched.large = v }
            out.matchedSet = matched
        }

        return out.normalised()
    }
}

private extension WidgetSpecVariant {
    func rewritingImageFileNames(using map: [String: String]) -> WidgetSpecVariant {
        guard !map.isEmpty else { return self }

        var out = self
        if let img = out.image {
            out.image = img.rewritingFileNames(using: map)
        }

        return out.normalised()
    }
}

private extension ImageSpec {
    func rewritingFileNames(using map: [String: String]) -> ImageSpec {
        guard !map.isEmpty else { return self }

        func mapped(_ raw: String) -> String? {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }

            if let direct = map[trimmed] { return direct }

            let last = (trimmed as NSString).lastPathComponent
            if let lastMapped = map[last] { return lastMapped }

            return nil
        }

        var out = self

        if let new = mapped(out.fileName) {
            out.fileName = new
        }

        if var sp = out.smartPhoto {
            if let newMaster = mapped(sp.masterFileName) {
                sp.masterFileName = newMaster
            }

            if var v = sp.small, let new = mapped(v.renderFileName) {
                v.renderFileName = new
                sp.small = v
            }

            if var v = sp.medium, let new = mapped(v.renderFileName) {
                v.renderFileName = new
                sp.medium = v
            }

            if var v = sp.large, let new = mapped(v.renderFileName) {
                v.renderFileName = new
                sp.large = v
            }

            out.smartPhoto = sp
        }

        return out.normalised()
    }
}
