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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("WidgetWeaver")
                        .font(.title2.weight(.semibold))

                    Spacer(minLength: 0)

                    Text(appVersionString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(
                    """
                    Build Home Screen widgets from simple templates.
                    Start from templates, customise layout + style, and (in Pro) add variables and interactive buttons. Designs are saved on your device and shown on your Home Screen.
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

                    Button {
                        onShowPro()
                    } label: {
                        if proManager.isProUnlocked {
                            Label("Pro (Unlocked)", systemImage: "checkmark.seal.fill")
                        } else {
                            Label("Upgrade to Pro", systemImage: "crown.fill")
                        }
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("WidgetWeaver")
        }
    }

    // MARK: - Featured Weather

    var featuredWeatherSection: some View {
        let template = Self.featuredWeatherTemplate

        return Section {
            VStack(alignment: .leading, spacing: 10) {
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
                        WidgetWeaverAboutPreviewLabeled(familyLabel: "Small") {
                            WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 86)
                        }
                        WidgetWeaverAboutPreviewLabeled(familyLabel: "Medium") {
                            WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 86)
                        }
                        WidgetWeaverAboutPreviewLabeled(familyLabel: "Large") {
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
                    "Add a WidgetWeaver widget to your Home Screen."
                ])

                Button {
                    showWeatherSettings = true
                } label: {
                    Label("Open Weather settings", systemImage: "cloud.sun.fill")
                }
                .controlSize(.small)
                .buttonStyle(.borderless)

                Divider()

                Text("Built-in weather keys (work in any text field)")
                    .font(.subheadline.weight(.semibold))

                WidgetWeaverAboutCodeBlock(
                    """
                    {{__weather_location|Set location}}
                    {{__weather_temp|--}}°
                    {{__weather_condition|Updating…}}
                    {{__weather_precip|0}}%
                    """
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
                .controlSize(.small)
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 6)
        } header: {
            Text("Featured")
        } footer: {
            Text("Weather data is provided by Weather. iOS widget refresh limits still apply; use Weather → Update now to refresh the cached snapshot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Featured Calendar

    var featuredCalendarSection: some View {
        let template = Self.featuredCalendarTemplate
        let canRead = WidgetWeaverCalendarStore.shared.canReadEvents()

        return Section {
            VStack(alignment: .leading, spacing: 10) {
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
                        Label(canRead ? "Refresh now" : "Enable access", systemImage: canRead ? "arrow.clockwise" : "checkmark.circle.fill")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderless)
                }

                if !template.tags.isEmpty {
                    WidgetWeaverAboutFlowTags(tags: template.tags)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        WidgetWeaverAboutPreviewLabeled(familyLabel: "Small") {
                            WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 86)
                        }
                        WidgetWeaverAboutPreviewLabeled(familyLabel: "Medium") {
                            WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 86)
                        }
                        WidgetWeaverAboutPreviewLabeled(familyLabel: "Large") {
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
                    "Add a WidgetWeaver widget to your Home Screen."
                ])
            }
            .padding(.vertical, 6)
        } header: {
            Text("Calendar")
        } footer: {
            Text("Calendar data is read on-device from Apple Calendar (EventKit). No events are uploaded by WidgetWeaver.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Capabilities

    var capabilitiesSection: some View {
        Section {
            WidgetWeaverAboutFeatureRow(
                title: "Templates library",
                subtitle: "Add starter designs (and Pro designs) to your library, then edit freely."
            )
            WidgetWeaverAboutFeatureRow(
                title: "Text-first widgets",
                subtitle: "Design name, primary text, and optional secondary text."
            )
            WidgetWeaverAboutFeatureRow(
                title: "Layout templates",
                subtitle: "Classic / Hero / Poster / Weather / Calendar presets, plus axis, alignment, spacing, and line limits."
            )
            WidgetWeaverAboutFeatureRow(
                title: "Built-in Weather template",
                subtitle: "A rain-first layout with glass panels and adaptive Small/Medium/Large composition."
            )
            WidgetWeaverAboutFeatureRow(
                title: "Built-in Calendar template",
                subtitle: "Next Up shows upcoming events (requires Calendar access)."
            )
            WidgetWeaverAboutFeatureRow(
                title: "Interactive buttons (Pro)",
                subtitle: "Add up to \(WidgetActionBarSpec.maxActions) widget buttons (iOS 17+) to increment variables or set timestamps."
            )
            WidgetWeaverAboutFeatureRow(
                title: "Sharing / import / export",
                subtitle: "Export JSON (optionally embedding images), then import back in without overwriting existing designs."
            )
        } header: {
            Text("What’s supported right now")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Examples of widgets that fit the current renderer:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                WidgetWeaverAboutBulletList(items: [
                    "Weather (rain-first nowcast + forecast) via the built-in Weather template",
                    "Next Up calendar widget (upcoming events) via the Calendar template",
                    "Habit tracker / streak counter (with Variables + interactive buttons in Pro)",
                    "Countdown widget (manual or variable-driven)",
                    "Daily focus / top task",
                    "Shopping list / reminder"
                ])
            }
        }
    }

    // MARK: - Templates

    var starterTemplatesSection: some View {
        Section {
            ForEach(Self.starterTemplates.filter {
                $0.id != Self.featuredWeatherTemplateID && $0.id != Self.featuredCalendarTemplateID
            }) { template in
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
            Text("Templates — Starter")
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
            Text("Templates — Pro")
        } footer: {
            Text("Pro templates can include Matched Sets, Variables + Shortcuts, and Interactive Buttons.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Interactive Buttons

    var interactiveButtonsSection: some View {
        Section {
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
                "Pairs with templates like {{count|0}} or {{last_done|Never|relative}}."
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
                .controlSize(.small)
            }
        } header: {
            Text("Interactive Buttons")
        } footer: {
            Text("Buttons only appear in the widget.\nConfigure them in the editor under Actions.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Variables

    var variablesSection: some View {
        Section {
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
                        """
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
                    .controlSize(.small)

                    Button {
                        copyToPasteboard("Streak: {{streak|0}} days\nLast done: {{last_done|Never|relative}}")
                    } label: {
                        Label("Copy Pro example", systemImage: "doc.on.doc")
                    }
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
                "Set WidgetWeaver Variable to Now"
            ])

            if !proManager.isProUnlocked {
                Label("Stored variables + Shortcuts actions are a Pro feature.", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)

                Button {
                    onShowPro()
                } label: {
                    Label("Unlock Pro", systemImage: "crown.fill")
                }
                .controlSize(.small)
            }
        } header: {
            Text("Variables + Shortcuts")
        } footer: {
            Text("Keys are canonicalised (trimmed, lowercased, internal whitespace collapsed). Weather keys use the cached snapshot from Weather settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI

    var aiSection: some View {
        Section {
            Text(WidgetSpecAIService.availabilityMessage())
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Generation and edits are designed to run on-device.\nImages are never generated; photos are chosen manually in the editor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Text("Prompt ideas")
                .font(.subheadline.weight(.semibold))

            ForEach(Self.promptIdeas, id: \.self) { prompt in
                WidgetWeaverAboutPromptRow(
                    text: prompt,
                    copyLabel: "Copy prompt",
                    onCopy: { copyToPasteboard(prompt) }
                )
            }

            Divider()

            Text("Patch ideas")
                .font(.subheadline.weight(.semibold))

            ForEach(Self.patchIdeas, id: \.self) { patch in
                WidgetWeaverAboutPromptRow(
                    text: patch,
                    copyLabel: "Copy patch",
                    onCopy: { copyToPasteboard(patch) }
                )
            }
        } header: {
            Text("AI (Optional)")
        }
    }

    // MARK: - Sharing

    var sharingSection: some View {
        Section {
            WidgetWeaverAboutFeatureRow(
                title: "Share one design or the whole library",
                subtitle: "Exports are JSON and can embed images when available."
            )
            WidgetWeaverAboutFeatureRow(
                title: "Import safely",
                subtitle: "Imported designs are duplicated with new IDs to avoid overwriting existing work."
            )
            WidgetWeaverAboutFeatureRow(
                title: "Offline-friendly",
                subtitle: "Images are stored in the App Group container and rendered without a network dependency."
            )
        } header: {
            Text("Sharing / Import / Export")
        }
    }

    // MARK: - Pro

    var proSection: some View {
        Section {
            if proManager.isProUnlocked {
                Label("WidgetWeaver Pro is unlocked.", systemImage: "checkmark.seal.fill")

                Text("Matched sets, variables, interactive buttons, and unlimited designs are enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    onShowPro()
                } label: {
                    Label("Manage Pro", systemImage: "crown.fill")
                }
                .controlSize(.small)
            } else {
                Label("Free tier", systemImage: "sparkles")

                Text("Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) saved designs.\nPro unlocks unlimited designs, matched sets, variables, and interactive buttons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    onShowPro()
                } label: {
                    Label("Unlock Pro", systemImage: "crown.fill")
                }
                .controlSize(.small)
            }
        } header: {
            Text("Pro")
        }
    }

    // MARK: - Diagnostics

    var diagnosticsSection: some View {
        Section {
            LabeledContent("App Group", value: AppGroup.identifier)

            Text("Storage:")
                .font(.subheadline.weight(.semibold))

            WidgetWeaverAboutBulletList(items: [
                "Designs: JSON in App Group UserDefaults",
                "Images: files in App Group container (WidgetWeaverImages/)",
                "Variables: JSON dictionary in App Group UserDefaults (Pro)",
                "Weather: location + cached snapshot + attribution in App Group UserDefaults",
                "Calendar: cached snapshot + last error in App Group UserDefaults",
                "Action bars: stored in the design spec; buttons run App Intents (iOS 17+)"
            ])
        } header: {
            Text("Implementation notes")
        }
    }
}
