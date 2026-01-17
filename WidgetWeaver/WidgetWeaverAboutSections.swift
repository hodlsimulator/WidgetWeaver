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

    // MARK: - Featured Clock (Home Screen)

    var featuredClockSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clock (Icon)")
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

                    Text("A standalone analogue clock widget. This is separate from Designs, the Library, and the Editor.")
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
                        "Search “WidgetWeaver” → add Clock (Icon) (Small).",
                        "Long-press the clock → Edit Widget → choose a colour scheme.",
                    ])
                }
            }
            .tint(.orange)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Clock", systemImage: "clock", accent: .orange)
        } footer: {
            Text("Clock (Icon) is a separate widget kind and can’t be added to your Design library like templates.")
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

    // MARK: - Starter templates

    var starterTemplatesSection: some View {
        let remindersEnabled = WidgetWeaverFeatureFlags.remindersTemplateEnabled
        let templates = Self.starterTemplates.filter { template in
            if remindersEnabled {
                return template.id != "starter-list"
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

// MARK: - Clock thumbnail (Explore)

private struct WidgetWeaverAboutClockThumbnail: View {
    enum Variant: String, CaseIterable {
        case classic
        case ocean
        case graphite
    }

    let variant: Variant

    @Environment(\.wwThumbnailRenderingEnabled) private var thumbnailRenderingEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if thumbnailRenderingEnabled {
                TimelineView(.periodic(from: Date(), by: 1.0)) { context in
                    clockBody(date: context.date)
                }
            } else {
                clockBody(date: Date())
            }
        }
        .frame(width: 86, height: 86)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private func clockBody(date: Date) -> some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let r = size * 0.5
            let dialR = r * 0.86

            let angles = Self.handAngles(for: date)
            let palette = Self.palette(for: variant, colorScheme: colorScheme)

            ZStack {
                LinearGradient(
                    colors: [palette.backgroundA, palette.backgroundB],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(palette.dialFill.opacity(0.95))
                    .frame(width: dialR * 2, height: dialR * 2)
                    .overlay(
                        Circle()
                            .strokeBorder(palette.dialStroke.opacity(0.55), lineWidth: max(1, size * 0.012))
                    )

                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) * 30.0
                    Capsule(style: .continuous)
                        .fill(palette.marker)
                        .frame(width: max(1, size * 0.020), height: max(2, size * 0.090))
                        .offset(y: -dialR + (size * 0.090))
                        .rotationEffect(.degrees(angle))
                }

                clockHand(length: dialR * 0.52, width: max(2, size * 0.040), color: palette.hourHand, angle: angles.hour)
                clockHand(length: dialR * 0.72, width: max(2, size * 0.028), color: palette.minuteHand, angle: angles.minute)
                clockHand(length: dialR * 0.76, width: max(1, size * 0.012), color: palette.secondHand, angle: angles.second)

                Circle()
                    .fill(palette.centre)
                    .frame(width: max(4, size * 0.06), height: max(4, size * 0.06))
                    .shadow(color: Color.black.opacity(0.18), radius: size * 0.02, x: 0, y: size * 0.01)
            }
        }
    }

    private func clockHand(length: CGFloat, width: CGFloat, color: Color, angle: Double) -> some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length * 0.5)
            .rotationEffect(.degrees(angle))
            .shadow(color: Color.black.opacity(0.12), radius: width, x: 0, y: width * 0.3)
    }

    private struct Angles {
        let hour: Double
        let minute: Double
        let second: Double
    }

    private static func handAngles(for date: Date) -> Angles {
        let cal = Calendar.autoupdatingCurrent
        let c = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: date)

        let hour = Double((c.hour ?? 0) % 12)
        let minuteInt = Double(c.minute ?? 0)
        let secondInt = Double(c.second ?? 0)
        let subSecond = Double(c.nanosecond ?? 0) / 1_000_000_000.0

        let seconds = secondInt + subSecond
        let minutes = minuteInt + (seconds / 60.0)
        let hours = hour + (minutes / 60.0)

        return Angles(
            hour: hours * 30.0,
            minute: minutes * 6.0,
            second: seconds * 6.0
        )
    }

    private struct Palette {
        let backgroundA: Color
        let backgroundB: Color
        let dialFill: Color
        let dialStroke: Color
        let marker: Color
        let hourHand: Color
        let minuteHand: Color
        let secondHand: Color
        let centre: Color
    }

    private static func palette(for variant: Variant, colorScheme: ColorScheme) -> Palette {
        switch variant {
        case .classic:
            if colorScheme == .dark {
                return Palette(
                    backgroundA: Color(white: 0.20),
                    backgroundB: Color(white: 0.10),
                    dialFill: Color(white: 0.08),
                    dialStroke: Color.white.opacity(0.18),
                    marker: Color.white.opacity(0.80),
                    hourHand: Color.white.opacity(0.92),
                    minuteHand: Color.white.opacity(0.78),
                    secondHand: Color.orange.opacity(0.92),
                    centre: Color.white.opacity(0.92)
                )
            } else {
                return Palette(
                    backgroundA: Color(white: 0.98),
                    backgroundB: Color(white: 0.88),
                    dialFill: Color.white,
                    dialStroke: Color.black.opacity(0.10),
                    marker: Color.black.opacity(0.65),
                    hourHand: Color.black.opacity(0.82),
                    minuteHand: Color.black.opacity(0.62),
                    secondHand: Color.orange.opacity(0.85),
                    centre: Color.black.opacity(0.78)
                )
            }

        case .ocean:
            if colorScheme == .dark {
                return Palette(
                    backgroundA: Color.blue.opacity(0.55),
                    backgroundB: Color.black.opacity(0.90),
                    dialFill: Color.black.opacity(0.35),
                    dialStroke: Color.white.opacity(0.22),
                    marker: Color.white.opacity(0.80),
                    hourHand: Color.white.opacity(0.92),
                    minuteHand: Color.white.opacity(0.78),
                    secondHand: Color.cyan.opacity(0.92),
                    centre: Color.white.opacity(0.92)
                )
            } else {
                return Palette(
                    backgroundA: Color.blue.opacity(0.55),
                    backgroundB: Color.cyan.opacity(0.35),
                    dialFill: Color.white.opacity(0.88),
                    dialStroke: Color.black.opacity(0.10),
                    marker: Color.black.opacity(0.65),
                    hourHand: Color.black.opacity(0.82),
                    minuteHand: Color.black.opacity(0.62),
                    secondHand: Color.blue.opacity(0.90),
                    centre: Color.black.opacity(0.78)
                )
            }

        case .graphite:
            if colorScheme == .dark {
                return Palette(
                    backgroundA: Color(white: 0.14),
                    backgroundB: Color(white: 0.04),
                    dialFill: Color(white: 0.06),
                    dialStroke: Color.white.opacity(0.16),
                    marker: Color.white.opacity(0.74),
                    hourHand: Color.white.opacity(0.92),
                    minuteHand: Color.white.opacity(0.78),
                    secondHand: Color.red.opacity(0.86),
                    centre: Color.white.opacity(0.92)
                )
            } else {
                return Palette(
                    backgroundA: Color(white: 0.26),
                    backgroundB: Color(white: 0.10),
                    dialFill: Color(white: 0.08),
                    dialStroke: Color.white.opacity(0.16),
                    marker: Color.white.opacity(0.75),
                    hourHand: Color.white.opacity(0.92),
                    minuteHand: Color.white.opacity(0.78),
                    secondHand: Color.red.opacity(0.86),
                    centre: Color.white.opacity(0.92)
                )
            }
        }
    }
}
