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
    /// The caller owns ID/UUID creation and any persistence details.
    var onAddTemplate: (_ spec: WidgetSpec, _ makeDefault: Bool) -> Void

    var onShowPro: () -> Void
    var onShowWidgetHelp: () -> Void
    var onOpenWeatherSettings: () -> Void
    var onOpenStepsSettings: () -> Void
    var onGoToLibrary: () -> Void

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
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .scrollClipDisabled()
            .listSectionSeparator(.hidden)
            .onScrollPhaseChange { _, newPhase in
                isListScrolling = !newPhase.isIdle
            }
        }
        .navigationTitle("Explore")
        .navigationBarTitleDisplayMode(.large)
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

    func handleAdd(template: WidgetSpec, makeDefault: Bool) {
        onAddTemplate(template, makeDefault)
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
                    await MainActor.run {
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

                    Text("Basic app metadata and counts to help debug.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Divider()

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

                    Button {
                        copyToPasteboard(appVersionString)
                    } label: {
                        Label("Copy version", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .task {
                    if designCount == nil {
                        let count = (try? WidgetDesignStore().readAll().count) ?? 0
                        await MainActor.run { designCount = count }
                    }
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Diagnostics", systemImage: "wrench.and.screwdriver", accent: .gray)
        }
    }
}
