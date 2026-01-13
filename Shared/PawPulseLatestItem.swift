//
//  PawPulseLatestItem.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import Foundation

public struct PawPulseLatestItem: Codable, Hashable, Sendable {
    public var source: String?
    public var pageID: String?
    public var pageName: String?
    public var postID: String?
    public var createdTime: String?
    public var permalinkURL: String?
    public var message: String?
    public var fetchedAt: String?
    public var imageURL: String?

    public init(
        source: String? = nil,
        pageID: String? = nil,
        pageName: String? = nil,
        postID: String? = nil,
        createdTime: String? = nil,
        permalinkURL: String? = nil,
        message: String? = nil,
        fetchedAt: String? = nil,
        imageURL: String? = nil
    ) {
        self.source = source
        self.pageID = pageID
        self.pageName = pageName
        self.postID = postID
        self.createdTime = createdTime
        self.permalinkURL = permalinkURL
        self.message = message
        self.fetchedAt = fetchedAt
        self.imageURL = imageURL
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case pageID = "page_id"
        case pageName = "page_name"
        case postID = "post_id"
        case createdTime = "created_time"
        case permalinkURL = "permalink_url"
        case message
        case fetchedAt = "fetched_at"
        case imageURL = "image_url"
    }

    public var stableIdentifier: String? {
        if let postID, !postID.isEmpty { return postID }
        if let permalinkURL, !permalinkURL.isEmpty { return permalinkURL }
        if let createdTime, !createdTime.isEmpty { return createdTime }
        return nil
    }

    public static func sample() -> PawPulseLatestItem {
        PawPulseLatestItem(
            source: "PawPulse",
            pageID: "1234567890",
            pageName: "PawPulse Test Page",
            postID: "123_456",
            createdTime: "2026-01-13T00:12:34+0000",
            permalinkURL: "https://www.facebook.com/permalink.php?story_fbid=123&id=456",
            message: "Meet Miso 🐾\nA gentle kitten looking for a home.",
            fetchedAt: "2026-01-13T01:00:00Z",
            imageURL: "https://example.com/media/latest.jpg"
        )
    }
}

public extension PawPulseLatestItem {
    var createdDate: Date? {
        PawPulseDateParsing.parse(createdTime)
    }

    var fetchedDate: Date? {
        PawPulseDateParsing.parse(fetchedAt)
    }
}

public enum PawPulseDateParsing {
    public static func parse(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let iso8601Fractional = ISO8601DateFormatter()
        iso8601Fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso8601Fractional.date(from: trimmed) { return d }

        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        if let d = iso8601.date(from: trimmed) { return d }

        let graph = DateFormatter()
        graph.locale = Locale(identifier: "en_US_POSIX")
        graph.timeZone = TimeZone(secondsFromGMT: 0)
        graph.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let d = graph.date(from: trimmed) { return d }

        return nil
    }
}
