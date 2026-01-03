//
//  WidgetSpecStore.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

public final class WidgetSpecStore: ObservableObject {
    @Published public private(set) var specs: [WidgetSpec] = []

    public init() {
        reload()
    }

    public func reload() {
        specs = AppGroup.loadSpecs()
    }

    public func save(_ specs: [WidgetSpec]) {
        do {
            try AppGroup.saveSpecs(specs.map { $0.normalised() })
            reload()
        } catch {
            // ignore
        }
    }

    public func upsert(_ spec: WidgetSpec) {
        var arr = specs
        if let idx = arr.firstIndex(where: { $0.id == spec.id }) {
            arr[idx] = spec
        } else {
            arr.insert(spec, at: 0)
        }
        save(arr)
    }

    public func delete(_ id: UUID) {
        let newSpecs = specs.filter { $0.id != id }
        save(newSpecs)
        cleanupUnusedImages()
    }

    // MARK: - Import / Export

    public func exportExchangeData(specIDs: Set<UUID>) -> Data? {
        let subset = specs.filter { specIDs.contains($0.id) }
        if subset.isEmpty { return nil }

        let images = buildEmbeddedImages(for: subset)
        let payload = WidgetWeaverDesignExchangePayload(
            formatVersion: WidgetWeaverDesignExchangePayload.currentFormatVersion,
            exportedAt: Date(),
            specs: subset,
            images: images
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        return try? encoder.encode(payload)
    }

    public func importExchangeData(_ data: Data) -> [WidgetSpec]? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let payload = try? decoder.decode(WidgetWeaverDesignExchangePayload.self, from: data) else {
            return nil
        }

        // Restore embedded images and build a mapping oldName -> newName.
        var mapping: [String: String] = [:]
        for embedded in payload.images {
            let oldName = embedded.originalFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !oldName.isEmpty else { continue }

            let newName = AppGroup.createImageFileName(ext: (oldName as NSString).pathExtension.isEmpty ? "jpg" : (oldName as NSString).pathExtension)

            if let data = Data(base64Encoded: embedded.base64Data) {
                try? AppGroup.writeImageData(data, fileName: newName)
                mapping[oldName] = newName
            }
        }

        // Rewrite specs to reference restored file names.
        let imported = payload.specs.map { $0.rewritingImageFileNames(using: mapping).normalised() }

        // Merge (upsert by id).
        var merged = specs
        for spec in imported {
            if let idx = merged.firstIndex(where: { $0.id == spec.id }) {
                merged[idx] = spec
            } else {
                merged.insert(spec, at: 0)
            }
        }

        save(merged)
        cleanupUnusedImages()

        return imported
    }

    // MARK: - Cleanup unused images

    public func cleanupUnusedImages() {
        let referenced = Set(collectUniqueImageFileNames(in: specs))
        let allFiles = AppGroup.listAllImageFiles()

        for url in allFiles {
            let name = url.lastPathComponent
            if !referenced.contains(name) {
                AppGroup.deleteImageFile(fileName: name)
            }
        }
    }

    // MARK: - Helpers

    private func buildEmbeddedImages(for specs: [WidgetSpec]) -> [WidgetWeaverEmbeddedImage] {
        let fileNames = collectUniqueImageFileNames(in: specs)
        var out: [WidgetWeaverEmbeddedImage] = []

        for fn in fileNames {
            let url = AppGroup.imageFileURL(fileName: fn)
            guard let data = try? Data(contentsOf: url) else { continue }

            out.append(
                WidgetWeaverEmbeddedImage(
                    originalFileName: fn,
                    base64Data: data.base64EncodedString()
                )
            )
        }

        return out
    }

    func collectUniqueImageFileNames(in specs: [WidgetSpec]) -> [String] {
        var set = Set<String>()

        func insertAll(from image: ImageSpec?) {
            guard let image else { return }
            for name in image.allReferencedFileNames() {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                set.insert(trimmed)
            }
        }

        for spec in specs {
            insertAll(from: spec.image)

            if let matched = spec.matchedSet {
                insertAll(from: matched.small?.image)
                insertAll(from: matched.medium?.image)
                insertAll(from: matched.large?.image)
            }
        }

        return Array(set).sorted()
    }
}

// MARK: - Image fileName rewriting (base + matched variants)

private extension ImageSpec {
    func rewritingFileNames(using map: [String: String]) -> ImageSpec {
        guard !map.isEmpty else { return self }

        var out = self

        func rewrite(_ fileName: String) -> String {
            let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
            let last = (trimmed as NSString).lastPathComponent
            let key = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if let mapped = map[key] {
                return mapped
            }
            return String(last.prefix(256))
        }

        out.fileName = rewrite(out.fileName)

        if var smart = out.smartPhoto {
            smart.masterFileName = rewrite(smart.masterFileName)

            if var v = smart.small {
                v.renderFileName = rewrite(v.renderFileName)
                smart.small = v
            }
            if var v = smart.medium {
                v.renderFileName = rewrite(v.renderFileName)
                smart.medium = v
            }
            if var v = smart.large {
                v.renderFileName = rewrite(v.renderFileName)
                smart.large = v
            }

            out.smartPhoto = smart
        }

        return out.normalised()
    }
}

private extension WidgetSpec {
    func rewritingImageFileNames(using map: [String: String]) -> WidgetSpec {
        guard !map.isEmpty else { return self }

        var out = self

        if let base = out.image {
            out.image = base.rewritingFileNames(using: map)
        }

        if var matched = out.matchedSet {
            if let small = matched.small { matched.small = small.rewritingImageFileNames(using: map) }
            if let medium = matched.medium { matched.medium = medium.rewritingImageFileNames(using: map) }
            if let large = matched.large { matched.large = large.rewritingImageFileNames(using: map) }
            out.matchedSet = matched
        }

        return out
    }
}

private extension WidgetSpecVariant {
    func rewritingImageFileNames(using map: [String: String]) -> WidgetSpecVariant {
        guard !map.isEmpty else { return self }

        var out = self

        if let img = out.image {
            out.image = img.rewritingFileNames(using: map)
        }

        return out
    }
}
