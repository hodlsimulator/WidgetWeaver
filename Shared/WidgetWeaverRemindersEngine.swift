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
                let title = cal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return ReminderListSummary(
                    id: cal.calendarIdentifier,
                    title: title.isEmpty ? "Untitled" : title,
                    sourceTitle: cal.source.title
                )
            }
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
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
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
    private func fetchReminderItems(
        matching predicate: NSPredicate,
        calendar: Calendar
    ) async -> [WidgetWeaverReminderItem] {
        await withCheckedContinuation { cont in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let items: [WidgetWeaverReminderItem] = (reminders ?? []).map { r in
                    let rawTitle = (r.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let title = rawTitle.isEmpty ? "Untitled" : rawTitle

                    let dueComponents = r.dueDateComponents
                    let dueDate = dueComponents.flatMap { calendar.date(from: $0) }
                    let dueHasTime = Self.componentsHaveTime(dueComponents)

                    let startComponents = r.startDateComponents
                    let startDate = startComponents.flatMap { calendar.date(from: $0) }
                    let startHasTime = Self.componentsHaveTime(startComponents)

                    return WidgetWeaverReminderItem(
                        id: r.calendarItemIdentifier,
                        title: title,
                        dueDate: dueDate,
                        dueHasTime: dueHasTime,
                        startDate: startDate,
                        startHasTime: startHasTime,
                        isCompleted: r.isCompleted,
                        isFlagged: false,
                        listID: r.calendar.calendarIdentifier,
                        listTitle: r.calendar.title.isEmpty ? "Untitled" : r.calendar.title
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
