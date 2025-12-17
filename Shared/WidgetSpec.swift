//
//  WidgetSpec.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

public struct WidgetSpec: Codable, Hashable, Identifiable {
    public var version: Int
    public var id: UUID
    public var name: String
    public var primaryText: String
    public var secondaryText: String?
    public var updatedAt: Date

    public init(
        version: Int = 1,
        id: UUID = UUID(),
        name: String,
        primaryText: String,
        secondaryText: String?,
        updatedAt: Date = Date()
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.primaryText = primaryText
        self.secondaryText = secondaryText
        self.updatedAt = updatedAt
    }

    public static func defaultSpec() -> WidgetSpec {
        WidgetSpec(
            name: "WidgetWeaver",
            primaryText: "Hello",
            secondaryText: "Saved spec → widget",
            updatedAt: Date()
        )
    }

    public func normalised() -> WidgetSpec {
        var s = self
        s.version = max(1, s.version)
        s.name = s.name.trimmingCharacters(in: .whitespacesAndNewlines)
        s.primaryText = s.primaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let secondary = s.secondaryText?.trimmingCharacters(in: .whitespacesAndNewlines), !secondary.isEmpty {
            s.secondaryText = secondary
        } else {
            s.secondaryText = nil
        }
        return s
    }
}
