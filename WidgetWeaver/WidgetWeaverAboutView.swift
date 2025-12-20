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

struct WidgetWeaverAboutView: View {
    @ObservedObject var proManager: WidgetWeaverProManager

    /// Adds a template into the design library.
    /// The caller owns ID/timestamp handling, selection updates, and widget refresh messaging.
    let onAddTemplate: @MainActor (_ spec: WidgetSpec, _ makeDefault: Bool) -> Void

    /// Switches the sheet to Pro UI.
    let onShowPro: @MainActor () -> Void

    /// Switches the sheet to widget help UI.
    let onShowWidgetHelp: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var designCount: Int = 0
    @State private var statusMessage: String = ""
    @State private var showWeatherSettings: Bool = false

    var body: some View {
        NavigationStack {
            List {
                aboutHeaderSection
                featuredWeatherSection
                capabilitiesSection
                starterTemplatesSection
                proTemplatesSection
                interactiveButtonsSection
                variablesSection
                aiSection
                sharingSection
                proSection
                diagnosticsSection
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear { refreshDesignCount() }
        }
        .navigationDestination(isPresented: $showWeatherSettings) {
            WidgetWeaverWeatherSettingsView()
        }
    }

    // MARK: - Header

    private var aboutHeaderSection: some View {
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
                    Start from starter designs, customise layout + style, and (in Pro) add variables and interactive buttons. Everything is saved on your device.
                    """
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button { onShowWidgetHelp() } label: {
                        Label("Widget Help", systemImage: "questionmark.circle")
                    }

                    Button { onShowPro() } label: {
                        if proManager.isProUnlocked {
                            Label("Pro (Unlocked)", systemImage: "checkmark.seal.fill")
                        } else {
                            Label("Upgrade to Pro", systemImage: "crown.fill")
                        }
                    }
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        } header: {
            Text("WidgetWeaver")
        }
    }

    // MARK: - Featured Weather

    private var featuredWeatherSection: some View {
        let template = Self.featuredWeatherTemplate

        return Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weather")
                            .font(.headline)
                        Text("Next-hour rain • hourly + daily • glass")
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
                    A rain-first Weather layout that focuses on the next-hour rain chart, with an hourly strip and daily highs/lows when available.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if !template.tags.isEmpty {
                    FlowTags(tags: template.tags)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        PreviewLabeled(familyLabel: "Small") {
                            WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 86)
                        }
                        PreviewLabeled(familyLabel: "Medium") {
                            WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 86)
                        }
                        PreviewLabeled(familyLabel: "Large") {
                            WidgetPreviewThumbnail(spec: template.spec, family: .systemLarge, height: 86)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Divider()

                Text("Setup")
                    .font(.subheadline.weight(.semibold))

                BulletList(items: [
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

                CodeBlock(
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

    // MARK: - Capabilities + Examples

    private var capabilitiesSection: some View {
        Section {
            FeatureRow(
                title: "Templates library",
                subtitle: "Add starter designs (and Pro designs) to your library, then edit freely."
            )

            FeatureRow(
                title: "Text-first widgets",
                subtitle: "Design name, primary text, and optional secondary text."
            )

            FeatureRow(
                title: "Layout templates",
                subtitle: "Classic / Hero / Poster / Weather presets, plus axis, alignment, spacing, and line limits."
            )

            FeatureRow(
                title: "Built-in Weather template",
                subtitle: "A rain-first layout with glass panels and adaptive Small/Medium/Large sizing."
            )

            FeatureRow(
                title: "Accent bar toggle",
                subtitle: "Optional accent bar per design (handy for Hero/Poster layouts)."
            )

            FeatureRow(
                title: "Style tokens",
                subtitle: "Padding, corner radius, background style, and accent colour."
            )

            FeatureRow(
                title: "“Wow” backgrounds",
                subtitle: "Aurora / Sunset / Midnight / Candy overlays for extra depth."
            )

            FeatureRow(
                title: "Optional SF Symbol",
                subtitle: "Choose a symbol name, size, weight, rendering, tint, and placement."
            )

            FeatureRow(
                title: "Optional photo banner",
                subtitle: "Pick a photo banner. Saved on your device so it works offline."
            )

            FeatureRow(
                title: "Interactive buttons (Pro)",
                subtitle: "Add up to \(WidgetActionBarSpec.maxActions) widget buttons (iOS 17+) to increment variables or set timestamps."
            )

            FeatureRow(
                title: "Template variables",
                subtitle: "{{key}} templates with number/date/relative formatting, plus built-in time + weather keys."
            )

            FeatureRow(
                title: "Matched sets (Pro)",
                subtitle: "Per-size overrides (Small/Medium/Large) while sharing style + typography tokens."
            )

            FeatureRow(
                title: "Per-widget selection",
                subtitle: "Each widget instance can follow Default (App) or a specific saved design."
            )

            FeatureRow(
                title: "Sharing / import / export",
                subtitle: "Export and import designs (optionally with images) without overwriting anything you already have."
            )

            FeatureRow(
                title: "On-device AI (optional)",
                subtitle: "Prompt → spec generation and patch edits, with deterministic fallbacks when unavailable."
            )

            FeatureRow(
                title: "Maintenance tools",
                subtitle: "Randomise Style (draft-only) and Clean Up Unused Images."
            )
        } header: {
            Text("What’s supported right now")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Examples of widgets that fit the current renderer:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                BulletList(items: [
                    "Weather (rain-first nowcast + forecast) via the built-in Weather template",
                    "Habit tracker / streak counter (with Variables + interactive buttons in Pro)",
                    "Counter widget (tap +1 / -1 in Pro)",
                    "Countdown widget (manual or variable-driven)",
                    "Daily focus / top task",
                    "Shopping list / reminder",
                    "Reading progress / next chapter",
                    "Workout plan / routine cue",
                    "Quote / affirmation card",
                    "Photo caption card (add a banner image)",
                    "Matched per-size designs (Small/Medium/Large) in Pro"
                ])
            }
        }
    }

    // MARK: - Templates

    private var starterTemplatesSection: some View {
        Section {
            ForEach(Self.starterTemplates.filter { $0.id != Self.featuredWeatherTemplateID }) { template in
                TemplateRow(
                    template: template,
                    isProUnlocked: proManager.isProUnlocked,
                    onAdd: { makeDefault in
                        handleAdd(template: template, makeDefault: makeDefault)
                    },
                    onShowPro: { onShowPro() }
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

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var proTemplatesSection: some View {
        Section {
            ForEach(Self.proTemplates) { template in
                TemplateRow(
                    template: template,
                    isProUnlocked: proManager.isProUnlocked,
                    onAdd: { makeDefault in
                        handleAdd(template: template, makeDefault: makeDefault)
                    },
                    onShowPro: { onShowPro() }
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

    @MainActor
    private func handleAdd(template: AboutTemplate, makeDefault: Bool) {
        if template.requiresPro && !proManager.isProUnlocked {
            statusMessage = "“\(template.title)” requires Pro."
            onShowPro()
            return
        }

        onAddTemplate(template.spec, makeDefault)
        statusMessage = makeDefault ? "Added “\(template.title)” and set as default." : "Added “\(template.title)”."
        refreshDesignCount()
    }

    // MARK: - Interactive Buttons

    private var interactiveButtonsSection: some View {
        Section {
            Text(
                """
                Interactive buttons add a compact action bar to the bottom of the widget on iOS 17+.
                Each button runs an action that updates a variable, so the widget can update without opening the app.
                """
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            BulletList(items: [
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

                Button { onShowPro() } label: {
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

    private var variablesSection: some View {
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

                    CodeBlock(
                        """
                        {{key}}
                        {{key|fallback}}
                        {{key|fallback|upper}}
                        {{amount|0|number:0}}
                        {{last_done|Never|relative}}
                        {{progress|0|bar:10}}
                        {{__now||date:HH:mm}}
                        {{__weather_temp|--}}°
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
                        copyToPasteboard(
                            """
                            Streak: {{streak|0}} days
                            Last done: {{last_done|Never|relative}}
                            """
                        )
                    } label: {
                        Label("Copy Pro example", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }

            Divider()

            Text("Shortcuts actions:")
                .font(.subheadline.weight(.semibold))

            BulletList(items: [
                "Set WidgetWeaver Variable",
                "Get WidgetWeaver Variable",
                "Remove WidgetWeaver Variable",
                "Increment WidgetWeaver Variable",
                "Set WidgetWeaver Variable to Now"
            ])

            if !proManager.isProUnlocked {
                Label("Stored variables + Shortcuts actions are a Pro feature.", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)

                Button { onShowPro() } label: {
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

    private var aiSection: some View {
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
                PromptRow(
                    text: prompt,
                    copyLabel: "Copy prompt",
                    onCopy: { copyToPasteboard(prompt) }
                )
            }

            Divider()

            Text("Patch ideas")
                .font(.subheadline.weight(.semibold))

            ForEach(Self.patchIdeas, id: \.self) { patch in
                PromptRow(
                    text: patch,
                    copyLabel: "Copy patch",
                    onCopy: { copyToPasteboard(patch) }
                )
            }
        } header: {
            Text("AI (Optional)")
        } footer: {
            Text("If AI is unavailable, you can still build designs manually with templates + editor controls.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Sharing

    private var sharingSection: some View {
        Section {
            FeatureRow(
                title: "Export designs",
                subtitle: "Exports are JSON and can embed images when available."
            )

            FeatureRow(
                title: "Import designs",
                subtitle: "Imports will not overwrite existing designs. Duplicates are renamed automatically."
            )

            FeatureRow(
                title: "Image storage",
                subtitle: "Images are stored in the App Group container and rendered without a network dependency."
            )
        } header: {
            Text("Sharing / Import / Export")
        } footer: {
            Text("Use Share → Export to create a package.\nUse Share → Import to bring packages back in.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pro

    private var proSection: some View {
        Section {
            if proManager.isProUnlocked {
                Label("Pro is unlocked on this device.", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.secondary)
            } else {
                Text(
                    """
                    Pro unlocks:
                    • More saved designs
                    • Interactive buttons
                    • Matched sets
                    • Variables + Shortcuts store
                    • Pro templates
                    """
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Button { onShowPro() } label: {
                    Label("Upgrade to Pro", systemImage: "crown.fill")
                }
                .controlSize(.small)
            }
        } header: {
            Text("Pro")
        } footer: {
            Text("Purchases are managed by Apple’s App Store.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsSection: some View {
        Section {
            LabeledContent("App Group", value: AppGroup.identifier)
                .font(.caption)

            Divider()

            Text("Storage locations:")
                .font(.subheadline.weight(.semibold))

            BulletList(items: [
                "Designs: JSON in App Group UserDefaults",
                "Images: files in App Group container (WidgetWeaverImages/)",
                "Variables: JSON dictionary in App Group UserDefaults (Pro)",
                "Weather: location + cached snapshot + attribution in App Group UserDefaults",
                "Action bars: stored in the design spec; buttons run App Intents (iOS 17+)"
            ])
        } header: {
            Text("Implementation notes")
        }
    }

    // MARK: - Helpers

    private var appVersionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    @MainActor
    private func refreshDesignCount() {
        designCount = WidgetSpecStore.shared.loadAll().count
    }

    private func copyToPasteboard(_ string: String) {
        UIPasteboard.general.string = string
        statusMessage = "Copied to clipboard."
    }
}

// MARK: - Template Models

private struct AboutTemplate: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let description: String
    let tags: [String]
    let requiresPro: Bool
    let spec: WidgetSpec
}

// MARK: - Template Rows

private struct TemplateRow: View {
    let template: AboutTemplate
    let isProUnlocked: Bool
    let onAdd: @MainActor (_ makeDefault: Bool) -> Void
    let onShowPro: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.title)
                        .font(.headline)
                    Text(template.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if template.requiresPro && !isProUnlocked {
                    Button { onShowPro() } label: {
                        Label("Pro required", systemImage: "lock.fill")
                    }
                    .controlSize(.small)
                } else {
                    Menu {
                        Button { onAdd(false) } label: {
                            Label("Add to library", systemImage: "plus")
                        }
                        Button { onAdd(true) } label: {
                            Label("Add & Make Default", systemImage: "star.fill")
                        }
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .controlSize(.small)
                }
            }

            Text(template.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !template.tags.isEmpty {
                FlowTags(tags: template.tags)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    PreviewLabeled(familyLabel: "Small") {
                        WidgetPreviewThumbnail(spec: template.spec, family: .systemSmall, height: 78)
                    }
                    PreviewLabeled(familyLabel: "Medium") {
                        WidgetPreviewThumbnail(spec: template.spec, family: .systemMedium, height: 78)
                    }
                    PreviewLabeled(familyLabel: "Large") {
                        WidgetPreviewThumbnail(spec: template.spec, family: .systemLarge, height: 78)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PreviewLabeled<Content: View>: View {
    let familyLabel: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(familyLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct FeatureRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(item)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }
}

private struct PromptRow: View {
    let text: String
    let copyLabel: String
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button(action: onCopy) {
                Label(copyLabel, systemImage: "doc.on.doc")
            }
            .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

private struct CodeBlock: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.primary)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10))
            )
            .textSelection(.enabled)
    }
}

private struct FlowTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Catalog

private extension WidgetWeaverAboutView {
    static let featuredWeatherTemplateID: String = "starter-weather"

    static var featuredWeatherTemplate: AboutTemplate {
        starterTemplates.first(where: { $0.id == featuredWeatherTemplateID })
        ?? AboutTemplate(
            id: featuredWeatherTemplateID,
            title: "Weather",
            subtitle: "Rain-first nowcast",
            description: "A rain-first layout with glass panels, glow, and adaptive Small/Medium/Large sizing.",
            tags: ["Weather", "Rain chart", "Dynamic", "Glass"],
            requiresPro: false,
            spec: specWeather()
        )
    }

    static var promptIdeas: [String] {
        [
            "minimal focus widget, teal accent, no symbol, short text",
            "bold countdown widget, centred layout, purple accent, bigger title",
            "quote card, subtle material background, grey accent, no secondary text",
            "shopping list reminder, green accent, checklist icon",
            "reading progress widget, blue accent, book icon, short secondary text",
            "workout routine widget, red accent, strong title, simple layout",
            "note widget, horizontal layout, orange accent, minimal styling",
            "habit streak widget, orange accent, uses {{streak|0}} and {{last_done|Never|relative}}, with interactive buttons",
            "weather widget, glass look, strong accent, rain-first"
        ]
    }

    static var patchIdeas: [String] {
        [
            "more minimal",
            "bigger title",
            "change accent to teal",
            "switch to horizontal layout",
            "centre the layout",
            "remove the symbol",
            "remove secondary text",
            "add interactive buttons"
        ]
    }

    static var starterTemplates: [AboutTemplate] {
        [
            AboutTemplate(
                id: "starter-focus",
                title: "Focus",
                subtitle: "Minimal daily focus card",
                description: "A clean, glanceable widget for a single priority.",
                tags: ["Text", "Symbol", "Accent glow"],
                requiresPro: false,
                spec: specFocus()
            ),
            AboutTemplate(
                id: "starter-countdown",
                title: "Countdown",
                subtitle: "Bold countdown styling",
                description: "A simple countdown layout with a larger primary line.",
                tags: ["Text", "Symbol", "Big type"],
                requiresPro: false,
                spec: specCountdown()
            ),
            AboutTemplate(
                id: "starter-quote",
                title: "Quote",
                subtitle: "Quote / affirmation card",
                description: "Good for short quotes, affirmations, or reminders.",
                tags: ["Text", "Symbol", "Material"],
                requiresPro: false,
                spec: specQuote()
            ),
            AboutTemplate(
                id: "starter-list",
                title: "List",
                subtitle: "Shopping / checklist style",
                description: "A compact list-style widget using a single text line.",
                tags: ["Text", "Symbol"],
                requiresPro: false,
                spec: specList()
            ),
            AboutTemplate(
                id: "starter-reading",
                title: "Reading",
                subtitle: "Progress cue",
                description: "A reading prompt with a clear next-step.",
                tags: ["Text", "Symbol", "Material"],
                requiresPro: false,
                spec: specReading()
            ),

            // Featured separately at the top of About.
            AboutTemplate(
                id: "starter-weather",
                title: "Weather",
                subtitle: "Rain-first • next-hour rain",
                description: "A rain-first layout with glass panels, glow, and adaptive Small/Medium/Large sizing.",
                tags: ["Weather", "Rain chart", "Dynamic", "Glass"],
                requiresPro: false,
                spec: specWeather()
            ),

            AboutTemplate(
                id: "starter-workout",
                title: "Workout",
                subtitle: "Routine cue",
                description: "A short workout reminder with a strong accent.",
                tags: ["Text", "Symbol", "Accent glow"],
                requiresPro: false,
                spec: specWorkout()
            ),
            AboutTemplate(
                id: "starter-photo",
                title: "Photo Caption",
                subtitle: "Designed for an image banner",
                description: "A simple caption layout that pairs well with a photo.",
                tags: ["Text", "Photo", "Material"],
                requiresPro: false,
                spec: specPhotoCaption()
            )
        ]
    }

    static var proTemplates: [AboutTemplate] {
        [
            AboutTemplate(
                id: "pro-habit",
                title: "Habit Streak",
                subtitle: "Variables + interactive buttons",
                description: "A streak counter with tap-to-increment buttons.",
                tags: ["Pro", "Buttons", "Variables"],
                requiresPro: true,
                spec: specHabitStreak()
            ),
            AboutTemplate(
                id: "pro-counter",
                title: "Counter",
                subtitle: "Tap +1 / -1",
                description: "A counter widget with two buttons.",
                tags: ["Pro", "Buttons", "Variables"],
                requiresPro: true,
                spec: specCounter()
            ),
            AboutTemplate(
                id: "pro-matched",
                title: "Matched Set",
                subtitle: "Small/Medium/Large overrides",
                description: "One design with per-size layout overrides.",
                tags: ["Pro", "Matched", "Library"],
                requiresPro: true,
                spec: specMatched()
            )
        ]
    }

    // MARK: - Specs

    static func specFocus() -> WidgetSpec {
        let layout = LayoutSpec(
            axis: .vertical,
            alignment: .leading,
            spacing: 8,
            primaryLineLimitSmall: 2,
            primaryLineLimit: 2,
            secondaryLineLimit: 1
        )

        let style = StyleSpec(
            padding: 16,
            cornerRadius: 22,
            background: .subtleMaterial,
            accent: .teal,
            nameTextStyle: .caption2,
            primaryTextStyle: .headline,
            secondaryTextStyle: .caption2
        )

        let symbol = SymbolSpec(
            name: "target",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )

        return WidgetSpec(
            name: "Focus",
            primaryText: "Write shipping notes",
            secondaryText: "One thing that moves the needle",
            updatedAt: Date(),
            symbol: symbol,
            image: nil,
            layout: layout,
            style: style,
            matchedSet: nil
        )
        .normalised()
    }

    static func specCountdown() -> WidgetSpec {
        let layout = LayoutSpec(
            axis: .vertical,
            alignment: .leading,
            spacing: 6,
            primaryLineLimitSmall: 1,
            primaryLineLimit: 1,
            secondaryLineLimit: 1
        )

        let style = StyleSpec(
            padding: 16,
            cornerRadius: 22,
            background: .accentGlow,
            accent: .purple,
            nameTextStyle: .caption2,
            primaryTextStyle: .title2,
            secondaryTextStyle: .caption2
        )

        let symbol = SymbolSpec(
            name: "hourglass",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )

        return WidgetSpec(
            name: "Countdown",
            primaryText: "12 days",
            secondaryText: "Until launch",
            updatedAt: Date(),
            symbol: symbol,
            image: nil,
            layout: layout,
            style: style,
            matchedSet: nil
        )
        .normalised()
    }

    static func specQuote() -> WidgetSpec {
        let layout = LayoutSpec(
            axis: .vertical,
            alignment: .leading,
            spacing: 8,
            primaryLineLimitSmall: 3,
            primaryLineLimit: 3,
            secondaryLineLimit: 1
        )

        let style = StyleSpec(
            padding: 16,
            cornerRadius: 22,
            background: .subtleMaterial,
            accent: .gray,
            nameTextStyle: .caption2,
            primaryTextStyle: .headline,
            secondaryTextStyle: .caption2
        )

        let symbol = SymbolSpec(
            name: "quote.opening",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )

        return WidgetSpec(
            name: "Quote",
            primaryText: "Do the obvious thing, for an unreasonably long time.",
            secondaryText: "— Unknown",
            updatedAt: Date(),
            symbol: symbol,
            image: nil,
            layout: layout,
            style: style,
            matchedSet: nil
        )
        .normalised()
    }

    static func specList() -> WidgetSpec {
        let layout = LayoutSpec(
            axis: .vertical,
            alignment: .leading,
            spacing: 6,
            primaryLineLimitSmall: 2,
            primaryLineLimit: 2,
            secondaryLineLimit: 1
        )

        let style = StyleSpec(
            padding: 16,
            cornerRadius: 22,
            background: .subtleMaterial,
            accent: .green,
            nameTextStyle: .caption2,
            primaryTextStyle: .headline,
            secondaryTextStyle: .caption2
        )

        let symbol = SymbolSpec(
            name: "checklist",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )

        return WidgetSpec(
            name: "List",
            primaryText: "• Milk\n• Eggs\n• Coffee",
            secondaryText: "Tap to open app",
            updatedAt: Date(),
            symbol: symbol,
            image: nil,
            layout: layout,
            style: style,
            matchedSet: nil
        )
        .normalised()
    }

    static func specReading() -> WidgetSpec {
        let layout = LayoutSpec(
            axis: .vertical,
            alignment: .leading,
            spacing: 8,
            primaryLineLimitSmall: 2,
            primaryLineLimit: 2,
            secondaryLineLimit: 1
        )

        let style = StyleSpec(
            padding: 16,
            cornerRadius: 22,
            background: .subtleMaterial,
            accent: .blue,
            nameTextStyle: .caption2,
            primaryTextStyle: .headline,
            secondaryTextStyle: .caption2
        )

        let symbol = SymbolSpec(
            name: "book.fill",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )

        return WidgetSpec(
            name: "Reading",
            primaryText: "Read 20 minutes",
            secondaryText: "Finish Chapter 6",
            updatedAt: Date(),
            symbol: symbol,
            image: nil,
            layout: layout,
            style: style,
            matchedSet: nil
        )
        .normalised()
    }

    static func specWeather() -> WidgetSpec {
        let layout = LayoutSpec(
            template: .weather,
            axis: .vertical,
            alignment: .leading,
            spacing: 10,
            primaryLineLimitSmall: 1,
            primaryLineLimit: 1,
            secondaryLineLimitSmall: 1,
            secondaryLineLimit: 2
        )

        let style = StyleSpec(
            padding: 18,
            cornerRadius: 26,
            background: .midnight,
            backgroundOverlay: .none,
            backgroundOverlayOpacity: 0,
            backgroundGlowEnabled: true,
            accent: .blue,
            nameTextStyle: .caption2,
            primaryTextStyle: .headline,
            secondaryTextStyle: .caption,
            symbolSize: 42,
            weatherScale: 1.05
        )

        return WidgetSpec(
            name: "Weather",
            primaryText: "{{__weather_temp|--}}°",
            secondaryText: "{{__weather_location|Set location}} • {{__weather_condition|Updating…}}",
            updatedAt: Date(),
            symbol: nil,
            image: nil,
            layout: layout,
            style: style,
            matchedSet: nil
        )
        .normalised()
    }

    static func specWorkout() -> WidgetSpec {
        let layout = LayoutSpec(
            axis: .vertical,
            alignment: .leading,
            spacing: 8,
            primaryLineLimitSmall: 1,
            primaryLineLimit: 2,
            secondaryLineLimit: 1
        )

        let style = StyleSpec(
            padding: 16,
            cornerRadius: 22,
            background: .accentGlow,
            accent: .red,
            nameTextStyle: .caption2,
            primaryTextStyle: .headline,
            secondaryTextStyle: .caption2
        )

        let symbol = SymbolSpec(
            name: "dumbbell.fill",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )

        return WidgetSpec(
            name: "Workout",
            primaryText: "Upper body",
            secondaryText: "Pull • Push • Core",
            updatedAt: Date(),
            symbol: symbol,
            image: nil,
            layout: layout,
            style: style,
            matchedSet: nil
        )
        .normalised()
    }

    static func specPhotoCaption() -> WidgetSpec {
        let layout = LayoutSpec(
            axis: .vertical,
            alignment: .leading,
            spacing: 8,
            primaryLineLimitSmall: 2,
            primaryLineLimit: 2,
            secondaryLineLimit: 2
        )

        let style = StyleSpec(
            padding: 16,
            cornerRadius: 22,
            background: .accentGlow,
            accent: .pink,
            nameTextStyle: .caption2,
            primaryTextStyle: .headline,
            secondaryTextStyle: .caption2
        )

        let symbol = SymbolSpec(
            name: "photo.on.rectangle",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )

        return WidgetSpec(
            name: "Photo",
            primaryText: "Favourite memory",
            secondaryText: "Add a photo in Image",
            updatedAt: Date(),
            symbol: symbol,
            image: nil,
            layout: layout,
            style: style,
            matchedSet: nil
        )
        .normalised()
    }

    static func specHabitStreak() -> WidgetSpec {
        var base = specFocus()
        base.name = "Habit"
        base.primaryText = "Streak: {{streak|0}}"
        base.secondaryText = "Last done: {{last_done|Never|relative}}"
        base.layout.spacing = 8
        base.style.accent = .orange
        base.style.background = .accentGlow

        let actionBar = WidgetActionBarSpec(
            actions: [
                WidgetActionSpec(
                    title: "+1",
                    symbolName: "plus",
                    action: .incrementVariable(key: "streak", amount: 1)
                ),
                WidgetActionSpec(
                    title: "Done",
                    symbolName: "checkmark",
                    action: .setVariableToNow(key: "last_done")
                )
            ]
        )

        base.actionBar = actionBar
        return base.normalised()
    }

    static func specCounter() -> WidgetSpec {
        var base = specCountdown()
        base.name = "Counter"
        base.primaryText = "{{count|0}}"
        base.secondaryText = "Tap to change"
        base.style.accent = .indigo
        base.style.primaryTextStyle = .title

        let actionBar = WidgetActionBarSpec(
            actions: [
                WidgetActionSpec(
                    title: "+1",
                    symbolName: "plus",
                    action: .incrementVariable(key: "count", amount: 1)
                ),
                WidgetActionSpec(
                    title: "-1",
                    symbolName: "minus",
                    action: .incrementVariable(key: "count", amount: -1)
                )
            ]
        )

        base.actionBar = actionBar
        return base.normalised()
    }

    static func specMatched() -> WidgetSpec {
        let base = specFocus()

        var small = base
        small.primaryText = "Today\n{{__now||date:EEE}}"
        small.secondaryText = "Focus: write"
        small.layout.primaryLineLimitSmall = 2
        small.layout.secondaryLineLimitSmall = 1

        var medium = base
        medium.primaryText = "Write shipping notes"
        medium.secondaryText = "One thing that moves the needle"
        medium.layout.primaryLineLimit = 2
        medium.layout.secondaryLineLimit = 2

        var large = base
        large.primaryText = "Write shipping notes"
        large.secondaryText = "One thing that moves the needle\nThen: answer messages"
        large.layout.primaryLineLimit = 2
        large.layout.secondaryLineLimit = 3

        let matched = MatchedSetSpec(
            small: small,
            medium: medium,
            large: large
        )

        var root = base
        root.name = "Matched"
        root.matchedSet = matched
        root.style.accent = .teal
        root.style.background = .aurora
        return root.normalised()
    }
}
