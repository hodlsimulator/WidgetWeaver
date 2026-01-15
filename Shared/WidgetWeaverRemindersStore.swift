//
//  WidgetWeaverRemindersStore.swift
//  WidgetWeaver
//
//  Created by . . on 1/15/26.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

/// App Group-backed store for Reminders snapshots (Phase 2).
///
/// Contract:
/// - Widget rendering reads cached snapshots only.
/// - EventKit access lives elsewhere (engine / app UI), and writes snapshots into this store.
public final class WidgetWeaverRemindersStore: @unchecked Sendable {
    public static let shared = WidgetWeaverRemindersStore()

    public enum Keys {
        public static let snapshotData = "widgetweaver.reminders.snapshot.v1"

        public static let lastUpdatedAt = "widgetweaver.reminders.lastUpdatedAt.v1"

        public static let lastErrorKind = "widgetweaver.reminders.lastError.kind.v1"
        public static let lastErrorMessage = "widgetweaver.reminders.lastError.message.v1"
        public static let lastErrorAt = "widgetweaver.reminders.lastError.at.v1"
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
    }

    // JSONEncoder/JSONDecoder instances are not safe to share across threads.
    // These helpers create a fresh instance per call.
    @inline(__always)
    private func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    @inline(__always)
    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func notifyWidgetsRemindersUpdated() {
        #if canImport(WidgetKit)
        // Avoid re-entrant reload loops while the widget extension is rendering.
        guard !WidgetWeaverRuntime.isRunningInAppExtension else { return }

        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
        }
        #endif
    }

    // MARK: Snapshot

    public func loadSnapshot() -> WidgetWeaverRemindersSnapshot? {
        let decoder = makeDecoder()

        if let data = defaults.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverRemindersSnapshot.self, from: data)
        {
            return snap
        }

        // Fallback for any legacy/misconfigured container situations.
        if let data = UserDefaults.standard.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverRemindersSnapshot.self, from: data)
        {
            // Heal: copy into the App Group store so the widget and app converge.
            let encoder = makeEncoder()
            if let healed = try? encoder.encode(snap) {
                defaults.set(healed, forKey: Keys.snapshotData)
            }
            return snap
        }

        return nil
    }

    public func saveSnapshot(_ snapshot: WidgetWeaverRemindersSnapshot?) {
        let encoder = makeEncoder()

        if let snapshot, let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: Keys.snapshotData)
            UserDefaults.standard.set(data, forKey: Keys.snapshotData)

            saveLastUpdatedAt(snapshot.generatedAt)
            clearLastError()
        } else {
            defaults.removeObject(forKey: Keys.snapshotData)
            UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        }

        notifyWidgetsRemindersUpdated()
    }

    public func clearSnapshot() {
        defaults.removeObject(forKey: Keys.snapshotData)
        UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        notifyWidgetsRemindersUpdated()
    }

    // MARK: Last updated

    public func loadLastUpdatedAt() -> Date? {
        let t = defaults.double(forKey: Keys.lastUpdatedAt)
        if t > 0 { return Date(timeIntervalSince1970: t) }

        let legacy = UserDefaults.standard.double(forKey: Keys.lastUpdatedAt)
        if legacy > 0 {
            defaults.set(legacy, forKey: Keys.lastUpdatedAt)
            return Date(timeIntervalSince1970: legacy)
        }

        return nil
    }

    public func saveLastUpdatedAt(_ date: Date?) {
        if let date {
            let t = date.timeIntervalSince1970
            defaults.set(t, forKey: Keys.lastUpdatedAt)
            UserDefaults.standard.set(t, forKey: Keys.lastUpdatedAt)
        } else {
            defaults.removeObject(forKey: Keys.lastUpdatedAt)
            UserDefaults.standard.removeObject(forKey: Keys.lastUpdatedAt)
        }
    }

    // MARK: Last error

    public func loadLastError() -> WidgetWeaverRemindersDiagnostics? {
        let rawMessage = (defaults.string(forKey: Keys.lastErrorMessage)
                          ?? UserDefaults.standard.string(forKey: Keys.lastErrorMessage)
                          ?? "")
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }

        let rawKind = (defaults.string(forKey: Keys.lastErrorKind)
                       ?? UserDefaults.standard.string(forKey: Keys.lastErrorKind)
                       ?? WidgetWeaverRemindersDiagnostics.Kind.error.rawValue)

        let kind = WidgetWeaverRemindersDiagnostics.Kind(rawValue: rawKind) ?? .error

        let timestamp = defaults.double(forKey: Keys.lastErrorAt)
        let at: Date = {
            if timestamp > 0 { return Date(timeIntervalSince1970: timestamp) }
            let legacy = UserDefaults.standard.double(forKey: Keys.lastErrorAt)
            if legacy > 0 {
                defaults.set(legacy, forKey: Keys.lastErrorAt)
                return Date(timeIntervalSince1970: legacy)
            }
            return Date()
        }()

        // Heal any legacy values.
        if defaults.string(forKey: Keys.lastErrorMessage) == nil {
            defaults.set(message, forKey: Keys.lastErrorMessage)
        }
        if defaults.string(forKey: Keys.lastErrorKind) == nil {
            defaults.set(kind.rawValue, forKey: Keys.lastErrorKind)
        }

        return WidgetWeaverRemindersDiagnostics(kind: kind, message: message, at: at)
    }

    public func saveLastError(_ error: WidgetWeaverRemindersDiagnostics?) {
        let cleanedKind = error?.kind.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedMessage = error?.message.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cleanedMessage, !cleanedMessage.isEmpty {
            let kindRaw = (cleanedKind?.isEmpty ?? true) ? WidgetWeaverRemindersDiagnostics.Kind.error.rawValue : cleanedKind!

            defaults.set(kindRaw, forKey: Keys.lastErrorKind)
            defaults.set(String(cleanedMessage.prefix(240)), forKey: Keys.lastErrorMessage)
            defaults.set((error?.at ?? Date()).timeIntervalSince1970, forKey: Keys.lastErrorAt)

            UserDefaults.standard.set(kindRaw, forKey: Keys.lastErrorKind)
            UserDefaults.standard.set(String(cleanedMessage.prefix(240)), forKey: Keys.lastErrorMessage)
            UserDefaults.standard.set((error?.at ?? Date()).timeIntervalSince1970, forKey: Keys.lastErrorAt)
        } else {
            clearLastError()
        }

        notifyWidgetsRemindersUpdated()
    }

    public func clearLastError() {
        defaults.removeObject(forKey: Keys.lastErrorKind)
        defaults.removeObject(forKey: Keys.lastErrorMessage)
        defaults.removeObject(forKey: Keys.lastErrorAt)

        UserDefaults.standard.removeObject(forKey: Keys.lastErrorKind)
        UserDefaults.standard.removeObject(forKey: Keys.lastErrorMessage)
        UserDefaults.standard.removeObject(forKey: Keys.lastErrorAt)
    }
}
