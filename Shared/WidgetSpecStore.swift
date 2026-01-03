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
    public var deletedCount: Int
    public var deletedFileNames: [String]

    public init(
        referencedCount: Int,
        existingCount: Int,
        deletedCount: Int,
        deletedFileNames: [String]
    ) {
        self.referencedCount = referencedCount
        self.existingCount = existingCount
        self.deletedCount = deletedCount
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

    public func loadAllSpecs() -> [WidgetSpec] {
        if let data = defaults.data(forKey: specsKey) {
            if let decoded = try? JSONDecoder().decode([WidgetSpec].self, from: data) {
                return decoded.map { $0.normalised() }
            }
        }
        return [WidgetSpec.defaultSpec()]
    }

    public func saveAllSpecs(_ specs: [WidgetSpec]) {
        let normalised = specs.map { $0.normalised() }
        if let data = try? JSONEncoder().encode(normalised) {
            defaults.set(data, forKey: specsKey)
        }
    }

    public func loadDefaultSpecID() -> UUID? {
        if let s = defaults.string(forKey: defaultIDKey), let id = UUID(uuidString: s) {
            return id
        }
        return nil
    }

    public func setDefaultSpecID(_ id: UUID?) {
        if let id {
            defaults.set(id.uuidString, forKey: defaultIDKey)
        } else {
            defaults.removeObject(forKey: defaultIDKey)
        }
    }

    public func loadDefaultSpec() -> WidgetSpec {
        let specs = loadAllSpecs()
        if let id = loadDefaultSpecID(), let found = specs.first(where: { $0.id == id }) {
            return found
        }
        return specs.first ?? WidgetSpec.defaultSpec()
    }

    public func upsertSpec(_ spec: WidgetSpec) {
        var specs = loadAllSpecs()
        if let idx = specs.firstIndex(where: { $0.id == spec.id }) {
            specs[idx] = spec.normalised()
        } else {
            specs.append(spec.normalised())
        }
        saveAllSpecs(specs)
        setDefaultSpecID(spec.id)
    }

    public func deleteSpec(id: UUID) {
        var specs = loadAllSpecs()
        specs.removeAll { $0.id == id }
        if specs.isEmpty {
            specs = [WidgetSpec.defaultSpec()]
        }
        saveAllSpecs(specs)

        if loadDefaultSpecID() == id {
            setDefaultSpecID(specs.first?.id)
        }
    }

    // MARK: - Cleanup (unused images)

    public func cleanupUnusedImages() -> WidgetWeaverImageCleanupResult {
        let specs = loadAllSpecs()
        let referenced = Set(collectUniqueImageFileNames(in: specs))
        let existing = Set(AppGroup.listImageFileNames())

        let orphaned = existing.subtracting(referenced)
        for f in orphaned {
            AppGroup.deleteImage(fileName: f)
        }

        return WidgetWeaverImageCleanupResult(
            referencedCount: referenced.count,
            existingCount: existing.count,
            deletedCount: orphaned.count,
            deletedFileNames: Array(orphaned).sorted()
        )
    }

    // MARK: - Design Exchange (export/import)

    public func exportExchangeFile(includeImages: Bool) -> String {
        let specs = loadAllSpecs()
        let payload = buildExchangePayload(specs: specs, includeImages: includeImages)
        return WidgetWeaverDesignExchangeCodec.encodePayloadToText(payload)
    }

    public func importExchangePayload(_ payload: WidgetWeaverDesignExchangePayload, mergeStrategy: WidgetWeaverImportMergeStrategy) throws {
        // Restore images first (if any).
        var imageFileNameMap: [String: String] = [:]

        if !payload.images.isEmpty {
            for embedded in payload.images {
                let original = embedded.originalFileName.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !original.isEmpty else { continue }

                let ext = (original as NSString).pathExtension
                let newFileName = AppGroup.createImageFileName(prefix: "imported", ext: ext.isEmpty ? "jpg" : ext)

                try AppGroup.writeImageData(embedded.data, fileName: newFileName)
                imageFileNameMap[original] = newFileName
            }
        }

        // Rewrite any fileName references inside imported specs.
        let rewrittenSpecs = payload.specs.map { $0.rewritingImageFileNames(using: imageFileNameMap).normalised() }

        switch mergeStrategy {
        case .replaceAll:
            saveAllSpecs(rewrittenSpecs)
            setDefaultSpecID(rewrittenSpecs.first?.id)

        case .mergeByID:
            var existing = loadAllSpecs()
            for incoming in rewrittenSpecs {
                if let idx = existing.firstIndex(where: { $0.id == incoming.id }) {
                    existing[idx] = incoming
                } else {
                    existing.append(incoming)
                }
            }
            saveAllSpecs(existing)

        case .addNewIDs:
            var existing = loadAllSpecs()
            let existingIDs = Set(existing.map(\.id))
            for incoming in rewrittenSpecs where !existingIDs.contains(incoming.id) {
                existing.append(incoming)
            }
            saveAllSpecs(existing)
        }
    }

    private func buildExchangePayload(specs: [WidgetSpec], includeImages: Bool) -> WidgetWeaverDesignExchangePayload {
        if includeImages {
            let uniqueFileNames = collectUniqueImageFileNames(in: specs)
            let embedded = uniqueFileNames.compactMap { name -> WidgetWeaverEmbeddedImage? in
                let url = AppGroup.imageFileURL(fileName: name)
                guard let data = try? Data(contentsOf: url) else { return nil }
                return WidgetWeaverEmbeddedImage(originalFileName: name, data: data)
            }
            return WidgetWeaverDesignExchangePayload(specs: specs, images: embedded)
        } else {
            return WidgetWeaverDesignExchangePayload(specs: specs, images: [])
        }
    }

    // MARK: - Legacy migration / seeding

    private func seedIfNeeded() {
        let specs = loadAllSpecs()
        if specs.isEmpty {
            saveAllSpecs([WidgetSpec.defaultSpec()])
        }
    }

    private func migrateLegacySingleSpecIfNeeded() {
        guard defaults.data(forKey: specsKey) == nil else { return }
        guard let legacyData = defaults.data(forKey: legacySingleSpecKey) else { return }

        if let decoded = try? JSONDecoder().decode(WidgetSpec.self, from: legacyData) {
            let spec = decoded.normalised()
            saveAllSpecs([spec])
            setDefaultSpecID(spec.id)
            defaults.removeObject(forKey: legacySingleSpecKey)
        }
    }
}

