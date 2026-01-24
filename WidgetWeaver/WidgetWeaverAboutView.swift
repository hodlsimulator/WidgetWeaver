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
    enum Mode {
        case explore
        case more
    }

    var mode: Mode = .explore

    @ObservedObject var proManager: WidgetWeaverProManager

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
    @State private var isPreheatingThumbnails: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    private var navTitle: String {
        switch mode {
        case .explore:
            return "Explore"
        case .more:
            return "More"
        }
    }

    var body: some View {
        ZStack {
            WidgetWeaverAboutBackground()

            List {
                aboutHeaderSection

                featuredPhotosSection
                featuredWeatherSection
                featuredClockTemplatesSection
                featuredCalendarSection
                featuredStepsSection

                remindersSmartStackSection

                noiseMachineSection

                starterTemplatesSection
                proTemplatesSection

                if mode == .more {
                    capabilitiesSection
                    interactiveButtonsSection

                    variablesSection
                    aiSection
                    privacySection
                }

                supportSection

                if mode == .explore {
                    exploreMoreSection
                }
            }
            .listStyle(.plain)
            .environment(\.wwThumbnailRenderingEnabled, !isListScrolling && !isPreheatingThumbnails)
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .scrollClipDisabled()
            .listSectionSeparator(.hidden)
            .onScrollPhaseChange { _, newPhase in
                isListScrolling = newPhase.isScrolling
            }
            .task(id: thumbnailPreheatTaskID) {
                await preheatExploreThumbnails()
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(mode == .explore ? .large : .inline)
    }

    private var thumbnailPreheatTaskID: String {
        let modeKey: String = {
            switch mode {
            case .explore:
                return "explore"
            case .more:
                return "more"
            }
        }()

        let schemeKey = (colorScheme == .dark) ? "dark" : "light"
        let scaleKey = Int((displayScale * 100).rounded())
        return "\(modeKey)|\(schemeKey)|\(scaleKey)"
    }

    private func preheatExploreThumbnails() async {
        guard !isPreheatingThumbnails else { return }
        isPreheatingThumbnails = true
        defer { isPreheatingThumbnails = false }

        await Task.yield()

        if Task.isCancelled { return }

        let templates = orderedTemplatesForThumbnailPreheat()

        let clockIDs = Set(Self.clockTemplates.map(\.id))
        let clockSpecs = templates.filter { clockIDs.contains($0.id) }.map(\.spec)
        let otherSpecs = templates.filter { !clockIDs.contains($0.id) }.map(\.spec)

        await WidgetPreviewThumbnail.preheat(
            specs: clockSpecs,
            families: [.systemSmall],
            colorScheme: colorScheme,
            displayScale: displayScale
        )

        await WidgetPreviewThumbnail.preheat(
            specs: otherSpecs,
            families: [.systemSmall, .systemMedium, .systemLarge],
            colorScheme: colorScheme,
            displayScale: displayScale
        )
    }

    private func orderedTemplatesForThumbnailPreheat() -> [WidgetWeaverAboutTemplate] {
        var templates: [WidgetWeaverAboutTemplate] = []

        templates.append(Self.featuredPhotoTemplate)
        templates.append(Self.featuredWeatherTemplate)
        templates.append(contentsOf: Self.clockTemplates)
        templates.append(Self.featuredCalendarTemplate)
        templates.append(Self.featuredStepsTemplate)
        templates.append(contentsOf: Self.starterTemplates)
        templates.append(contentsOf: Self.proTemplates)

        var seen = Set<UUID>()
        return templates.filter { seen.insert($0.spec.id).inserted }
    }

    private var exploreMoreSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .gray) {
                NavigationLink {
                    WidgetWeaverAboutView(
                        mode: .more,
                        proManager: proManager,
                        onAddTemplate: onAddTemplate,
                        onShowPro: onShowPro,
                        onShowWidgetHelp: onShowWidgetHelp,
                        onOpenWeatherSettings: onOpenWeatherSettings,
                        onOpenStepsSettings: onOpenStepsSettings,
                        onGoToLibrary: onGoToLibrary,
                        onShowRemindersSmartStackGuide: onShowRemindersSmartStackGuide
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("More")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Guides, variables, privacy, and extra tools")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .wwAboutListRow()
        }
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


// MARK: - Featured Clock (Templates)

extension WidgetWeaverAboutView {
    var featuredClockTemplatesSection: some View {
        let templates = Self.clockTemplates

        return Section {
            WidgetWeaverAboutCard(accent: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clock")
                                .font(.headline)

                            Text("Analogue clock • saved as a Design")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Menu {
                            ForEach(templates) { template in
                                Button { handleAdd(template: template, makeDefault: false) } label: {
                                    Label("Add \(template.subtitle)", systemImage: "plus")
                                }

                                Button { handleAdd(template: template, makeDefault: true) } label: {
                                    Label("Add \(template.subtitle) & Make Default", systemImage: "star.fill")
                                }

                                if template.id != templates.last?.id {
                                    Divider()
                                }
                            }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text(
                        """
                        These are clock Designs you can add to your Library and edit.
                        Use the Editor’s Layout tool to change the clock scheme.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !templates.isEmpty {
                        WidgetWeaverAboutFlowTags(tags: ["Clock", "Template", "Time‑dependent"])
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(templates) { template in
                                let accent = template.spec.style.accent.swiftUIColor

                                WidgetWeaverAboutPreviewLabeled(familyLabel: template.subtitle, accent: accent) {
                                    WidgetPreviewThumbnail(
                                        spec: template.spec,
                                        family: .systemSmall,
                                        height: 86,
                                        renderingStyle: (isListScrolling || isPreheatingThumbnails) ? .rasterCached : .live
                                    )
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()

                    Text("Tip")
                        .font(.subheadline.weight(.semibold))

                    WidgetWeaverAboutBulletList(items: [
                        "Add one of these Clock (Designer) templates to your Library.",
                        "Open it in the Editor and use Scheme (Layout tool) to switch Classic / Ocean / Mint / Orchid / Sunset / Ember / Graphite.",
                        "Add a WidgetWeaver widget to your Home Screen to see it live.",
                    ])

                    Button { onShowWidgetHelp() } label: {
                        Label("How widgets work", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Text(
                        """
                        Note: WidgetWeaver also ships a separate “Clock (Quick)” Home Screen widget.
                        The templates above are Clock (Designer) Designs that work with the main WidgetWeaver widget.
                        """
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            .tint(.orange)
        } header: {
            WidgetWeaverAboutSectionHeader("Clock", systemImage: "clock", accent: .orange)
        } footer: {
            Text("Clock templates are added to your Library as Designs.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static let clockTemplates: [WidgetWeaverAboutTemplate] = [
        WidgetWeaverAboutTemplate(
            id: "starter-clock-classic",
            title: "Clock (Designer)",
            subtitle: "Classic",
            description: "Analogue clock design (Classic theme).",
            tags: ["Clock"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specClockTemplate(name: "Clock (Designer — Classic)", theme: "classic", accent: .orange)
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-clock-ocean",
            title: "Clock (Designer)",
            subtitle: "Ocean",
            description: "Analogue clock design (Ocean theme).",
            tags: ["Clock"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specClockTemplate(name: "Clock (Designer — Ocean)", theme: "ocean", accent: .blue)
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-clock-graphite",
            title: "Clock (Designer)",
            subtitle: "Graphite",
            description: "Analogue clock design (Graphite theme).",
            tags: ["Clock"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specClockTemplate(name: "Clock (Designer — Graphite)", theme: "graphite", accent: .gray)
        ),
    ]

    private static func specClockTemplate(name: String, theme: String, accent: AccentToken) -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()

        spec.name = name
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.symbol = nil
        spec.image = nil

        spec.layout.template = .clockIcon
        spec.layout.showsAccentBar = false

        spec.style.accent = accent

        spec.clockConfig = WidgetWeaverClockDesignConfig(theme: theme)

        return spec.normalised()
    }
}
