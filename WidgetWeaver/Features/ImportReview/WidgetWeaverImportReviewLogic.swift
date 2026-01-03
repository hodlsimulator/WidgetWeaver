//
//  WidgetWeaverImportReviewLogic.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation

enum WidgetWeaverImportReviewLogic {

    struct ImportReviewResult {
        let subsetPayloadData: Data
        let subsetSpecIDs: Set<UUID>
        let subsetImageFileNames: Set<String>
    }

    static func makeSubsetPayload(from payload: WidgetWeaverDesignExchangePayload, selectedSpecIDs: Set<UUID>) -> ImportReviewResult? {
        let selectedSpecs = payload.specs.filter { selectedSpecIDs.contains($0.id) }
        guard !selectedSpecs.isEmpty else { return nil }

        let referencedNames = referencedImageFileNames(in: selectedSpecs)

        let selectedImages = payload.images.filter { embedded in
            let trimmed = embedded.originalFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return referencedNames.contains(trimmed)
        }

        let subsetPayload = WidgetWeaverDesignExchangePayload(
            formatVersion: payload.formatVersion,
            exportedAt: payload.exportedAt,
            specs: selectedSpecs,
            images: selectedImages
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let encoded = try? encoder.encode(subsetPayload) else { return nil }

        return ImportReviewResult(
            subsetPayloadData: encoded,
            subsetSpecIDs: Set(selectedSpecs.map(\.id)),
            subsetImageFileNames: referencedNames
        )
    }

    static func isAnythingToImport(from payload: WidgetWeaverDesignExchangePayload) -> Bool {
        for s in payload.specs {
            if specHasAnyImage(s) { return true }
        }
        return !payload.specs.isEmpty
    }

    private static func specHasAnyImage(_ spec: WidgetSpec) -> Bool {
        func hasAnyImage(_ image: ImageSpec?) -> Bool {
            guard let image else { return false }
            return image.allReferencedFileNames().contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }

        if hasAnyImage(spec.image) { return true }

        if let matched = spec.matchedSet {
            if hasAnyImage(matched.small?.image) { return true }
            if hasAnyImage(matched.medium?.image) { return true }
            if hasAnyImage(matched.large?.image) { return true }
        }

        return false
    }

    private static func referencedImageFileNames(in specs: [WidgetSpec]) -> Set<String> {
        var out = Set<String>()

        func add(_ image: ImageSpec?) {
            guard let image else { return }
            for name in image.allReferencedFileNames() {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                out.insert(trimmed)
            }
        }

        for s in specs {
            add(s.image)

            if let matched = s.matchedSet {
                add(matched.small?.image)
                add(matched.medium?.image)
                add(matched.large?.image)
            }
        }

        return out
    }
}
