//
//  WidgetWeaverRemindersSettingsView.swift
//  WidgetWeaver
//
//  Created by . . on 1/14/26.
//

import EventKit
import SwiftUI

/// Reminders settings screen for the Reminders Pack.
///
/// Phase 1A (app-only spikes):
/// - 1A.1: Permission diagnostics (authorisation state + request full access).
/// - 1A.2: Read spike (list names + a small sample of incomplete reminders for Today).
/// - 1A.3: Complete spike (tap a Today sample row to complete the reminder).
///
/// Note: This screen remains gated behind `WidgetWeaverFeatureFlags.remindersTemplateEnabled`.
struct WidgetWeaverRemindersSettingsView: View {
    let onClose: (() -> Void)?

    @StateObject private var permissions = RemindersPermissionsModel()
    @StateObject private var readSpike = RemindersReadSpikeModel()

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reminders Pack")
                        .font(.headline)

                    Text("Phase 1A.3: in-app complete spike (lists + Today sample + tap to complete). Widgets still render placeholders and do not read or modify reminders yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Reminders access") {
                HStack {
                    Text("Authorisation")
                    Spacer()
                    Text(permissions.statusTitle)
                        .foregroundStyle(.secondary)
                }

                if let hint = permissions.statusHint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    permissions.requestFullAccess()
                } label: {
                    HStack {
                        Text("Request full access")
                        Spacer()
                        if permissions.isRequesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(permissions.isRequesting)

                if let summary = permissions.lastRequestSummary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("Refresh status") {
                    permissions.refreshStatus()
                }
                .disabled(permissions.isRequesting)
            }

            Section("Read + complete spike (in-app only)") {
                Text("Loads reminder lists and a small set of incomplete reminders due Today. Tap a Today row to mark it complete (in-app only).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    readSpike.loadLists()
                } label: {
                    HStack {
                        Text("Load lists")
                        Spacer()
                        if readSpike.isLoadingLists {
                            ProgressView()
                        }
                    }
                }
                .disabled(readSpike.isBusy)

                Button {
                    readSpike.loadTodaySample()
                } label: {
                    HStack {
                        Text("Load Today sample")
                        Spacer()
                        if readSpike.isLoadingReminders {
                            ProgressView()
                        }
                    }
                }
                .disabled(readSpike.isBusy)

                if let lastUpdated = readSpike.lastUpdatedAt {
                    Text("Last updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let summary = readSpike.lastCompletionSummary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let err = readSpike.lastError {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if readSpike.lists.isEmpty {
                    Text("Lists: none loaded")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Lists: \(readSpike.lists.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(readSpike.lists) { list in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(list.title)
                            if let sourceTitle = list.sourceTitle {
                                Text(sourceTitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if readSpike.todaySample.isEmpty {
                    Text("Today sample: none loaded")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Today sample: \(readSpike.todaySample.count)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text("Tap a row to mark it complete.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ForEach(readSpike.todaySample) { r in
                        Button {
                            readSpike.completeTodaySampleReminder(reminderID: r.id)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.title)
                                        .lineLimit(2)

                                    HStack(spacing: 8) {
                                        Text(r.listTitle)
                                        if let dueText = r.dueText {
                                            Text("•")
                                            Text(dueText)
                                        }
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                if readSpike.completingReminderID == r.id {
                                    ProgressView()
                                }
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                        .disabled(readSpike.isBusy)
                    }
                }
            }

            Section("Feature flag") {
                HStack {
                    Text("Reminders template enabled")
                    Spacer()
                    Text(WidgetWeaverFeatureFlags.remindersTemplateEnabled ? "On" : "Off")
                        .foregroundStyle(.secondary)
                }

                Text("This screen is reachable from the toolbar only when the flag is enabled.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Next") {
                Label("Complete spike (tap row in-app)", systemImage: "checkmark.circle.fill")
                Label("Widget interactivity spike (AppIntent)", systemImage: "hand.tap")
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onClose() }
                }
            }
        }
        .onAppear {
            permissions.refreshStatus()
        }
    }
}

@MainActor
private final class RemindersPermissionsModel: ObservableObject {
    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    @Published private(set) var isRequesting: Bool = false
    @Published private(set) var lastRequest: RequestResult?

    private let eventStore = EKEventStore()

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .reminder)
    }

    var statusTitle: String {
        switch status {
        case .notDetermined:
            return "Not determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .fullAccess:
            return "Full access"
        case .writeOnly:
            return "Write-only"
        @unknown default:
            return "Unknown"
        }
    }

    var statusHint: String? {
        switch status {
        case .notDetermined:
            return "Requesting access should trigger the system permission prompt."
        case .restricted:
            return "Access is restricted by device policy (Screen Time or MDM)."
        case .denied:
            return "Access has been denied. Grant access in Settings if needed."
        case .writeOnly:
            return "Write-only access can create/modify reminders, but may not be able to read them."
        default:
            return nil
        }
    }

    var lastRequestSummary: String? {
        guard let lastRequest else { return nil }
        let grantedText = lastRequest.granted ? "true" : "false"
        if let errorDescription = lastRequest.errorDescription {
            return "Last request: granted=\(grantedText), error=\(errorDescription)"
        }
        return "Last request: granted=\(grantedText)"
    }

    func requestFullAccess() {
        guard !isRequesting else { return }
        isRequesting = true
        lastRequest = nil

        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            let errorDescription = error?.localizedDescription
            Task { @MainActor in
                guard let self else { return }
                self.isRequesting = false
                self.refreshStatus()
                self.lastRequest = RequestResult(granted: granted, errorDescription: errorDescription)
            }
        }
    }

    struct RequestResult: Equatable, Sendable {
        let granted: Bool
        let errorDescription: String?
    }
}

@MainActor
private final class RemindersReadSpikeModel: ObservableObject {
    struct ReminderListRow: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let sourceTitle: String?
    }

    struct ReminderRow: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let listTitle: String
        let dueDate: Date?
        let dueHasTime: Bool

        var dueText: String? {
            guard let dueDate else { return nil }
            if dueHasTime {
                return dueDate.formatted(date: .abbreviated, time: .shortened)
            }
            return dueDate.formatted(date: .abbreviated, time: .omitted)
        }
    }

