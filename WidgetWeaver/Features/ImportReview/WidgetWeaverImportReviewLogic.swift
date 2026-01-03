//
//  WidgetWeaverImportReviewLogic.swift
//  WidgetWeaver
//
//  Created by . . on 01/03/26.
//

import Foundation

enum WidgetWeaverImportReviewError: Error, LocalizedError {
    case invalidText

    var errorDescription: String? {
        switch self {
        case .invalidText:
            return "Could not decode the shared design text."
        }
    }
}

struct WidgetWeaverImportReviewSummary: Hashable, Sendable {
    var designCount: Int
    var imageCount: Int
    var totalImageBytes: Int
    var newestUpdatedAt: Date?
    var includesSmartPhotos: Bool
}

enum WidgetWeaverImportReviewLogic {

    static func decodePayload(from rawText: String) throws -> WidgetWeaverDesignExchangePayload {
        let trimmed = rawText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard let payload = WidgetWeaverDesignExchangeCodec.decodeFromText(trimmed) else {
            throw WidgetWeaverImportReviewError.invalidText
        }
        return payload
    }

    static func summarise(payload: WidgetWeaverDesignExchangePayload) -> WidgetWeaverImportReviewSummary {
        let designCount = payload.specs.count
        let imageCount = payload.images.count
        let totalBytes = payload.images.reduce(0) { $0 + $1.data.count }
        let newest = payload.specs.map { $0.updatedAt }.max()

        var includesSmart = false
        for s in payload.specs {
            if s.image?.smartPhoto != nil { includesSmart = true; break }
            if let matched = s.matchedSet {
                if matched.small?.image?.smartPhoto != nil { includesSmart = true; break }
                if matched.medium?.image?.smartPhoto != nil { includesSmart = true; break }
                if matched.large?.image?.smartPhoto != nil { includesSmart = true; break }
            }
        }

        return WidgetWeaverImportReviewSummary(
            designCount: designCount,
            imageCount: imageCount,
            totalImageBytes: totalBytes,
            newestUpdatedAt: newest,
            includesSmartPhotos: includesSmart
        )
    }
}
