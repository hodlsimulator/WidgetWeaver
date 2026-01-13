//
//  PawPulseSettingsView.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import SwiftUI

@MainActor
struct PawPulseSettingsView: View {
    @AppStorage(PawPulseSettingsStore.Keys.baseURLString, store: AppGroup.userDefaults)
    private var baseURLString: String = ""

    @AppStorage(PawPulseSettingsStore.Keys.displayName, store: AppGroup.userDefaults)
    private var displayName: String = ""

    @State private var statusMessage: String = ""
    @State private var isWorking: Bool = false

    var body: some View {
        Form {
            Section("Feed") {
                TextField("Base URL (e.g. https://example.com)", text: $baseURLString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextField("Display name (optional)", text: $displayName)
                    .textInputAutocapitalization(.words)

                Text("Tip: the widget only reads cache. The app populates cache from /api/latest + /media/latest.jpg.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Actions") {
                Button {
                    PawPulseCache.ensureDirectoryExists()
                    PawPulseBackgroundTasks.scheduleNextEarliest(minutesFromNow: 30)
                    statusMessage = "Saved. Background refresh scheduled."
                } label: {
                    Text("Save & schedule refresh")
                }

                Button {
                    Task { await testFetch(force: true) }
                } label: {
                    if isWorking {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Fetching…")
                        }
                    } else {
                        Text("Test fetch now")
                    }
                }
                .disabled(isWorking)

                Button(role: .destructive) {
                    PawPulseCache.clearCache()
                    statusMessage = "Cache cleared."
                } label: {
                    Text("Clear PawPulse cache")
                }
            }

            Section("Cache") {
                let item = PawPulseCache.loadLatestItem()

                HStack {
                    Text("Has JSON")
                    Spacer()
                    Text(item == nil ? "No" : "Yes")
                        .foregroundStyle(.secondary)
                }

                if let item {
                    if let postID = item.postID, !postID.isEmpty {
                        LabeledContent("post_id") {
                            Text(postID)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    if let created = item.createdDate {
                        LabeledContent("created_time") {
                            Text(created.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        }
                    } else if let raw = item.createdTime, !raw.isEmpty {
                        LabeledContent("created_time") {
                            Text(raw)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }

                    if let permalink = item.permalinkURL, !permalink.isEmpty {
                        LabeledContent("permalink_url") {
                            Text(permalink)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("PawPulse Settings")
    }

    private func testFetch(force: Bool) async {
        isWorking = true
        defer { isWorking = false }

        let result = await PawPulseEngine.shared.updateIfNeeded(force: force)
        statusMessage = result.statusMessage
    }
}
