//
//  WidgetWeaverAboutSections.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation
import SwiftUI
import WidgetKit

extension WidgetWeaverAboutView {
    // MARK: - Header

    var aboutHeaderSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: WidgetWeaverAboutTheme.pageTint) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        WidgetWeaverAboutMark(accent: WidgetWeaverAboutTheme.pageTint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("WidgetWeaver")
                                .font(.title3.weight(.semibold))
                            Text(appVersionString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    Text(
                        """
                        Explore curated templates, then customise layout + style in the Editor.
                        Featured starters include Weather, Next Up (Calendar), and Steps.
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    aboutHeaderActions
                        .controlSize(.regular)

                    if !statusMessage.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(WidgetWeaverAboutTheme.pageTint)
                            Text(statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .wwAboutListRow()
        } header: {
            EmptyView()
        }
    }

    // MARK: - Header actions (adaptive)

    @ViewBuilder
    private var aboutHeaderActions: some View {
        ViewThatFits(in: .horizontal) {
            aboutHeaderActionsSingleRow
            aboutHeaderActionsTwoRows
        }
    }

    private var aboutHeaderActionsSingleRow: some View {
        HStack(spacing: 12) {
            Button { onGoToLibrary() } label: {
                aboutHeaderButtonContent("Library", systemImage: "square.grid.2x2", fixedSize: true)
            }
            .buttonStyle(.bordered)

            Button { onShowWidgetHelp() } label: {
                aboutHeaderButtonContent("Widget Help", systemImage: "questionmark.circle", fixedSize: true)
            }
            .buttonStyle(.bordered)

            Button { onShowPro() } label: {
                aboutHeaderProContent(fixedSize: true)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var aboutHeaderActionsTwoRows: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button { onGoToLibrary() } label: {
                    aboutHeaderButtonContent("Library", systemImage: "square.grid.2x2", fixedSize: false)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button { onShowWidgetHelp() } label: {
                    aboutHeaderButtonContent("Widget Help", systemImage: "questionmark.circle", fixedSize: false)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }

            Button { onShowPro() } label: {
                aboutHeaderProContent(fixedSize: false)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func aboutHeaderButtonContent(_ title: String, systemImage: String, fixedSize: Bool) -> some View {
        let content = HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
        }

        if fixedSize {
            content.fixedSize(horizontal: true, vertical: false)
        } else {
            content
        }
    }

    @ViewBuilder
    private func aboutHeaderProContent(fixedSize: Bool) -> some View {
        if proManager.isProUnlocked {
            aboutHeaderButtonContent("Pro (Unlocked)", systemImage: "checkmark.seal.fill", fixedSize: fixedSize)
        } else {
            aboutHeaderButtonContent("Upgrade to Pro", systemImage: "crown.fill", fixedSize: fixedSize)
        }
    }

    // MARK: - Featured Weather

    var featuredWeatherSection: some View {
        let template = Self.featuredWeatherTemplate

        return Section {
            WidgetWeaverAboutCard(accent: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Weather")
                                .font(.headline)
                            Text("Rain-first nowcast • glass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Menu {
                            Button { handleAdd(template: template, makeDefault: false) } label: {
                                Label("Add to library", systemImage: "plus")
                            }
                            Button { handleAdd(template: template, makeDefault: true) } label: {
                                Label("Add & Make Default", systemImage: "star.fill")
                            }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text(
                        """
                        A weather layout template that focuses on the next-hour rain chart, with an hourly strip and daily highs/lows when available.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if !template.tags.isEmpty {
                        WidgetWeaverAboutFlowTags(tags: template.tags)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Small", accent: .blue) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 86)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Medium", accent: .blue) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 86)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Large", accent: .blue) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemLarge, height: 86)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()

                    Text("Setup")
                        .font(.subheadline.weight(.semibold))

                    WidgetWeaverAboutBulletList(items: [
                        "Open Weather settings and choose a location (Current Location or search).",
                        "Add the Weather template to your library (optionally make it Default).",
                        "Add a WidgetWeaver widget to your Home Screen.",
                    ])

                    Button { onOpenWeatherSettings() } label: {
                        Label("Open Weather settings", systemImage: "cloud.rain")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Divider()

                    Text("Built-in weather keys (work in any text field)")
                        .font(.subheadline.weight(.semibold))

                    WidgetWeaverAboutCodeBlock(
                        """
                        {{__weather_location|Set location}}
                        {{__weather_temp|--}}°
                        {{__weather_condition|Updating…}}
                        {{__weather_precip|0}}%
                        """,
                        accent: .blue
                    )

                    Button {
                        copyToPasteboard(
                            """
                            Weather: {{__weather_temp|--}}° • {{__weather_condition|Updating…}}
                            Chance: {{__weather_precip|0}}% • Humidity: {{__weather_humidity|0}}%
                            """
                        )
                    } label: {
                        Label("Copy weather example", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .tint(.blue)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Featured", systemImage: "sparkles", accent: .blue)
        } footer: {
            Text(
                """
                Weather data is provided by Weather.
                iOS widget refresh limits still apply; use Weather → Update now to refresh the cached snapshot.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Featured Clock (Quick) (Home Screen)

    var featuredClockSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clock (Quick)")
                                .font(.headline)
                            Text("Analogue • Home Screen (Small)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer(minLength: 0)
                        
                        Button { onShowWidgetHelp() } label: {
                            Label("How to add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Text("A standalone analogue clock widget (Home Screen, Small). Fast to set up with minimal configuration. For deep customisation, use Clock (Designer) inside the WidgetWeaver widget.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Classic", accent: .orange) {
                                WidgetWeaverAboutClockThumbnail(variant: .classic)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Ocean", accent: .orange) {
                                WidgetWeaverAboutClockThumbnail(variant: .ocean)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Graphite", accent: .orange) {
                                WidgetWeaverAboutClockThumbnail(variant: .graphite)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    
                    Divider()
                    
                    Text("Setup")
                        .font(.subheadline.weight(.semibold))
                    
                    WidgetWeaverAboutBulletList(items: [
                        "On the Home Screen: long-press → Edit Home Screen → “+”.",
                        "Search “WidgetWeaver” → add Clock (Quick) (Small).",
                        "Long-press the clock → Edit Widget → choose a colour scheme.",
                    ])
                }
            }
            .tint(.orange)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Clock", systemImage: "clock", accent: .orange)
        } footer: {
            Text("Clock (Quick) is a separate widget kind and can’t be added to your Design library like templates. For deep customisation, create a Clock (Designer) design in the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Featured Calendar (Next Up)

    var featuredCalendarSection: some View {
        let template = Self.featuredCalendarTemplate
        let canRead = WidgetWeaverCalendarStore.shared.canReadEvents()

        return Section {
            WidgetWeaverAboutCard(accent: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next Up")
                                .font(.headline)
                            Text("Calendar events • on-device")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Menu {
                            Button { handleAdd(template: template, makeDefault: false) } label: {
                                Label("Add to library", systemImage: "plus")
                            }
                            Button { handleAdd(template: template, makeDefault: true) } label: {
                                Label("Add & Make Default", systemImage: "star.fill")
                            }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("Shows your next event (and the one after) from your calendars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Label(
                            canRead ? "Access: On" : "Access: Off",
                            systemImage: canRead ? "checkmark.seal.fill" : "calendar.badge.exclamationmark"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Button { presentCalendarPermissionFlow() } label: {
                            Label(
                                canRead ? "Refresh now" : "Enable access",
                                systemImage: canRead ? "arrow.clockwise" : "checkmark.circle.fill"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !template.tags.isEmpty {
                        WidgetWeaverAboutFlowTags(tags: template.tags)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Small", accent: .green) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 86)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Medium", accent: .green) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 86)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Large", accent: .green) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemLarge, height: 86)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()

                    Text("Setup")
                        .font(.subheadline.weight(.semibold))

                    WidgetWeaverAboutBulletList(items: [
                        "Add the Next Up template to your library.",
                        "When prompted, allow Calendar access.",
                        "Add a WidgetWeaver widget to your Home Screen.",
                    ])
                }
            }
            .tint(.green)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Next Up", systemImage: "calendar", accent: .green)
        } footer: {
            Text(
                """
                Calendar data is read on-device from Apple Calendar (EventKit).
                No events are uploaded by WidgetWeaver.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Featured Steps

    var featuredStepsSection: some View {
        let template = Self.featuredStepsTemplate
        let access = WidgetWeaverStepsStore.shared.loadLastAccess()

        let accessLabel: String = {
            switch access {
            case .authorised: return "Access: On"
            case .denied: return "Access: Off"
            case .notDetermined: return "Access: Not set"
            case .notAvailable: return "Access: Not available"
            case .unknown: return "Access: Unknown"
            }
        }()

        let accessIcon: String = {
            switch access {
            case .authorised: return "checkmark.seal.fill"
            case .denied: return "heart.slash"
            case .notDetermined: return "heart.circle"
            case .notAvailable: return "exclamationmark.triangle.fill"
            case .unknown: return "questionmark.circle"
            }
        }()

        return Section {
            WidgetWeaverAboutCard(accent: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Steps")
                                .font(.headline)
                            Text("Today • goal • streak-ready")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Menu {
                            Button { handleAdd(template: template, makeDefault: false) } label: {
                                Label("Add to library", systemImage: "plus")
                            }
                            Button { handleAdd(template: template, makeDefault: true) } label: {
                                Label("Add & Make Default", systemImage: "star.fill")
                            }
                        } label: {
                            Label("Add", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text("Shows your step count, goal progress, and is ready for streaks.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Label(accessLabel, systemImage: accessIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Button { onOpenStepsSettings() } label: {
                            Label("Open Steps", systemImage: "heart.fill")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !template.tags.isEmpty {
                        WidgetWeaverAboutFlowTags(tags: template.tags)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Small", accent: .green) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 86)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Medium", accent: .green) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 86)
                            }
                            WidgetWeaverAboutPreviewLabeled(familyLabel: "Large", accent: .green) {
                                WidgetPreviewThumbnail(spec: template.spec, family: .systemLarge, height: 86)
                            }
                        }
                        .padding(.vertical, 2)
                    }

                    Divider()

                    Text("Setup")
                        .font(.subheadline.weight(.semibold))

                    WidgetWeaverAboutBulletList(items: [
                        "Open Steps settings and allow Health access.",
                        "Add the Steps template to your library.",
                        "Add a WidgetWeaver widget to your Home Screen.",
                    ])
                }
            }
            .tint(.green)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Steps", systemImage: "figure.walk", accent: .green)
        } footer: {
            Text(
                """
                Steps data is read on-device from HealthKit.
                WidgetWeaver caches today’s snapshot for widgets to read.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

        // MARK: - Reminders Smart Stack kit

        @ViewBuilder
        var remindersSmartStackSection: some View {
            if WidgetWeaverFeatureFlags.remindersTemplateEnabled {
                Section {
                    remindersSmartStackKitIntroRow

                    ForEach(remindersSmartStackTemplates) { template in
                        WidgetWeaverAboutTemplateRow(
                            template: template,
                            isProUnlocked: proManager.isProUnlocked,
                            onAdd: { makeDefault in handleAdd(template: template, makeDefault: makeDefault) },
                            onShowPro: onShowPro
                        )
                    }
                } header: {
                    WidgetWeaverAboutSectionHeader("Smart Stack Kit", systemImage: "square.stack.3d.up.fill", accent: .orange)
                } footer: {
                    Text("These 6 templates are designed to be stacked together. Add them to your Library, then build a Smart Stack on the Home Screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private var remindersSmartStackTemplates: [WidgetWeaverAboutTemplate] {
            let desiredIDs = [
                "starter-reminders-today",
                "starter-reminders-overdue",
                "starter-reminders-soon",
                "starter-reminders-priority",
                "starter-reminders-focus",
                "starter-reminders-list",
            ]

            let byID = Dictionary(uniqueKeysWithValues: Self.starterTemplates.map { ($0.id, $0) })
            return desiredIDs.compactMap { byID[$0] }
        }

        private var remindersSmartStackKitIntroRow: some View {
            WidgetWeaverAboutCard(accent: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.16))

                            Circle()
                                .strokeBorder(Color.orange.opacity(0.26), lineWidth: 1)

                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                        .frame(width: 28, height: 28)
                        .padding(.top, 1)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Reminders Smart Stack")
                                    .font(.headline)

                                WidgetWeaverAboutBadge("6 designs", accent: .orange)
                            }

                            Text("Six Reminders templates designed to be used together in one Smart Stack. Swipe to switch between Today, Overdue, Soon, Priority, Focus, and Lists.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            remindersSmartStackKitAddAllButton
                            remindersSmartStackKitGuideButton
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            remindersSmartStackKitAddAllButton
                            remindersSmartStackKitGuideButton
                        }
                    }
                }
            }
            .tint(.orange)
            .wwAboutListRow()
        }

        private var remindersSmartStackKitAddAllButton: some View {
            Button {
                handleAddRemindersSmartStackKit()
            } label: {
                Label("Add all 6", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }

        private var remindersSmartStackKitGuideButton: some View {
            Button {
                onShowRemindersSmartStackGuide()
            } label: {
                Label("Guide", systemImage: "book.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }

    // MARK: - Starter templates

    var starterTemplatesSection: some View {
        let remindersEnabled = WidgetWeaverFeatureFlags.remindersTemplateEnabled
        let templates = Self.starterTemplates.filter { template in
            if remindersEnabled {
                    return template.id != "starter-list" && !template.id.hasPrefix("starter-reminders-")
            }
            return !template.id.hasPrefix("starter-reminders-")
        }

            return Section {
                ForEach(templates) { template in
                WidgetWeaverAboutTemplateRow(
                    template: template,
                    isProUnlocked: proManager.isProUnlocked,
                    onAdd: { makeDefault in handleAdd(template: template, makeDefault: makeDefault) },
                    onShowPro: onShowPro
                )
            }
        } header: {
            WidgetWeaverAboutSectionHeader("Templates", systemImage: "square.grid.2x2.fill", accent: .pink)
        } footer: {
            Text("Templates are added to your Library as Designs. Edit them any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pro templates

    var proTemplatesSection: some View {
        Section {
            ForEach(Self.proTemplates) { template in
                WidgetWeaverAboutTemplateRow(
                    template: template,
                    isProUnlocked: proManager.isProUnlocked,
                    onAdd: { makeDefault in handleAdd(template: template, makeDefault: makeDefault) },
                    onShowPro: onShowPro
                )
            }
        } header: {
            WidgetWeaverAboutSectionHeader("Pro Templates", systemImage: "crown.fill", accent: .yellow)
        } footer: {
            Text("Pro templates showcase buttons, variables, and matched sets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Capabilities

    var capabilitiesSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WidgetWeaver renders a saved design spec into a widget view. Templates are starting points you can customise.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        WidgetWeaverAboutFeatureRow(
                            title: "Templates + Remixes",
                            subtitle: "Curated starters, then tweak layout + style."
                        )
                        WidgetWeaverAboutFeatureRow(
                            title: "Design Library",
                            subtitle: "Save multiple designs and choose a default."
                        )
                        WidgetWeaverAboutFeatureRow(
                            title: "Widget families",
                            subtitle: "Small / Medium / Large Home Screen widgets."
                        )
                        WidgetWeaverAboutFeatureRow(
                            title: "Lock Screen widgets",
                            subtitle: "Weather, Next Up, and Steps lock widgets."
                        )
                    }
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Capabilities", systemImage: "wand.and.stars", accent: .purple)
        } footer: {
            Text("Some features require iOS 17+ (interactive widgets).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Interactive buttons

    var interactiveButtonsSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .teal) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Interactive widgets can trigger AppIntents to update shared variables.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Requires iOS 17+.",
                        "Buttons update variables stored in the App Group.",
                        "Use variables in any text field with {{__var_name}}."
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Buttons", systemImage: "hand.tap.fill", accent: .teal)
        } footer: {
            Text("Interactive buttons are supported on Home Screen widgets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Variables

    var variablesSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .teal) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Variables are small pieces of state shared between the app and widgets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Use {{__var_name|Fallback}} in any text field.",
                        "Variables can be updated by buttons (iOS 17+).",
                        "Variables live in the App Group store."
                    ])

                    Divider()

                    Text("Example")
                        .font(.subheadline.weight(.semibold))

                    WidgetWeaverAboutCodeBlock(
                        """
                        Streak: {{__var_streak|0}} days
                        """,
                        accent: .teal
                    )

                    Button {
                        copyToPasteboard("Streak: {{__var_streak|0}} days")
                    } label: {
                        Label("Copy variable example", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Variables", systemImage: "curlybraces.square", accent: .teal)
        } footer: {
            Text("Variables are stored on-device only.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI

    var aiSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .indigo) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Generate and patch designs on-device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Prompts create a starter design.",
                        "Patches tweak layout and style tokens.",
                        "AI output is editable in the Editor."
                    ])

                    Divider()

                    Text("Prompt ideas")
                        .font(.subheadline.weight(.semibold))

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.promptIdeas, id: \.self) { idea in
                            WidgetWeaverAboutPromptRow(
                                text: idea,
                                copyLabel: "Copy prompt",
                                onCopy: { copyToPasteboard(idea) }
                            )
                        }
                    }

                    Divider()

                    Text("Patch ideas")
                        .font(.subheadline.weight(.semibold))

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Self.patchIdeas, id: \.self) { idea in
                            WidgetWeaverAboutPromptRow(
                                text: idea,
                                copyLabel: "Copy patch",
                                onCopy: { copyToPasteboard(idea) }
                            )
                        }
                    }
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("AI", systemImage: "sparkles", accent: .indigo)
        } footer: {
            Text("AI runs on-device where available.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Privacy

    var privacySection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .gray) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WidgetWeaver keeps your data on-device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Designs: saved locally in the App Group.",
                        "Images: stored locally in the App Group container.",
                        "Weather: cached snapshot + attribution stored locally.",
                        "Calendar: cached upcoming events stored locally.",
                        "Steps: cached today snapshot and (optionally) cached history stored locally.",
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Privacy", systemImage: "hand.raised.fill", accent: .gray)
        } footer: {
            Text("No accounts.\nNo servers. No tracking.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Support

    var supportSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("This is a prototype app for exploring widget layouts and spec-driven rendering.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "If widgets look stale, use Editor → Widgets → Refresh Widgets.",
                        "If Weather looks stale, open Weather settings and Update now.",
                        "Steps widgets require opening the app to grant Health permission and cache today.",
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Support", systemImage: "lifepreserver", accent: .pink)
        } footer: {
            Text("Thanks for testing WidgetWeaver.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
