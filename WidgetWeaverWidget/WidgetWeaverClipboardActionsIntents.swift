//
//  WidgetWeaverClipboardActionsIntents.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import AppIntents
import EventKit
import Foundation
import ScreenActionsCore
import WidgetKit

private enum ClipboardActionIntentError: Error, LocalizedError {
    case emptyInbox
    case eventsAccessDenied
    case noWritableCalendar

    var errorDescription: String? {
        switch self {
        case .emptyInbox:
            return "Clipboard inbox is empty."
        case .eventsAccessDenied:
            return "Calendar access was not granted."
        case .noWritableCalendar:
            return "No writable calendar is available."
        }
    }
}

@MainActor
private enum ClipboardActionHelpers {

    static func loadInboxText() throws -> String {
        let snap = WidgetWeaverClipboardInboxStore.load()
        guard let t = snap.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            throw ClipboardActionIntentError.emptyInbox
        }
        return t
    }

    static func setResult(kind: String, message: String, exportedCSVURL: URL? = nil) {
        WidgetWeaverClipboardInboxStore.setLastAction(kind: kind, message: message, exportedCSVURL: exportedCSVURL)
    }

    static func titleFromText(_ text: String, fallback: String) -> String {
        let first = text.components(separatedBy: .newlines).first ?? ""
        let t = first.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return fallback }
        return String(t.prefix(64))
    }

    static func requestEventsFullAccess(_ store: EKEventStore) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestFullAccessToEvents { granted, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard granted else {
                    cont.resume(throwing: ClipboardActionIntentError.eventsAccessDenied)
                    return
                }
                cont.resume(returning: ())
            }
        }
    }

    static func writableEventCalendar(in store: EKEventStore) throws -> EKCalendar {
        if let cal = store.defaultCalendarForNewEvents, cal.allowsContentModifications {
            return cal
        }
        if let cal = store.calendars(for: .event).first(where: { $0.allowsContentModifications }) {
            return cal
        }
        throw ClipboardActionIntentError.noWritableCalendar
    }

    static func firstLocationHint(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue) {
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            if let match = detector.firstMatch(in: trimmed, options: [], range: range),
               let r = Range(match.range, in: trimmed) {
                let candidate = String(trimmed[r]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty { return candidate }
            }
        }

        let patterns = [#"(?:^|\s)(?:at|@|in)\s+([^\n,.;:|]{3,80})"#]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive]) {
                let r = NSRange(trimmed.startIndex..., in: trimmed)
                if let m = re.firstMatch(in: trimmed, options: [], range: r),
                   m.numberOfRanges >= 2,
                   let range1 = Range(m.range(at: 1), in: trimmed)
                {
                    let candidate = String(trimmed[range1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty { return candidate }
                }
            }
        }

        return nil
    }

    static func createEvent(from text: String) async throws -> String {
        let store = EKEventStore()
        try await requestEventsFullAccess(store)

        let range: ScreenActionsCore.DetectedDateRange = {
            if let r = ScreenActionsCore.DateParser.firstDateRange(in: text) { return r }
            let start = Date().addingTimeInterval(15 * 60)
            let end = start.addingTimeInterval(60 * 60)
            return ScreenActionsCore.DetectedDateRange(start: start, end: end)
        }()

        let event = EKEvent(eventStore: store)
        event.calendar = try writableEventCalendar(in: store)
        event.title = titleFromText(text, fallback: "New Event")
        event.startDate = range.start
        event.endDate = range.end
        event.notes = text

        if let loc = firstLocationHint(in: text) {
            event.location = loc
        }

        try store.save(event, span: .thisEvent, commit: true)

        let id = event.eventIdentifier ?? ""
        return id.isEmpty ? UUID().uuidString : id
    }

    static func createReminder(from text: String) async throws -> String {
        let due = ScreenActionsCore.DateParser.firstDateRange(in: text)?.start
        let title = titleFromText(text, fallback: "New Reminder")

        let service = ScreenActionsCore.RemindersService(defaults: AppGroup.userDefaults)
        return try await service.addReminder(title: title, due: due, notes: text)
    }

    static func createContact(from text: String) async throws -> String {
        let detected = ScreenActionsCore.ContactParser.detect(in: text)
        return try await ScreenActionsCore.ContactsService.save(contact: detected)
    }

    static func exportReceiptCSV(from text: String) async throws -> URL {
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

// MARK: - Intents

struct WidgetWeaverClipboardAutoDetectIntent: AppIntent {
    static var title: LocalizedStringResource { "Auto Detect Clipboard Action" }
    static var description: IntentDescription {
        IntentDescription("Creates a reminder, event, contact, or receipt CSV from the clipboard inbox.")
    }
    static var openAppWhenRun: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            let text = try ClipboardActionHelpers.loadInboxText()
            let decision = ScreenActionsCore.ActionRouter.route(text: text)

            switch decision.kind {
            case .receipt:
                let url = try await ClipboardActionHelpers.exportReceiptCSV(from: text)
                ClipboardActionHelpers.setResult(kind: "auto-receipt", message: "CSV exported.", exportedCSVURL: url)

            case .contact:
                let id = try await ClipboardActionHelpers.createContact(from: text)
                ClipboardActionHelpers.setResult(kind: "auto-contact", message: "Contact saved. (\(id))")

            case .event:
                let id = try await ClipboardActionHelpers.createEvent(from: text)
                let usedDefault = (ScreenActionsCore.DateParser.firstDateRange(in: text) == nil)
                let msg = usedDefault ? "Event created (default time). (\(id))" : "Event created. (\(id))"
                ClipboardActionHelpers.setResult(kind: "auto-event", message: msg)

            case .reminder:
                let id = try await ClipboardActionHelpers.createReminder(from: text)
                ClipboardActionHelpers.setResult(kind: "auto-reminder", message: "Reminder created. (\(id))")
            }
        } catch {
            ClipboardActionHelpers.setResult(kind: "auto-error", message: error.localizedDescription)
        }

        return .result()
    }
}

