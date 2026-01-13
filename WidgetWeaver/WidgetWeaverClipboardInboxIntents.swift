//
//  WidgetWeaverClipboardInboxIntents.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import AppIntents
import Contacts
import EventKit
import Foundation
import ScreenActionsCore
import WidgetKit

private enum WWClipboardIntentHelpers {
    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func titleFromText(_ text: String, fallback: String) -> String {
        let first = text.components(separatedBy: .newlines).first ?? ""
        let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return fallback }
        return String(t.prefix(64))
    }

    static func defaultDateRange() -> ScreenActionsCore.DetectedDateRange {
        let start = Date().addingTimeInterval(15 * 60)
        let end = start.addingTimeInterval(60 * 60)
        return ScreenActionsCore.DetectedDateRange(start: start, end: end)
    }

    static func exportReceiptCSV(text: String) throws -> URL {
        let csv = ScreenActionsCore.CSVExporter.makeReceiptCSV(from: text)

        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = df.string(from: Date())

        let fileName = "receipt-\(stamp).csv"
        let dir = WidgetWeaverClipboardInboxStore.exportsDirectoryURL()
        return try ScreenActionsCore.CSVExporter.writeCSV(filename: fileName, csv: csv, directory: dir)
    }
}

struct WidgetWeaverSetClipboardInboxIntent: AppIntent {
    static var title: LocalizedStringResource { "Set WidgetWeaver Clipboard Inbox" }
    static var description: IntentDescription {
        IntentDescription("Stores text into WidgetWeaver’s clipboard inbox so widgets can act on it.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set WidgetWeaver clipboard inbox")
    }

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleaned = WWClipboardIntentHelpers.clean(text)
        guard !cleaned.isEmpty else {
            return .result(dialog: "Text was empty.")
        }

        WidgetWeaverClipboardInboxStore.saveInboxText(cleaned, capturedAt: Date())
        WidgetWeaverClipboardInboxStore.setLastAction(kind: "inbox", message: "Inbox updated.")

        return .result(dialog: "Inbox updated.")
    }
}

struct WidgetWeaverAutoDetectFromTextIntent: AppIntent {
    static var title: LocalizedStringResource { "Auto Detect (WidgetWeaver) from Text" }
    static var description: IntentDescription {
        IntentDescription("Runs WidgetWeaver’s Screen Actions-style auto-detect on text, and updates the clipboard widget inbox + status.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Text")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Auto-detect action from text")
    }

    init() {}

    init(text: String) {
        self.text = text
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleaned = WWClipboardIntentHelpers.clean(text)
        guard !cleaned.isEmpty else {
            return .result(dialog: "Text was empty.")
        }

        WidgetWeaverClipboardInboxStore.saveInboxText(cleaned, capturedAt: Date())

        let decision = ScreenActionsCore.ActionRouter.route(text: cleaned)

        do {
            switch decision.kind {
            case .receipt:
                let url = try WWClipboardIntentHelpers.exportReceiptCSV(text: cleaned)
                WidgetWeaverClipboardInboxStore.setLastAction(
                    kind: "auto-receipt",
                    message: "CSV exported.",
                    exportedCSVURL: url
                )
                return .result(dialog: "CSV exported.")

            case .contact:
                let detected = ScreenActionsCore.ContactParser.detect(in: cleaned)
                let id = try await ScreenActionsCore.ContactsService.save(contact: detected)
                WidgetWeaverClipboardInboxStore.setLastAction(
                    kind: "auto-contact",
                    message: "Contact saved. (\(id))"
                )
                return .result(dialog: "Contact saved.")

            case .event:
                let range = ScreenActionsCore.DateParser.firstDateRange(in: cleaned) ?? WWClipboardIntentHelpers.defaultDateRange()
                let title = WWClipboardIntentHelpers.titleFromText(cleaned, fallback: "New Event")

                let calendar = ScreenActionsCore.CalendarService()
                let id = try await calendar.addEvent(
                    title: title,
                    start: range.start,
                    end: range.end,
                    notes: cleaned,
                    locationHint: nil
                )

                let usedDefault = (ScreenActionsCore.DateParser.firstDateRange(in: cleaned) == nil)
                let msg = usedDefault ? "Event created (default time). (\(id))" : "Event created. (\(id))"
                WidgetWeaverClipboardInboxStore.setLastAction(kind: "auto-event", message: msg)
                return .result(dialog: usedDefault ? "Event created (default time)." : "Event created.")

            case .reminder:
                let due = ScreenActionsCore.DateParser.firstDateRange(in: cleaned)?.start
                let title = WWClipboardIntentHelpers.titleFromText(cleaned, fallback: "New Reminder")

                let reminders = ScreenActionsCore.RemindersService(defaults: AppGroup.userDefaults)
                let id = try await reminders.addReminder(title: title, due: due, notes: cleaned)

                WidgetWeaverClipboardInboxStore.setLastAction(
                    kind: "auto-reminder",
                    message: "Reminder created. (\(id))"
                )
                return .result(dialog: "Reminder created.")
            }
        } catch {
            WidgetWeaverClipboardInboxStore.setLastAction(kind: "auto-error", message: error.localizedDescription)
            return .result(dialog: "Failed: \(error.localizedDescription)")
        }
    }
}
