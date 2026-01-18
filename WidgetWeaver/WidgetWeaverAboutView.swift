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
    var onShowRemindersSmartStackGuide: @MainActor @Sendable () -> Void

    @State private var isListScrolling = false
    @State var statusMessage: String = ""

    var body: some View {
        ZStack {
            WidgetWeaverAboutBackground()

            List {
                aboutHeaderSection

                featuredPhotosSection
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

    func handleAddRemindersSmartStackKit() {
        let kitSpecs: [WidgetSpec] = [
            Self.specRemindersToday(),
            Self.specRemindersOverdue(),
            Self.specRemindersSoon(),
            Self.specRemindersPriority(),
            Self.specRemindersFocus(),
            Self.specRemindersLists(),
        ]

        let store = WidgetSpecStore.shared
        let existingNames = Set(store.loadAll().map(\.name))

        var alreadyCount = 0
        var addedCount = 0

        for spec in kitSpecs {
            if existingNames.contains(spec.name) {
                alreadyCount += 1
                continue
            }

            let beforeCount = store.loadAll().count
            onAddTemplate(spec, false)
            let afterCount = store.loadAll().count

            if afterCount > beforeCount {
                addedCount += 1
            } else {
                break
            }
        }

        let total = kitSpecs.count
        let missingCount = total - alreadyCount
        let remainingMissing = max(0, missingCount - addedCount)

        let message: String = {
            if alreadyCount == total {
                return "All 6 already in Library."
            }

            if remainingMissing == 0 {
                if alreadyCount == 0 { return "Added all 6." }
                if addedCount == 0 { return "No changes." }
                return "Added \(addedCount). \(alreadyCount) already in Library."
            }

            if addedCount == 0 {
                if alreadyCount == 0 { return "Unable to add (design limit)." }
                return "\(alreadyCount) already in Library. Unlock Pro for the rest."
            }

            return "Added \(addedCount) of \(missingCount) missing. Unlock Pro for the rest."
        }()

        withAnimation(.spring(duration: 0.35)) {
            statusMessage = message
        }

        Task {
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            await MainActor.run {
                withAnimation(.spring(duration: 0.35)) {
                    if statusMessage == message { statusMessage = "" }
                }
            }
        }

        if addedCount > 0 || alreadyCount > 0 {
            onGoToLibrary()
            onShowRemindersSmartStackGuide()
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
}