struct WidgetWeaverClipboardCreateReminderIntent: AppIntent {
    static var title: LocalizedStringResource { "Create Reminder from Clipboard" }
    static var openAppWhenRun: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            let text = try ClipboardActionHelpers.loadInboxText()
            let id = try await ClipboardActionHelpers.createReminder(from: text)
            ClipboardActionHelpers.setResult(kind: "reminder", message: "Reminder created. (\(id))")
        } catch {
            ClipboardActionHelpers.setResult(kind: "reminder-error", message: error.localizedDescription)
        }
        return .result()
    }
}

struct WidgetWeaverClipboardCreateEventIntent: AppIntent {
    static var title: LocalizedStringResource { "Create Event from Clipboard" }
    static var openAppWhenRun: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            let text = try ClipboardActionHelpers.loadInboxText()
            let id = try await ClipboardActionHelpers.createEvent(from: text)
            let usedDefault = (ScreenActionsCore.DateParser.firstDateRange(in: text) == nil)
            let msg = usedDefault ? "Event created (default time). (\(id))" : "Event created. (\(id))"
            ClipboardActionHelpers.setResult(kind: "event", message: msg)
        } catch {
            ClipboardActionHelpers.setResult(kind: "event-error", message: error.localizedDescription)
        }
        return .result()
    }
}

struct WidgetWeaverClipboardCreateContactIntent: AppIntent {
    static var title: LocalizedStringResource { "Create Contact from Clipboard" }
    static var openAppWhenRun: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            let text = try ClipboardActionHelpers.loadInboxText()
            let id = try await ClipboardActionHelpers.createContact(from: text)
            ClipboardActionHelpers.setResult(kind: "contact", message: "Contact saved. (\(id))")
        } catch {
            ClipboardActionHelpers.setResult(kind: "contact-error", message: error.localizedDescription)
        }
        return .result()
    }
}

struct WidgetWeaverClipboardExportReceiptCSVIntent: AppIntent {
    static var title: LocalizedStringResource { "Export Receipt CSV from Clipboard" }
    static var openAppWhenRun: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        do {
            let text = try ClipboardActionHelpers.loadInboxText()
            let url = try await ClipboardActionHelpers.exportReceiptCSV(from: text)
            ClipboardActionHelpers.setResult(kind: "csv", message: "CSV exported.", exportedCSVURL: url)
        } catch {
            ClipboardActionHelpers.setResult(kind: "csv-error", message: error.localizedDescription)
        }
        return .result()
    }
}

struct WidgetWeaverClipboardClearInboxIntent: AppIntent {
    static var title: LocalizedStringResource { "Clear Clipboard Inbox" }
    static var openAppWhenRun: Bool { false }

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetWeaverClipboardInboxStore.clearAll()
        WidgetWeaverClipboardInboxStore.setLastAction(kind: "clear", message: "Inbox cleared.")
        return .result()
    }
}
