//
//  WidgetWeaverRemindersDebugStore.swift
//  WidgetWeaver
//
//  Created by . . on 1/15/26.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

public struct WidgetWeaverRemindersDebugSnapshot: Sendable, Hashable {
    public var testReminderID: String?

    public var lastActionKind: String?
    public var lastActionMessage: String?
    public var lastActionAt: Date?

    public init(
        testReminderID: String? = nil,
        lastActionKind: String? = nil,
        lastActionMessage: String? = nil,
        lastActionAt: Date? = nil
    ) {
        self.testReminderID = testReminderID
        self.lastActionKind = lastActionKind
        self.lastActionMessage = lastActionMessage
        self.lastActionAt = lastActionAt
    }
}

public enum WidgetWeaverRemindersDebugStore {
    public enum Keys {
        public static let testReminderID = "widgetweaver.reminders.debug.testReminderID.v1"

        public static let lastActionKind = "widgetweaver.reminders.debug.lastAction.kind.v1"
        public static let lastActionMessage = "widgetweaver.reminders.debug.lastAction.message.v1"
        public static let lastActionAt = "widgetweaver.reminders.debug.lastAction.at.v1"
    }

    public static func load() -> WidgetWeaverRemindersDebugSnapshot {
        let ud = AppGroup.userDefaults

        let testReminderID: String? = {
            let raw = ud.string(forKey: Keys.testReminderID)
            let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        let lastActionKind = ud.string(forKey: Keys.lastActionKind)
        let lastActionMessage = ud.string(forKey: Keys.lastActionMessage)

        let lastActionAt: Date? = {
            let t = ud.double(forKey: Keys.lastActionAt)
            if t <= 0 { return nil }
            return Date(timeIntervalSince1970: t)
        }()

        return WidgetWeaverRemindersDebugSnapshot(
            testReminderID: testReminderID,
            lastActionKind: lastActionKind,
            lastActionMessage: lastActionMessage,
            lastActionAt: lastActionAt
        )
    }

    public static func setTestReminderID(_ reminderID: String?) {
        let ud = AppGroup.userDefaults

        let cleaned: String? = {
            guard let reminderID else { return nil }
            let trimmed = reminderID.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        if let cleaned {
            ud.set(cleaned, forKey: Keys.testReminderID)
        } else {
            ud.removeObject(forKey: Keys.testReminderID)
        }

        ud.synchronize()
        reloadDebugSpikeWidgetTimelines()
    }

    public static func clearAll() {
        let ud = AppGroup.userDefaults
        ud.removeObject(forKey: Keys.testReminderID)
        ud.removeObject(forKey: Keys.lastActionKind)
        ud.removeObject(forKey: Keys.lastActionMessage)
        ud.removeObject(forKey: Keys.lastActionAt)
        ud.synchronize()

        reloadDebugSpikeWidgetTimelines()
    }

    public static func setLastAction(kind: String, message: String, at: Date = Date()) {
        let ud = AppGroup.userDefaults

        ud.set(kind, forKey: Keys.lastActionKind)
        ud.set(String(message.prefix(240)), forKey: Keys.lastActionMessage)
        ud.set(at.timeIntervalSince1970, forKey: Keys.lastActionAt)
        ud.synchronize()

        reloadDebugSpikeWidgetTimelines()
    }

    private static func reloadDebugSpikeWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.remindersDebugSpike)
        #endif
    }
}
