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
    let onAddTemplate: @MainActor (WidgetSpec, Bool) -> Void

    /// Shows the Pro paywall.
    let onShowPro: @MainActor () -> Void

    /// Shows Widget help.
    let onShowWidgetHelp: @MainActor () -> Void

    /// Opens Weather settings (sheet owned by ContentView).
    let onOpenWeatherSettings: @MainActor () -> Void

    /// Opens Steps settings (sheet owned by ContentView).
    let onOpenStepsSettings: @MainActor () -> Void

    /// Switches the selection to the Library tab.
    let onGoToLibrary: @MainActor () -> Void

    @State var designCount: Int = 0
    @State var statusMessage: String = ""

    @State private var isListScrolling: Bool = false
    @State private var clockDebugOverlayEnabled: Bool = false
    @State private var clockWidgetLastRenderAt: Date? = nil
    @State private var clockWidgetLastRenderInfo: String = ""
    @State private var clockFontOK: Bool? = nil

    @State private var showCalendarAccessExplainer: Bool = false
    @State private var showCalendarDeniedAlert: Bool = false
    @State private var calendarAccessInFlight: Bool = false
    @State private var calendarPromptSourceTitle: String = "Calendar"

    @Environment(\.wwThumbnailRenderingEnabled) private var globalThumbnailRenderingEnabled
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            WidgetWeaverAboutBackground()

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
                                Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    isListScrolling = false
                                }
                            }
                    )
            }
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
        .overlay(alignment: .top) {
            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("Calendar access needed", isPresented: $showCalendarAccessExplainer) {
            Button("Continue") { requestCalendarAccess() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("WidgetWeaver can show upcoming events. Access is optional and can be changed later in Settings.")
        }
        .alert("Calendar access denied", isPresented: $showCalendarDeniedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Calendar access was denied. Enable it later in Settings → Privacy & Security → Calendars.")
        }
        .onAppear { refreshDesignCount() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshDesignCount()
            }
        }
    }

    var list: some View {
        List {
            headerSection
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
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .environment(\.wwThumbnailRenderingEnabled, globalThumbnailRenderingEnabled && !isListScrolling)
    }

    // MARK: - Header

    var headerSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WidgetWeaver")
                        .font(.title2.weight(.semibold))

                    Text("Build and customise WidgetKit widgets from a growing template catalogue, then save them into your library.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            onGoToLibrary()
                        } label: {
                            Label("Open Library", systemImage: "books.vertical")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onShowWidgetHelp()
                        } label: {
                            Label("Widget Help", systemImage: "questionmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .wwAboutListRow()
        }
    }

    // MARK: - Featured templates

    var featuredWeatherSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .cyan) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Weather")
                        .font(.headline)

                    Text("Rain timeline with uncertainty and intensity, designed for quick decisions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        onOpenWeatherSettings()
                    } label: {
                        Label("Add / Configure Weather", systemImage: "cloud.rain")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Featured", systemImage: "sparkles", accent: .cyan)
        }
    }

    var featuredClockSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .indigo) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Clock")
                        .font(.headline)

                    Text("A mechanical face with a ticking seconds hand.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        statusMessage = "Add the Clock widget from the Home Screen widget picker."
                    } label: {
                        Label("How to add Clock", systemImage: "clock")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .wwAboutListRow()
        }
    }

    var featuredCalendarSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Calendar")
                        .font(.headline)

                    Text("Upcoming events in a compact widget layout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        calendarPromptSourceTitle = "Calendar"
                        showCalendarAccessExplainer = true
                    } label: {
                        Label("Enable Calendar access", systemImage: "calendar")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(calendarAccessInFlight)
                }
            }
            .wwAboutListRow()
        }
    }

    var featuredStepsSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Steps")
                        .font(.headline)

                    Text("Simple health progress and streak-focused layouts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        onOpenStepsSettings()
                    } label: {
                        Label("Add / Configure Steps", systemImage: "figure.walk")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .wwAboutListRow()
        }
    }

    // MARK: - Templates

    var starterTemplatesSection: some View {
        Section {
            ForEach(WidgetWeaverAboutTemplates.starter) { template in
                WidgetWeaverAboutTemplateRow(template: template) { makeDefault in
                    onAddTemplate(template.spec, makeDefault)
                    refreshDesignCount()
                    statusMessage = makeDefault ? "Added & set as default." : "Added."
                }
                .wwAboutListRow()
            }
        } header: {
            WidgetWeaverAboutSectionHeader("Starter templates", systemImage: "square.grid.2x2", accent: .blue)
        }
    }

    var proTemplatesSection: some View {
        Section {
            ForEach(WidgetWeaverAboutTemplates.pro) { template in
                WidgetWeaverAboutTemplateRow(template: template) { makeDefault in
                    onAddTemplate(template.spec, makeDefault)
                    refreshDesignCount()
                    statusMessage = makeDefault ? "Added & set as default." : "Added."
                }
                .wwAboutListRow()
            }
        } header: {
            WidgetWeaverAboutSectionHeader("Pro templates", systemImage: "sparkles", accent: .cyan)
        } footer: {
            Text("Pro templates can be previewed but require Pro to keep in your library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Capabilities

    var capabilitiesSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Capabilities")
                        .font(.headline)

                    Text("Widgets are fully offline and render from your saved designs via an App Group.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Widget previews in the editor.",
                        "Library + search + duplication.",
                        "Theme extraction from images.",
                        "Import / export designs."
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("What’s inside", systemImage: "wand.and.stars", accent: .purple)
        }
    }

    var interactiveButtonsSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Interactive buttons")
                        .font(.headline)

                    Text("Some widgets support Action Bars with tappable buttons.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Buttons are configured per design.",
                        "Actions can launch the app or run intents.",
                        "Pro unlocks more options."
                    ])
                }
            }
            .wwAboutListRow()
        }
    }

    // MARK: - Variables

    var variablesSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .teal) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Variables")
                        .font(.headline)

                    Text("Reusable values that can be injected into designs.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Templates can reference variables.",
                        "Variables can be edited in the app.",
                        "More automation is planned."
                    ])
                }
            }
            .wwAboutListRow()
        }
    }

    // MARK: - AI

    var aiSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .yellow) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("On-device AI")
                        .font(.headline)

                    Text("Optional generation and patch edits when available.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "AI is optional.",
                        "Specs remain editable.",
                        "Nothing is uploaded by default."
                    ])
                }
            }
            .wwAboutListRow()
        }
    }

    // MARK: - Privacy

    var privacySection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .gray) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacy")
                        .font(.headline)

                    Text("No accounts. Widgets render offline.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Designs are stored locally.",
                        "Weather uses device location only when enabled.",
                        "Calendar access is optional."
                    ])
                }
            }
            .wwAboutListRow()
        }
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
            WidgetWeaverAboutCard(accent: .cyan) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pro")
                        .font(.headline)

                    Text("Unlock more templates and advanced styling.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Button {
                        onShowPro()
                    } label: {
                        Label("View Pro", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .wwAboutListRow()
        } footer: {
            Text("Purchases are handled by the App Store.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    var appVersionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
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

    private enum ClockWidgetDebugKeys {
        static let overlayEnabled = "widgetweaver.clock.debug.overlay.enabled"
        static let lastRenderTS = "widgetweaver.clock.widget.render.last.ts"
        static let lastRenderInfo = "widgetweaver.clock.widget.render.info"
        static let fontOK = "widgetweaver.clock.font.ok"
    }

    @MainActor
    private func refreshClockWidgetDiagnostics() {
        let defaults = AppGroup.userDefaults
        clockDebugOverlayEnabled = defaults.bool(forKey: ClockWidgetDebugKeys.overlayEnabled)

        let ts = defaults.double(forKey: ClockWidgetDebugKeys.lastRenderTS)
        clockWidgetLastRenderAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        clockWidgetLastRenderInfo = defaults.string(forKey: ClockWidgetDebugKeys.lastRenderInfo) ?? ""

        if defaults.object(forKey: ClockWidgetDebugKeys.fontOK) != nil {
            clockFontOK = defaults.bool(forKey: ClockWidgetDebugKeys.fontOK)
        } else {
            clockFontOK = nil
        }
    }

    private func clockWidgetDiagnosticsString() -> String {
        var out: [String] = []
        out.append("WidgetWeaver \(appVersionString)")
        out.append("Clock debug overlay: \(clockDebugOverlayEnabled ? "ON" : "OFF")")

        if let d = clockWidgetLastRenderAt {
            out.append("Clock widget last render: \(d.formatted(date: .numeric, time: .standard))")
        } else {
            out.append("Clock widget last render: —")
        }

        out.append("Clock widget last info: \(clockWidgetLastRenderInfo.isEmpty ? "—" : clockWidgetLastRenderInfo)")

        if let ok = clockFontOK {
            out.append("Clock font OK: \(ok ? "YES" : "NO")")
        } else {
            out.append("Clock font OK: —")
        }

        return out.joined(separator: "\n")
    }

    @MainActor
    private func setClockDebugOverlayEnabled(_ enabled: Bool) {
        let defaults = AppGroup.userDefaults
        defaults.set(enabled, forKey: ClockWidgetDebugKeys.overlayEnabled)
        defaults.synchronize()
        WidgetWeaverWidgetRefresh.forceKickIncludingClock()
    }

    // MARK: - Calendar

    private func requestCalendarAccess() {
        if calendarAccessInFlight {
            return
        }

        calendarAccessInFlight = true

        Task {
            let granted = await WidgetWeaverCalendarEngine.shared.requestAccess()
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

    // MARK: - Diagnostics

    var diagnosticsSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .gray) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Useful for debugging widget refresh + configuration.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    let clockLast = clockWidgetLastRenderAt.map { $0.formatted(date: .numeric, time: .standard) } ?? "—"
                    let clockFont = clockFontOK.map { $0 ? "OK" : "MISSING" } ?? "—"

                    WidgetWeaverAboutBulletList(items: [
                        "Design count: \(designCount)",
                        "Pro: \(proManager.isProUnlocked ? "Unlocked" : "Locked")",
                        "Clock debug overlay: \(clockDebugOverlayEnabled ? "On" : "Off")",
                        "Clock font: \(clockFont)",
                        "Clock last render: \(clockLast)"
                    ])

                    Divider()

                    Toggle(isOn: Binding(
                        get: { clockDebugOverlayEnabled },
                        set: { newValue in
                            clockDebugOverlayEnabled = newValue
                            setClockDebugOverlayEnabled(newValue)
                            refreshClockWidgetDiagnostics()
                        }
                    )) {
                        Text("Clock widget debug overlay")
                    }

                    HStack(spacing: 10) {
                        Button {
                            refreshClockWidgetDiagnostics()
                            copyToPasteboard(clockWidgetDiagnosticsString())
                        } label: {
                            Label("Copy clock diagnostics", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            refreshClockWidgetDiagnostics()
                            statusMessage = "Refreshed clock diagnostics."
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    if !clockWidgetLastRenderInfo.isEmpty {
                        Text(clockWidgetLastRenderInfo)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
            }
            .onAppear { refreshClockWidgetDiagnostics() }
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
