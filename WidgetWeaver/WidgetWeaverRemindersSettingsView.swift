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
    @StateObject private var snapshotDebug = RemindersSnapshotDebugModel()

    #if DEBUG
    @AppStorage(WidgetWeaverRemindersDebugStore.Keys.testReminderID, store: AppGroup.userDefaults)
    private var widgetTestReminderID: String = ""
    #endif

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

                    #if DEBUG
                    Text("Long-press a row to set it as the widget test reminder ID (for the Reminders Spike widget).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    #endif

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

                        #if DEBUG
                        .contextMenu {
                            Button {
                                WidgetWeaverRemindersDebugStore.setTestReminderID(r.id)
                            } label: {
                                Label("Use as widget test ID", systemImage: "widget.small")
                            }

                            if !widgetTestReminderID.isEmpty {
                                Button(role: .destructive) {
                                    WidgetWeaverRemindersDebugStore.setTestReminderID(nil)
                                } label: {
                                    Label("Clear widget test ID", systemImage: "xmark.circle")
                                }
                            }
                        }
                        #endif
                    }
                }
            }



            Section("Snapshot cache (debug)") {
                Text("Writes a temporary snapshot into the App Group so widgets and previews can render Reminders content without any EventKit reads in the widget.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    snapshotDebug.writeSnapshotFromTodaySample(readSpike.todaySample)
                } label: {
                    HStack {
                        Text("Write snapshot now")
                        Spacer()
                        if snapshotDebug.isWriting {
                            ProgressView()
                        }
                    }
                }
                .disabled(snapshotDebug.isWriting)

                Button(role: .destructive) {
                    snapshotDebug.clearSnapshot()
                } label: {
                    Text("Clear snapshot")
                }

                if let snapshot = snapshotDebug.snapshot {
                    Text("Snapshot: \(snapshot.items.count) item(s) • generated \(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let diag = snapshot.diagnostics {
                        Text("Diagnostics (\(diag.kind.rawValue)) \(diag.at.formatted(date: .abbreviated, time: .shortened)): \(diag.message)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Snapshot: none")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let lastUpdated = snapshotDebug.lastUpdatedAt {
                    Text("Last updated \(lastUpdated.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let err = snapshotDebug.lastError {
                    Text("Last error (\(err.kind.rawValue)) \(err.at.formatted(date: .abbreviated, time: .shortened)): \(err.message)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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

            #if DEBUG
            Section("Widget interactivity spike (debug)") {
                HStack {
                    Text("Widget test reminder")
                    Spacer()
                    Text(widgetTestReminderID.isEmpty ? "Not set" : shortIDForUI(widgetTestReminderID))
                        .foregroundStyle(.secondary)
                }

                Text("The “Reminders Spike” widget reads this ID from the App Group and runs an AppIntent to complete it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Clear widget test ID") {
                    WidgetWeaverRemindersDebugStore.setTestReminderID(nil)
                }
                .disabled(widgetTestReminderID.isEmpty)
            }
            #endif
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
            snapshotDebug.refreshFromStore()
        }
    }

    #if DEBUG
    private func shortIDForUI(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return trimmed }
        let start = trimmed.prefix(4)
        let end = trimmed.suffix(4)
        return "\(start)…\(end)"
    }
    #endif
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
    nonisolated struct ReminderListRow: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let sourceTitle: String?
    }

    nonisolated struct ReminderRow: Identifiable, Hashable, Sendable {
        let id: String
        let title: String
        let listID: String
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

        lastError = nil

        let mapped: [ReminderRow] = await Task.detached(priority: .userInitiated) {
            let store = EKEventStore()
            store.reset()

            let now = Date()
            let cal = Calendar.current
            let todayYMD = cal.dateComponents([.year, .month, .day], from: now)

            func matchesToday(_ comps: DateComponents?) -> Bool {
                guard let comps else { return false }
                return comps.year == todayYMD.year
                    && comps.month == todayYMD.month
                    && comps.day == todayYMD.day
            }

            func componentsHaveTime(_ comps: DateComponents?) -> Bool {
                guard let comps else { return false }
                return comps.hour != nil || comps.minute != nil || comps.second != nil
            }

            let calendars = store.calendars(for: .reminder)

            // Broad fetch, then filter locally by YYYY-MM-DD to match what users perceive as "Today".
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: calendars
            )

            return await withCheckedContinuation { cont in
                store.fetchReminders(matching: predicate) { reminders in
                    let rows: [ReminderRow] = (reminders ?? []).compactMap { r in
                        // Include "today" if either due date OR start date lands on today.
                        let dueComps = r.dueDateComponents
                        let startComps = r.startDateComponents

                        let useDue = matchesToday(dueComps)
                        let useStart = matchesToday(startComps)

                        guard useDue || useStart else { return nil }

                        let chosenComps = useDue ? dueComps : startComps
                        let chosenDate = chosenComps.flatMap { cal.date(from: $0) }
                        let chosenHasTime = componentsHaveTime(chosenComps)

                        let title = (r.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let safeTitle = title.isEmpty ? "Untitled" : title

                        return ReminderRow(
                            id: r.calendarItemIdentifier,
                            title: safeTitle,
                            listID: r.calendar.calendarIdentifier,
                            listTitle: r.calendar.title.isEmpty ? "Untitled" : r.calendar.title,
                            dueDate: chosenDate,
                            dueHasTime: chosenHasTime
                        )
                    }

                    cont.resume(returning: rows)
                }
            }
        }.value

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
    
    private nonisolated static func fetchReminderRowsDueToday(
        eventStore: EKEventStore,
        matching predicate: NSPredicate,
        calendar: Calendar,
        todayYMD: DateComponents
    ) async -> [ReminderRow] {
        await withCheckedContinuation { cont in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let rows: [ReminderRow] = (reminders ?? []).compactMap { r in
                    guard let dueComponents = r.dueDateComponents else { return nil }
                    guard
                        dueComponents.year == todayYMD.year,
                        dueComponents.month == todayYMD.month,
                        dueComponents.day == todayYMD.day
                    else { return nil }

                    let title = (r.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let safeTitle = title.isEmpty ? "Untitled" : title

                    let dueDate = calendar.date(from: dueComponents)
                    let hasTime = (dueComponents.hour != nil) || (dueComponents.minute != nil) || (dueComponents.second != nil)

                    return ReminderRow(
                        id: r.calendarItemIdentifier,
                        title: safeTitle,
                        listID: r.calendar.calendarIdentifier,
                        listTitle: r.calendar.title.isEmpty ? "Untitled" : r.calendar.title,
                        dueDate: dueDate,
                        dueHasTime: hasTime
                    )
                }

                cont.resume(returning: rows)
            }
        }
    }

    /// Converts EventKit reminders into Sendable rows inside the EventKit callback,
    /// so no `EKReminder` values cross an `await` boundary.
    private nonisolated static func fetchReminderRows(
        eventStore: EKEventStore,
        matching predicate: NSPredicate,
        calendar: Calendar
    ) async -> [ReminderRow] {
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
                        listID: r.calendar.calendarIdentifier,
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

@MainActor
private final class RemindersSnapshotDebugModel: ObservableObject {
    @Published private(set) var snapshot: WidgetWeaverRemindersSnapshot?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastError: WidgetWeaverRemindersDiagnostics?

    @Published private(set) var isWriting: Bool = false

    private let store = WidgetWeaverRemindersStore.shared

    func refreshFromStore() {
        snapshot = store.loadSnapshot()
        lastUpdatedAt = store.loadLastUpdatedAt()
        lastError = store.loadLastError()
    }

    func writeSnapshotFromTodaySample(_ sample: [RemindersReadSpikeModel.ReminderRow]) {
        guard !isWriting else { return }
        isWriting = true
        defer { isWriting = false }

        let now = Date()

        let items: [WidgetWeaverReminderItem]
        if sample.isEmpty {
            items = WidgetWeaverRemindersSnapshot.sample(now: now).items
        } else {
            items = sample.map { r in
                WidgetWeaverReminderItem(
                    id: r.id,
                    title: r.title,
                    dueDate: r.dueDate,
                    dueHasTime: r.dueHasTime,
                    startDate: nil,
                    startHasTime: false,
                    isCompleted: false,
                    isFlagged: false,
                    listID: r.listID,
                    listTitle: r.listTitle
                )
            }
        }

        let snapshot = WidgetWeaverRemindersSnapshot(
            generatedAt: now,
            items: items,
            modes: [],
            diagnostics: WidgetWeaverRemindersDiagnostics(
                kind: .ok,
                message: sample.isEmpty
                    ? "Debug snapshot (built-in sample)"
                    : "Debug snapshot (Today sample, \(items.count) item(s))",
                at: now
            )
        )

        store.saveSnapshot(snapshot)
        refreshFromStore()
    }

    func clearSnapshot() {
        store.clearSnapshot()
        store.saveLastUpdatedAt(nil)
        store.clearLastError()
        refreshFromStore()
    }
}
