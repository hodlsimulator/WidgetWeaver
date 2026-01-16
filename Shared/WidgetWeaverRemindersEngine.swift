//
//  WidgetWeaverRemindersEngine.swift
//  WidgetWeaver
//
//  Created by . . on 1/16/26.
//
//  Phase 3.1: EventKit-backed Reminders engine (skeleton).
//
//  Contract:
//  - Widgets render from cached snapshots only (WidgetWeaverRemindersStore).
//  - This engine lives in the host app (and can later be shared with AppIntents), and is the only
//    place where EventKit reads/writes are performed for Reminders Pack.
//

import EventKit
import Foundation

/// Single owner for EventKit Reminders reads/writes.
///
/// Notes:
/// - `EKEventStore` is not `Sendable`. Actor isolation provides the safety boundary.
/// - Any mapping from `EKReminder` to `Sendable` models must occur inside the EventKit callback,
///   so no `EKReminder` values cross an `await` boundary.
public actor WidgetWeaverRemindersEngine {
    public static let shared = WidgetWeaverRemindersEngine()

    public struct ReminderListSummary: Identifiable, Hashable, Sendable {
        public var id: String
        public var title: String
        public var sourceTitle: String?

        public init(id: String, title: String, sourceTitle: String?) {
            self.id = id
            self.title = title
            self.sourceTitle = sourceTitle
        }
    }

    public enum EngineError: Error, LocalizedError, Sendable {
        case notAuthorised(status: EKAuthorizationStatus)
        case failedToComputeDateWindow

        public var errorDescription: String? {
            switch self {
            case .notAuthorised(let status):
                return "Reminders access is not granted (status=\(status))."
            case .failedToComputeDateWindow:
                return "Failed to compute the requested date window."
            }
        }
    }

    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    // MARK: - Authorisation

    public static func authorisationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    /// Requests Full Access to Reminders if the current status is `.notDetermined`.
    ///
    /// Returns `true` when Full Access is granted.
    @discardableResult
    public func requestAccessIfNeeded() async -> Bool {
        let status = Self.authorisationStatus()
        switch status {
        case .fullAccess:
            return true
        case .notDetermined:
            return await requestFullAccessToReminders()
        default:
            return false
        }
    }

    private func requestFullAccessToReminders() async -> Bool {
        await withCheckedContinuation { cont in
            eventStore.requestFullAccessToReminders { granted, error in
                if let error {
                    _ = error
                }
                cont.resume(returning: granted)
            }
        }
    }

    private func requireFullAccess() throws {
        let status = Self.authorisationStatus()
        guard status == .fullAccess else {
            throw EngineError.notAuthorised(status: status)
        }
    }

    // MARK: - Lists

    /// Loads all reminder lists (EventKit reminder calendars).
    public func fetchReminderLists() throws -> [ReminderListSummary] {
        try requireFullAccess()

        return eventStore.calendars(for: .reminder)
            .sorted { a, b in
                a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
            .map { cal in
                let title = cal.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                return ReminderListSummary(
                    id: cal.calendarIdentifier,
                    title: title.isEmpty ? "Untitled" : title,
                    sourceTitle: cal.source.title
                )
            }
    }

    // MARK: - Snapshot generation (Phase 3.2)

    /// Builds and writes a real Reminders snapshot into the App Group store.
    ///
    /// Behaviour:
    /// - When not authorised (including write-only), clears the cached snapshot (privacy) and writes a helpful error.
    /// - When authorised, writes a snapshot of *incomplete* reminders (capped to `maxItems`).
    ///
    /// Widgets must continue to render from the cached snapshot only.
    @discardableResult
    public func refreshSnapshotCache(maxItems: Int = 250) async -> WidgetWeaverRemindersDiagnostics {
        let store = WidgetWeaverRemindersStore.shared
        let status = Self.authorisationStatus()

        guard status == .fullAccess else {
            let diag = diagnosticsForUnauthorisedStatus(status)
            store.clearSnapshot()
            store.saveLastUpdatedAt(nil)
            store.saveLastError(diag)
            return diag
        }

        let startedAt = Date()

        do {
            let snapshot = try await buildGlobalIncompleteSnapshot(maxItems: maxItems)
            store.saveSnapshot(snapshot)

            let duration = Date().timeIntervalSince(startedAt)
            let durationString = String(format: "%.2f", duration)
            let message = "Snapshot updated in \(durationString)s."
            let diag = WidgetWeaverRemindersDiagnostics(kind: .ok, message: message, at: Date())
            return diag
        } catch {
            let diag = WidgetWeaverRemindersDiagnostics(
                kind: .error,
                message: "Snapshot refresh failed: \(error.localizedDescription)",
                at: Date()
            )
            store.saveLastError(diag)
            return diag
        }
    }

    private func diagnosticsForUnauthorisedStatus(_ status: EKAuthorizationStatus) -> WidgetWeaverRemindersDiagnostics {
        switch status {
        case .notDetermined:
            return WidgetWeaverRemindersDiagnostics(kind: .notAuthorised, message: "Reminders access has not been requested yet.")
        case .denied:
            return WidgetWeaverRemindersDiagnostics(kind: .denied, message: "Reminders access is denied. Grant Full Access in Settings to enable Reminders widgets.")
        case .restricted:
            return WidgetWeaverRemindersDiagnostics(kind: .restricted, message: "Reminders access is restricted by device policy.")
        case .writeOnly:
            return WidgetWeaverRemindersDiagnostics(kind: .writeOnly, message: "Reminders access is write-only. Widgets need Full Access to render snapshots.")
        case .fullAccess:
            return WidgetWeaverRemindersDiagnostics(kind: .ok, message: "Reminders access granted.")
        @unknown default:
            return WidgetWeaverRemindersDiagnostics(kind: .error, message: "Unknown Reminders authorisation status.")
        }
    }

    private func buildGlobalIncompleteSnapshot(maxItems: Int) async throws -> WidgetWeaverRemindersSnapshot {
        try requireFullAccess()

        let cal = Calendar.current
        let calendars = eventStore.calendars(for: .reminder)

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        let fetched = await fetchReminderItems(matching: predicate, calendar: cal)

        let cappedMax = max(1, min(maxItems, 2_000))
        let limited = Array(fetched.prefix(cappedMax))

        let message: String = {
            if fetched.count > limited.count {
                return "Fetched \(fetched.count) reminder(s) (trimmed to \(limited.count))."
            }
            return "Fetched \(limited.count) reminder(s)."
        }()

        return WidgetWeaverRemindersSnapshot(
            generatedAt: Date(),
            items: limited,
            modes: [],
            diagnostics: WidgetWeaverRemindersDiagnostics(kind: .ok, message: message, at: Date())
        )
    }

    // MARK: - Fetching

    /// Fetches incomplete reminders matching a due-date window.
    ///
    /// - Parameters:
    ///   - start: Start of the due window (inclusive). Pass `nil` for "any".
    ///   - end: End of the due window (exclusive). Pass `nil` for "any".
    ///   - selectedListIDs: Optional list filter (EKCalendar.calendarIdentifier). Empty means "all".
    ///   - limit: Optional limit applied after sorting.
    public func fetchIncompleteReminders(
        dueStarting start: Date?,
        dueEnding end: Date?,
        selectedListIDs: [String] = [],
        limit: Int? = nil
    ) async throws -> [WidgetWeaverReminderItem] {
        try requireFullAccess()

        let calendars = calendarsForSelectedLists(selectedListIDs)

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: calendars
        )

        let cal = Calendar.current
        let fetched = await fetchReminderItems(matching: predicate, calendar: cal)

        let sorted = fetched.sorted { a, b in
            switch (a.dueDate, b.dueDate) {
            case let (da?, db?):
                if da != db { return da < db }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }

        if let limit, limit > 0 {
            return Array(sorted.prefix(limit))
        }

        return sorted
    }

    /// Convenience for "Today" (start-of-day to start-of-next-day).
    public func fetchTodayIncompleteReminders(
        selectedListIDs: [String] = [],
        limit: Int = 25
    ) async throws -> [WidgetWeaverReminderItem] {
        try requireFullAccess()

        let now = Date()
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else {
            throw EngineError.failedToComputeDateWindow
        }

        return try await fetchIncompleteReminders(
            dueStarting: start,
            dueEnding: end,
            selectedListIDs: selectedListIDs,
            limit: limit
        )
    }

    private func calendarsForSelectedLists(_ selectedListIDs: [String]) -> [EKCalendar]? {
        let cleaned = selectedListIDs
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleaned.isEmpty else {
            return eventStore.calendars(for: .reminder)
        }

        let set = Set(cleaned)
        let calendars = eventStore.calendars(for: .reminder)
        let filtered = calendars.filter { set.contains($0.calendarIdentifier) }
        return filtered
    }

    /// Converts EventKit reminders into `WidgetWeaverReminderItem` inside the EventKit callback.
    ///
    /// This implementation intentionally avoids calling `.map` on an Optional, because SwiftUI
    /// provides a Gesture-related `map` overload that can be selected in some contexts and produce
    /// `_MapGesture` type errors.
    private func fetchReminderItems(
        matching predicate: NSPredicate,
        calendar: Calendar
    ) async -> [WidgetWeaverReminderItem] {
        await withCheckedContinuation { (cont: CheckedContinuation<[WidgetWeaverReminderItem], Never>) in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let reminderList: [EKReminder]
                if let reminders {
                    reminderList = reminders
                } else {
                    reminderList = []
                }

                var items: [WidgetWeaverReminderItem] = []
                items.reserveCapacity(reminderList.count)

                for r in reminderList {
                    let rawTitle = (r.title ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    let title = rawTitle.isEmpty ? "Untitled" : rawTitle

                    let dueComponents = r.dueDateComponents
                    let dueDate = dueComponents.flatMap { calendar.date(from: $0) }
                    let dueHasTime = Self.componentsHaveTime(dueComponents)

                    let startComponents = r.startDateComponents
                    let startDate = startComponents.flatMap { calendar.date(from: $0) }
                    let startHasTime = Self.componentsHaveTime(startComponents)

                    let rawListTitle = r.calendar.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    let listTitle = rawListTitle.isEmpty ? "Untitled" : rawListTitle

                    items.append(
                        WidgetWeaverReminderItem(
                            id: r.calendarItemIdentifier,
                            title: title,
                            dueDate: dueDate,
                            dueHasTime: dueHasTime,
                            startDate: startDate,
                            startHasTime: startHasTime,
                            isCompleted: r.isCompleted,
                            isFlagged: false,
                            listID: r.calendar.calendarIdentifier,
                            listTitle: listTitle
                        )
                    )
                }

                cont.resume(returning: items)
            }
        }
    }

    private static func componentsHaveTime(_ components: DateComponents?) -> Bool {
        guard let components else { return false }
        return components.hour != nil || components.minute != nil || components.second != nil
    }
}
