//
//  WidgetSpecStore.swift
//  WidgetWeaver
//
//  Created by . . on 12/16/25.
//

import Foundation

public struct WidgetSpecStoreSaveResults: Hashable {
    public var savedSpecs: [WidgetSpec]
    public var defaultSpecID: UUID?
}

public struct WidgetSpecStoreImportResults: Hashable {
    public var savedSpecs: [WidgetSpec]
    public var defaultSpecID: UUID?
    public var importedIDs: [UUID]
}

public enum WidgetWeaverDesignExchangeDedupePolicy: String, Codable, CaseIterable, Hashable {
    case renameIncomingIfConflict
    case replaceOnIDConflict
}

public struct WidgetWeaverEmbeddedImage: Codable, Hashable {
    public var originalFileName: String
    public var mimeType: String
    public var data: Data

    public init(originalFileName: String, mimeType: String, data: Data) {
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.data = data
    }
}

public struct WidgetWeaverDesignExchangePayload: Codable, Hashable {
    public var magic: String
    public var formatVersion: Int
    public var createdAt: Date
    public var specs: [WidgetSpec]
    public var images: [WidgetWeaverEmbeddedImage]

    public init(magic: String, formatVersion: Int, createdAt: Date, specs: [WidgetSpec], images: [WidgetWeaverEmbeddedImage]) {
        self.magic = magic
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.specs = specs
        self.images = images
    }
}

public final class WidgetSpecStore: ObservableObject {
    public static let shared = WidgetSpecStore()

    private init() {}

    // MARK: - Storage

    private let specsKey = "widgetweaver.specs.v1"
    private let defaultIDKey = "widgetweaver.defaultSpecID.v1"

    public func loadSpecs() -> [WidgetSpec] {
        guard let data = UserDefaults.standard.data(forKey: specsKey) else {
            return [WidgetSpec.defaultSpec()]
        }

        do {
            let specs = try JSONDecoder().decode([WidgetSpec].self, from: data)
            if specs.isEmpty {
                return [WidgetSpec.defaultSpec()]
            }
            return specs
        } catch {
            return [WidgetSpec.defaultSpec()]
        }
    }

    public func saveSpecs(_ specs: [WidgetSpec]) {
        do {
            let data = try JSONEncoder().encode(specs)
            UserDefaults.standard.set(data, forKey: specsKey)
        } catch {
            // Intentionally ignored.
        }
    }

