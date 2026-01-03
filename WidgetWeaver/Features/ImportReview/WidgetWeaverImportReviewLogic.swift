//
//  WidgetWeaverImportReviewLogic.swift
//  WidgetWeaver
//
//  Created by . . on 01/01/26.
//

import Foundation

enum WidgetWeaverImportReviewLogic {

    static func decodeImportFile(data: Data) throws -> WidgetWeaverDesignExchangePayload {
        try WidgetWeaverDesignExchangeCodec.decodeAny(data)
    }

    static func makeReviewModel(
        payload: WidgetWeaverDesignExchangePayload,
        fileName: String
    ) -> WidgetWeaverImportReviewModel {
        let items = deriveItems(payload: payload)
        return WidgetWeaverImportReviewModel(
            fileName: fileName,
            items: items,
            payload: payload,
            createdAt: payload.createdAt
        )
    }

    static func deriveItems(payload: WidgetWeaverDesignExchangePayload) -> [WidgetWeaverImportReviewItem] {
        let sortedSpecs = payload.specs.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        return sortedSpecs.map { spec in
            WidgetWeaverImportReviewItem(
                id: spec.id,
                name: spec.name,
                templateDisplay: spec.layout.template.displayName,
                updatedAt: spec.updatedAt,
                hasImage: specHasAnyImage(spec)
            )
        }
    }

    static func makeSubsetPayload(
        payload: WidgetWeaverDesignExchangePayload,
        selectedIDs: Set<UUID>
    ) -> WidgetWeaverDesignExchangePayload {
        let selectedSpecs = payload.specs.filter { selectedIDs.contains($0.id) }
        let referencedFileNames = referencedImageFileNames(in: selectedSpecs)

        var seen = Set<String>()
        let selectedImages = payload.images.compactMap { embedded -> WidgetWeaverEmbeddedImage? in
            let trimmed = embedded.originalFileName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            guard referencedFileNames.contains(trimmed) else { return nil }
            guard seen.insert(trimmed).inserted else { return nil }
            return embedded
        }

        return WidgetWeaverDesignExchangePayload(
            magic: payload.magic,
            formatVersion: payload.formatVersion,
            createdAt: payload.createdAt,
            specs: selectedSpecs,
            images: selectedImages
        )
    }

    private static func specHasAnyImage(_ spec: WidgetSpec) -> Bool {
        !spec.normalised().allReferencedImageFileNames().isEmpty
    }

    private static func referencedImageFileNames(in specs: [WidgetSpec]) -> Set<String> {
        var out = Set<String>()

        for spec in specs {
            for name in spec.normalised().allReferencedImageFileNames() {
                out.insert(name)
            }
        }

        return out
    }
}
