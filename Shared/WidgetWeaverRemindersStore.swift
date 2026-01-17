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

        public static let lastActionKind = "widgetweaver.reminders.lastAction.kind.v1"
        public static let lastActionMessage = "widgetweaver.reminders.lastAction.message.v1"
        public static let lastActionAt = "widgetweaver.reminders.lastAction.at.v1"

        // Phase 3.4: Refresh throttling/backoff (metadata only).
        public static let refreshLastAttemptAt = "widgetweaver.reminders.refresh.lastAttemptAt.v1"
        public static let refreshNextAllowedAt = "widgetweaver.reminders.refresh.nextAllowedAt.v1"
        public static let refreshConsecutiveFailureCount = "widgetweaver.reminders.refresh.consecutiveFailureCount.v1"
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

    @inline(__always)
    private func synchroniseAppGroupDefaults() {
        defaults.synchronize()
    }

    private func notifyWidgetsRemindersUpdated() {
        #if canImport(WidgetKit)
        // Avoid re-entrant reload loops while the widget extension is rendering.
        guard !WidgetWeaverRuntime.isRunningInAppExtension else { return }

        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
            #if DEBUG
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        #endif
    }

    // MARK: Snapshot

    public func loadSnapshot() -> WidgetWeaverRemindersSnapshot? {
        synchroniseAppGroupDefaults()

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
                synchroniseAppGroupDefaults()
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

            synchroniseAppGroupDefaults()

            saveLastUpdatedAt(snapshot.generatedAt)
            clearLastError()
        } else {
            defaults.removeObject(forKey: Keys.snapshotData)
            UserDefaults.standard.removeObject(forKey: Keys.snapshotData)

            synchroniseAppGroupDefaults()
        }

        notifyWidgetsRemindersUpdated()
    }

    public func clearSnapshot() {
        defaults.removeObject(forKey: Keys.snapshotData)
        UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        synchroniseAppGroupDefaults()
        notifyWidgetsRemindersUpdated()
    }

    // MARK: Last updated

    public func loadLastUpdatedAt() -> Date? {
        synchroniseAppGroupDefaults()

        let t = defaults.double(forKey: Keys.lastUpdatedAt)
        if t > 0 { return Date(timeIntervalSince1970: t) }

        let legacy = UserDefaults.standard.double(forKey: Keys.lastUpdatedAt)
        if legacy > 0 {
            defaults.set(legacy, forKey: Keys.lastUpdatedAt)
            synchroniseAppGroupDefaults()
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

        synchroniseAppGroupDefaults()
    }

    // MARK: Last error

    public func loadLastError() -> WidgetWeaverRemindersDiagnostics? {
        synchroniseAppGroupDefaults()

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
                synchroniseAppGroupDefaults()
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

        synchroniseAppGroupDefaults()

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

        synchroniseAppGroupDefaults()
        notifyWidgetsRemindersUpdated()
    }

    public func clearLastError() {
        defaults.removeObject(forKey: Keys.lastErrorKind)
        defaults.removeObject(forKey: Keys.lastErrorMessage)
        defaults.removeObject(forKey: Keys.lastErrorAt)

        UserDefaults.standard.removeObject(forKey: Keys.lastErrorKind)
        UserDefaults.standard.removeObject(forKey: Keys.lastErrorMessage)
        UserDefaults.standard.removeObject(forKey: Keys.lastErrorAt)

        synchroniseAppGroupDefaults()
    }


    // MARK: Last action

    public func loadLastAction() -> WidgetWeaverRemindersActionDiagnostics? {
        synchroniseAppGroupDefaults()

        let rawMessage = (defaults.string(forKey: Keys.lastActionMessage)
                          ?? UserDefaults.standard.string(forKey: Keys.lastActionMessage)
                          ?? "")
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }

        let rawKind = (defaults.string(forKey: Keys.lastActionKind)
                       ?? UserDefaults.standard.string(forKey: Keys.lastActionKind)
                       ?? WidgetWeaverRemindersActionDiagnostics.Kind.error.rawValue)

        let kind = WidgetWeaverRemindersActionDiagnostics.Kind(rawValue: rawKind) ?? .error

        let timestamp = defaults.double(forKey: Keys.lastActionAt)
        let at: Date = {
            if timestamp > 0 { return Date(timeIntervalSince1970: timestamp) }
            let legacy = UserDefaults.standard.double(forKey: Keys.lastActionAt)
            if legacy > 0 {
                defaults.set(legacy, forKey: Keys.lastActionAt)
                synchroniseAppGroupDefaults()
                return Date(timeIntervalSince1970: legacy)
            }
            return Date()
        }()

        // Heal any legacy values.
        if defaults.string(forKey: Keys.lastActionMessage) == nil {
            defaults.set(message, forKey: Keys.lastActionMessage)
        }
        if defaults.string(forKey: Keys.lastActionKind) == nil {
            defaults.set(kind.rawValue, forKey: Keys.lastActionKind)
        }

        synchroniseAppGroupDefaults()

        return WidgetWeaverRemindersActionDiagnostics(kind: kind, message: message, at: at)
    }

    public func saveLastAction(_ action: WidgetWeaverRemindersActionDiagnostics?) {
        let cleanedKind = action?.kind.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedMessage = action?.message.trimmingCharacters(in: .whitespacesAndNewlines)

        if let cleanedMessage, !cleanedMessage.isEmpty {
            let kindRaw = (cleanedKind?.isEmpty ?? true) ? WidgetWeaverRemindersActionDiagnostics.Kind.error.rawValue : cleanedKind!

            defaults.set(kindRaw, forKey: Keys.lastActionKind)
            defaults.set(String(cleanedMessage.prefix(240)), forKey: Keys.lastActionMessage)
            defaults.set((action?.at ?? Date()).timeIntervalSince1970, forKey: Keys.lastActionAt)

            UserDefaults.standard.set(kindRaw, forKey: Keys.lastActionKind)
            UserDefaults.standard.set(String(cleanedMessage.prefix(240)), forKey: Keys.lastActionMessage)
            UserDefaults.standard.set((action?.at ?? Date()).timeIntervalSince1970, forKey: Keys.lastActionAt)
        } else {
            clearLastAction()
        }

        synchroniseAppGroupDefaults()
        notifyWidgetsRemindersUpdated()
    }

    public func clearLastAction() {
        defaults.removeObject(forKey: Keys.lastActionKind)
        defaults.removeObject(forKey: Keys.lastActionMessage)
        defaults.removeObject(forKey: Keys.lastActionAt)

        UserDefaults.standard.removeObject(forKey: Keys.lastActionKind)
        UserDefaults.standard.removeObject(forKey: Keys.lastActionMessage)
        UserDefaults.standard.removeObject(forKey: Keys.lastActionAt)

        synchroniseAppGroupDefaults()
        notifyWidgetsRemindersUpdated()
    }

    // MARK: Refresh throttling (Phase 3.4)

    public func loadRefreshLastAttemptAt() -> Date? {
        synchroniseAppGroupDefaults()

        let t = defaults.double(forKey: Keys.refreshLastAttemptAt)
        if t > 0 { return Date(timeIntervalSince1970: t) }

        let legacy = UserDefaults.standard.double(forKey: Keys.refreshLastAttemptAt)
        if legacy > 0 {
            defaults.set(legacy, forKey: Keys.refreshLastAttemptAt)
            synchroniseAppGroupDefaults()
            return Date(timeIntervalSince1970: legacy)
        }

        return nil
    }

    public func saveRefreshLastAttemptAt(_ date: Date?) {
        if let date {
            let t = date.timeIntervalSince1970
            defaults.set(t, forKey: Keys.refreshLastAttemptAt)
            UserDefaults.standard.set(t, forKey: Keys.refreshLastAttemptAt)
        } else {
            defaults.removeObject(forKey: Keys.refreshLastAttemptAt)
            UserDefaults.standard.removeObject(forKey: Keys.refreshLastAttemptAt)
        }

        synchroniseAppGroupDefaults()
    }

    public func loadRefreshNextAllowedAt() -> Date? {
        synchroniseAppGroupDefaults()

        let t = defaults.double(forKey: Keys.refreshNextAllowedAt)
        if t > 0 { return Date(timeIntervalSince1970: t) }

        let legacy = UserDefaults.standard.double(forKey: Keys.refreshNextAllowedAt)
        if legacy > 0 {
            defaults.set(legacy, forKey: Keys.refreshNextAllowedAt)
            synchroniseAppGroupDefaults()
            return Date(timeIntervalSince1970: legacy)
        }

        return nil
    }

    public func saveRefreshNextAllowedAt(_ date: Date?) {
        if let date {
            let t = date.timeIntervalSince1970
            defaults.set(t, forKey: Keys.refreshNextAllowedAt)
            UserDefaults.standard.set(t, forKey: Keys.refreshNextAllowedAt)
        } else {
            defaults.removeObject(forKey: Keys.refreshNextAllowedAt)
            UserDefaults.standard.removeObject(forKey: Keys.refreshNextAllowedAt)
        }

        synchroniseAppGroupDefaults()
    }

    public func loadRefreshConsecutiveFailureCount() -> Int {
        synchroniseAppGroupDefaults()

        let count = defaults.integer(forKey: Keys.refreshConsecutiveFailureCount)
        if count > 0 { return count }

        let legacy = UserDefaults.standard.integer(forKey: Keys.refreshConsecutiveFailureCount)
        if legacy > 0 {
            defaults.set(legacy, forKey: Keys.refreshConsecutiveFailureCount)
            synchroniseAppGroupDefaults()
            return legacy
        }

        return 0
    }

    public func saveRefreshConsecutiveFailureCount(_ count: Int) {
        let cleaned = max(0, count)
        defaults.set(cleaned, forKey: Keys.refreshConsecutiveFailureCount)
        UserDefaults.standard.set(cleaned, forKey: Keys.refreshConsecutiveFailureCount)
        synchroniseAppGroupDefaults()
    }

    public func clearRefreshThrottleState() {
        defaults.removeObject(forKey: Keys.refreshLastAttemptAt)
        defaults.removeObject(forKey: Keys.refreshNextAllowedAt)
        defaults.removeObject(forKey: Keys.refreshConsecutiveFailureCount)

        UserDefaults.standard.removeObject(forKey: Keys.refreshLastAttemptAt)
        UserDefaults.standard.removeObject(forKey: Keys.refreshNextAllowedAt)
        UserDefaults.standard.removeObject(forKey: Keys.refreshConsecutiveFailureCount)

        synchroniseAppGroupDefaults()
    }


    // MARK: Snapshot diagnostics (metadata-only)

    /// Updates `snapshot.diagnostics` without updating `lastUpdatedAt` or notifying widgets.
    ///
    /// Intended for Phase 3.4 throttling diagnostics so the settings screen can surface
    /// the most recent refresh decision without causing WidgetKit churn.
    @discardableResult
    public func updateSnapshotDiagnosticsInPlace(_ diagnostics: WidgetWeaverRemindersDiagnostics?) -> Bool {
        guard var snap = loadSnapshot() else { return false }

        snap.diagnostics = diagnostics

        let encoder = makeEncoder()
        guard let data = try? encoder.encode(snap) else { return false }

        defaults.set(data, forKey: Keys.snapshotData)
        UserDefaults.standard.set(data, forKey: Keys.snapshotData)

        synchroniseAppGroupDefaults()
        return true
    }

}
