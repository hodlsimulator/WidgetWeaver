//
//  WidgetWeaverAboutView.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit
import EventKit

struct WidgetWeaverAboutView: View {
    @ObservedObject var proManager: WidgetWeaverProManager

    /// Adds a template into the design library.
    /// The caller owns ID/timestamp handling, selection updates, and widget refresh messaging.
    let onAddTemplate: @MainActor (_ spec: WidgetSpec, _ makeDefault: Bool) -> Void

    /// Switches the sheet to Pro UI.
    let onShowPro: @MainActor () -> Void

    /// Switches the sheet to widget help UI.
    let onShowWidgetHelp: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss

    @State var designCount: Int = 0
    @State var statusMessage: String = ""
    @State var showWeatherSettings: Bool = false

    @State private var showCalendarAccessExplainer: Bool = false
    @State private var showCalendarDeniedAlert: Bool = false
    @State private var calendarAccessInFlight: Bool = false
    @State private var calendarPromptSourceTitle: String = "Calendar"

    var body: some View {
        NavigationStack {
            ZStack {
                WidgetWeaverAboutBackground()

                List {
                    aboutHeaderSection
                    featuredWeatherSection
                    featuredCalendarSection
                    capabilitiesSection
                    starterTemplatesSection
                    proTemplatesSection
                    interactiveButtonsSection
                    variablesSection
                    aiSection
                    sharingSection
                    proSection
                    diagnosticsSection
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
                .listSectionSeparator(.hidden)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .tint(WidgetWeaverAboutTheme.pageTint)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear {
                refreshDesignCount()
            }
            .navigationDestination(isPresented: $showWeatherSettings) {
                WidgetWeaverWeatherSettingsView()
            }
            .alert("Enable Calendar access?", isPresented: $showCalendarAccessExplainer) {
                Button("Not now", role: .cancel) { }

                Button(calendarAccessInFlight ? "Requesting…" : "Continue") {
                    requestCalendarAccess()
                }
                .disabled(calendarAccessInFlight)
            } message: {
                Text("“\(calendarPromptSourceTitle)” uses Calendar access to show your upcoming events in the widget.\nEvents stay on-device.")
            }
            .alert("Calendar access is off", isPresented: $showCalendarDeniedAlert) {
                Button("OK", role: .cancel) { }
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("Enable Calendar access in Settings to show upcoming events in the Calendar template.")
            }
        }
    }

    // MARK: - Template add handler

    @MainActor
    func handleAdd(template: WidgetWeaverAboutTemplate, makeDefault: Bool) {
        if template.requiresPro && !proManager.isProUnlocked {
            statusMessage = "“\(template.title)” requires Pro."
            onShowPro()
            return
        }

        onAddTemplate(template.spec, makeDefault)

        statusMessage = makeDefault ? "Added “\(template.title)” and set as default." : "Added “\(template.title)”."
        refreshDesignCount()

        if template.triggersCalendarPermission {
            calendarPromptSourceTitle = template.title
            presentCalendarPermissionFlow()
        }
    }

    // MARK: - Calendar permission flow (after selecting template)

    private enum CalendarPermissionState {
        case granted
        case notDetermined
        case denied
    }

    private func calendarPermissionState() -> CalendarPermissionState {
        let status = EKEventStore.authorizationStatus(for: .event)

        if #available(iOS 17.0, *) {
            if status == .fullAccess { return .granted }
            if status == .notDetermined { return .notDetermined }
            return .denied
        } else {
            if status == .authorized { return .granted }
            if status == .notDetermined { return .notDetermined }
            return .denied
        }
    }

    @MainActor
    func presentCalendarPermissionFlow() {
        switch calendarPermissionState() {
        case .granted:
            Task {
                _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: true)
            }

        case .notDetermined:
            showCalendarAccessExplainer = true

        case .denied:
            showCalendarDeniedAlert = true
        }
    }

    @MainActor
    private func requestCalendarAccess() {
        guard !calendarAccessInFlight else { return }
        calendarAccessInFlight = true

        Task {
            let granted = await WidgetWeaverCalendarEngine.shared.requestAccessIfNeeded()

            if granted {
                _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: true)
                await MainActor.run {
                    statusMessage = "Calendar access enabled."
                    calendarAccessInFlight = false
                }
            } else {
                await MainActor.run {
                    calendarAccessInFlight = false
                    showCalendarDeniedAlert = true
                }
            }
        }
    }

    // MARK: - Helpers used across modular files

    var appVersionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    @MainActor
    func refreshDesignCount() {
        designCount = WidgetSpecStore.shared.loadAll().count
    }

    func copyToPasteboard(_ string: String) {
        UIPasteboard.general.string = string
        statusMessage = "Copied to clipboard."
    }
}
