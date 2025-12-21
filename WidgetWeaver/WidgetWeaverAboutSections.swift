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
                        Build Home Screen widgets from simple templates.
                        Start from templates, customise layout + style, and (in Pro) add variables and interactive buttons.
                        Designs are saved on your device and shown on your Home Screen.
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            onShowWidgetHelp()
                        } label: {
                            Label("Widget Help", systemImage: "questionmark.circle")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            onShowPro()
                        } label: {
                            if proManager.isProUnlocked {
                                Label("Pro (Unlocked)", systemImage: "checkmark.seal.fill")
                            } else {
                                Label("Upgrade to Pro", systemImage: "crown.fill")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
                            Button {
                                handleAdd(template: template, makeDefault: false)
                            } label: {
                                Label("Add to library", systemImage: "plus")
                            }

                            Button {
                                handleAdd(template: template, makeDefault: true)
                            } label: {
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
                        "In the app: … → Weather → choose a location (Current Location or search).",
                        "Add the Weather template to your library (optionally make it Default).",
                        "Add a WidgetWeaver widget to your Home Screen.",
                    ])

                    Button {
                        showWeatherSettings = true
                    } label: {
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
                        {{__weather_temp|--}}° {{__weather_condition|Updating…}}
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

    // MARK: - Featured Calendar

    var featuredCalendarSection: some View {
        let template = Self.featuredCalendarTemplate
        let canRead = WidgetWeaverCalendarStore.shared.canReadEvents()

        return Section {
            WidgetWeaverAboutCard(accent: .green) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Calendar")
                                .font(.headline)
                            Text("Next Up • upcoming events")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Menu {
                            Button {
                                handleAdd(template: template, makeDefault: false)
                            } label: {
                                Label("Add to library", systemImage: "plus")
                            }

                            Button {
                                handleAdd(template: template, makeDefault: true)
                            } label: {
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

                        Button {
                            presentCalendarPermissionFlow()
                        } label: {
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
                        "Add the Calendar template to your library.",
                        "When prompted, allow Calendar access.",
                        "Add a WidgetWeaver widget to your Home Screen.",
                    ])
                }
            }
            .tint(.green)
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Calendar", systemImage: "calendar", accent: .green)
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

    // MARK: - Capabilities

    var capabilitiesSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    WidgetWeaverAboutFeatureRow(
                        title: "Templates library",
                        subtitle: "Add starter designs (and Pro designs) to your library, then edit freely."
                    )
                    Divider()
                    WidgetWeaverAboutFeatureRow(
                        title: "Text-first widgets",
                        subtitle: "Design name, primary text, and optional secondary text."
                    )
                    Divider()
                    WidgetWeaverAboutFeatureRow(
                        title: "Layout templates",
                        subtitle: "Classic / Hero / Poster / Weather / Calendar presets, plus a starter Steps template, plus axis, alignment, spacing, and line limits."
                    )
                    Divider()
                    WidgetWeaverAboutFeatureRow(
                        title: "Built-in Weather template",
                        subtitle: "A rain-first layout with glass panels and adaptive Small/Medium/Large composition."
                    )
                    Divider()
                    WidgetWeaverAboutFeatureRow(
                        title: "Matched Sets (Pro)",
                        subtitle: "Override Small/Medium/Large content for one design."
                    )
                    Divider()
                    WidgetWeaverAboutFeatureRow(
                        title: "Variables + Shortcuts (Pro)",
                        subtitle: "Create shared variables and fill them from Shortcuts or interactive widget buttons."
                    )
                    Divider()
                    WidgetWeaverAboutFeatureRow(
                        title: "Interactive buttons (Pro)",
                        subtitle: "Add an action bar to the widget (iOS 17+) to update variables without opening the app."
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Examples of widgets that fit the current renderer:")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        WidgetWeaverAboutBulletList(items: [
                            "Weather (rain-first nowcast + forecast) via the built-in Weather template",
                            "Next Up calendar widget (upcoming events) via the Calendar template",
                            "Steps widget (Health) via the Steps template",
                            "Habit tracker / streak counter (with Variables + interactive buttons in Pro)",
                            "Countdown widget (manual or variable-driven)",
                            "Daily focus / top task",
                            "Shopping list / reminder",
                        ])
                    }
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Capabilities", systemImage: "wand.and.stars", accent: .purple)
        } footer: {
            Text("Each design renders into Small/Medium/Large with size-aware layout rules.\nSome presets (Weather/Calendar) are special layouts.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Templates

    var starterTemplatesSection: some View {
        Section {
            ForEach(Self.starterTemplates.filter { $0.id != Self.featuredWeatherTemplateID && $0.id != Self.featuredCalendarTemplateID }) { template in
                WidgetWeaverAboutTemplateRow(
                    template: template,
                    isProUnlocked: proManager.isProUnlocked,
                    onAdd: { makeDefault in
                        handleAdd(template: template, makeDefault: makeDefault)
                    },
                    onShowPro: {
                        onShowPro()
                    }
                )
            }
        } header: {
            WidgetWeaverAboutSectionHeader("Templates — Starter", systemImage: "square.grid.2x2", accent: .pink)
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Templates add a new saved design to the library.\nEdit freely, then Save to refresh widgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !proManager.isProUnlocked {
                    Text("Free tier designs: \(designCount)/\(WidgetWeaverEntitlements.maxFreeDesigns)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var proTemplatesSection: some View {
        Section {
            ForEach(Self.proTemplates) { template in
                WidgetWeaverAboutTemplateRow(
                    template: template,
                    isProUnlocked: proManager.isProUnlocked,
                    onAdd: { makeDefault in
                        handleAdd(template: template, makeDefault: makeDefault)
                    },
                    onShowPro: {
                        onShowPro()
                    }
                )
            }
        } header: {
            WidgetWeaverAboutSectionHeader("Templates — Pro", systemImage: "crown.fill", accent: .yellow)
        } footer: {
            Text("Pro templates can include Matched Sets, Variables + Shortcuts, and Interactive Buttons.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Interactive Buttons

    var interactiveButtonsSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        """
                        Interactive buttons add a compact action bar to the bottom of the widget on iOS 17+.
                        Each button runs an App Intent and updates a variable in the App Group, so the widget can update without opening the app.
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Up to \(WidgetActionBarSpec.maxActions) buttons per widget.",
                        "Actions: Increment Variable, Set Variable to Now.",
                        "Buttons can include a title and optional SF Symbol.",
                        "Pairs with templates like {{count|0}} or {{last_done|Never|relative}}.",
                    ])

                    if proManager.isProUnlocked {
                        Text("See Templates — Pro for ready-made button examples (e.g. Habit Streak, Counter).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Interactive buttons are a Pro feature.", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)

                        Button {
                            onShowPro()
                        } label: {
                            Label("Unlock Pro", systemImage: "crown.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Interactive Buttons", systemImage: "hand.tap", accent: .orange)
        } footer: {
            Text("Buttons only appear in the widget.\nConfigure them in the editor under Actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Variables

    var variablesSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .teal) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        """
                        Template variables let text fields pull values at render time.
                        Some keys are built-in (time/date + weather). Pro unlocks a shared variable store that can be updated via Shortcuts and interactive widget buttons.
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Template syntax")
                                .font(.subheadline.weight(.semibold))

                            WidgetWeaverAboutCodeBlock(
                                """
                                {{key}}
                                {{key|fallback}}
                                {{key|fallback|upper}}
                                {{amount|0|number:0}}
                                {{last_done|Never|relative}}
                                {{progress|0|bar:10}}
                                {{__now||date:HH:mm}}
                                {{__weather_temp|--}}
                                {{__weather_condition|Updating…}}
                                {{=done/total*100|0|number:0}}%
                                """,
                                accent: .teal
                            )
                        }

                        Spacer(minLength: 0)

                        VStack(alignment: .trailing, spacing: 8) {
                            Button {
                                copyToPasteboard(
                                    """
                                    Weather: {{__weather_temp|--}}° • {{__weather_condition|Updating…}}
                                    Location: {{__weather_location|Set location}}
                                    """
                                )
                            } label: {
                                Label("Copy weather", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                copyToPasteboard("Streak: {{streak|0}} days\nLast done: {{last_done|Never|relative}}")
                            } label: {
                                Label("Copy Pro example", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    Text("Shortcuts actions (App Intents):")
                        .font(.subheadline.weight(.semibold))

                    WidgetWeaverAboutBulletList(items: [
                        "Set WidgetWeaver Variable",
                        "Get WidgetWeaver Variable",
                        "Remove WidgetWeaver Variable",
                        "Increment WidgetWeaver Variable",
                        "Set WidgetWeaver Variable to Now",
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("Variables", systemImage: "curlybraces", accent: .teal)
        } footer: {
            Text("Variables render at widget refresh time.\nUse built-in keys (weather/steps) or Pro variables for interactive widgets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI

    var aiSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .indigo) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        """
                        AI features are optional and run on-device.
                        They can generate or patch your WidgetSpec, but they never generate images.
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "Generate a design spec from a prompt.",
                        "Patch edits: “make it more minimal”, “turn accent to teal”, etc.",
                        "Results are validated and clamped to safe ranges.",
                    ])
                }
            }
            .wwAboutListRow()
        } header: {
            WidgetWeaverAboutSectionHeader("AI (Optional)", systemImage: "sparkles", accent: .indigo)
        } footer: {
            Text("AI is currently intended as a prototype helper for spec exploration.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Privacy

    var privacySection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .gray) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        """
                        WidgetWeaver stores designs and caches locally on your device.
                        Weather and calendar data is read on-device and saved into the App Group cache for widgets to render offline.
                        """
                    )
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
            Text("No accounts. No servers. No tracking.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Support

    var supportSection: some View {
        Section {
            WidgetWeaverAboutCard(accent: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(
                        """
                        This is a prototype app for exploring widget layouts and spec-driven rendering.
                        """
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    WidgetWeaverAboutBulletList(items: [
                        "If widgets look stale, use … → Refresh Widgets.",
                        "If Weather looks stale, use Weather → Update now.",
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
