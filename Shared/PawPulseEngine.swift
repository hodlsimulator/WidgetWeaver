//
//  PawPulseEngine.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import Foundation
import WidgetKit

public struct PawPulseUpdateResult: Sendable {
    public let didUpdate: Bool
    public let item: PawPulseLatestItem?
    public let statusMessage: String

    public init(didUpdate: Bool, item: PawPulseLatestItem?, statusMessage: String) {
        self.didUpdate = didUpdate
        self.item = item
        self.statusMessage = statusMessage
    }
}

public actor PawPulseEngine {
    public static let shared = PawPulseEngine()

    private let session: URLSession

    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 35
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    public func updateIfNeeded(force: Bool) async -> PawPulseUpdateResult {
        guard let baseURL = PawPulseSettingsStore.resolvedBaseURL() else {
            return PawPulseUpdateResult(
                didUpdate: false,
                item: PawPulseCache.loadLatestItem(),
                statusMessage: "PawPulse feed not configured. Set a base URL in PawPulse Settings."
            )
        }

        let latestURL = baseURL.appendingPathComponent("api/latest")
        let imageURL = baseURL.appendingPathComponent("media/latest.jpg")

        do {
            let (jsonData, jsonResponse) = try await session.data(from: latestURL)
            guard let http = jsonResponse as? HTTPURLResponse else {
                return PawPulseUpdateResult(didUpdate: false, item: PawPulseCache.loadLatestItem(), statusMessage: "Feed returned a non-HTTP response.")
            }
            guard (200...299).contains(http.statusCode) else {
                return PawPulseUpdateResult(didUpdate: false, item: PawPulseCache.loadLatestItem(), statusMessage: "Feed error (HTTP \(http.statusCode)).")
            }

            let decoder = JSONDecoder()
            let newItem = try decoder.decode(PawPulseLatestItem.self, from: jsonData)

            let oldItem = PawPulseCache.loadLatestItem()
            let oldID = oldItem?.stableIdentifier
            let newID = newItem.stableIdentifier

            let noCacheYet = (oldItem == nil)
            let changed = force || noCacheYet || (newID != nil && newID != oldID)

            if changed {
                let (imageData, imageResponse) = try await session.data(from: imageURL)
                if let httpImg = imageResponse as? HTTPURLResponse, !(200...299).contains(httpImg.statusCode) {
                    try PawPulseCache.writeLatest(jsonData: jsonData, imageData: nil)
                    await reloadPawPulseWidget()
                    return PawPulseUpdateResult(didUpdate: true, item: newItem, statusMessage: "Updated JSON, but image fetch failed (HTTP \(httpImg.statusCode)).")
                }

                try PawPulseCache.writeLatest(jsonData: jsonData, imageData: imageData)
                await reloadPawPulseWidget()

                return PawPulseUpdateResult(didUpdate: true, item: newItem, statusMessage: "Updated: new post detected.")
            }

            return PawPulseUpdateResult(didUpdate: false, item: newItem, statusMessage: "No change: latest post unchanged.")

        } catch {
            let fallback = PawPulseCache.loadLatestItem()
            return PawPulseUpdateResult(didUpdate: false, item: fallback, statusMessage: "Update failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func reloadPawPulseWidget() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.pawPulseLatestCat)
    }
}
