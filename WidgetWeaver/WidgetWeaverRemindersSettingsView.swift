//
//  WidgetWeaverRemindersSettingsView.swift
//  WidgetWeaver
//
//  Created by . . on 1/14/26.
//

import EventKit
import SwiftUI
import UIKit

struct WidgetWeaverRemindersSettingsView: View {
    let onClose: (() -> Void)?

    @Environment(\.openURL) private var openURL

    @StateObject private var permissions = RemindersPermissionsModel()
    @StateObject private var listSelection = RemindersListSelectionModel()
    @StateObject private var readSpike = RemindersReadSpikeModel()
    @StateObject private var snapshotDebug = RemindersSnapshotDebugModel()

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Manage Reminders Pack access, list inclusion, and snapshot refresh. Widgets render cached snapshots only; row taps can complete reminders when Full Access is granted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Note: Snapshot generation and completion require Reminders Full Access (not write-only). Widgets still do not read EventKit directly.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Reminders access") {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(permissions.statusTitle)
                            .foregroundStyle(.secondary)
                    }

                    Text(permissions.statusHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        permissions.requestFullAccess()
                    } label: {
                        HStack {
                            Text("Request Full Access")
                            Spacer()
                            if permissions.isRequesting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(permissions.isRequesting)

                    if permissions.shouldOfferOpenSettings {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        } label: {
                            Label("Open Settings", systemImage: "gear")
                        }
                        .disabled(permissions.isRequesting)
                    }

                    if let summary = permissions.lastRequestSummary {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button("Refresh status") {
                        permissions.refreshStatus()
                    }
                }

                Section("Lists included in snapshots") {
                    Text("This list selection affects snapshot refresh for all Reminders Pack widgets. After changing it, refresh the snapshot below.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Text("Current selection")
                        Spacer()
                        Text(listSelection.selectionSummary)
                            .foregroundStyle(.secondary)
                    }

                    Toggle(isOn: Binding(
                        get: { listSelection.includeAllLists },
                        set: { listSelection.setIncludeAllLists($0) }
                    )) {
                        Text("Include all lists")
                    }

                    if !listSelection.includeAllLists {
                        Button {
                            listSelection.loadLists()
                        } label: {
                            HStack {
                                Text(listSelection.lists.isEmpty ? "Load lists" : "Reload lists")
                                Spacer()
                                if listSelection.isLoadingLists {
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(listSelection.isLoadingLists)

                        if let err = listSelection.lastError {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if listSelection.lists.isEmpty {
                            Text("No lists loaded yet.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(listSelection.lists) { list in
                                Toggle(isOn: Binding(
                                    get: { listSelection.selectedListIDs.contains(list.id) },
                                    set: { newValue in listSelection.setListIncluded(newValue, listID: list.id) }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(list.title)
                                        if let sourceTitle = list.sourceTitle {
                                            Text(sourceTitle)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }

                        if let message = listSelection.validationMessage {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Section("Read + complete spike (in-app only)") {
                    Text("Loads lists + Today items inside the app for feasibility. Widgets still render from snapshots only.")
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
                    .disabled(readSpike.isLoadingLists)

                    if let err = readSpike.loadListsError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !readSpike.lists.isEmpty {
                        ForEach(readSpike.lists.indices, id: \.self) { idx in
                            let list = readSpike.lists[idx]
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.title)
                                if let source = list.sourceTitle {
                                    Text(source)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Text(list.id)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    Divider()

                    Button {
                        readSpike.loadToday()
                    } label: {
                        HStack {
                            Text("Load Today (sample)")
                            Spacer()
                            if readSpike.isLoadingToday {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(readSpike.isLoadingToday)

                    if let err = readSpike.loadTodayError {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !readSpike.todayItems.isEmpty {
                        ForEach(readSpike.todayItems.indices, id: \.self) { idx in
                            let item = readSpike.todayItems[idx]
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                        Text(item.listTitle)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if item.isCompleted {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                if let due = item.dueDate {
                                    Text("Due: \(due.formatted(date: .abbreviated, time: item.dueHasTime ? .shortened : .omitted))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Due: —")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                if !item.isCompleted {
                                    Button {
                                        readSpike.complete(id: item.id)
                                    } label: {
                                        HStack {
                                            Text("Complete")
                                            Spacer()
                                            if readSpike.isCompletingID == item.id {
                                                ProgressView()
                                            }
                                        }
                                    }
                                    .disabled(readSpike.isCompletingID != nil)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                Section("Snapshot cache (App Group)") {
                    Text("This is what widgets actually render. Use this to validate widget content and WidgetKit caching behaviour.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let snapshot = snapshotDebug.snapshot {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Generated: \(snapshot.generatedAt.formatted(date: .abbreviated, time: .standard))")
                            Text("Items: \(snapshot.items.count)")
                            if let diag = snapshot.diagnostics {
                                Text("Diagnostics: \(diag.kind.rawValue) — \(diag.message)")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    } else {
                        Text("No snapshot cached yet.")
                            .foregroundStyle(.secondary)
                    }

                    if let lastUpdated = snapshotDebug.lastUpdatedAt {
                        Text("Last updated at: \(lastUpdated.formatted(date: .abbreviated, time: .standard))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let lastError = snapshotDebug.lastError {
                        Text("Last error: \(lastError.kind.rawValue) — \(lastError.message)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let lastAction = snapshotDebug.lastAction {
                        Text("Last action: \(lastAction.kind.rawValue) — \(lastAction.message)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Last action at: \(lastAction.at.formatted(date: .abbreviated, time: .standard))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if snapshotDebug.refreshLastAttemptAt != nil || snapshotDebug.refreshNextAllowedAt != nil || snapshotDebug.refreshConsecutiveFailureCount > 0 {
                        RemindersRefreshThrottleStatusView(
                            lastAttemptAt: snapshotDebug.refreshLastAttemptAt,
                            nextAllowedAt: snapshotDebug.refreshNextAllowedAt,
                            consecutiveFailures: snapshotDebug.refreshConsecutiveFailureCount
                        )
                    }

                    if snapshotDebug.lastAction != nil {
                        Button("Clear last action") {
                            snapshotDebug.clearLastAction()
                        }
                    }

                    Button {
                        snapshotDebug.refreshSnapshotFromRemindersEngine()
                    } label: {
                        HStack {
                            Text("Refresh snapshot now")
                            Spacer()
                            if snapshotDebug.isWriting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(snapshotDebug.isWriting)

                    Button {
                        snapshotDebug.refreshSnapshotFromRemindersEngine(force: true)
                    } label: {
                        HStack {
                            Text("Force refresh snapshot now")
                            Spacer()
                            if snapshotDebug.isWriting {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(snapshotDebug.isWriting)

                    Button("Clear refresh throttle/backoff") {
                        snapshotDebug.clearRefreshThrottleState()
                    }

                    Button(role: .destructive) {
                        snapshotDebug.clearSnapshot()
                    } label: {
                        Text("Clear snapshot")
                    }

                    #if DEBUG
                    Button(role: .destructive) {
                        snapshotDebug.writeDebugSampleSnapshot()
                    } label: {
                        Text("Write debug sample snapshot (DEBUG)")
                    }
                    #endif
                }

                Section {
                    if let onClose {
                        Button {
                            onClose()
                        } label: {
                            Text("Done")
                        }
                    }
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if let onClose {
                        Button("Done") {
                            onClose()
                        }
                    }
                }
            }
        }
        .onAppear {
            permissions.refreshStatus()
            listSelection.refreshFromStore()
            snapshotDebug.refreshFromStore()

            if permissions.status == .fullAccess {
                listSelection.loadLists()
            }
        }
        .onChange(of: permissions.status) { _, newStatus in
            if newStatus == .fullAccess {
                listSelection.loadLists()
            }
        }
    }
}

private struct RemindersRefreshThrottleStatusView: View {
    let lastAttemptAt: Date?
    let nextAllowedAt: Date?
    let consecutiveFailures: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Refresh throttling")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Last attempt: \(lastAttemptAt?.formatted(date: .abbreviated, time: .standard) ?? "—")")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                let now = context.date

                Group {
                    if let nextAllowedAt {
                        if nextAllowedAt <= now {
                            Text("Next allowed: now")
                        } else {
                            let remainingSeconds = Int(max(0, nextAllowedAt.timeIntervalSince(now)).rounded(.up))
                            Text("Next allowed: \(nextAllowedAt.formatted(date: .abbreviated, time: .standard)) (in \(remainingSeconds)s)")
                        }
                    } else {
                        Text("Next allowed: —")
                    }

                    Text("Consecutive failures: \(max(0, consecutiveFailures))")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Permissions model

@MainActor
private final class RemindersPermissionsModel: ObservableObject {
    @Published private(set) var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    @Published private(set) var isRequesting: Bool = false
    @Published private(set) var lastRequestSummary: String?

    var statusTitle: String {
        switch status {
        case .notDetermined: return "Not determined"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .writeOnly: return "Write-only"
        case .fullAccess: return "Full Access"
        @unknown default: return "Unknown"
        }
    }

    var statusHint: String {
        switch status {
        case .notDetermined:
            return "Tap “Request Full Access” to allow snapshot refresh and widget completion."
        case .denied:
            return "Access is denied. Enable Reminders Full Access in Settings to use the Reminders Pack."
        case .restricted:
            return "Access is restricted by device policy (e.g. Screen Time / MDM)."
        case .writeOnly:
            return "Write-only access cannot read reminders. Widgets need Full Access to render snapshots."
        case .fullAccess:
            return "Full Access granted. Snapshots can be refreshed and widgets can complete reminders."
        @unknown default:
            return "Unknown authorisation status."
        }
    }

    var shouldOfferOpenSettings: Bool {
        switch status {
        case .denied, .restricted, .writeOnly:
            return true
        default:
            return false
        }
    }

    func refreshStatus() {
        status = EKEventStore.authorizationStatus(for: .reminder)
    }

    func requestFullAccess() {
        guard !isRequesting else { return }
        isRequesting = true
        lastRequestSummary = nil

        Task { @MainActor in
            defer { self.isRequesting = false }

            let before = EKEventStore.authorizationStatus(for: .reminder)
            _ = await WidgetWeaverRemindersEngine.shared.requestAccessIfNeeded()
            let after = EKEventStore.authorizationStatus(for: .reminder)

            self.status = after

            self.lastRequestSummary = "Request finished (before=\(before), after=\(after))."
        }
    }
}

// MARK: - List selection model (Phase 6)

@MainActor
private final class RemindersListSelectionModel: ObservableObject {
    @Published private(set) var lists: [WidgetWeaverRemindersEngine.ReminderListSummary] = []
    @Published private(set) var selectedListIDs: Set<String> = []
    @Published private(set) var includeAllLists: Bool = true
    @Published private(set) var isLoadingLists: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var validationMessage: String?

    var selectionSummary: String {
        if includeAllLists { return "All lists" }
        let count = selectedListIDs.count
        return "\(count) selected"
    }

    func refreshFromStore() {
        let ids = WidgetWeaverRemindersStore.shared.loadSelectedListIDs()
        includeAllLists = ids.isEmpty
        selectedListIDs = Set(ids)
        lastError = nil
        validationMessage = nil
    }

    func setIncludeAllLists(_ includeAll: Bool) {
        validationMessage = nil
        lastError = nil

        if includeAll {
            includeAllLists = true
            selectedListIDs = []
            WidgetWeaverRemindersStore.shared.saveSelectedListIDs([])
            return
        }

        includeAllLists = false

        if lists.isEmpty {
            loadLists()
            return
        }

        if selectedListIDs.isEmpty {
            selectedListIDs = Set(lists.map { $0.id })
        }

        WidgetWeaverRemindersStore.shared.saveSelectedListIDs(Array(selectedListIDs))
    }

    func loadLists() {
        guard !isLoadingLists else { return }
        isLoadingLists = true
        lastError = nil

        Task { @MainActor in
            defer { self.isLoadingLists = false }

            do {
                let fetched = try await WidgetWeaverRemindersEngine.shared.fetchReminderLists()
                self.lists = fetched

                if !self.includeAllLists {
                    let known = Set(fetched.map { $0.id })
                    let pruned = self.selectedListIDs.intersection(known)
                    if pruned.isEmpty {
                        self.selectedListIDs = known
                    } else {
                        self.selectedListIDs = pruned
                    }

                    if !self.selectedListIDs.isEmpty {
                        WidgetWeaverRemindersStore.shared.saveSelectedListIDs(Array(self.selectedListIDs))
                    }
                }
            } catch {
                self.lastError = error.localizedDescription
            }
        }
    }

    func setListIncluded(_ included: Bool, listID: String) {
        guard !includeAllLists else { return }
        validationMessage = nil
        lastError = nil

        var next = selectedListIDs
        if included {
            next.insert(listID)
        } else {
            next.remove(listID)
            if next.isEmpty {
                validationMessage = "Select at least one list (or enable “Include all lists”)."
                next.insert(listID)
                selectedListIDs = next
                return
            }
        }

        selectedListIDs = next
        WidgetWeaverRemindersStore.shared.saveSelectedListIDs(Array(next))
    }
}

// MARK: - Read spike model (in-app)

@MainActor
private final class RemindersReadSpikeModel: ObservableObject {
    struct ListRow: Identifiable, Hashable {
        let id: String
        let title: String
        let sourceTitle: String?
    }

    @Published private(set) var isLoadingLists: Bool = false
    @Published private(set) var lists: [ListRow] = []
    @Published private(set) var loadListsError: String?

    @Published private(set) var isLoadingToday: Bool = false
    @Published private(set) var todayItems: [WidgetWeaverReminderItem] = []
    @Published private(set) var loadTodayError: String?

    @Published private(set) var isCompletingID: String?
    @Published private(set) var completeError: String?

    private let store = EKEventStore()

    private var canReadReminders: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .fullAccess
    }

    func loadLists() {
        guard !isLoadingLists else { return }
        isLoadingLists = true
        loadListsError = nil

        Task { @MainActor in
            defer { self.isLoadingLists = false }

            guard self.canReadReminders else {
                self.loadListsError = "Reminders Full Access not granted (status=\(EKEventStore.authorizationStatus(for: .reminder)))."
                self.lists = []
                return
            }

            let calendars = store.calendars(for: .reminder)

            self.lists = calendars.map { cal in
                let title = cal.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedTitle = title.isEmpty ? "Untitled" : title

                let sourceTitle: String? = {
                    let s = cal.source.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if s.isEmpty { return nil }
                    return s
                }()

                return ListRow(id: cal.calendarIdentifier, title: cleanedTitle, sourceTitle: sourceTitle)
            }
            .sorted { a, b in
                let sa = a.sourceTitle ?? ""
                let sb = b.sourceTitle ?? ""
                if sa != sb { return sa.localizedCaseInsensitiveCompare(sb) == .orderedAscending }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
    }

    func loadToday() {
        guard !isLoadingToday else { return }
        isLoadingToday = true
        loadTodayError = nil

        Task { @MainActor in
            defer { self.isLoadingToday = false }

            guard self.canReadReminders else {
                self.loadTodayError = "Reminders Full Access not granted (status=\(EKEventStore.authorizationStatus(for: .reminder)))."
                self.todayItems = []
                return
            }

            do {
                let items = try await WidgetWeaverRemindersEngine.shared.fetchTodayIncompleteReminders(limit: 25)
                self.todayItems = items
            } catch {
                self.loadTodayError = error.localizedDescription
                self.todayItems = []
            }
        }
    }

    func complete(id: String) {
        guard isCompletingID == nil else { return }
        isCompletingID = id
        completeError = nil

        Task { @MainActor in
            defer { self.isCompletingID = nil }

            let action = await WidgetWeaverRemindersEngine.shared.completeReminder(identifier: id)

            if action.kind == .completed {
                // Refresh local list for display.
                self.loadToday()
            } else if action.kind == .error {
                self.completeError = action.message
            }
        }
    }
}

// MARK: - Snapshot debug model

@MainActor
private final class RemindersSnapshotDebugModel: ObservableObject {
    @Published private(set) var snapshot: WidgetWeaverRemindersSnapshot?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastError: WidgetWeaverRemindersDiagnostics?
    @Published private(set) var lastAction: WidgetWeaverRemindersActionDiagnostics?

    @Published private(set) var refreshLastAttemptAt: Date?
    @Published private(set) var refreshNextAllowedAt: Date?
    @Published private(set) var refreshConsecutiveFailureCount: Int = 0

    @Published private(set) var isWriting: Bool = false

    private let store = WidgetWeaverRemindersStore.shared

    func refreshFromStore() {
        snapshot = store.loadSnapshot()
        lastUpdatedAt = store.loadLastUpdatedAt()
        lastError = store.loadLastError()
        lastAction = store.loadLastAction()

        refreshLastAttemptAt = store.loadRefreshLastAttemptAt()
        refreshNextAllowedAt = store.loadRefreshNextAllowedAt()
        refreshConsecutiveFailureCount = store.loadRefreshConsecutiveFailureCount()
    }

    func refreshSnapshotFromRemindersEngine(maxItems: Int = 250, force: Bool = false) {
        guard !isWriting else { return }
        isWriting = true

        Task { @MainActor in
            defer { self.isWriting = false }

            _ = await WidgetWeaverRemindersEngine.shared.refreshSnapshotCache(maxItems: maxItems, force: force)
            self.refreshFromStore()
        }
    }

    func clearRefreshThrottleState() {
        store.clearRefreshThrottleState()
        refreshFromStore()
    }

    func clearLastAction() {
        store.clearLastAction()
        refreshFromStore()
    }

    func clearSnapshot() {
        store.clearSnapshot()
        store.clearRefreshThrottleState()
        store.saveLastUpdatedAt(nil)
        store.saveLastError(nil)
        refreshFromStore()
    }

    #if DEBUG
    func writeDebugSampleSnapshot() {
        let sample = WidgetWeaverRemindersSnapshot.sample()
        store.saveSnapshot(sample)
        refreshFromStore()
    }
    #endif
}
