//
//  PhotoFilterSpec.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import Foundation

/// Curated photo filter options.
///
/// Notes:
/// - Raw values are stable identifiers used for persistence.
/// - Display names are user-facing labels.
public enum PhotoFilterToken: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case none
    case noir
    case mono
    case chrome
    case fade
    case instant
    case process
    case transfer
    case sepia

    public var id: String { rawValue }

    public var stableIdentifier: String { rawValue }

    public var displayName: String {
        switch self {
        case .none:
            return "None"
        case .noir:
            return "Noir"
        case .mono:
            return "Mono"
        case .chrome:
            return "Chrome"
        case .fade:
            return "Fade"
        case .instant:
            return "Instant"
        case .process:
            return "Process"
        case .transfer:
            return "Transfer"
        case .sepia:
            return "Sepia"
        }
    }
}

/// Non-destructive photo filter configuration.
///
/// The intensity value should be treated as a blend amount:
/// - `0` means original image
/// - `1` means fully filtered output
public struct PhotoFilterSpec: Hashable, Codable, Sendable {
    public var token: PhotoFilterToken

    /// Blend amount in `0...1`.
    public var intensity: Double

    public init(token: PhotoFilterToken, intensity: Double) {
        self.token = token
        self.intensity = intensity
    }
}
