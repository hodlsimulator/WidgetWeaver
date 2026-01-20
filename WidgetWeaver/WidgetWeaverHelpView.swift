//
//  WidgetWeaverHelpView.swift
//  WidgetWeaver
//
//  Created by . . on 1/20/26.
//

import SwiftUI
import UIKit

struct WidgetWeaverHelpView: View {
    @Environment(\.dismiss) private var dismiss

    // Expanded by default to support first-run onboarding.
    @State private var quickStartExpanded: Bool = true
    @State private var glossaryExpanded: Bool = false
    @State private var clockPathsExpanded: Bool = false
    @State private var designSelectionExpanded: Bool = true
    @State private var designerWorkflowExpanded: Bool = false
    @State private var smartPhotosExpanded: Bool = false
    @State private var variablesExpanded: Bool = false
    @State private var permissionsExpanded: Bool = false
    @State private var updatesExpanded: Bool = true
    @State private var troubleshootingExpanded: Bool = true
    @State private var powerUserExpanded: Bool = false

    var body: some View {
        NavigationStack {
            List {
                overviewSection
                gettingStartedSection
                customisationSection
                dataAndPermissionsSection
                updatesAndTroubleshootingSection
                powerUserSection
            }
            .navigationTitle("Widget Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var overviewSection: some View {
        Section {
            Text(
                "WidgetWeaver edits Designs in the app, then WidgetKit displays them as widgets. A widget can either follow the app’s Default design, or be pinned to a specific named design."
            )
            .foregroundStyle(.secondary)

            WWHelpFlowDiagram(
                title: "The big picture",
                steps: [
                    .init(systemImage: "sparkles", title: "Choose a starter", detail: "Pick a template in Explore (or start from Default)."),
                    .init(systemImage: "slider.horizontal.3", title: "Customise", detail: "Edit text, layout, style, and any data sources."),
                    .init(systemImage: "tray.and.arrow.down", title: "Save", detail: "Saving writes the Design to shared storage and signals widgets."),
                    .init(systemImage: "square.grid.2x2", title: "Place", detail: "Add the widget on the Home Screen and choose which Design it should use.")
                ]
            )

            DisclosureGroup(isExpanded: $glossaryExpanded) {
                VStack(alignment: .leading, spacing: 10) {
                    WWHelpDefinition(term: "Template", meaning: "A curated starting point (layout + sensible defaults).")
                    WWHelpDefinition(term: "Design", meaning: "A saved, named configuration. Designs are what widgets render.")
                    WWHelpDefinition(term: "Default (App)", meaning: "The app’s current default Design. Widgets set to Default (App) always follow it.")
                    WWHelpDefinition(term: "Pinned design", meaning: "A widget configured to a specific Design name. It will not change when the app default changes.")
                    WWHelpDefinition(term: "Draft", meaning: "Unsaved edits in the editor. Drafts do not reach widgets until Save.")
                }
                .padding(.top, 6)
            } label: {
                Label("Glossary", systemImage: "book")
            }
        } header: {
            Text("Overview")
        }
    }

    private var gettingStartedSection: some View {
        Section {
            DisclosureGroup(isExpanded: $quickStartExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("This is the simplest way to get a reliable widget on the Home Screen.")
                        .foregroundStyle(.secondary)

                    WWHelpFlowDiagram(
                        title: "Path A — One widget that always matches the app default",
                        steps: [
                            .init(systemImage: "sparkles", title: "Pick a template", detail: "Explore → choose a template (or stay on the default)."),
                            .init(systemImage: "pencil", title: "Edit", detail: "Make changes in the editor (Preview size changes how it looks)."),
                            .init(systemImage: "checkmark.circle.fill", title: "Save & Make Default", detail: "This updates Default (App) and refreshes widgets."),
                            .init(systemImage: "plus", title: "Add widget", detail: "Home Screen → long-press → Edit Home Screen → + → WidgetWeaver."),
                            .init(systemImage: "slider.horizontal.3", title: "Set Design", detail: "Edit Widget → Design → Default (App).")
                        ]
                    )

                    WWHelpCallout(
                        systemImage: "square.stack.3d.up",
                        title: "Multiple widgets with different looks",
                        message: "For two (or more) widgets that stay different: save two Designs with different names, then Edit Widget on each widget and pick a specific named Design (not Default (App))."
                    )

                    WWHelpFlowDiagram(
                        title: "Path B — Two widgets, two designs",
                        steps: [
                            .init(systemImage: "tray.and.arrow.down", title: "Save Design A", detail: "Give it a clear name (e.g. \"Weather — Blue\")."),
                            .init(systemImage: "tray.and.arrow.down", title: "Save Design B", detail: "Create a second look (e.g. \"Weather — Minimal\")."),
                            .init(systemImage: "square.grid.2x2", title: "Add two widgets", detail: "Add WidgetWeaver twice (same size or different sizes)."),
                            .init(systemImage: "slider.horizontal.3", title: "Pin each widget", detail: "Edit Widget → Design → pick the named design for each widget.")
                        ]
                    )

                    Text("If a widget looks stale: open WidgetWeaver and use Widgets → Refresh Widgets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } label: {
                Label("Quick start", systemImage: "bolt.fill")
            }

            DisclosureGroup(isExpanded: $clockPathsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Clock has two placement paths. Use the one that matches the intent.")
                        .foregroundStyle(.secondary)

                    WWHelpFlowDiagram(
                        title: "Clock (Quick) — standalone clock",
                        steps: [
                            .init(systemImage: "plus", title: "Add from the widget gallery", detail: "Home Screen → + → choose the Clock (Quick) widget."),
                            .init(systemImage: "paintpalette", title: "Configure", detail: "Edit Widget to choose colour scheme and options."),
                            .init(systemImage: "hand.tap", title: "Done", detail: "Fast setup with a compact configuration.")
                        ]
                    )

                    WWHelpFlowDiagram(
                        title: "Clock (Designer) — full editor workflow",
                        steps: [
                            .init(systemImage: "sparkles", title: "Create a Clock Design", detail: "In the app, pick a Clock template and customise it."),
                            .init(systemImage: "checkmark.circle.fill", title: "Save", detail: "Save the Design (optionally make it the default)."),
                            .init(systemImage: "square.grid.2x2", title: "Add WidgetWeaver widget", detail: "Home Screen → + → WidgetWeaver → choose a size."),
                            .init(systemImage: "slider.horizontal.3", title: "Select Design", detail: "Edit Widget → Design → choose the saved Clock design.")
                        ]
                    )

                    WWHelpCallout(
                        systemImage: "lightbulb",
                        title: "Which should be used?",
                        message: "If uncertain, start with Clock (Quick). Use Clock (Designer) when a Clock should match other templates, use Variables, or share styling across sizes."
                    )
                }
                .padding(.vertical, 6)
            } label: {
                Label("Clock: Quick vs Designer", systemImage: "clock")
            }

            DisclosureGroup(isExpanded: $designSelectionExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Design selection controls whether a widget follows the app default, or stays locked to one Design.")
                        .foregroundStyle(.secondary)

                    WWHelpMonospaceBlock(
                        text:
                        """
                        Home Screen widget
                        ├─ Design: Default (App)
                        │  └─ follows whatever is currently set as the app default
                        └─ Design: A specific named Design
                           └─ stays fixed until changed in Edit Widget
                        """
                    )

                    Text(
                        "To change it: long-press the widget → Edit Widget → Design.\n\nIf several widgets keep changing together, they are usually all set to Default (App). Pin each one to a named design instead."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    WWHelpCallout(
                        systemImage: "star",
                        title: "Default design tip",
                        message: "Keep one Design as the default and treat it like a ‘main’ widget. Pin other widgets to named Designs for specialised layouts (e.g. one Weather, one Calendar, one Photo)."
                    )
                }
                .padding(.vertical, 6)
            } label: {
                Label("Choose which Design a widget uses", systemImage: "slider.horizontal.3")
            }
        } header: {
            Text("Getting started")
        }
    }

    private var customisationSection: some View {
        Section {
            DisclosureGroup(isExpanded: $designerWorkflowExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Most templates use the Designer workflow: pick a template, edit it, then save as a Design.")
                        .foregroundStyle(.secondary)

                    WWHelpFlowDiagram(
                        title: "Template → Design",
                        steps: [
                            .init(systemImage: "sparkles", title: "Explore", detail: "Pick a starter (Weather, Next Up, Steps, Photo, etc.)."),
                            .init(systemImage: "rectangle.3.group", title: "Preview size", detail: "Switch preview size to see Small/Medium/Large layout changes."),
                            .init(systemImage: "slider.horizontal.3", title: "Tools", detail: "Use the context-aware tools to adjust layout, style, and data."),
                            .init(systemImage: "tray.and.arrow.up", title: "Share", detail: "Export a .wwdesign file to share or archive."),
                            .init(systemImage: "tray.and.arrow.down", title: "Save", detail: "Save to update widgets (and optionally set as Default).")
                        ]
                    )

                    WWHelpCallout(
                        systemImage: "square.on.square",
                        title: "Matched Set",
                        message: "Matched Set enables a coordinated Small/Medium/Large set. When enabled, edits apply to the selected preview size, and Copy Size can propagate the current layout across all sizes."
                    )
                }
                .padding(.vertical, 6)
            } label: {
                Label("Designer workflow (templates, previews, matched sizes)", systemImage: "wand.and.rays")
            }

            DisclosureGroup(isExpanded: $smartPhotosExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Smart Photos prepare photo widgets in the app so widgets stay fast and deterministic.")
                        .foregroundStyle(.secondary)

                    WWHelpFlowDiagram(
                        title: "Smart Photos",
                        steps: [
                            .init(systemImage: "photo.on.rectangle", title: "Choose photos", detail: "Select photos inside WidgetWeaver (Photos access may be required)."),
                            .init(systemImage: "crop", title: "Crop once", detail: "Adjust the crop for each widget size so it looks correct."),
                            .init(systemImage: "shuffle", title: "Optional rotation", detail: "Enable rotation schedules to cycle through prepared photos."),
                            .init(systemImage: "checkmark.circle.fill", title: "Save", detail: "Saving updates the Design and refreshes widgets.")
                        ]
                    )

                    Text("If a photo widget shows an old crop or doesn’t rotate, open the app once so preparation can complete, then use Refresh Widgets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } label: {
                Label("Smart Photos (photo widgets)", systemImage: "photo")
            }

            DisclosureGroup(isExpanded: $variablesExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Variables let text fields pull values at render time (time, weather, steps, custom counters, and more).")
                        .foregroundStyle(.secondary)

                    WWHelpMonospaceBlock(
                        text:
                        """
                        Basic:
                        {{key}}          {{key|fallback}}

                        Built-ins:
                        {{__time}}       {{__today}}       {{__weekday}}

                        Examples:
                        Streak: {{streak|0}}
                        Last done: {{last_done|Never|relative}}
                        Progress: {{progress|0|bar:10}}
                        """
                    )

                    WWHelpCallout(
                        systemImage: "crown",
                        title: "Pro note",
                        message: "Custom variables are managed in the Variables sheet (Pro). Built-in keys (e.g. __time, __weather_*, __steps_*, __activity_*) can still resolve in designs even without Pro."
                    )

                    Text("Tip: the Variables sheet includes a ‘Try it’ area to test templates and copy snippets.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } label: {
                Label("Variables (dynamic text)", systemImage: "curlybraces")
            }
        } header: {
            Text("Customisation")
        }
    }

    private var dataAndPermissionsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $permissionsExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Some templates need permission so WidgetWeaver can cache on-device snapshots for widgets.")
                        .foregroundStyle(.secondary)

                    WWHelpMonospaceBlock(
                        text:
                        """
                        Common permissions
                        • Photos: Smart Photos / photo-backed templates
                        • Location: Weather (Current Location)
                        • Calendar: Next Up
                        • Reminders: Reminders template
                        • Health / Motion: Steps and Activity
                        """
                    )

                    Text("When permission is missing, widgets typically show placeholders (e.g. ‘Enable access’). Grant permission in the app, then refresh widgets.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        Label("Open iOS Settings for WidgetWeaver", systemImage: "gear")
                    }

                    Text("Privacy note: widgets render from prepared/cached data so they stay fast. Data sources update on an iOS schedule; opening the app can help refresh snapshots sooner.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } label: {
                Label("Permissions and data sources", systemImage: "hand.raised")
            }
        } header: {
            Text("Data & permissions")
        }
    }

    private var updatesAndTroubleshootingSection: some View {
        Section {
            DisclosureGroup(isExpanded: $updatesExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Widgets are snapshots. iOS decides when to refresh them, and it may delay updates to save power.")
                        .foregroundStyle(.secondary)

                    WWHelpFlowDiagram(
                        title: "What normally triggers an update",
                        steps: [
                            .init(systemImage: "pencil", title: "Edit in WidgetWeaver", detail: "Changes are applied to a draft."),
                            .init(systemImage: "tray.and.arrow.down", title: "Save", detail: "Saving writes to the App Group and requests a widget reload."),
                            .init(systemImage: "clock", title: "iOS refresh window", detail: "The Home Screen updates when iOS applies the next snapshot."),
                            .init(systemImage: "arrow.clockwise", title: "Refresh Widgets", detail: "If needed, use Widgets → Refresh Widgets in the editor.")
                        ]
                    )

                    Text("Time-based designs (clocks, relative time, some weather) update on minute boundaries, but delivery is still best-effort.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } label: {
                Label("How updates work", systemImage: "arrow.triangle.2.circlepath")
            }

            DisclosureGroup(isExpanded: $troubleshootingExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If something looks wrong, these checks resolve most issues.")
                        .foregroundStyle(.secondary)

                    WWHelpMonospaceBlock(
                        text:
                        """
                        Troubleshooting checklist
                        1) Confirm the widget’s Design: Edit Widget → Design
                        2) If using Default (App), confirm the app default is the intended Design
                        3) In WidgetWeaver: Save (or Save & Make Default)
                        4) In WidgetWeaver: Widgets → Refresh Widgets
                        5) Remove the widget and add it again
                        6) Confirm permissions for the template (Weather/Calendar/Reminders/Health/Photos)
                        """
                    )

                    WWHelpCallout(
                        systemImage: "exclamationmark.triangle",
                        title: "Stuck preview vs Home Screen",
                        message: "Previews can update sooner than the live Home Screen widget. If the Home Screen stays stale, refresh widgets and wait for the next iOS update window (often under a minute for time-based widgets)."
                    )

                    Text("If a widget shows placeholders for a data source (Weather, Next Up, Reminders, Steps), open the relevant access/settings screen in WidgetWeaver to grant access and refresh the cache.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            } label: {
                Label("Troubleshooting", systemImage: "lifepreserver")
            }
        } header: {
            Text("Updates & troubleshooting")
        }
    }

    private var powerUserSection: some View {
        Section {
            DisclosureGroup(isExpanded: $powerUserExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("These patterns keep large setups predictable.")
                        .foregroundStyle(.secondary)

                    WWHelpMonospaceBlock(
                        text:
                        """
                        Power-user patterns
                        • Name designs by purpose: “Weather — Blue”, “Calendar — Work”, “Photo — Shuffle”
                        • Keep one Default (App) design as a ‘main’ widget
                        • Pin specialised widgets to named designs
                        • Use Matched Set for coordinated Small/Medium/Large widgets
                        • Export .wwdesign files as backups or to share setups
                        • Use Variables for counters, streaks, and dynamic text
                        """
                    )

                    WWHelpCallout(
                        systemImage: "square.stack.3d.up",
                        title: "Smart Stacks",
                        message: "When using Smart Stacks, pin each widget to a named design to avoid unexpected changes when the app default is edited."
                    )
                }
                .padding(.vertical, 6)
            } label: {
                Label("Power-user tips", systemImage: "hammer")
            }
        } header: {
            Text("Power user")
        }
    }
}

// MARK: - Helpers

private struct WWHelpStep: Identifiable, Hashable {
    let id: UUID = UUID()
    let systemImage: String
    let title: String
    let detail: String
}

private struct WWHelpFlowDiagram: View {
    let title: String
    let steps: [WWHelpStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: step.systemImage)
                        .foregroundStyle(.tint)
                        .frame(width: 22)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))

                        Text(step.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                if index < (steps.count - 1) {
                    HStack(spacing: 12) {
                        Color.clear
                            .frame(width: 22)

                        Image(systemName: "arrow.down")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Spacer(minLength: 0)
                    }
                    .accessibilityHidden(true)
                }
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

private struct WWHelpCallout: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }
}

private struct WWHelpMonospaceBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
    }
}

private struct WWHelpDefinition: View {
    let term: String
    let meaning: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(term)
                .font(.subheadline.weight(.semibold))

            Text(meaning)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
