//
//  PawPulseSettingsStore.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import Foundation

public enum PawPulseSettingsStore {
    public enum Keys {
        public static let baseURLString: String = "pawpulse.feed.baseURL.v1"
        public static let displayName: String = "pawpulse.feed.displayName.v1"
    }

    public static func loadBaseURLString(defaults: UserDefaults = AppGroup.userDefaults) -> String {
        defaults.string(forKey: Keys.baseURLString) ?? ""
    }

    public static func saveBaseURLString(_ raw: String, defaults: UserDefaults = AppGroup.userDefaults) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmed, forKey: Keys.baseURLString)
        defaults.synchronize()
    }

    public static func loadDisplayName(defaults: UserDefaults = AppGroup.userDefaults) -> String {
        defaults.string(forKey: Keys.displayName) ?? ""
    }

    public static func saveDisplayName(_ raw: String, defaults: UserDefaults = AppGroup.userDefaults) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        defaults.set(trimmed, forKey: Keys.displayName)
        defaults.synchronize()
    }

    public static func resolvedBaseURL(defaults: UserDefaults = AppGroup.userDefaults) -> URL? {
        let raw = loadBaseURLString(defaults: defaults)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalised = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed

        if let url = URL(string: normalised), url.scheme != nil {
            return url
        }

        if let url = URL(string: "https://" + normalised) {
            return url
        }

        return nil
    }
}