    @Published private(set) var lists: [ReminderListRow] = []
    @Published private(set) var todaySample: [ReminderRow] = []

    @Published private(set) var isLoadingLists: Bool = false
    @Published private(set) var isLoadingReminders: Bool = false
    @Published private(set) var isCompletingReminder: Bool = false
    @Published private(set) var completingReminderID: String?

    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var lastCompletionSummary: String?

    private let eventStore = EKEventStore()

    var isBusy: Bool { isLoadingLists || isLoadingReminders || isCompletingReminder }

    func loadLists() {
        guard !isBusy else { return }
        lastError = nil
        isLoadingLists = true
        defer { isLoadingLists = false }

        guard canReadReminders() else {
            lists = []
            lastError = "Cannot read reminders (authorisation is not Full Access)."
            return
        }

        let calendars = eventStore.calendars(for: .reminder)
            .sorted { a, b in
                a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }

        lists = calendars.map { cal in
            ReminderListRow(
                id: cal.calendarIdentifier,
                title: cal.title.isEmpty ? "Untitled" : cal.title,
                sourceTitle: cal.source.title
            )
        }

        lastUpdatedAt = Date()
    }

    func loadTodaySample() {
        guard !isBusy else { return }
        lastError = nil
        lastCompletionSummary = nil
        isLoadingReminders = true

        Task { @MainActor in
            defer { isLoadingReminders = false }

            await refreshTodaySampleInternal()
        }
    }

    func completeTodaySampleReminder(reminderID: String) {
        guard !isBusy else { return }
        lastError = nil
        lastCompletionSummary = nil
        isCompletingReminder = true
        completingReminderID = reminderID

        Task { @MainActor in
            defer {
                self.isCompletingReminder = false
                self.completingReminderID = nil
            }

            guard canWriteReminders() else {
                lastError = "Cannot complete reminders (authorisation is not Full Access or Write-only)."
                return
            }

            guard let reminder = eventStore.calendarItem(withIdentifier: reminderID) as? EKReminder else {
                lastError = "Reminder not found (it may have been deleted)."
                return
            }

            let rawTitle = (reminder.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let safeTitle = rawTitle.isEmpty ? "Untitled" : rawTitle

            reminder.isCompleted = true
            reminder.completionDate = Date()

            do {
                try eventStore.save(reminder, commit: true)
            } catch {
                lastError = "Failed to complete reminder: \(error.localizedDescription)"
                return
            }

            if canReadReminders() {
                isLoadingReminders = true
                defer { isLoadingReminders = false }
                await refreshTodaySampleInternal()
            } else {
                todaySample.removeAll { $0.id == reminderID }
            }

            lastCompletionSummary = "Completed “\(safeTitle)”."
        }
    }

    private func canReadReminders() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .fullAccess
    }

    private func canWriteReminders() -> Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .fullAccess || status == .writeOnly
    }

    private func refreshTodaySampleInternal() async {
        guard canReadReminders() else {
            todaySample = []
            lastError = "Cannot read reminders (authorisation is not Full Access)."
            return
        }

        let now = Date()
        let cal = Calendar.current
        let start = cal.startOfDay(for: now)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else {
            todaySample = []
            lastError = "Failed to compute Today window."
            return
        }

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: start,
            ending: end,
            calendars: calendars
        )

        let mapped = await fetchReminderRows(matching: predicate, calendar: cal)

        todaySample = mapped
            .sorted { a, b in
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
            .prefix(25)
            .map { $0 }

        lastUpdatedAt = Date()
    }

    /// Converts EventKit reminders into Sendable rows inside the EventKit callback,
    /// so no `EKReminder` values cross an `await` boundary.
    private func fetchReminderRows(matching predicate: NSPredicate, calendar: Calendar) async -> [ReminderRow] {
        await withCheckedContinuation { cont in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let rows: [ReminderRow] = (reminders ?? []).map { r in
                    let title = (r.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let safeTitle = title.isEmpty ? "Untitled" : title

                    let dueComponents = r.dueDateComponents
                    let dueDate = dueComponents.flatMap { calendar.date(from: $0) }
                    let hasTime = (dueComponents?.hour != nil) || (dueComponents?.minute != nil) || (dueComponents?.second != nil)

                    return ReminderRow(
                        id: r.calendarItemIdentifier,
                        title: safeTitle,
                        listTitle: r.calendar.title.isEmpty ? "Untitled" : r.calendar.title,
                        dueDate: dueDate,
                        dueHasTime: hasTime
                    )
                }

                cont.resume(returning: rows)
            }
        }
    }
}
