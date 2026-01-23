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

import AppIntents
import EventKit
import Foundation
import WidgetKit

public struct WidgetWeaverRemindersRefreshPolicy: Sendable {
    public let minimumIntervalSeconds: TimeInterval
    public let maximumConsecutiveFailureCount: Int

    public init(minimumIntervalSeconds: TimeInterval, maximumConsecutiveFailureCount: Int) {
        self.minimumIntervalSeconds = minimumIntervalSeconds
        self.maximumConsecutiveFailureCount = max(1, maximumConsecutiveFailureCount)
    }

    public func backoffSeconds(consecutiveFailures: Int) -> TimeInterval {
        // Exponential backoff: 2^n seconds (capped).
        let n = max(0, consecutiveFailures)
        let exp = pow(2.0, Double(n))
        return min(300, exp)
    }

    public static let `default` = WidgetWeaverRemindersRefreshPolicy(minimumIntervalSeconds: 15, maximumConsecutiveFailureCount: 6)
    public static let widgetAction = WidgetWeaverRemindersRefreshPolicy(minimumIntervalSeconds: 3, maximumConsecutiveFailureCount: 4)
}

public enum WidgetWeaverRemindersEngineAccessResult: Sendable {
    case granted
    case denied
    case writeOnly
    case restricted
    case notDetermined
    case error(String)
}

public enum WidgetWeaverRemindersEngineAccessKind: String, Sendable {
    case notDetermined
    case denied
    case restricted
    case writeOnly
    case fullAccess
    case error
}

public enum WidgetWeaverRemindersEngineRequiredAccess: String, Sendable {
    case fullAccess
}

public enum WidgetWeaverRemindersEngineError: Error, LocalizedError, Sendable {
    case notAuthorised
    case writeOnly
    case denied
    case restricted
    case failedToComputeDateWindow
    case missingIdentifier
    case failedToFindReminder
    case saveFailed

    public var errorDescription: String? {
        switch self {
        case .notAuthorised:
            return "Reminders access has not been granted."
        case .writeOnly:
            return "Reminders access is write-only. Full access is required."
        case .denied:
            return "Reminders access is denied."
        case .restricted:
            return "Reminders access is restricted."
        case .failedToComputeDateWindow:
            return "Failed to compute the requested due-date window."
        case .missingIdentifier:
            return "Missing reminder identifier."
        case .failedToFindReminder:
            return "Failed to find the requested reminder."
        case .saveFailed:
            return "Failed to save the reminder."
        }
    }
}

public final class WidgetWeaverRemindersEngine: @unchecked Sendable {
    public static let shared = WidgetWeaverRemindersEngine()

    // MARK: - List summaries (Phase 6)

    public struct ReminderListSummary: Identifiable, Hashable, Sendable {
        public let id: String
        public let title: String
        public let sourceTitle: String?

        public init(id: String, title: String, sourceTitle: String?) {
            self.id = id
            self.title = title
            self.sourceTitle = sourceTitle
        }
    }

    private let eventStore: EKEventStore
    private var inFlightRefresh: Task<WidgetWeaverRemindersDiagnostics, Never>?

    private init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    // MARK: - Authorisation

