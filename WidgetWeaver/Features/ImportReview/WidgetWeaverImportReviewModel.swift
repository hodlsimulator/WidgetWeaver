//
//  WidgetWeaverImportReviewModel.swift
//  WidgetWeaver
//
//  Created by . . on 01/01/26.
//

import Foundation

struct WidgetWeaverImportReviewModel: Identifiable, Hashable {
    let id: UUID
    let fileName: String
    let items: [WidgetWeaverImportReviewItem]
    let payload: WidgetWeaverDesignExchangePayload
    let createdAt: Date?

    init(
        id: UUID = UUID(),
        fileName: String,
        items: [WidgetWeaverImportReviewItem],
        payload: WidgetWeaverDesignExchangePayload,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.items = items
        self.payload = payload
        self.createdAt = createdAt
    }
}

struct WidgetWeaverImportReviewItem: Identifiable, Hashable {
    let id: UUID
    let name: String
    let templateDisplay: String
    let updatedAt: Date
    let hasImage: Bool
}

enum WidgetWeaverImportReviewLimitState: Equatable {
    case ok
    case exceedsFreeLimit(available: Int)

    var isImportAllowed: Bool {
        switch self {
        case .ok: return true
        case .exceedsFreeLimit: return false
        }
    }
}

extension WidgetWeaverImportReviewModel {
    static func defaultSelection(
        items: [WidgetWeaverImportReviewItem],
        isProUnlocked: Bool,
        availableSlots: Int
    ) -> Set<UUID> {
        if isProUnlocked {
            return Set(items.map(\.id))
        }

        let available = max(0, availableSlots)
        guard available > 0 else { return [] }

        let sorted = items.sorted { $0.updatedAt > $1.updatedAt }
        return Set(sorted.prefix(available).map(\.id))
    }

    static func limitState(
        isProUnlocked: Bool,
        selectionCount: Int,
        availableSlots: Int
    ) -> WidgetWeaverImportReviewLimitState {
        if isProUnlocked { return .ok }

        let available = max(0, availableSlots)
        if selectionCount > available {
            return .exceedsFreeLimit(available: available)
        }

        return .ok
    }
}