    public func loadDefaultSpecID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: defaultIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    public func setDefaultSpecID(_ id: UUID?) {
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: defaultIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultIDKey)
        }
    }

    // MARK: - High-level ops

    public func saveSpec(_ spec: WidgetSpec) -> WidgetSpecStoreSaveResults {
        var specs = loadSpecs()
        let defaultID = loadDefaultSpecID()

        if let idx = specs.firstIndex(where: { $0.id == spec.id }) {
            specs[idx] = spec.normalised()
        } else {
            specs.append(spec.normalised())
        }

        specs.sort { $0.updatedAt > $1.updatedAt }

        saveSpecs(specs)

        return WidgetSpecStoreSaveResults(savedSpecs: specs, defaultSpecID: defaultID)
    }

    public func deleteSpec(id: UUID) -> WidgetSpecStoreSaveResults {
        var specs = loadSpecs()
        var defaultID = loadDefaultSpecID()

        specs.removeAll { $0.id == id }

        if defaultID == id {
            defaultID = nil
            setDefaultSpecID(nil)
        }

        if specs.isEmpty {
            specs = [WidgetSpec.defaultSpec()]
        }

        saveSpecs(specs)

        return WidgetSpecStoreSaveResults(savedSpecs: specs, defaultSpecID: defaultID)
    }

    // MARK: - Image cleanup

    public func cleanupUnusedImages() -> Int {
        let specs = loadSpecs()
        let referenced = Set(collectUniqueImageFileNames(in: specs))
        let disk = Set(AppGroup.listImageFileNames())
        let unused = disk.subtracting(referenced)

        for name in unused {
            AppGroup.deleteImage(fileName: name)
        }

        return unused.count
    }

    // MARK: - Design exchange

    public func exportExchangePayload(specs: [WidgetSpec], includeImages: Bool) throws -> WidgetWeaverDesignExchangePayload {
        let magic = "WIDGETWEAVER"
        let formatVersion = 1
        let createdAt = Date()

        var images: [WidgetWeaverEmbeddedImage] = []

        if includeImages {
            let fileNames = collectUniqueImageFileNames(in: specs)
            for name in fileNames {
                if let data = AppGroup.readImageData(fileName: name) {
                    let mime = name.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
                    images.append(WidgetWeaverEmbeddedImage(originalFileName: name, mimeType: mime, data: data))
                }
            }
        }

        return WidgetWeaverDesignExchangePayload(
            magic: magic,
            formatVersion: formatVersion,
            createdAt: createdAt,
            specs: specs.map { $0.normalised() },
            images: images
        )
    }

    public func importExchangePayload(_ payload: WidgetWeaverDesignExchangePayload, dedupePolicy: WidgetWeaverDesignExchangeDedupePolicy) throws -> WidgetSpecStoreImportResults {
        var saved = loadSpecs()
        var defaultID = loadDefaultSpecID()

        // Restore images first and build a mapping from original fileName -> new fileName.
        var map: [String: String] = [:]

        for embedded in payload.images {
            let original = embedded.originalFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !original.isEmpty else { continue }

            if map[original] != nil { continue }

            let ext = original.lowercased().hasSuffix(".png") ? "png" : "jpg"
            let newFileName = AppGroup.createImageFileName(prefix: "imported", ext: ext)

            AppGroup.writeImageData(embedded.data, fileName: newFileName)
            map[original] = newFileName
        }

        // Rewrite specs to point at restored image fileNames.
        var incomingSpecs = payload.specs.map { $0.rewritingImageFileNames(using: map) }

        // Apply dedupe.
        var importedIDs: [UUID] = []

        for spec in incomingSpecs {
            switch dedupePolicy {
            case .replaceOnIDConflict:
                if let idx = saved.firstIndex(where: { $0.id == spec.id }) {
                    saved[idx] = spec
                } else {
                    saved.append(spec)
                }
                importedIDs.append(spec.id)

            case .renameIncomingIfConflict:
                if saved.contains(where: { $0.id == spec.id }) {
                    var renamed = spec
                    renamed.id = UUID()
                    renamed.updatedAt = Date()
                    renamed.name = "\(spec.name) (Imported)"
                    saved.append(renamed.normalised())
                    importedIDs.append(renamed.id)
                } else {
                    saved.append(spec.normalised())
                    importedIDs.append(spec.id)
                }
            }
        }

        saved.sort { $0.updatedAt > $1.updatedAt }
        saveSpecs(saved)

        return WidgetSpecStoreImportResults(
            savedSpecs: saved,
            defaultSpecID: defaultID,
            importedIDs: importedIDs
        )
    }
}

public enum WidgetWeaverDesignExchangeCodec {
    public static func encode(_ payload: WidgetWeaverDesignExchangePayload) throws -> Data {
        try JSONEncoder().encode(payload)
    }

    public static func decodeAny(_ data: Data) throws -> WidgetWeaverDesignExchangePayload {
        try JSONDecoder().decode(WidgetWeaverDesignExchangePayload.self, from: data)
    }
}

private extension WidgetSpecStore {

    func collectUniqueImageFileNames(in specs: [WidgetSpec]) -> [String] {
        var set = Set<String>()

        func add(_ image: ImageSpec?) {
            guard let image else { return }
            for fileName in image.allReferencedFileNames() {
                let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                set.insert(trimmed)
            }
        }

        for spec in specs {
            add(spec.image)

            if let matched = spec.matchedSet {
                if let v = matched.small { add(v.image) }
                if let v = matched.medium { add(v.image) }
                if let v = matched.large { add(v.image) }
            }
        }

        return Array(set).sorted()
    }
}

// MARK: - Image fileName rewriting (base + matched variants)

private extension ImageSpec {
    func rewritingFileNames(using map: [String: String]) -> ImageSpec {
        guard !map.isEmpty else { return self }

        func rewrite(_ fileName: String) -> String {
            let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let new = map[trimmed] {
                return new
            }
            return fileName
        }

        var out = self
        out.fileName = rewrite(out.fileName)

        if var smart = out.smartPhoto {
            smart.masterFileName = rewrite(smart.masterFileName)
            smart.small.renderFileName = rewrite(smart.small.renderFileName)
            smart.medium.renderFileName = rewrite(smart.medium.renderFileName)
            smart.large.renderFileName = rewrite(smart.large.renderFileName)
            out.smartPhoto = smart.normalised()
        }

        return out.normalised()
    }
}

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
