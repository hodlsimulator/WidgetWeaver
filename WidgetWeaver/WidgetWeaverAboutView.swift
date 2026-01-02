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

    /// Opens Weather settings (sheet owned by ContentView).
    let onOpenWeatherSettings: @MainActor () -> Void

    /// Opens Steps settings (sheet owned by ContentView).
    let onOpenStepsSettings: @MainActor () -> Void

    /// Jumps to Library tab.
    let onGoToLibrary: @MainActor () -> Void

    @State var designCount: Int = 0
    @State var statusMessage: String = ""

    @State private var isListScrolling: Bool = false

    @State private var showCalendarAccessExplainer: Bool = false
    @State private var showCalendarDeniedAlert: Bool = false
    @State private var calendarAccessInFlight: Bool = false
    @State private var calendarPromptSourceTitle: String = "Calendar"

    var body: some View {
        ZStack {
            WidgetWeaverAboutBackground()

            aboutList
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .tint(WidgetWeaverAboutTheme.pageTint)
        .onAppear { refreshDesignCount() }
        .alert("Enable Calendar access?", isPresented: $showCalendarAccessExplainer) {
            Button("Not now", role: .cancel) { }
            Button(calendarAccessInFlight ? "Requesting…" : "Continue") { requestCalendarAccess() }
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

    @ViewBuilder
    private var aboutList: some View {
        let list = List {
            aboutHeaderSection

            featuredWeatherSection
            featuredClockSection
            featuredCalendarSection
            featuredStepsSection

            starterTemplatesSection
            proTemplatesSection

            capabilitiesSection
            interactiveButtonsSection
            variablesSection
            aiSection
            privacySection

            sharingSection
            proSection
            diagnosticsSection
            supportSection
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
        .listSectionSeparator(.hidden)
        .environment(\.wwThumbnailRenderingEnabled, !isListScrolling)

        if #available(iOS 17.0, *) {
            list
                .onScrollPhaseChange { _, newPhase in
                    isListScrolling = newPhase.isScrolling
                }
        } else {
            list
                .simultaneousGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            isListScrolling = true
                        }
                        .onEnded { _ in
                            // In iOS 16 and earlier, this is a best-effort signal.
                            // Rendering is re-enabled after a small delay to avoid
                            // doing heavy work during deceleration.
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                isListScrolling = false
                            }
                        }
                )
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
            Task { _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: true) }
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

    // MARK: - Sharing

    var sharingSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .mint) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Share a design as a small package (JSON + image).\nOthers can import it into their library.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Share from the editor: Share → Package.",
                        "Import by opening the package in WidgetWeaver.",
                        "Packages do not include personal data."
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Sharing", systemImage: "square.and.arrow.up", accent: .mint)
        } footer: {
            Text("Packages contain only the widget spec and preview image.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pro

    var proSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .yellow) {
                VStack(alignment: .leading, spacing: 12) {
                    if proManager.isProUnlocked {
                        Label("Pro is unlocked on this device.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.secondary)

                        WidgetWeaverAboutBulletList(items: [
                            "Matched Sets",
                            "Variables + Shortcuts",
                            "Interactive buttons (iOS 17+)",
                            "More saved designs",
                            "Remix + AI features"
                        ])
                    } else {
                        Text("Pro unlocks advanced features for power users.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        WidgetWeaverAboutBulletList(items: [
                            "Matched Sets (Small/Medium/Large overrides)",
                            "Variables store + Shortcuts",
                            "Interactive buttons (iOS 17+)",
                            "More saved designs"
                        ])

                        Button { onShowPro() } label: {
                            Label("Upgrade to Pro", systemImage: "crown.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Pro", systemImage: "crown.fill", accent: .yellow)
        } footer: {
            Text("Purchases are handled by the App Store.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Diagnostics

    var diagnosticsSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .gray) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Useful for debugging widget refresh + configuration.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Design count: \(designCount)",
                        "Pro: \(proManager.isProUnlocked ? "Unlocked" : "Locked")",
                        "Widgets reload when you Save a design."
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Diagnostics", systemImage: "stethoscope", accent: .gray)
        } footer: {
            Text("If widgets don’t update: open the app, Save the design again, and wait a moment for WidgetKit refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
