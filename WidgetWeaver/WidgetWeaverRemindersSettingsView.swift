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
/// Phase 1A.1 (app-only spike):
/// - Show current EventKit authorisation state for reminders.
/// - Allow requesting full access.
/// - No reminder reads or writes yet.
///
/// Note: This screen remains gated behind `WidgetWeaverFeatureFlags.remindersTemplateEnabled`.
struct WidgetWeaverRemindersSettingsView: View {
    let onClose: (() -> Void)?

    @StateObject private var permissions = RemindersPermissionsModel()

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reminders Pack")
                        .font(.headline)

                    Text("Phase 1A.1: permission diagnostics only. No reminders are read or modified yet.")
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
                Label("Read spike (lists + sample reminders)", systemImage: "list.bullet")
                Label("Complete spike (tap row in-app)", systemImage: "checkmark.circle")
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
        if let errorDescription = lastRequest.errorDescription {
            return "Last request: granted=\(lastRequest.granted ? "true" : "false"), error=\(errorDescription)"
        }
        return "Last request: granted=\(lastRequest.granted ? "true" : "false")"
    }

    func requestFullAccess() {
        guard !isRequesting else { return }
        isRequesting = true
        lastRequest = nil

        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            Task { @MainActor in
                guard let self else { return }
                self.isRequesting = false
                self.refreshStatus()
                self.lastRequest = RequestResult(granted: granted, error: error)
            }
        }
    }

    struct RequestResult: Equatable {
        let granted: Bool
        let errorDescription: String?

        init(granted: Bool, error: Error?) {
            self.granted = granted
            self.errorDescription = error?.localizedDescription
        }
    }
}
