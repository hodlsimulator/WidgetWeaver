//
//  ContentView+Sections.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI

extension ContentView {
    func sectionHeader(_ title: String) -> some View {
        let headerID = "EditorSectionHeader." + title.replacingOccurrences(of: " ", with: "_")

        return Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityIdentifier(headerID)
    }

    // MARK: - New: Content (template + data sources)
    var contentSection: some View {
        let currentTemplate = currentFamilyDraft().template
        let canReadCalendar = WidgetWeaverCalendarStore.shared.canReadEvents()
        let remindersEnabled = WidgetWeaverFeatureFlags.remindersTemplateEnabled

        let templateTokens: [LayoutTemplateToken] = {
            var tokens = LayoutTemplateToken.allCases.filter { token in
                // Reminders is feature-flag gated.
                return remindersEnabled || token != .reminders
            }

            // If a hidden template is already selected (eg. imported design), include it so the
            // picker has a matching tag. Do not expose it as selectable when the flag is off.
            if !remindersEnabled, currentTemplate == .reminders, !tokens.contains(.reminders) {
                tokens.append(.reminders)
            }

            return tokens
        }()

        return Section {
            Picker("Template", selection: binding(\.template)) {
                ForEach(templateTokens) { token in
                    Text(token.displayName)
                        .tag(token)
                        .disabled(token == .reminders && !remindersEnabled)
                }
            }

            if currentTemplate == .reminders && !remindersEnabled {
                Text("Reminders template is disabled (feature flag off).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlGroup {
                Button {
                    addTemplateDesign(WidgetWeaverAboutView.featuredWeatherTemplate.spec, makeDefault: false)
                    selectedTab = .editor
                } label: {
                    Label("Weather", systemImage: "cloud.sun.fill")
                }

                Button {
                    addTemplateDesign(WidgetWeaverAboutView.featuredCalendarTemplate.spec, makeDefault: false)
                    selectedTab = .editor
                } label: {
                    Label("Next Up", systemImage: "calendar")
                }

                Menu {
                    Button {
                        applyStepsStarterPreset(copyToAllSizes: false)
                    } label: {
                        Label("Apply to this size (\(editingFamilyLabel))", systemImage: "figure.walk")
                    }

                    if matchedSetEnabled {
                        Button {
                            applyStepsStarterPreset(copyToAllSizes: true)
                        } label: {
                            Label("Apply to all sizes", systemImage: "square.on.square")
                        }
                    }

                    Divider()

                    Button {
                        activeSheet = .steps
                    } label: {
                        Label("Open Steps settings", systemImage: "heart")
                    }
                } label: {
                    Label("Steps", systemImage: "figure.walk")
                }
            }
            .controlSize(.small)

            if currentTemplate == .weather {
                Button {
                    activeSheet = .weather
                } label: {
                    Label("Weather settings", systemImage: "cloud.rain")
                }

                Text("Weather template renders from cached Weather snapshots.\nUse Weather settings to pick a location and force an update.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if currentTemplate == .nextUpCalendar {
                Button {
                    Task {
                        let granted = await WidgetWeaverCalendarEngine.shared.requestAccessIfNeeded()
                        if granted {
                            _ = await WidgetWeaverCalendarEngine.shared.updateIfNeeded(force: true)
                            await MainActor.run { saveStatusMessage = "Calendar refreshed.\nWidgets will update on next reload." }
                        } else {
                            await MainActor.run { saveStatusMessage = "Calendar access is off.\nEnable access to use Next Up." }
                        }
                    }
                } label: {
                    Label(
                        canReadCalendar ? "Refresh Calendar cache" : "Enable Calendar access",
                        systemImage: canReadCalendar ? "arrow.clockwise" : "checkmark.circle.fill"
                    )
                }

                Text("Next Up reads events on-device via EventKit and caches a small snapshot for widgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                selectedTab = .explore
            } label: {
                Label("Browse templates (Explore)", systemImage: "sparkles")
            }
        } header: {
            sectionHeader("Content")
        } footer: {
            Text("Template controls the overall renderer.\nUse Explore for curated starters (Weather / Next Up / Steps) and then customise here.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status / Tools

    var statusSection: some View {
        Section {
            HStack {
                Label("Preview size", systemImage: "rectangle.3.group")
                Spacer()
                Text(editingFamilyLabel)
                    .foregroundStyle(.secondary)
            }

            if let lastSavedAt {
                Text("Last saved: \(lastSavedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not saved yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlGroup {
                Button { activeSheet = .inspector } label: {
                    Label("Inspector", systemImage: "info.circle")
                }

                Button { activeSheet = .widgetHelp } label: {
                    Label("Widget help", systemImage: "questionmark.circle")
                }
            }
            .controlSize(.small)

            Button {
                showRevertConfirmation = true
            } label: {
                Label("Revert unsaved changes…", systemImage: "arrow.uturn.backward.circle")
            }
        } header: {
            sectionHeader("Status")
        } footer: {
            Text("Edits are applied to a draft.\nUse Save to update widgets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - AI

    var aiSection: some View {
        Section {
            if !WidgetWeaverFeatureFlags.aiEnabled {
                Text("AI is disabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !proManager.isProUnlocked {
                EditorUnavailableStateView(
                    state: EditorUnavailableState.proRequiredForAI(),
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else {
                Text(WidgetSpecAIService.availabilityMessage())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Prompt (generate a new design)", text: $aiPrompt, axis: .vertical)
                    .lineLimit(2...6)

                Toggle("Make generated design default", isOn: $aiMakeGeneratedDefault)

                Button {
                    Task {
                        if WidgetWeaverFeatureFlags.aiReviewUIEnabled {
                            await generateNewDesignCandidateFromPrompt()
                        } else {
                            await generateNewDesignFromPrompt()
                        }
                    }
                } label: {
                    Label("Generate design", systemImage: "sparkles")
                }
                .disabled(aiPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Divider()

                TextField("Patch instruction (edit this design)", text: $aiPatchInstruction, axis: .vertical)
                    .lineLimit(2...6)

                Button {
                    Task {
                        if WidgetWeaverFeatureFlags.aiReviewUIEnabled {
                            await applyPatchCandidateToCurrentDesign()
                        } else {
                            await applyPatchToCurrentDesign()
                        }
                    }
                } label: {
                    Label("Apply patch", systemImage: "wand.and.stars")
                }
                .disabled(aiPatchInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if !aiStatusMessage.isEmpty {
                    Text(aiStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if WidgetWeaverFeatureFlags.aiReviewUIEnabled && WidgetSpecAISnapshotStore.hasSnapshot {
                Divider()

                Button {
                    undoLastAIApplyIfAvailable()
                } label: {
                    Label("Undo last AI apply", systemImage: "arrow.uturn.backward")
                }
                .controlSize(.small)
            }

        } header: {
            sectionHeader("AI")
        } footer: {
            Text(
                WidgetWeaverFeatureFlags.aiReviewUIEnabled
                    ? "AI runs on-device where available.\nReview mode is enabled: AI outputs are not saved until applied."
                    : "AI runs on-device where available.\nGenerated designs are saved to the library like any other design."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Existing sections
    var designsSection: some View {
        Section {
            if savedSpecs.isEmpty {
                Text("No saved designs yet.")
                    .foregroundStyle(.secondary)
            } else {
                WidgetWeaverDesignSwitchGuardedPicker(
                    title: "Design",
                    specs: savedSpecs,
                    selectedSpecID: $selectedSpecID,
                    displayName: specDisplayName,
                    isDirty: { hasUnsavedChanges },
                    onSaveCurrent: { saveSelected(makeDefault: false) }
                )
            }

            if let defaultName {
                LabeledContent("App default", value: defaultName)
            }

            if !proManager.isProUnlocked {
                LabeledContent("Free tier designs", value: "\(savedSpecs.count)/\(WidgetWeaverEntitlements.maxFreeDesigns)")
            }

            if selectedSpecID == defaultSpecID {
                Text("This design is the app default.\nWidgets set to \"Default (App)\" will show it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This design is not the app default.\nUse \"Save & Make Default\" to update widgets set to \"Default (App)\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlGroup {
                Button { createNewDesign() } label: { Label("New", systemImage: "plus") }
                Button { duplicateCurrentDesign() } label: { Label("Duplicate", systemImage: "doc.on.doc") }
                    .disabled(savedSpecs.isEmpty)
                Button(role: .destructive) { showDeleteConfirmation = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(savedSpecs.count <= 1)
            }
            .controlSize(.small)
        } header: {
            sectionHeader("Design")
        } footer: {
            Text("Each widget instance can be configured to follow \"Default (App)\" or a specific saved design (long-press the widget → Edit Widget).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var proSection: some View {
        Section {
            if proManager.isProUnlocked {
                Label("WidgetWeaver Pro is unlocked.", systemImage: "checkmark.seal.fill")
                Button { activeSheet = .pro } label: { Label("Manage Pro", systemImage: "crown.fill") }
            } else {
                Label("Free tier", systemImage: "sparkles")
                Text("Free tier allows up to \(WidgetWeaverEntitlements.maxFreeDesigns) saved designs.\nPro unlocks unlimited designs, matched sets, and variables.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { activeSheet = .pro } label: { Label("Unlock Pro", systemImage: "crown.fill") }
                if !proManager.statusMessage.isEmpty {
                    Text(proManager.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Pro")
        }
    }

    var variablesManagerSection: some View {
        let unavailable = EditorToolRegistry.unavailableState(for: .variables, context: editorToolContext)

        return Section {
            if let unavailable {
                EditorUnavailableStateView(
                    state: unavailable,
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else {
                let vars = WidgetWeaverVariableStore.shared.loadAll()
                LabeledContent("Saved variables", value: "\(vars.count)")
                Button { activeSheet = .variables } label: { Label("Open Variables", systemImage: "curlybraces.square") }

                Text("Variables are stored on-device.\nOpen Variables → use “Insert variable…” (or “Build snippet…”) so there is no need to type {{ }}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Variables")
        }
    }

    var sharingSection: some View {
        Section {
            ShareLink(item: sharePackageForCurrentDesign(), preview: SharePreview("Design", icon: Image(systemName: "square.and.arrow.up"))) {
                Label("Share this design", systemImage: "square.and.arrow.up")
            }

            ShareLink(item: sharePackageForAllDesigns(), preview: SharePreview("Designs", icon: Image(systemName: "square.and.arrow.up"))) {
                Label("Share all designs", systemImage: "square.and.arrow.up")
            }

            Button {
                showImportPicker = true
            } label: {
                Label("Import designs…", systemImage: "square.and.arrow.down")
            }
            .disabled(importInProgress)

            Text("Sharing exports a .wwdesign file.\nImports are reviewed before applying.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            sectionHeader("Sharing")
        }
    }

    var matchedSetSection: some View {
        let unavailable = EditorToolRegistry.unavailableState(for: .matchedSet, context: editorToolContext)

        return Section {
            if let unavailable {
                EditorUnavailableStateView(
                    state: unavailable,
                    isBusy: false,
                    onPerformCTA: performEditorUnavailableCTA
                )
            } else {
                Toggle("Matched set (Small/Medium/Large)", isOn: matchedSetBinding)

                if matchedSetEnabled {
                    Text("Matched set is on.\nEdits apply to \(editingFamilyLabel).")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button { copyCurrentSizeToAllSizes() } label: {
                        Label("Copy \(editingFamilyLabel) to all sizes", systemImage: "square.on.square")
                    }
                } else {
                    Text("Matched set off.\nThe design is a single spec (Medium default).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            sectionHeader("Matched Set")
        }
    }

    var widgetWorkflowSection: some View {
        Section {
            Button { saveSelected(makeDefault: true) } label: { Label("Save & Make Default", systemImage: "checkmark.circle.fill") }
            Button { saveSelected(makeDefault: false) } label: { Label("Save (Keep Default)", systemImage: "tray.and.arrow.down") }

            if selectedSpecID != defaultSpecID {
                Button {
                    store.setDefault(id: selectedSpecID)
                    defaultSpecID = store.defaultSpecID()
                    lastWidgetRefreshAt = Date()
                    saveStatusMessage = "Made default.\nWidgets refreshed."
                } label: {
                    Label("Make This Design Default", systemImage: "star")
                }
            }

            Button { refreshWidgets() } label: { Label("Refresh Widgets", systemImage: "arrow.clockwise") }

            if !saveStatusMessage.isEmpty {
                Text(saveStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastWidgetRefreshAt {
                Text("Last refresh: \(lastWidgetRefreshAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Widgets")
        } footer: {
            Text("If a widget doesn’t change, check which Design it is using (Edit Widget).\nWidgets set to \"Default (App)\" always follow the app default design.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var textSection: some View {
        WidgetWeaverEditorTextToolSection(
            designName: $designName,
            primaryText: binding(\.primaryText),
            secondaryText: binding(\.secondaryText),
            matchedSetEnabled: matchedSetEnabled,
            editingFamilyLabel: editingFamilyLabel,
            isProUnlocked: proManager.isProUnlocked
        )
    }

    var symbolSection: some View {
        Section {
            TextField("SF Symbol name (optional)", text: binding(\.symbolName))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            Picker("Placement", selection: binding(\.symbolPlacement)) {
                ForEach(SymbolPlacementToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            HStack {
                Text("Size")
                Slider(value: binding(\.symbolSize), in: 8...96, step: 1)
                Text("\(Int(currentFamilyDraft().symbolSize))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Picker("Weight", selection: binding(\.symbolWeight)) {
                ForEach(SymbolWeightToken.allCases) { token in
                    Text(token.rawValue).tag(token)
                }
            }

            Picker("Rendering", selection: binding(\.symbolRenderingMode)) {
                ForEach(SymbolRenderingModeToken.allCases) { token in
                    Text(token.rawValue.capitalized).tag(token)
                }
            }

            Picker("Tint", selection: binding(\.symbolTint)) {
                ForEach(SymbolTintToken.allCases) { token in
                    Text(token.rawValue.capitalized).tag(token)
                }
            }

            if matchedSetEnabled {
                Text("Symbol settings are currently editing: \(editingFamilyLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Symbol")
        }
    }

    var layoutSection: some View {
        let currentTemplate = currentFamilyDraft().template
        let remindersEnabled = WidgetWeaverFeatureFlags.remindersTemplateEnabled

        let templateTokens: [LayoutTemplateToken] = {
            var tokens = LayoutTemplateToken.allCases.filter { token in
                // Reminders is feature-flag gated.
                return remindersEnabled || token != .reminders
            }
            if !remindersEnabled, currentTemplate == .reminders, !tokens.contains(.reminders) {
                tokens.append(.reminders)
            }
            return tokens
        }()

        return Section {
            Picker("Layout template", selection: binding(\.template)) {
                ForEach(templateTokens) { token in
                    Text(token.displayName)
                        .tag(token)
                        .disabled(token == .reminders && !remindersEnabled)
                }
            }

            if currentTemplate == .reminders && !remindersEnabled {
                Text("Reminders template is disabled (feature flag off).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if currentTemplate == .reminders && remindersEnabled {
                RemindersPackControls(
                    config: Binding(
                        get: { remindersDraft.normalised() },
                        set: { newValue in remindersDraft = newValue.normalised() }
                    ),
                    onOpenRemindersSettings: { activeSheet = .reminders }
                )
            }
            if FeatureFlags.posterSuiteEnabled && currentTemplate == .poster {
                PosterSuiteStage1Controls(
                    posterOverlayMode: binding(\.posterOverlayMode),
                    alignment: binding(\.alignment),
                    imageContentMode: binding(\.imageContentMode),
                    styleDraft: $styleDraft
                )
            }

            Toggle("Show accent bar", isOn: binding(\.showsAccentBar))

            Stepper(
                "Max primary lines: \(currentFamilyDraft().primaryLineLimit)",
                value: binding(\.primaryLineLimit),
                in: 1...6
            )

            Stepper(
                "Max secondary lines: \(currentFamilyDraft().secondaryLineLimit)",
                value: binding(\.secondaryLineLimit),
                in: 0...6
            )

            if matchedSetEnabled {
                Text("Layout is currently editing: \(editingFamilyLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Layout")
        }
    }

    var styleSection: some View {
        let template = currentFamilyDraft().template
        let isPoster = (template == .poster)

        return Section {
            WidgetWeaverThemePickerRow(
                applyToDraft: { themeID in
                    applyThemeToDraft(themeID: themeID)
                }
            )

            if !isPoster {
                HStack {
                    Text("Padding")
                    Slider(value: $styleDraft.padding, in: 0...40, step: 1)
                    Text("\(Int(styleDraft.padding))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Inner corner radius")
                    Slider(value: $styleDraft.cornerRadius, in: 0...44, step: 1)
                    Text("\(Int(styleDraft.cornerRadius))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Text("Widget outer corners are fixed by iOS; this radius affects inner cards and panels.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if template == .weather {
                HStack {
                    Text("Weather scale")
                    Slider(value: $styleDraft.weatherScale, in: 0.75...1.25, step: 0.01)
                    Text(String(format: "%.2f×", styleDraft.weatherScale))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Background", selection: $styleDraft.background) {
                ForEach(BackgroundToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Accent", selection: $styleDraft.accent) {
                ForEach(AccentToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            if !isPoster {
                Button { randomiseStyleDraft() } label: { Label("Randomise Style (Draft)", systemImage: "shuffle") }
            }

            if matchedSetEnabled {
                Text("Style is shared across Small/Medium/Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Style")
        }
    }

    var typographySection: some View {
        Section {
            Picker("Name text style", selection: $styleDraft.nameTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Primary text style", selection: $styleDraft.primaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            Picker("Secondary text style", selection: $styleDraft.secondaryTextStyle) {
                ForEach(TextStyleToken.allCases) { token in
                    Text(token.displayName).tag(token)
                }
            }

            if matchedSetEnabled {
                Text("Typography is shared across Small/Medium/Large.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Typography")
        }
    }

}
