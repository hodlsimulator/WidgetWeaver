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

                    WidgetWeaverAboutBulletList(items: [
                        "{{__weather_temp}} — temperature",
                        "{{__weather_condition}} — condition name",
                        "{{__weather_rain_next_hour}} — next-hour rain summary",
                        "{{__weather_city}} — city name",
                    ])
                }
            }
            .tint(.blue)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Weather", systemImage: "cloud.rain", accent: .blue)
        } footer: {
            Text("Weather widgets read cached forecasts stored in the App Group.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Featured Calendar (Next Up)

    var featuredCalendarSection: some View {
        let template = Self.featuredCalendarTemplate

        return Section {
            WidgetWeaverAboutCard(accent: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next Up")
                                .font(.headline)
                            Text("Calendar • upcoming events")
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

                    Text("A native Calendar widget that shows the next upcoming event and its time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                        "Open Editor → Calendar and grant permission.",
                        "Add Next Up to your library (optionally make it Default).",
                        "Add a WidgetWeaver widget to your Home Screen.",
                    ])
                }
            }
            .tint(.green)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Calendar", systemImage: "calendar", accent: .green)
        } footer: {
            Text("Calendar widgets read cached events stored in the App Group.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Featured Steps

    var featuredStepsSection: some View {
        let template = Self.featuredStepsTemplate

        return Section {
            WidgetWeaverAboutCard(accent: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Steps")
                                .font(.headline)
                            Text("HealthKit • today’s steps")
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

                    Text("A Steps widget that reads cached HealthKit steps stored in the App Group.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                        Primary:  {{__var_count|0}}
                        Button:   +1 (updates __var_count)
                        """,
                        accent: .teal
                    )
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Variables", systemImage: "square.and.pencil", accent: .teal)
        } footer: {
            Text("Variables can power counters, streaks, and small interactive dashboards.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI

    var aiSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .indigo) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI tools are optional and always review-first. When unavailable, the app falls back to deterministic behaviour.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Review before apply (generate + patch).",
                        "Undo last apply is one tap.",
                        "No networking in the AI pipeline.",
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("AI", systemImage: "sparkles", accent: .indigo)
        } footer: {
            Text("AI features are gated behind internal flags during QA.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Privacy

    var privacySection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .gray) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("WidgetWeaver stores designs and cached snapshots in an App Group so widgets can read them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "No accounts.",
                        "No tracking.",
                        "No servers required for widgets to run.",
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Privacy", systemImage: "hand.raised.fill", accent: .gray)
        } footer: {
            Text("Some templates require permissions (Weather, Calendar, Reminders, Steps).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Support

    var supportSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If something looks wrong, refreshing widgets and snapshots fixes most issues.")
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
