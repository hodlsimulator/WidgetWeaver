//
//  RemindersPackControls.swift
//  WidgetWeaver
//
//  Created by . . on 1/23/26.
//

import SwiftUI
import EventKit

struct RemindersPackControls: View {
    @Binding var config: WidgetWeaverRemindersConfig
    let onOpenRemindersSettings: () -> Void

    @State private var lists: [WidgetWeaverRemindersEngine.ReminderListSummary] = []
    @State private var isLoadingLists: Bool = false
    @State private var lastError: String?

    @State private var enableFilteringAfterLoad: Bool = false

    private var permissionStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .reminder)
    }

    private var permissionTitle: String {
        switch permissionStatus {
        case .notDetermined: return "Not requested"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Authorised"
        case .fullAccess: return "Full Access"
        case .writeOnly: return "Write Only"
        @unknown default: return "Unknown"
        }
    }

    private var listSummary: String {
        if config.selectedListIDs.isEmpty { return "All lists" }
        return "\(config.selectedListIDs.count) selected"
    }

    private var soonWindowOptions: [Int] {
        [
            60 * 6,
            60 * 12,
            60 * 24,
            60 * 24 * 3,
            60 * 24 * 7,
            60 * 24 * 14,
            60 * 24 * 31,
        ]
    }

    private func soonWindowTitle(minutes: Int) -> String {
        let clamped = max(15, minutes)
        let days = clamped / (60 * 24)
        let hours = (clamped % (60 * 24)) / 60
        if days > 0 {
            if hours == 0 { return "\(days)d" }
            return "\(days)d \(hours)h"
        }
        return "\(max(1, hours))h"
    }

    private func loadLists() {
        guard !isLoadingLists else { return }
        isLoadingLists = true
        lastError = nil

        Task { @MainActor in
            defer { self.isLoadingLists = false }

            do {
                let fetched = try await WidgetWeaverRemindersEngine.shared.fetchReminderLists()
                self.lists = fetched

                if self.enableFilteringAfterLoad {
                    self.enableFilteringAfterLoad = false
                    self.config.selectedListIDs = fetched.map { $0.id }
                }

                // If filtering is enabled, keep IDs aligned with currently-known lists.
                if !self.config.selectedListIDs.isEmpty {
                    let known = Set(fetched.map { $0.id })
                    let current = Set(self.config.selectedListIDs)
                    let pruned = current.intersection(known)

                    if pruned.isEmpty {
                        // Fallback to all known lists rather than silently switching to “All lists” (empty means all).
                        self.config.selectedListIDs = fetched.map { $0.id }
                    } else {
                        // Preserve stable ordering from the fetched lists.
                        self.config.selectedListIDs = fetched.map { $0.id }.filter { pruned.contains($0) }
                    }
                }

            } catch {
                self.enableFilteringAfterLoad = false
                self.lastError = error.localizedDescription
            }
        }
    }

    private func enableListFiltering() {
        lastError = nil

        if lists.isEmpty {
            enableFilteringAfterLoad = true
            loadLists()
            return
        }

        config.selectedListIDs = lists.map { $0.id }
    }

    private func disableListFiltering() {
        lastError = nil
        config.selectedListIDs = []
    }

    private func setListIncluded(_ included: Bool, listID: String) {
        var next = Set(config.selectedListIDs)

        if included {
            next.insert(listID)
        } else {
            next.remove(listID)

            if next.isEmpty {
                // Keep at least one list selected when filtering is enabled.
                next.insert(listID)
                lastError = "Select at least one list, or disable list filtering to show all lists."
            }
        }

        if lists.isEmpty {
            config.selectedListIDs = Array(next)
        } else {
            config.selectedListIDs = lists.map { $0.id }.filter { next.contains($0) }
        }
    }

    var body: some View {
        Group {
            HStack {
                Text("Reminders access")
                Spacer()
                Text(permissionTitle)
                    .foregroundStyle(.secondary)
            }

            Button {
                onOpenRemindersSettings()
            } label: {
                Label("Open Reminders settings", systemImage: "gear")
            }

            Divider()

            Picker("Mode", selection: Binding(
                get: { config.mode },
                set: { newValue in config.mode = newValue; config = config.normalised() }
            )) {
                ForEach(WidgetWeaverRemindersMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            Picker("Presentation", selection: Binding(
                get: { config.presentation },
                set: { newValue in config.presentation = newValue; config = config.normalised() }
            )) {
                ForEach(WidgetWeaverRemindersPresentation.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }

            Toggle("Hide completed", isOn: Binding(
                get: { config.hideCompleted },
                set: { newValue in config.hideCompleted = newValue; config = config.normalised() }
            ))

            Toggle("Show due times", isOn: Binding(
                get: { config.showDueTimes },
                set: { newValue in config.showDueTimes = newValue; config = config.normalised() }
            ))

            Toggle("Show progress badge", isOn: Binding(
                get: { config.showProgressBadge },
                set: { newValue in config.showProgressBadge = newValue; config = config.normalised() }
            ))

            if config.mode == .today {
                Toggle("Include start dates in Today", isOn: Binding(
                    get: { config.includeStartDatesInToday },
                    set: { newValue in config.includeStartDatesInToday = newValue; config = config.normalised() }
                ))
            }

            if config.mode == .soon {
                Picker("Soon window", selection: Binding(
                    get: { config.soonWindowMinutes },
                    set: { newValue in config.soonWindowMinutes = newValue; config = config.normalised() }
                )) {
                    ForEach(soonWindowOptions, id: \.self) { minutes in
                        Text(soonWindowTitle(minutes: minutes)).tag(minutes)
                    }
                }
            }

            Divider()

            Button {
                loadLists()
            } label: {
                Label(isLoadingLists ? "Loading lists…" : "Refresh lists", systemImage: "arrow.clockwise")
            }
            .disabled(isLoadingLists)

            Toggle("Enable list filtering", isOn: Binding(
                get: { !config.selectedListIDs.isEmpty },
                set: { enabled in
                    if enabled { enableListFiltering() }
                    else { disableListFiltering() }
                    config = config.normalised()
                }
            ))

            if !config.selectedListIDs.isEmpty {
                HStack {
                    Text("Lists")
                    Spacer()
                    Text(listSummary)
                        .foregroundStyle(.secondary)
                }

                if lists.isEmpty {
                    Text("No lists loaded yet.\nTap Refresh lists.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(lists, id: \.id) { list in
                        Toggle(list.title, isOn: Binding(
                            get: { config.selectedListIDs.contains(list.id) },
                            set: { included in
                                setListIncluded(included, listID: list.id)
                                config = config.normalised()
                            }
                        ))
                    }
                }
            }

            if let lastError, !lastError.isEmpty {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
