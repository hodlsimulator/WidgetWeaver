//
//  WidgetWeaverStepsSettingsView.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//

import SwiftUI
import WidgetKit
import UIKit

struct WidgetWeaverStepsSettingsView: View {
    var onClose: (() -> Void)? = nil

    @Environment(\.openURL) private var openURL

    @State private var isWorking: Bool = false
    @State private var statusText: String? = nil

    @State private var authStatus: WidgetWeaverStepsAuthorisationStatus = .notDetermined
    @State private var snapshot: WidgetWeaverStepsSnapshot? = WidgetWeaverStepsStore.shared.snapshotForToday()
    @State private var goalSteps: Int = WidgetWeaverStepsStore.shared.loadGoalSteps()

    private let store = WidgetWeaverStepsStore.shared
    private let engine = WidgetWeaverStepsEngine.shared

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Steps")
                            .font(.headline)

                        Spacer()

                        if let onClose {
                            Button("Done") { onClose() }
                                .font(.headline)
                        }
                    }

                    Text("Used by the Steps lock screen widget.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Access") {
                HStack {
                    Label(accessStatusTitle, systemImage: accessStatusSymbol)
                        .foregroundStyle(accessStatusTint)

                    Spacer()

                    Button("Refresh") {
                        Task { await refreshLocalState(showDebug: true) }
                    }
                    .disabled(isWorking)
                }

                if authStatus == .notDetermined {
                    Button {
                        Task { await requestAccess() }
                    } label: {
                        Label("Enable Steps Access", systemImage: "checkmark.shield")
                    }
                    .disabled(isWorking)
                }

                if authStatus == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                    }
                    .disabled(isWorking)
                }

                Text(accessStatusHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let statusText {
                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Goal") {
                Stepper(
                    "Daily goal: \(goalSteps.formatted(.number.grouping(.automatic)))",
                    value: $goalSteps,
                    in: 500...200_000,
                    step: 500
                )
                .onChange(of: goalSteps) { _, newValue in
                    store.saveGoalSteps(newValue)
                    reloadWidgets()
                }

                Text("The circular widget shows progress towards this goal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Today") {
                if let snap = snapshot {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(snap.stepsToday.formatted(.number.grouping(.automatic))) steps")
                            .font(.headline)

                        Text("Updated \(snap.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No cached steps yet.")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await updateNow(force: true) }
                } label: {
                    Label("Update now", systemImage: "arrow.clockwise")
                }
                .disabled(isWorking)

                Button(role: .destructive) {
                    store.clearSnapshot()
                    Task { await refreshLocalState(showDebug: false) }
                    reloadWidgets()
                } label: {
                    Label("Clear cached steps", systemImage: "trash")
                }
                .disabled(snapshot == nil)
            }
        }
        .navigationTitle("Steps")
        .overlay {
            if isWorking {
                ProgressView()
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .onAppear {
            Task { await refreshLocalState(showDebug: false) }
        }
    }

    private var accessStatusTitle: String {
        switch authStatus {
        case .authorised: return "Authorised"
        case .notDetermined: return "Not enabled"
        case .denied: return "Denied"
        case .unavailable: return "Unavailable"
        }
    }

    private var accessStatusSymbol: String {
        switch authStatus {
        case .authorised: return "checkmark.circle.fill"
        case .notDetermined: return "questionmark.circle"
        case .denied: return "xmark.octagon.fill"
        case .unavailable: return "exclamationmark.triangle.fill"
        }
    }

    private var accessStatusTint: Color {
        switch authStatus {
        case .authorised: return .green
        case .notDetermined: return .secondary
        case .denied: return .orange
        case .unavailable: return .secondary
        }
    }

    private var accessStatusHelpText: String {
        switch authStatus {
        case .authorised:
            return "Steps can be read from Health."
        case .notDetermined:
            return "Tap “Enable Steps Access” to grant read access to step count."
        case .denied:
            return "Enable Health access for WidgetWeaver in Settings."
        case .unavailable:
            return "Health data is not available on this device."
        }
    }

    private func refreshLocalState(showDebug: Bool) async {
        let probe = await engine.readAuthorisationProbe()
        let snap = store.snapshotForToday()
        let goal = store.loadGoalSteps()

        await MainActor.run {
            authStatus = probe.status
            snapshot = snap
            goalSteps = goal
            if showDebug {
                statusText = probe.debug
            } else if probe.status == .authorised {
                statusText = nil
            }
        }
    }

    private func reloadWidgets() {
        AppGroup.userDefaults.synchronize()
        Task { @MainActor in
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.lockScreenSteps)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func requestAccess() async {
        isWorking = true
        statusText = nil
        defer { isWorking = false }

        _ = await engine.requestReadAuthorisation()
        await refreshLocalState(showDebug: true)
    }

    private func updateNow(force: Bool) async {
        isWorking = true
        statusText = nil
        defer { isWorking = false }

        let result = await engine.updateIfNeeded(force: force)
        await refreshLocalState(showDebug: false)
        reloadWidgets()

        await MainActor.run {
            statusText = result.errorDescription ?? "Updated."
        }
    }
}