    public static func authorisationStatus() -> EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    public static func accessKind() -> WidgetWeaverRemindersEngineAccessKind {
        let status = authorisationStatus()
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .writeOnly:
            return .writeOnly
        case .fullAccess:
            return .fullAccess
        @unknown default:
            return .error
        }
    }

    public func requestAccessIfNeeded() async -> Bool {
        let result = await requestFullAccessIfNeeded()
        switch result {
        case .granted:
            return true
        case .denied, .writeOnly, .restricted, .notDetermined, .error:
            return false
        }
    }

    public func requestFullAccessIfNeeded() async -> WidgetWeaverRemindersEngineAccessResult {
        let status = Self.authorisationStatus()

        if status == .fullAccess {
            return .granted
        }

        if status == .denied {
            return .denied
        }

        if status == .restricted {
            return .restricted
        }

        if status == .writeOnly {
            return .writeOnly
        }

        guard status == .notDetermined else {
            return .error("Unknown status: \(status)")
        }

        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            return granted ? .granted : .denied
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func requireFullAccess() throws {
        let status = Self.authorisationStatus()
        switch status {
        case .fullAccess:
            return
        case .notDetermined:
            throw WidgetWeaverRemindersEngineError.notAuthorised
        case .writeOnly:
            throw WidgetWeaverRemindersEngineError.writeOnly
        case .denied:
            throw WidgetWeaverRemindersEngineError.denied
        case .restricted:
            throw WidgetWeaverRemindersEngineError.restricted
        @unknown default:
            throw WidgetWeaverRemindersEngineError.notAuthorised
        }
    }

    // MARK: - Completion (Phase 5)

    public func completeReminder(identifier: String) async -> WidgetWeaverRemindersActionDiagnostics {
        let cleaned = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return WidgetWeaverRemindersActionDiagnostics(kind: .error, message: "Missing reminder identifier.")
        }

        let status = Self.authorisationStatus()
        guard status == .fullAccess else {
            return WidgetWeaverRemindersActionDiagnostics(kind: .error, message: "Reminders Full Access not granted.")
        }

        do {
            try requireFullAccess()

            // Fast path: direct lookup by identifier.
            if let item = eventStore.calendarItem(withIdentifier: cleaned) as? EKReminder {
                item.isCompleted = true
                try eventStore.save(item, commit: true)

                let title = item.title ?? "Untitled"
                return WidgetWeaverRemindersActionDiagnostics(kind: .completed, message: "Completed: \(title).")
            }
        } catch {
            return WidgetWeaverRemindersActionDiagnostics(kind: .error, message: "Failed to complete reminder: \(error.localizedDescription)")
        }

        // Fallback: full fetch and complete within the EventKit callback to avoid sending EKReminder across
        // a concurrency boundary (EKReminder is not Sendable).
        return await withCheckedContinuation { (cont: CheckedContinuation<WidgetWeaverRemindersActionDiagnostics, Never>) in
            let predicate = self.eventStore.predicateForReminders(in: self.eventStore.calendars(for: .reminder))
            self.eventStore.fetchReminders(matching: predicate) { rs in
                guard let reminder = rs?.first(where: { $0.calendarItemIdentifier == cleaned }) else {
                    cont.resume(returning: WidgetWeaverRemindersActionDiagnostics(kind: .error, message: "Reminder not found."))
                    return
                }

                reminder.isCompleted = true

                do {
                    try self.eventStore.save(reminder, commit: true)
                    let title = reminder.title ?? "Untitled"
                    cont.resume(returning: WidgetWeaverRemindersActionDiagnostics(kind: .completed, message: "Completed: \(title)."))
                } catch {
                    cont.resume(returning: WidgetWeaverRemindersActionDiagnostics(kind: .error, message: "Failed to complete reminder: \(error.localizedDescription)"))
                }
            }
        }
    }

    // MARK: - Lists (Phase 6)

    public func fetchReminderLists() async throws -> [ReminderListSummary] {
        try requireFullAccess()

        let calendars = eventStore.calendars(for: .reminder)

        var out: [ReminderListSummary] = []
        out.reserveCapacity(calendars.count)

        for cal in calendars {
            let rawTitle = cal.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let title = rawTitle.isEmpty ? "Untitled" : rawTitle

            let rawSourceTitle = cal.source.title.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let sourceTitle: String? = rawSourceTitle.isEmpty ? nil : rawSourceTitle

            out.append(ReminderListSummary(id: cal.calendarIdentifier, title: title, sourceTitle: sourceTitle))
        }

        out.sort { a, b in
            let sa = a.sourceTitle ?? ""
            let sb = b.sourceTitle ?? ""
            if sa != sb {
                return sa.localizedCaseInsensitiveCompare(sb) == .orderedAscending
            }

            if a.title != b.title {
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }

            return a.id < b.id
        }

        return out
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
    public func refreshSnapshotCache(
        maxItems: Int = 250,
        force: Bool = false,
        policy: WidgetWeaverRemindersRefreshPolicy = .default
    ) async -> WidgetWeaverRemindersDiagnostics {
        if let inFlightRefresh {
            return await inFlightRefresh.value
        }

        let task = Task { () -> WidgetWeaverRemindersDiagnostics in
            await self.performRefreshSnapshotCache(maxItems: maxItems, force: force, policy: policy)
        }

        inFlightRefresh = task
        let out = await task.value
        inFlightRefresh = nil
        return out
    }

    private func performRefreshSnapshotCache(
        maxItems: Int,
        force: Bool,
        policy: WidgetWeaverRemindersRefreshPolicy
    ) async -> WidgetWeaverRemindersDiagnostics {
        let store = WidgetWeaverRemindersStore.shared
        let now = Date()

        store.saveRefreshLastAttemptAt(now)

        if !force, let nextAllowedAt = store.loadRefreshNextAllowedAt(), now < nextAllowedAt {
            let remaining = max(0, nextAllowedAt.timeIntervalSince(now))
            let remainingSeconds = Int(ceil(remaining))
            let message = "Refresh skipped (throttled). Try again in \(remainingSeconds)s."
            let diag = WidgetWeaverRemindersDiagnostics(kind: .ok, message: message, at: now)

            // Surface the decision in app settings without causing widget reload churn.
            _ = store.updateSnapshotDiagnosticsInPlace(diag)
            return diag
        }

        let status = Self.authorisationStatus()

        guard status == .fullAccess else {
            let base = diagnosticsForUnauthorisedStatus(status)

            // For permission-denied paths, do not carry over exponential backoff.
            store.saveRefreshConsecutiveFailureCount(0)

            let permissionThrottleSeconds = min(policy.minimumIntervalSeconds, 10)
            let nextAllowedAt = now.addingTimeInterval(max(0, permissionThrottleSeconds))
            store.saveRefreshNextAllowedAt(nextAllowedAt)

            let remainingSeconds = Int(ceil(max(0, nextAllowedAt.timeIntervalSince(now))))
            let message = "\(base.message) Next retry after \(remainingSeconds)s."
            let diag = WidgetWeaverRemindersDiagnostics(kind: base.kind, message: message, at: now)

            store.clearSnapshot()
            store.saveLastUpdatedAt(nil)
            store.saveLastError(diag)
            return diag
        }

        let startedAt = Date()
        let selectedListIDs = store.loadSelectedListIDs()

        do {
            let (items, fetchedCount) = try await fetchGlobalIncompleteReminderItems(
                maxItems: maxItems,
                selectedListIDs: selectedListIDs
            )

            let duration = Date().timeIntervalSince(startedAt)
            let durationString = String(format: "%.2f", duration)

            let listFilterText: String = {
                if selectedListIDs.isEmpty { return "" }
                return " (\(selectedListIDs.count) list(s))"
            }()

            let message: String = {
                if fetchedCount > items.count {
                    return "Fetched \(fetchedCount) reminder(s)\(listFilterText) (trimmed to \(items.count)) in \(durationString)s."
                }
                return "Fetched \(items.count) reminder(s)\(listFilterText) in \(durationString)s."
            }()

            let diag = WidgetWeaverRemindersDiagnostics(kind: .ok, message: message, at: now)

            let snapshot = WidgetWeaverRemindersSnapshot(
                generatedAt: now,
                items: items,
                modes: Self.buildModeSnapshots(items: items),
                diagnostics: diag
            )

            store.saveSnapshot(snapshot)

            store.saveRefreshConsecutiveFailureCount(0)
            store.saveRefreshNextAllowedAt(now.addingTimeInterval(max(0, policy.minimumIntervalSeconds)))

            return diag
        } catch {
            let duration = Date().timeIntervalSince(startedAt)
            let durationString = String(format: "%.2f", duration)

            let previousFailures = store.loadRefreshConsecutiveFailureCount()
            let nextFailures = min(previousFailures + 1, policy.maximumConsecutiveFailureCount)
            store.saveRefreshConsecutiveFailureCount(nextFailures)

            let backoffSeconds = max(policy.minimumIntervalSeconds, policy.backoffSeconds(consecutiveFailures: nextFailures))
            let nextAllowedAt = now.addingTimeInterval(max(0, backoffSeconds))
            store.saveRefreshNextAllowedAt(nextAllowedAt)

            let remainingSeconds = Int(ceil(max(0, nextAllowedAt.timeIntervalSince(now))))

            let diag = WidgetWeaverRemindersDiagnostics(
                kind: .error,
                message: "Snapshot refresh failed in \(durationString)s: \(error.localizedDescription) Next retry after \(remainingSeconds)s.",
                at: now
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

    private func fetchGlobalIncompleteReminderItems(
        maxItems: Int,
        selectedListIDs: [String]
    ) async throws -> (items: [WidgetWeaverReminderItem], fetchedCount: Int) {
        try requireFullAccess()

        let cal = Calendar.current
        let calendars = calendarsForSelectedLists(selectedListIDs)

        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        let fetched = await fetchReminderItems(matching: predicate, calendar: cal)

        let cappedMax = max(1, min(maxItems, 2_000))
        let limited = Array(fetched.prefix(cappedMax))

        return (items: limited, fetchedCount: fetched.count)
    }

    // MARK: - Mode snapshots (Phase 3.3)

    /// Builds per-mode ordering indices for widget rendering.
    ///
    /// Notes:
    /// - These are intentionally *ordering* indices, not per-widget filters.
    /// - Widgets still apply their own config filters (list selection, soon window, etc.).
    /// - Tie-breaks include `id` to keep ordering stable.
    private static func buildModeSnapshots(items: [WidgetWeaverReminderItem]) -> [WidgetWeaverRemindersModeSnapshot] {
        func compareGeneral(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let da = a.dueDate ?? a.startDate ?? Date.distantFuture
            let db = b.dueDate ?? b.startDate ?? Date.distantFuture

            if da != db { return da < db }

            let titleComp = a.title.localizedCaseInsensitiveCompare(b.title)
            if titleComp != .orderedSame { return titleComp == .orderedAscending }

            return a.id < b.id
        }

        func compareDueOnly(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let da = a.dueDate ?? Date.distantFuture
            let db = b.dueDate ?? Date.distantFuture

            if da != db { return da < db }

            let titleComp = a.title.localizedCaseInsensitiveCompare(b.title)
            if titleComp != .orderedSame { return titleComp == .orderedAscending }

            return a.id < b.id
        }

        func compareList(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let listComp = a.listTitle.localizedCaseInsensitiveCompare(b.listTitle)
            if listComp != .orderedSame { return listComp == .orderedAscending }

            let da = a.dueDate ?? a.startDate ?? Date.distantFuture
            let db = b.dueDate ?? b.startDate ?? Date.distantFuture

            if da != db { return da < db }

            let titleComp = a.title.localizedCaseInsensitiveCompare(b.title)
            if titleComp != .orderedSame { return titleComp == .orderedAscending }

            return a.id < b.id
        }

        let allSorted = items.sorted(by: compareGeneral)
        let dueSorted = items
            .filter { $0.dueDate != nil }
            .sorted(by: compareDueOnly)

        let flaggedSorted = items
            .filter { $0.isFlagged }
            .sorted(by: compareGeneral)

        let listSorted = items.sorted(by: compareList)

        return [
            WidgetWeaverRemindersModeSnapshot(mode: .today, itemIDs: allSorted.map { $0.id }),
            WidgetWeaverRemindersModeSnapshot(mode: .overdue, itemIDs: dueSorted.map { $0.id }),
            WidgetWeaverRemindersModeSnapshot(mode: .soon, itemIDs: dueSorted.map { $0.id }),
            WidgetWeaverRemindersModeSnapshot(mode: .flagged, itemIDs: flaggedSorted.map { $0.id }),
            WidgetWeaverRemindersModeSnapshot(mode: .focus, itemIDs: allSorted.map { $0.id }),
            WidgetWeaverRemindersModeSnapshot(mode: .list, itemIDs: listSorted.map { $0.id }),
        ]
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
            throw WidgetWeaverRemindersEngineError.failedToComputeDateWindow
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

                    let isRecurring = !(r.recurrenceRules?.isEmpty ?? true)

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
                            isFlagged: Self.isFlaggedApproximation(priority: r.priority),
                            isRecurring: isRecurring,
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

    private static func isFlaggedApproximation(priority: Int) -> Bool {
        // EventKit does not currently expose the Reminders app "Flagged" state.
        // Approximation: treat "High Priority" (1-4) as "flagged" so the mode is useful.
        guard priority > 0 else { return false }
        return priority <= 4
    }

}

// MARK: - Widget action intent (Phase 5)

/// Completes a reminder from an interactive widget row tap.
///
/// Behaviour:
/// - Writes last-action diagnostics to the Reminders store.
/// - Refreshes the snapshot cache so the widget content converges.
/// - Reloads the main widget timelines so Home Screen redraws promptly.
public struct WidgetWeaverCompleteReminderWidgetIntent: AppIntent {
    public static var title: LocalizedStringResource { "Complete Reminder" }

    public static var description: IntentDescription {
        IntentDescription("Marks a specific reminder (by identifier) as completed.")
    }

    public static var openAppWhenRun: Bool { false }

    @Parameter(title: "Reminder ID")
    public var reminderID: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Complete reminder \(\.$reminderID)")
    }

    public init() {}

    public init(reminderID: String) {
        self.reminderID = reminderID
    }

    public func perform() async throws -> some IntentResult {
        let cleanedID = reminderID.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        let store = WidgetWeaverRemindersStore.shared

        let action = await WidgetWeaverRemindersEngine.shared.completeReminder(identifier: cleanedID)
        store.saveLastAction(action)

        let beforeUpdatedAt = store.loadLastUpdatedAt()

        let refresh = await WidgetWeaverRemindersEngine.shared.refreshSnapshotCache(policy: .widgetAction)

        let afterUpdatedAt = store.loadLastUpdatedAt()
        let refreshAdvanced: Bool = {
            guard let afterUpdatedAt else { return false }
            guard let beforeUpdatedAt else { return true }
            return afterUpdatedAt > beforeUpdatedAt
        }()

        if action.kind == .completed, refresh.kind == .ok, refreshAdvanced {
            store.clearLastAction()
        }

        await MainActor.run {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
            #if DEBUG
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }

        return .result()
    }
}
