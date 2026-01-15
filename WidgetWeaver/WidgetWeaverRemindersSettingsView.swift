//
//  WidgetWeaverRemindersSettingsView.swift
//  WidgetWeaver
//
//  Created by . . on 1/14/26.
//

import SwiftUI

/// Placeholder settings screen for the Reminders integration.
///
/// Phase 0 guardrails:
/// - No EventKit usage.
/// - Remains gated behind `WidgetWeaverFeatureFlags.remindersTemplateEnabled`.
struct WidgetWeaverRemindersSettingsView: View {
    let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reminders Pack")
                        .font(.headline)

                    Text("Phase 0 placeholder. Reminders permission is not requested yet and no EventKit calls are made.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
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

            Section("Planned") {
                Label("Permission state + diagnostics", systemImage: "hand.raised.fill")
                Label("List selection + per-mode defaults", systemImage: "list.bullet")
                Label("Snapshot cache for widget rendering", systemImage: "tray.full")
                Label("Tap-to-complete via AppIntent", systemImage: "checkmark.circle")
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
    }
}
