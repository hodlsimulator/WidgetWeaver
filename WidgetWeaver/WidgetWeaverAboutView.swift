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

    @AppStorage("widgetweaver.theme.selectedPresetID")
    private var selectedThemePresetIDRaw: String = ""

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

    private var resolvedSelectedThemePreset: WidgetWeaverThemePreset {
        if let preset = WidgetWeaverThemeCatalog.preset(matching: selectedThemePresetIDRaw) {
            return preset
        }

        if let preset = WidgetWeaverThemeCatalog.preset(matching: WidgetWeaverThemeCatalog.defaultPresetID) {
            return preset
        }

        return WidgetWeaverThemeCatalog.ordered.first
            ?? WidgetWeaverThemePreset(
                id: "classic",
                displayName: "Classic",
                detail: "System default theme.",
                style: StyleSpec.defaultStyle
            )
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

    private func applySelectedTheme(to spec: WidgetSpec) -> WidgetSpec {
        WidgetWeaverThemeApplier.apply(preset: resolvedSelectedThemePreset, to: spec)
    }

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
        onAddTemplate(applySelectedTheme(to: template.spec), makeDefault)
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
        typealias Upgrader = WidgetWeaverRemindersSmartStackKitUpgrader

        let store = WidgetSpecStore.shared

        let slots: [(slot: Upgrader.Slot, makeBaseSpec: () -> WidgetSpec)] = [
            (.today, { Self.specRemindersToday() }),
            (.overdue, { Self.specRemindersOverdue() }),
            (.upcoming, { Self.specRemindersSoon() }),
            (.highPriority, { Self.specRemindersPriority() }),
            (.anytime, { Self.specRemindersFocus() }),
            (.lists, { Self.specRemindersLists() }),
        ]

        var allSpecs = store.loadAll()

        func kitNamePrefix(for slot: Upgrader.Slot) -> String {
            "Reminders \(slot.sortIndex) —"
        }

        func isKitCandidate(_ spec: WidgetSpec, for slot: Upgrader.Slot) -> Bool {
            guard spec.layout.template == .reminders else { return false }
            guard spec.remindersConfig?.mode == slot.mode else { return false }

            let name = spec.name.trimmingCharacters(in: .whitespacesAndNewlines)

            if name == slot.v1DefaultDesignName { return true }
            if name == slot.v2DefaultDesignName { return true }
            if name.hasPrefix(kitNamePrefix(for: slot)) { return true }

            return false
        }

        func pickDeterministicCandidate(from specs: [WidgetSpec], for slot: Upgrader.Slot) -> WidgetSpec? {
            let candidates = specs.filter { isKitCandidate($0, for: slot) }
            guard !candidates.isEmpty else { return nil }

            func rank(_ name: String) -> Int {
                if name == slot.v2DefaultDesignName { return 2 }
                if name == slot.v1DefaultDesignName { return 1 }
                return 0
            }

            return candidates.sorted { a, b in
                let aName = a.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let bName = b.name.trimmingCharacters(in: .whitespacesAndNewlines)

                let ra = rank(aName)
                let rb = rank(bName)
                if ra != rb { return ra > rb }

                if a.updatedAt != b.updatedAt { return a.updatedAt < b.updatedAt }
                return a.id.uuidString < b.id.uuidString
            }.first
        }

        var upgradedCount = 0
        var addedCount = 0
        var presentAtStartCount = 0

        var presentSlots = Set<Upgrader.Slot>()

        for entry in slots {
            let slot = entry.slot

            if let existing = pickDeterministicCandidate(from: allSpecs, for: slot) {
                presentAtStartCount += 1
                presentSlots.insert(slot)

                let result = Upgrader.upgradeV1ToV2IfNeeded(spec: existing, slot: slot)
                if result.didChange {
                    store.save(result.spec, makeDefault: false)
                    upgradedCount += 1

                    if let idx = allSpecs.firstIndex(where: { $0.id == existing.id }) {
                        allSpecs[idx] = result.spec
                    } else {
                        allSpecs = store.loadAll()
                    }
                }

                continue
            }

            let beforeCount = allSpecs.count

            var base = entry.makeBaseSpec()
            let upgraded = Upgrader.upgradeV1ToV2IfNeeded(spec: base, slot: slot)
            base = upgraded.spec

            onAddTemplate(applySelectedTheme(to: base), false)

            let refreshed = store.loadAll()
            let afterCount = refreshed.count

            if afterCount > beforeCount {
                addedCount += 1
                presentSlots.insert(slot)
                allSpecs = refreshed
            } else {
                break
            }
        }

        let total = slots.count
        let nowPresentCount = presentSlots.count
        let remainingMissing = max(0, total - nowPresentCount)

        let message: String = {
            if nowPresentCount == 0 {
                return "Unable to add (design limit)."
            }

            if remainingMissing > 0 {
                if upgradedCount > 0 && addedCount > 0 {
                    return "Upgraded \(upgradedCount), added \(addedCount). Unlock Pro for the rest."
                }
                if upgradedCount > 0 {
                    return "Upgraded \(upgradedCount). Unlock Pro for the rest."
                }
                if addedCount > 0 {
                    return "Added \(addedCount). Unlock Pro for the rest."
                }
                return "No changes."
            }

            if upgradedCount == 0 && addedCount == 0 {
                return "All 6 already in Library."
            }

            if presentAtStartCount == 0 && addedCount == total {
                return "Added all 6."
            }

            if upgradedCount > 0 && addedCount > 0 {
                return "Upgraded \(upgradedCount), added \(addedCount)."
            }

            if upgradedCount > 0 {
                return "Upgraded \(upgradedCount)."
            }

            if addedCount > 0 && presentAtStartCount > 0 {
                return "Added \(addedCount). \(presentAtStartCount) already in Library."
            }

            return "Added \(addedCount)."
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

        if nowPresentCount > 0 {
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
                        WidgetWeaverAboutFlowTags(tags: ["Clock", "Template", "Time-dependent"])
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
