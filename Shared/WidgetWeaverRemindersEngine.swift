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

#if canImport(WidgetKit)
import WidgetKit
#endif

/// Controls how aggressively the Reminders engine refreshes the snapshot cache.
///
/// Goals:
/// - Avoid churn and WidgetKit budget issues.
/// - Converge quickly after interactive widget actions.
/// - Back off after repeated failures to prevent tight error loops.
public struct WidgetWeaverRemindersRefreshPolicy: Hashable, Sendable {
    /// Minimum time between refresh attempts after a successful refresh.
    public var minimumIntervalSeconds: TimeInterval

    /// Base delay applied after the first failure. Subsequent failures double this value.
    public var baseErrorBackoffSeconds: TimeInterval

    /// Maximum delay cap for exponential backoff.
    public var maximumErrorBackoffSeconds: TimeInterval

    /// Caps the consecutive failure count used for backoff calculations.
    public var maximumConsecutiveFailureCount: Int

    public init(
        minimumIntervalSeconds: TimeInterval,
        baseErrorBackoffSeconds: TimeInterval,
        maximumErrorBackoffSeconds: TimeInterval,
        maximumConsecutiveFailureCount: Int
    ) {
        self.minimumIntervalSeconds = max(0, minimumIntervalSeconds)
        self.baseErrorBackoffSeconds = max(0, baseErrorBackoffSeconds)
        self.maximumErrorBackoffSeconds = max(0, maximumErrorBackoffSeconds)
        self.maximumConsecutiveFailureCount = max(1, maximumConsecutiveFailureCount)
    }

    /// Default policy for user-initiated refreshes.
    public static let `default` = WidgetWeaverRemindersRefreshPolicy(
        minimumIntervalSeconds: 15,
        baseErrorBackoffSeconds: 20,
        maximumErrorBackoffSeconds: 60 * 10,
        maximumConsecutiveFailureCount: 8
    )

    /// Policy tuned for interactive widget actions (row taps).
    public static let widgetAction = WidgetWeaverRemindersRefreshPolicy(
        minimumIntervalSeconds: 3,
        baseErrorBackoffSeconds: 10,
        maximumErrorBackoffSeconds: 60 * 2,
        maximumConsecutiveFailureCount: 6
    )

    /// Policy for unattended refreshes (future use).
    public static let background = WidgetWeaverRemindersRefreshPolicy(
        minimumIntervalSeconds: 60,
        baseErrorBackoffSeconds: 60,
        maximumErrorBackoffSeconds: 60 * 30,
        maximumConsecutiveFailureCount: 10
    )

    /// Returns the backoff delay for the given consecutive failure count.
    public func backoffSeconds(consecutiveFailures: Int) -> TimeInterval {
        let failures = max(1, consecutiveFailures)
        let clamped = min(maximumConsecutiveFailureCount, failures)
        let exponent = max(0, clamped - 1)

        let seconds = baseErrorBackoffSeconds * pow(2.0, Double(exponent))
        return min(maximumErrorBackoffSeconds, seconds)
    }
}

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

    // Phase 3.4: Coalesce refresh calls to avoid overlapping EventKit fetches.
    private var inFlightRefresh: Task<WidgetWeaverRemindersDiagnostics, Never>?

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


    // MARK: - Completion (Phase 5)

    /// Marks a reminder as completed.
    ///
    /// Notes:
    /// - This requires Full Access because the widget reads reminder identifiers from snapshots.
    /// - This does not prompt for permission (AppIntents must not prompt).
    public func completeReminder(identifier: String) async -> WidgetWeaverRemindersActionDiagnostics {
        let cleanedID = identifier.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !cleanedID.isEmpty else {
            return WidgetWeaverRemindersActionDiagnostics(kind: .error, message: "Missing reminder ID.")
        }

        let status = Self.authorisationStatus()
        guard status == .fullAccess else {
            return WidgetWeaverRemindersActionDiagnostics(
                kind: .error,
                message: "Reminders Full Access is not granted (status=\(status)). Open WidgetWeaver → Reminders and request Full Access."
            )
        }

        guard let reminder = eventStore.calendarItem(withIdentifier: cleanedID) as? EKReminder else {
            return WidgetWeaverRemindersActionDiagnostics(
                kind: .error,
                message: "Reminder not found (or not readable). It may have been deleted, or the snapshot is stale."
            )
        }

        let rawTitle = (reminder.title ?? "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let title = rawTitle.isEmpty ? "Untitled" : rawTitle

        if reminder.isCompleted {
            return WidgetWeaverRemindersActionDiagnostics(kind: .noop, message: "Already completed: \(title).")
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            return WidgetWeaverRemindersActionDiagnostics(
                kind: .error,
                message: "Failed to complete reminder: \(error.localizedDescription)"
            )
        }

        return WidgetWeaverRemindersActionDiagnostics(kind: .completed, message: "Completed: \(title).")
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

        do {
            let (items, fetchedCount) = try await fetchGlobalIncompleteReminderItems(maxItems: maxItems)

            let duration = Date().timeIntervalSince(startedAt)
            let durationString = String(format: "%.2f", duration)

            let message: String = {
                if fetchedCount > items.count {
                    return "Fetched \(fetchedCount) reminder(s) (trimmed to \(items.count)) in \(durationString)s."
                }
                return "Fetched \(items.count) reminder(s) in \(durationString)s."
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
        maxItems: Int
    ) async throws -> (items: [WidgetWeaverReminderItem], fetchedCount: Int) {
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
                            isFlagged: Self.isFlaggedApproximation(priority: r.priority),
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
