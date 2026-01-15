//
//  WidgetWeaverRemindersIntents.swift
//  WidgetWeaver
//
//  Created by . . on 1/15/26.
//

import AppIntents
import EventKit
import Foundation

struct WidgetWeaverCompleteReminderIntent: AppIntent {
    static var title: LocalizedStringResource { "Complete Reminder" }
    static var description: IntentDescription {
        IntentDescription("Marks a specific reminder (by identifier) as completed.")
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Reminder ID")
    var reminderID: String

    static var parameterSummary: some ParameterSummary {
        Summary("Complete reminder \(\.$reminderID)")
    }

    init() {}

    init(reminderID: String) {
        self.reminderID = reminderID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let cleanedID = reminderID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedID.isEmpty else {
            WidgetWeaverRemindersDebugStore.setLastAction(kind: "error", message: "Missing reminder ID.")
            return .result()
        }

        let status = EKEventStore.authorizationStatus(for: .reminder)
        guard status == .fullAccess || status == .writeOnly else {
            WidgetWeaverRemindersDebugStore.setLastAction(
                kind: "error",
                message: "Reminders access is not granted (status=\(status)). Open WidgetWeaver → Reminders and request Full Access."
            )
            return .result()
        }

        let eventStore = EKEventStore()

        guard let reminder = eventStore.calendarItem(withIdentifier: cleanedID) as? EKReminder else {
            WidgetWeaverRemindersDebugStore.setLastAction(
                kind: "error",
                message: "Reminder not found (or not readable). It may have been deleted, or Full Access is required."
            )
            return .result()
        }

        let rawTitle = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "Untitled" : rawTitle

        if reminder.isCompleted {
            WidgetWeaverRemindersDebugStore.setLastAction(kind: "noop", message: "Already completed: \(title).")
            return .result()
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            WidgetWeaverRemindersDebugStore.setLastAction(
                kind: "error",
                message: "Failed to complete reminder: \(error.localizedDescription)"
            )
            return .result()
        }

        WidgetWeaverRemindersDebugStore.setLastAction(kind: "completed", message: "Completed: \(title).")
        return .result()
    }
}
