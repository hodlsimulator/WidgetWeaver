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

@MainActor
struct WidgetWeaverAboutView: View {
    @ObservedObject var proManager: WidgetWeaverProManager

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    @ObservedObject private var thumbnailDeps = WidgetPreviewThumbnailDependencies.shared

    /// Adds a template into the design library.
    /// The caller owns ID/UUID creation and any persistence details.
    var onAddTemplate: @MainActor @Sendable (_ spec: WidgetSpec, _ makeDefault: Bool) -> Void

    var onShowPro: @MainActor @Sendable () -> Void
    var onShowWidgetHelp: @MainActor @Sendable () -> Void
    var onOpenWeatherSettings: @MainActor @Sendable () -> Void
    var onOpenStepsSettings: @MainActor @Sendable () -> Void
    var onGoToLibrary: @MainActor @Sendable () -> Void

    @State private var isListScrolling = false
    @State var statusMessage: String = ""

    var body: some View {
        ZStack {
            WidgetWeaverAboutBackground()

            List {
                aboutHeaderSection

                featuredWeatherSection
                featuredClockSection
                featuredCalendarSection
                featuredStepsSection

                starterTemplatesSection
                proTemplatesSection

                capabilitiesSection
                interactiveButtonsSection

                noiseMachineSection

                variablesSection
                aiSection
                privacySection

                sharingSection
                proSection
                diagnosticsSection

                supportSection
            }
            .listStyle(.plain)
            .environment(\.wwThumbnailRenderingEnabled, !isListScrolling)
            .task(id: preheatTaskID) {
                await preheatExploreThumbnailsIfNeeded()
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .scrollClipDisabled()
            .listSectionSeparator(.hidden)
            .onScrollPhaseChange { _, newPhase in
                isListScrolling = newPhase.isScrolling
            }
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
    }

    private var preheatTaskID: String {
        let scheme = (colorScheme == .dark) ? "dark" : "light"
        return "\(scheme)|\(thumbnailDeps.variablesFingerprint)|\(thumbnailDeps.weatherFingerprint)"
    }

    private func preheatExploreThumbnailsIfNeeded() async {
        guard #available(iOS 16.0, *) else { return }

        let specs = (Self.starterTemplatesAll + Self.proTemplates).map { $0.spec }
        await WidgetPreviewThumbnail.preheat(
            specs: specs,
            colorScheme: colorScheme,
            displayScale: displayScale
        )
    }

    // MARK: - Helpers

    var appVersionString: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    func copyToPasteboard(_ string: String) {
        UIPasteboard.general.string = string
        withAnimation(.spring(duration: 0.35)) {
            statusMessage = "Copied"
        }

        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.spring(duration: 0.35)) {
                    if statusMessage == "Copied" { statusMessage = "" }
                }
            }
        }
    }

    func handleAdd(template: WidgetWeaverAboutTemplate, makeDefault: Bool) {
        onAddTemplate(template.spec, makeDefault)
        withAnimation(.spring(duration: 0.35)) {
            statusMessage = makeDefault ? "Added & set as default" : "Added"
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            await MainActor.run {
                withAnimation(.spring(duration: 0.35)) {
                    if statusMessage == "Added" || statusMessage == "Added & set as default" {
                        statusMessage = ""
                    }
                }
            }
        }
    }

    func presentCalendarPermissionFlow() {
        let store = EKEventStore()
        store.requestFullAccessToEvents { granted, error in
            DispatchQueue.main.async {
                if granted {
                    withAnimation(.spring(duration: 0.35)) {
                        statusMessage = "Calendar access granted"
                    }
                } else if let error {
                    withAnimation(.spring(duration: 0.35)) {
                        statusMessage = "Calendar access denied: \(error.localizedDescription)"
                    }
                } else {
                    withAnimation(.spring(duration: 0.35)) {
                        statusMessage = "Calendar access denied"
                    }
                }

                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    DispatchQueue.main.async {
                        withAnimation(.spring(duration: 0.35)) {
                            statusMessage = ""
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sharing

    var sharingSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Sharing")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(.secondary)
                    }

                    Text("Export widget designs as images or JSON so they can be shared or versioned.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    WidgetWeaverAboutBulletList(items: [
                        "Export images for previews and social posts.",
                        "Export JSON for backups and version control.",
                        "Import JSON to restore or move designs across devices."
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Sharing", systemImage: "square.and.arrow.up", accent: .orange)
        }
    }

    // MARK: - Pro

    var proSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .cyan) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Pro")
                            .font(.headline)
                        Spacer()
                        Text(proManager.isProUnlocked ? "Unlocked" : "Locked")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(proManager.isProUnlocked ? .green : .secondary)
                    }

                    Text("Unlock the full template set and advanced widget features.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    WidgetWeaverAboutBulletList(items: [
                        "Full template catalogue",
                        "More styling controls",
                        "More widget types"
                    ])

                    if !proManager.isProUnlocked {
                        Button {
                            onShowPro()
                        } label: {
                            Label("View Pro", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Pro", systemImage: "sparkles", accent: .cyan)
        }
    }

    // MARK: - Diagnostics

    @State private var designCount: Int? = nil

    @State private var clockLogPreview: String = ""
    @State private var clockLogLineCount: Int = 0
    @State private var clockLastTimelineBuild: Date? = nil

    @State private var clockLogEnabled: Bool = false

    @State private var photoLogPreview: String = ""
    @State private var photoLogLineCount: Int = 0
    @State private var photoLogEnabled: Bool = false

    var diagnosticsSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .gray) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Diagnostics")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundStyle(.secondary)
                    }

                    Text("Basic app metadata and shareable debug logs for clock + photos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Enable clock log", isOn: Binding(
                            get: { clockLogEnabled },
                            set: { newValue in
                                clockLogEnabled = newValue
                                WWClockDebugLog.setEnabled(newValue)
                                refreshClockDiagnostics()
                            }
                        ))

                        Toggle("Enable photo log", isOn: Binding(
                            get: { photoLogEnabled },
                            set: { newValue in
                                photoLogEnabled = newValue
                                WWPhotoDebugLog.setEnabled(newValue)
                                refreshPhotoDiagnostics()
                            }
                        ))
                    }
                    .font(.subheadline)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("App")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(appVersionString)
                                .monospacedDigit()
                        }

                        HStack {
                            Text("Designs")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(designCount.map(String.init) ?? "—")
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)

                    HStack(spacing: 10) {
                        Button {
                            copyToPasteboard(appVersionString)
                        } label: {
                            Label("Copy version", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            WidgetWeaverWidgetRefresh.forceKickIncludingClock()
                            withAnimation(.spring(duration: 0.35)) {
                                statusMessage = "Requested widget refresh"
                            }

                            Task {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                await MainActor.run {
                                    withAnimation(.spring(duration: 0.35)) {
                                        if statusMessage == "Requested widget refresh" { statusMessage = "" }
                                    }
                                }
                            }
                        } label: {
                            Label("Refresh widgets", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Clock timeline build")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let d = clockLastTimelineBuild {
                                Text(d, format: .dateTime.year().month().day().hour().minute().second())
                                    .monospacedDigit()
                            } else {
                                Text("—")
                                    .monospacedDigit()
                            }
                        }

                        HStack {
                            Text("Clock log lines")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(clockLogLineCount)")
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)

                    HStack(spacing: 10) {
                        Button {
                            refreshClockDiagnostics()
                        } label: {
                            Label("Reload clock log", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            let text = WWClockDebugLog.readText(maxLines: 240)
                            copyToPasteboard(text.isEmpty ? "Clock debug log is empty." : text)
                        } label: {
                            Label("Copy clock log", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        WWClockDebugLog.clear()
                        refreshClockDiagnostics()
                        withAnimation(.spring(duration: 0.35)) {
                            statusMessage = "Cleared clock log"
                        }

                        Task {
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            await MainActor.run {
                                withAnimation(.spring(duration: 0.35)) {
                                    if statusMessage == "Cleared clock log" { statusMessage = "" }
                                }
                            }
                        }
                    } label: {
                        Label("Clear clock log", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if !clockLogPreview.isEmpty {
                        ScrollView {
                            Text(clockLogPreview)
                                .font(.caption2.monospacedDigit())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 180)
                    } else {
                        Text("No clock log entries yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Photo log lines")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(photoLogLineCount)")
                                .monospacedDigit()
                        }
                    }
                    .font(.subheadline)

                    HStack(spacing: 10) {
                        Button {
                            refreshPhotoDiagnostics()
                        } label: {
                            Label("Reload photo log", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            let text = WWPhotoDebugLog.readText(maxLines: 240)
                            copyToPasteboard(text.isEmpty ? "Photo debug log is empty." : text)
                        } label: {
                            Label("Copy photo log", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(role: .destructive) {
                        WWPhotoDebugLog.clear()
                        refreshPhotoDiagnostics()
                        withAnimation(.spring(duration: 0.35)) {
                            statusMessage = "Cleared photo log"
                        }

                        Task {
                            try? await Task.sleep(nanoseconds: 900_000_000)
                            await MainActor.run {
                                withAnimation(.spring(duration: 0.35)) {
                                    if statusMessage == "Cleared photo log" { statusMessage = "" }
                                }
                            }
                        }
                    } label: {
                        Label("Clear photo log", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    if !photoLogPreview.isEmpty {
                        ScrollView {
                            Text(photoLogPreview)
                                .font(.caption2.monospacedDigit())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .frame(maxHeight: 180)
                    } else {
                        Text("No photo log entries yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .task {
                    if designCount == nil {
                        let count = WidgetSpecStore.shared.loadAll().count
                        await MainActor.run { designCount = count }
                    }
                    refreshClockDiagnostics()
                    refreshPhotoDiagnostics()
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Diagnostics", systemImage: "wrench.and.screwdriver", accent: .gray)
        }
    }

    private func refreshClockDiagnostics() {
        let defaults = AppGroup.userDefaults
        clockLastTimelineBuild = defaults.object(forKey: "widgetweaver.clock.timelineBuild.last") as? Date

        clockLogEnabled = WWClockDebugLog.isEnabled()

        let lines = WWClockDebugLog.readLines()
        clockLogLineCount = lines.count
        clockLogPreview = lines.suffix(40).joined(separator: "\n")
    }

    private func refreshPhotoDiagnostics() {
        photoLogEnabled = WWPhotoDebugLog.isEnabled()

        let lines = WWPhotoDebugLog.readLines()
        photoLogLineCount = lines.count
        photoLogPreview = lines.suffix(40).joined(separator: "\n")
    }
}
