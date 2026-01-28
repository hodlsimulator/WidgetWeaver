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

    private enum CodingKeys: String, CodingKey {
        case token
        case intensity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.token = (try? c.decode(PhotoFilterToken.self, forKey: .token)) ?? .none

        let rawIntensity = (try? c.decode(Double.self, forKey: .intensity)) ?? 1.0
        self.intensity = rawIntensity.normalised().clamped(to: 0.0...1.0)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(token, forKey: .token)
        try c.encode(intensity.normalised().clamped(to: 0.0...1.0), forKey: .intensity)
    }

    /// Returns a cleaned filter spec, or `nil` when it should behave as "None".
    ///
    /// Rules:
    /// - `token == .none` => `nil`
    /// - `intensity <= 0` => `nil`
    /// - intensity is clamped to `0...1`
    public func normalisedOrNil() -> PhotoFilterSpec? {
        let cleaned = intensity.normalised().clamped(to: 0.0...1.0)
        guard token != .none else { return nil }
        guard cleaned > 0.0 else { return nil }
        return PhotoFilterSpec(token: token, intensity: cleaned)
    }
}