// MARK: - Exchange payload + codec

public enum WidgetWeaverImportMergeStrategy: String, Codable, CaseIterable, Identifiable, Sendable {
    case replaceAll
    case mergeByID
    case addNewIDs

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .replaceAll: return "Replace All"
        case .mergeByID: return "Merge by ID"
        case .addNewIDs: return "Add New IDs Only"
        }
    }
}

public struct WidgetWeaverEmbeddedImage: Codable, Hashable, Sendable {
    public var originalFileName: String
    public var data: Data

    public init(originalFileName: String, data: Data) {
        self.originalFileName = originalFileName
        self.data = data
    }
}

public struct WidgetWeaverDesignExchangePayload: Codable, Hashable, Sendable {
    public var specs: [WidgetSpec]
    public var images: [WidgetWeaverEmbeddedImage]

    public init(specs: [WidgetSpec], images: [WidgetWeaverEmbeddedImage]) {
        self.specs = specs
        self.images = images
    }
}

public enum WidgetWeaverDesignExchangeCodec {
    private static let prefix = "WidgetWeaverDesign:"
    private static let version = "v1"

    public static func encodePayloadToText(_ payload: WidgetWeaverDesignExchangePayload) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if #available(iOS 15.0, *) {
            encoder.dateEncodingStrategy = .iso8601
        }

        guard let data = try? encoder.encode(payload) else { return "" }
        let b64 = data.base64EncodedString()

        return "\(prefix)\(version):\(b64)"
    }

    public static func decodeFromText(_ text: String) -> WidgetWeaverDesignExchangePayload? {
        let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return nil }

        let rest = String(trimmed.dropFirst(prefix.count))
        guard rest.hasPrefix(version + ":") else { return nil }

        let b64 = String(rest.dropFirst((version + ":").count))
        guard let data = Data(base64Encoded: b64) else { return nil }

        let decoder = JSONDecoder()
        if #available(iOS 15.0, *) {
            decoder.dateDecodingStrategy = .iso8601
        }

        return try? decoder.decode(WidgetWeaverDesignExchangePayload.self, from: data)
    }
}

// MARK: - Helpers

private extension WidgetSpecStore {
    func collectUniqueImageFileNames(in specs: [WidgetSpec]) -> [String] {
        var set = Set<String>()

        for spec in specs {
            if let image = spec.image {
                for name in image.allReferencedFileNames() {
                    let trimmed = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if !trimmed.isEmpty { set.insert(trimmed) }
                }
            }

            if let matched = spec.matchedSet {
                if let v = matched.small, let image = v.image {
                    for name in image.allReferencedFileNames() {
                        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        if !trimmed.isEmpty { set.insert(trimmed) }
                    }
                }
                if let v = matched.medium, let image = v.image {
                    for name in image.allReferencedFileNames() {
                        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        if !trimmed.isEmpty { set.insert(trimmed) }
                    }
                }
                if let v = matched.large, let image = v.image {
                    for name in image.allReferencedFileNames() {
                        let trimmed = name.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                        if !trimmed.isEmpty { set.insert(trimmed) }
                    }
                }
            }
        }

        return Array(set).sorted()
    }
}

private extension ImageSpec {
    func rewritingFileNames(using map: [String: String]) -> ImageSpec {
        guard !map.isEmpty else { return self }

        func rewrite(_ raw: String) -> String {
            let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let last = (trimmed as NSString).lastPathComponent
            if let mapped = map[last] { return mapped }
            if let mapped = map[trimmed] { return mapped }
            return last
        }

        var out = self
        out.fileName = rewrite(out.fileName)

        if var smart = out.smartPhoto {
            smart.masterFileName = rewrite(smart.masterFileName)

            if var v = smart.small { v.renderFileName = rewrite(v.renderFileName); smart.small = v }
            if var v = smart.medium { v.renderFileName = rewrite(v.renderFileName); smart.medium = v }
            if var v = smart.large { v.renderFileName = rewrite(v.renderFileName); smart.large = v }

            out.smartPhoto = smart.normalised()
        }

        return out.normalised()
    }
}

// MARK: - Image fileName rewriting (base + matched variants)

private extension WidgetSpec {
    func rewritingImageFileNames(using map: [String: String]) -> WidgetSpec {
        guard !map.isEmpty else { return self }

        var out = self

        if var base = out.image {
            base = base.rewritingFileNames(using: map)
            out.image = base
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
        if var img = out.image {
            img = img.rewritingFileNames(using: map)
            out.image = img
        }

        return out.normalised()
    }
}
