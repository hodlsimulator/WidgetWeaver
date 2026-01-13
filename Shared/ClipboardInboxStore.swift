//
//  ClipboardInboxStore.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

public struct WidgetWeaverClipboardInboxSnapshot: Sendable, Hashable {
    public var text: String?
    public var capturedAt: Date?

    public var lastActionKind: String?
    public var lastActionMessage: String?
    public var lastActionAt: Date?

    public var lastExportedCSVPath: String?

    public init(
        text: String? = nil,
        capturedAt: Date? = nil,
        lastActionKind: String? = nil,
        lastActionMessage: String? = nil,
        lastActionAt: Date? = nil,
        lastExportedCSVPath: String? = nil
    ) {
        self.text = text
        self.capturedAt = capturedAt
        self.lastActionKind = lastActionKind
        self.lastActionMessage = lastActionMessage
        self.lastActionAt = lastActionAt
        self.lastExportedCSVPath = lastExportedCSVPath
    }
}

public enum WidgetWeaverClipboardInboxStore {
    private static let textKey = "widgetweaver.clipboardInbox.text.v1"
    private static let capturedAtKey = "widgetweaver.clipboardInbox.capturedAt.v1"

    private static let lastActionKindKey = "widgetweaver.clipboardInbox.lastAction.kind.v1"
    private static let lastActionMessageKey = "widgetweaver.clipboardInbox.lastAction.message.v1"
    private static let lastActionAtKey = "widgetweaver.clipboardInbox.lastAction.at.v1"

    private static let lastExportedCSVPathKey = "widgetweaver.clipboardInbox.lastExportedCSVPath.v1"

    private static let maxStoredCharacters: Int = 4000

    public static func load() -> WidgetWeaverClipboardInboxSnapshot {
        let ud = AppGroup.userDefaults

        let rawText = ud.string(forKey: textKey)
        let text: String? = {
            guard let rawText else { return nil }
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }()

        let capturedAt: Date? = {
            let t = ud.double(forKey: capturedAtKey)
            if t <= 0 { return nil }
            return Date(timeIntervalSince1970: t)
        }()

        let lastActionKind = ud.string(forKey: lastActionKindKey)
        let lastActionMessage = ud.string(forKey: lastActionMessageKey)

        let lastActionAt: Date? = {
            let t = ud.double(forKey: lastActionAtKey)
            if t <= 0 { return nil }
            return Date(timeIntervalSince1970: t)
        }()

        let lastExportedCSVPath = ud.string(forKey: lastExportedCSVPathKey)

        return WidgetWeaverClipboardInboxSnapshot(
            text: text,
            capturedAt: capturedAt,
            lastActionKind: lastActionKind,
            lastActionMessage: lastActionMessage,
            lastActionAt: lastActionAt,
            lastExportedCSVPath: lastExportedCSVPath
        )
    }

    public static func saveInboxText(_ text: String?, capturedAt: Date = Date()) {
        let ud = AppGroup.userDefaults

        if let text {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                ud.removeObject(forKey: textKey)
                ud.removeObject(forKey: capturedAtKey)
            } else {
                ud.set(String(trimmed.prefix(maxStoredCharacters)), forKey: textKey)
                ud.set(capturedAt.timeIntervalSince1970, forKey: capturedAtKey)
            }
        } else {
            ud.removeObject(forKey: textKey)
            ud.removeObject(forKey: capturedAtKey)
        }

        ud.synchronize()
        reloadClipboardWidgetTimelines()
    }

    public static func clearAll() {
        let ud = AppGroup.userDefaults
        ud.removeObject(forKey: textKey)
        ud.removeObject(forKey: capturedAtKey)
        ud.removeObject(forKey: lastActionKindKey)
        ud.removeObject(forKey: lastActionMessageKey)
        ud.removeObject(forKey: lastActionAtKey)
        ud.removeObject(forKey: lastExportedCSVPathKey)
        ud.synchronize()

        reloadClipboardWidgetTimelines()
    }

    public static func setLastAction(
        kind: String,
        message: String,
        at: Date = Date(),
        exportedCSVURL: URL? = nil
    ) {
        let ud = AppGroup.userDefaults

        ud.set(kind, forKey: lastActionKindKey)
        ud.set(String(message.prefix(160)), forKey: lastActionMessageKey)
        ud.set(at.timeIntervalSince1970, forKey: lastActionAtKey)

        if let exportedCSVURL {
            ud.set(exportedCSVURL.path, forKey: lastExportedCSVPathKey)
        }

        ud.synchronize()
        reloadClipboardWidgetTimelines()
    }

    public static func exportsDirectoryURL() -> URL {
        AppGroup.containerURL.appendingPathComponent("ClipboardExports", isDirectory: true)
    }

    private static func reloadClipboardWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.clipboardActions)
        #endif
    }
}
